import 'dart:io';
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../forum_model.dart'; // 访问 globalImageCache
import 'package:flutter/foundation.dart'; // 需要引入 foundation 以使用 compute

// 【新增】：必须写在类外面的顶级函数，专门给后台多线程跑
int _calculateSizeInIsolate(String dirPath) {
  int total = 0;
  try {
    final dir = Directory(dirPath);
    if (dir.existsSync()) {
      // 在后台线程同步暴力遍历，速度极快且不卡 UI
      for (var entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
    }
  } catch (_) {}
  return total;
}

class CacheHelper {
  // ================= 基础路径获取 =================
  static Future<String> getCachePath() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  // 【核心修复】：将计算任务丢给后台线程
  static Future<int> getTotalCacheSize() async {
    int total = 0;
    try {
      // 1. 获取目录路径
      final tempDir = await getTemporaryDirectory();

      // 2. 使用 compute 开启后台 Isolate 计算庞大的文件大小，绝对不卡主界面！
      total += await compute(_calculateSizeInIsolate, tempDir.path);

      // 3. 估算 SharedPreferences 文本缓存 (这个很少，留给主线程即可)
      final prefs = await SharedPreferences.getInstance();
      for (String key in prefs.getKeys()) {
        if (key.startsWith('thread_cache_')) {
          String? content = prefs.getString(key);
          if (content != null) total += content.length * 2;
        }
      }
    } catch (e) {
      print("❌ 计算缓存大小出错: $e");
    }
    return total;
  }

  static String formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(2)} ${suffixes[i]}";
  }

  // ================= 【核心增强】强力清理逻辑 =================
  static Future<void> clearAllCaches({
    bool clearFiles = true,
    bool clearHtml = true,
  }) async {
    print("🧹 [CacheHelper] 开始强力清理...");
    try {
      if (clearFiles) {
        // 1. 清理图片库缓存
        try {
          await DefaultCacheManager().emptyCache();
          await globalImageCache.emptyCache();
        } catch (_) {}

        // 2. 暴力清理临时目录 (包括压缩图片残余)
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists()) {
          await for (var entity in tempDir.list(followLinks: false)) {
            try {
              // 删除所有文件 (通常是 jpg, png 临时文件)
              if (entity is File) {
                await entity.delete();
              }
              // 删除特定的缓存目录
              else if (entity is Directory) {
                String name = p.basename(entity.path).toLowerCase();
                // 只要不是 flutter 的核心库目录，或者是我们认识的缓存目录，就删
                // 一般 temp 目录下的都可以删
                if (name != 'lib') {
                  await entity.delete(recursive: true);
                }
              }
            } catch (e) {
              print("⚠️ 删除失败: ${entity.path}");
            }
          }
        }
      }

      if (clearHtml) {
        await clearHtmlCache();
      }
      print("✅ 清理完成");
    } catch (e) {
      print("❌ 清理过程出错: $e");
    }
  }

  static Future<int> clearHtmlCache() async {
    final prefs = await SharedPreferences.getInstance();
    int count = 0;
    for (String key in prefs.getKeys()) {
      if (key.startsWith('thread_cache_') || key == 'home_page_cache') {
        await prefs.remove(key);
        count++;
      }
    }
    return count;
  }

  // ================= 导入/导出功能 (保持不变) =================
  static Future<String?> exportThreadData(
    String tid,
    int page,
    String subject,
  ) async {
    // ... 保持原有逻辑 ...
    try {
      final prefs = await SharedPreferences.getInstance();
      String key = 'thread_cache_${tid}_$page';
      String? data = prefs.getString(key);
      if (data == null) {
        key = 'thread_cache_${tid}_${page}_landlord';
        data = prefs.getString(key);
        if (data == null) return null;
      }
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download/GW_Archives');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      if (!await directory.exists()) await directory.create(recursive: true);

      String safeSubject = subject.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (safeSubject.length > 20) safeSubject = safeSubject.substring(0, 20);
      String fileName = "GW_${safeSubject}_${tid}_P$page.json";
      File file = File('${directory.path}/$fileName');

      Map<String, dynamic> archiveData = {
        "meta": {
          "version": 1,
          "app": "GiantessWaltz_App",
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        },
        "content": {
          "tid": tid,
          "page": page,
          "subject": subject,
          "key_suffix": key.contains("landlord") ? "_landlord" : "",
          "body": data,
        },
      };
      await file.writeAsString(jsonEncode(archiveData));
      return file.path;
    } catch (e) {
      print("❌ 导出失败: $e");
      return null;
    }
  }

  static Future<int> importArchive() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: true,
      );
      if (result == null) return 0;
      final prefs = await SharedPreferences.getInstance();
      int successCount = 0;
      for (var file in result.files) {
        if (file.path == null) continue;
        try {
          File f = File(file.path!);
          String content = await f.readAsString();
          Map<String, dynamic> json = jsonDecode(content);
          if (json['content'] != null) {
            var data = json['content'];
            String tid = data['tid'].toString();
            String page = data['page'].toString();
            String body = data['body'];
            String suffix = data['key_suffix'] ?? "";
            await prefs.setString('thread_cache_${tid}_${page}$suffix', body);
            successCount++;
          }
        } catch (_) {}
      }
      return successCount;
    } catch (e) {
      return 0;
    }
  }
}
