import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../forum_model.dart'; // 为了访问 globalImageCache

class CacheHelper {
  static Future<String> getCachePath() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  // 获取所有相关缓存的大小 (字节)
  static Future<int> getTotalCacheSize() async {
    int total = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      print("🔍 [CacheHelper] 正在扫描缓存目录: ${tempDir.path}");

      // 扫描整个临时目录，不仅仅是特定的文件夹
      // 这样能发现所有潜在的垃圾文件
      if (await tempDir.exists()) {
        await for (var entity in tempDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            try {
              int size = await entity.length();
              total += size;
              // 打印大文件，方便调试
              if (size > 1024 * 1024) {
                // > 1MB
                print(
                  "  📄 发现大文件: ${p.basename(entity.path)} (${formatSize(size)})",
                );
              }
            } catch (e) {
              // 忽略无法读取的文件
            }
          }
        }
      }

      print("📊 [CacheHelper] 扫描完成，总大小: ${formatSize(total)}");
    } catch (e) {
      print("❌ [CacheHelper] 计算大小出错: $e");
    }
    return total;
  }

  // 格式化大小
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

  // 强力清理
  static Future<void> clearAllCaches() async {
    print("🧹 [CacheHelper] 开始强力清理...");
    try {
      // 1. 调用库的标准清理 (优雅清理)
      try {
        await DefaultCacheManager().emptyCache();
        await globalImageCache.emptyCache();
      } catch (e) {
        print("  ⚠️ 库方法清理失败 (非致命): $e");
      }

      // 2. 暴力清理目录
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        // 专门针对 WebView 目录进行处理 (不区分大小写)
        final webViewDir = Directory(p.join(tempDir.path, 'WebView'));
        if (await webViewDir.exists()) {
          print("  🗑️ 发现 WebView 目录，尝试强制删除: ${webViewDir.path}");
          try {
            await webViewDir.delete(recursive: true);
            print("    ✅ WebView 目录删除成功");
          } catch (e) {
            print("    ❌ WebView 目录删除失败: $e");
          }
        }

        await for (var entity in tempDir.list(followLinks: false)) {
          // 跳过 lib 文件夹 (防止误删 Flutter 核心文件，虽然通常不在 temp)
          // 但为了安全，我们只删除我们认识的或者看起来像缓存的
          // 实际上 temp 目录下的东西理论上都可以删
          if (entity is Directory) {
            String name = p.basename(entity.path);
            String lowerName = name.toLowerCase();
            // 匹配常见的缓存目录名
            if (lowerName.contains('cache') ||
                lowerName.contains('img') ||
                lowerName.contains('web') ||
                lowerName == 'webview') {
              // 显式添加 webview
              print("  🗑️ 删除目录: $name");
              try {
                await entity.delete(recursive: true);
              } catch (e) {
                print("    ❌ 删除失败: $e");
              }
            }
          } else if (entity is File) {
            try {
              await entity.delete();
            } catch (e) {}
          }
        }
      }

      print("✅ [CacheHelper] 清理完成");
    } catch (e) {
      print("❌ [CacheHelper] 强力清理致命错误: $e");
      rethrow;
    }
  }

  // 调试方法：打印目录结构
  static Future<String> debugAnalyze() async {
    StringBuffer sb = StringBuffer();
    try {
      final tempDir = await getTemporaryDirectory();
      sb.writeln("临时目录: ${tempDir.path}");
      await for (var entity in tempDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          sb.writeln(
            "  📄 ${p.basename(entity.path)} - ${formatSize(await entity.length())}",
          );
        } else if (entity is Directory) {
          sb.writeln("📁 ${p.relative(entity.path, from: tempDir.path)}");
        }
      }
    } catch (e) {
      sb.writeln("分析出错: $e");
    }
    return sb.toString();
  }
}
