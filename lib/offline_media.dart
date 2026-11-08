import 'dart:convert';

import 'forum_model.dart';

/// 从离线保存的原始 API JSON 中提取图片直链：
/// 帖子正文里的 <img> 标签 + 图片附件（url + attachment）。
List<String> extractImageUrls(String jsonContent) {
  final urls = <String>{};
  try {
    final data = jsonDecode(jsonContent);
    final vars = data['Variables'];
    final rawPostList = vars?['postlist'];
    final items = rawPostList is List
        ? rawPostList
        : (rawPostList is Map ? rawPostList.values.toList() : const []);
    final imgTag = RegExp(r'<img[^>]+src=["' "'" r']([^"' "'" r']+)["' "'" r']');
    for (final p in items) {
      final message = p['message']?.toString() ?? '';
      for (final m in imgTag.allMatches(message)) {
        urls.add(m.group(1)!);
      }
      final attachments = p['attachments'];
      if (attachments is Map) {
        for (final a in attachments.values) {
          final isImg = (a['isimage'] != '0' && a['isimage'] != 0) ||
              (a['attachimg'] == '1' || a['attachimg'] == 1);
          if (isImg) {
            final full = '${a['url'] ?? ''}${a['attachment'] ?? ''}';
            if (full.startsWith('http')) urls.add(full);
          }
        }
      }
    }
  } catch (_) {}
  urls.removeWhere((u) => u.isEmpty || !u.startsWith('http'));
  return urls.toList();
}

class OfflineImageFetchResult {
  final int total;
  final int done;
  const OfflineImageFetchResult(this.total, this.done);
}

/// 把一页 JSON 里的图片预拉进 [globalImageCache] 磁盘缓存。
/// 单张失败不阻塞整本离线，返回 该页图片总数 / 成功数。
Future<OfflineImageFetchResult> prefetchOfflineImages(String jsonContent) async {
  final urls = extractImageUrls(jsonContent);
  if (urls.isEmpty) return const OfflineImageFetchResult(0, 0);
  var done = 0;
  const batchSize = 4;
  for (var i = 0; i < urls.length; i += batchSize) {
    final batch = urls.skip(i).take(batchSize);
    await Future.wait(batch.map((url) async {
      try {
        await globalImageCache.downloadFile(url);
        done++;
      } catch (_) {
        // 单张失败忽略，继续
      }
    }));
  }
  return OfflineImageFetchResult(urls.length, done);
}
