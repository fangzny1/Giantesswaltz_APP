import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class OfflineManager {
  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  // 获取存储目录 (Documents目录，不会被系统清理缓存删掉)
  Future<String> _getDirPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/gw_offline_data';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  // === 核心功能：保存/更新某一页 ===
  // 逻辑：直接覆盖文件，绝对不会滚雪球
  Future<void> savePage({
    required String tid,
    required int page,
    required String subject,
    required String author,
    required String authorId, // 【新增】保存作者ID
    required String jsonContent, // API返回的原始JSON字符串
  }) async {
    try {
      final dirPath = await _getDirPath();

      // 1. 保存内容文件 (文件名: thread_{tid}_{page}.json)
      final file = File('$dirPath/thread_${tid}_$page.json');
      await file.writeAsString(jsonContent); // writeAsString 默认就是覆盖模式

      // 2. 更新索引 (记录存了哪些帖子，方便列表展示)
      await _updateIndex(tid, subject, author, authorId, page);

      print("✅ [离线] 已保存 TID:$tid 第$page页");
    } catch (e) {
      print("❌ [离线] 保存失败: $e");
    }
  }

  // === 核心功能：读取某一页 ===
  Future<String?> readPage(String tid, int page) async {
    try {
      final dirPath = await _getDirPath();
      final file = File('$dirPath/thread_${tid}_$page.json');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print("❌ [离线] 读取失败: $e");
    }
    return null;
  }

  // === 内部方法：更新索引文件 ===
  Future<void> _updateIndex(
    String tid,
    String subject,
    String author,
    String authorId,
    int page,
  ) async {
    final dirPath = await _getDirPath();
    final indexFile = File('$dirPath/index.json');

    Map<String, dynamic> indexMap = {};
    if (await indexFile.exists()) {
      try {
        indexMap = jsonDecode(await indexFile.readAsString());
      } catch (_) {}
    }

    // 更新该贴的元数据
    int maxPage = page;
    if (indexMap.containsKey(tid)) {
      int oldMax = indexMap[tid]['max_page'] ?? 0;
      if (oldMax > maxPage) maxPage = oldMax; // 保留最大的页数记录
    }

    indexMap[tid] = {
      'tid': tid,
      'subject': subject,
      'author': author,
      'author_id': authorId, // 【新增】保存ID
      'max_page': maxPage,
      'update_time': DateTime.now().millisecondsSinceEpoch,
    };

    await indexFile.writeAsString(jsonEncode(indexMap));
  }

  // === 获取离线帖子列表 ===
  Future<List<Map<String, dynamic>>> getOfflineList() async {
    final dirPath = await _getDirPath();
    final indexFile = File('$dirPath/index.json');
    if (!await indexFile.exists()) return [];

    try {
      final json = jsonDecode(await indexFile.readAsString()) as Map;
      List<Map<String, dynamic>> list = [];
      json.forEach((k, v) {
        list.add(v as Map<String, dynamic>);
      });
      // 按时间倒序
      list.sort(
        (a, b) => (b['update_time'] ?? 0).compareTo(a['update_time'] ?? 0),
      );
      return list;
    } catch (e) {
      return [];
    }
  }

  // === 删除帖子 ===
  Future<void> deleteThread(String tid) async {
    final dirPath = await _getDirPath();
    final dir = Directory(dirPath);

    // 1. 删除所有相关页面文件
    if (await dir.exists()) {
      await for (var entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          // 匹配 thread_12345_1.json, thread_12345_2.json ...
          if (name.startsWith('thread_${tid}_')) {
            await entity.delete();
          }
        }
      }
    }

    // 2. 从索引中移除
    final indexFile = File('$dirPath/index.json');
    if (await indexFile.exists()) {
      Map indexMap = jsonDecode(await indexFile.readAsString());
      indexMap.remove(tid);
      await indexFile.writeAsString(jsonEncode(indexMap));
    }
  }
}
