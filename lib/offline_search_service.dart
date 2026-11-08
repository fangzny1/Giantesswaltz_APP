import 'dart:convert';

import 'offline_manager.dart';

/// 离线全文搜索的单条命中。
class OfflineSearchHit {
  final String tid;
  final String subject;
  final String author;
  final String authorId;
  final String pid;
  final int floor;
  final int page;
  final String text; // 去标签后的楼层纯文本
  final int matchStart;
  final int matchLength;
  final bool isTitleHit; // 命中标题/作者而非正文

  const OfflineSearchHit({
    required this.tid,
    required this.subject,
    required this.author,
    required this.authorId,
    required this.pid,
    required this.floor,
    required this.page,
    required this.text,
    required this.matchStart,
    required this.matchLength,
    this.isTitleHit = false,
  });
}

/// 一条可搜索的楼层记录（纯数据，方便单测）。
class OfflinePostRecord {
  final String tid;
  final String subject;
  final String pid;
  final String author;
  final String authorId;
  final int floor;
  final int page;
  final String text;

  const OfflinePostRecord({
    required this.tid,
    required this.subject,
    required this.pid,
    required this.author,
    required this.authorId,
    required this.floor,
    required this.page,
    required this.text,
  });
}

/// 去 HTML 标签与常见实体，得到纯文本。
String stripHtml(String html) {
  var text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>'), ' ');
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 从一页离线 JSON 提取所有楼层的纯文本记录。
List<OfflinePostRecord> extractSearchablePosts(
    String tid, String subject, int page, String jsonContent) {
  final posts = <OfflinePostRecord>[];
  try {
    final data = jsonDecode(jsonContent);
    final vars = data['Variables'];
    final rawPostList = vars?['postlist'];
    final items = rawPostList is List
        ? rawPostList
        : (rawPostList is Map ? rawPostList.values.toList() : const []);
    for (final p in items) {
      try {
        final text = stripHtml(p['message']?.toString() ?? '');
        if (text.isEmpty) continue;
        posts.add(OfflinePostRecord(
          tid: tid,
          subject: subject,
          pid: p['pid']?.toString() ?? '',
          author: p['author']?.toString() ?? '',
          authorId: p['authorid']?.toString() ?? '',
          // 【修复】真实 API 的 number 是字符串（"1"），必须容错解析
          floor: int.tryParse(p['number']?.toString() ?? '') ?? 0,
          page: page,
          text: text,
        ));
      } catch (_) {
        // 单个楼层数据异常不拖垮整页
      }
    }
  } catch (_) {}
  return posts;
}

/// 离线全文搜索。
///
/// 当前实现：全量扫描 + 子串匹配（中文台词搜索不需要分词，
/// 个人离线库规模下毫秒级出结果）。
/// 【Rust 升级点】若离线库变大，可把 [search]/[extractSearchablePosts]
/// 换成 flutter_rust_bridge + tantivy 的实现，对外接口保持不变。
class OfflineSearchService {
  static const int maxHits = 200;
  static const int snippetRadius = 30;

  Future<List<OfflineSearchHit>> search(String query) async {
    final trimmed = query.trim();
    final q = trimmed.toLowerCase();
    if (q.isEmpty) return [];

    final hits = <OfflineSearchHit>[];
    final threads = await OfflineManager().getOfflineList();
    for (final meta in threads) {
      final tid = meta['tid']?.toString() ?? '';
      final subject = meta['subject']?.toString() ?? '';
      final maxPage = (meta['max_page'] as num?)?.toInt() ?? 0;
      // 标题/作者命中：直达首楼
      final metaHit = matchThreadMeta(
        tid,
        subject,
        meta['author']?.toString() ?? '',
        meta['author_id']?.toString() ?? '',
        trimmed,
      );
      if (metaHit != null) {
        hits.add(metaHit);
        if (hits.length >= maxHits) return hits;
      }
      for (var page = 1; page <= maxPage; page++) {
        final json = await OfflineManager().readPage(tid, page);
        if (json == null) continue;
        for (final post in extractSearchablePosts(tid, subject, page, json)) {
          final start = post.text.toLowerCase().indexOf(q);
          if (start < 0) continue;
          hits.add(OfflineSearchHit(
            tid: post.tid,
            subject: post.subject,
            author: post.author,
            authorId: post.authorId,
            pid: post.pid,
            floor: post.floor,
            page: post.page,
            text: post.text,
            matchStart: start,
            matchLength: trimmed.length,
          ));
          if (hits.length >= maxHits) return hits;
        }
      }
    }
    return hits;
  }

  /// 帖子元信息（标题/作者）匹配：命中时返回直达首楼的标题命中。
  static OfflineSearchHit? matchThreadMeta(
      String tid, String subject, String author, String authorId, String query) {
    final text = '$subject · 作者：$author';
    final start = text.toLowerCase().indexOf(query.toLowerCase());
    if (start < 0) return null;
    return OfflineSearchHit(
      tid: tid,
      subject: subject,
      author: author,
      authorId: authorId,
      pid: '',
      floor: 1,
      page: 1,
      text: text,
      matchStart: start,
      matchLength: query.length,
      isTitleHit: true,
    );
  }

  /// 命中处前后各留 [snippetRadius] 字的上下文片段。
  static String buildSnippet(String text, int start, int length) {
    final from = (start - snippetRadius).clamp(0, text.length);
    final to = (start + length + snippetRadius).clamp(0, text.length);
    return (from > 0 ? '…' : '') +
        text.substring(from, to) +
        (to < text.length ? '…' : '');
  }
}
