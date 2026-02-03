// lib/forum_model.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

const String kBaseUrl = 'https://giantesswaltz.org/';
const String kCookieDomain = 'giantesswaltz.org';
const String kBaseDomain = kCookieDomain;

String mergeCookies(String currentCookie, List<String> newCookieHeaders) {
  final Map<String, String> finalKv = {};

  void parseAndAdd(String raw) {
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || !trimmed.contains('=')) continue;
      final eq = trimmed.indexOf('=');
      final k = trimmed.substring(0, eq).trim();
      final v = trimmed.substring(eq + 1).trim();
      if (k.isNotEmpty &&
          !k.toLowerCase().contains('path') &&
          !k.toLowerCase().contains('domain')) {
        finalKv[k] = v;
      }
    }
  }

  parseAndAdd(currentCookie);

  for (final header in newCookieHeaders) {
    String cookiePart = header.split(';')[0];
    parseAndAdd(cookiePart);
  }

  return finalKv.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

class Category {
  final String fid;
  final String name;
  final List<String> forumIds;

  Category({required this.fid, required this.name, required this.forumIds});

  factory Category.fromJson(Map<String, dynamic> json) {
    // Discuz 的 forums 字段有时候是 List，有时候是 null
    List<String> fids = [];
    if (json['forums'] != null && json['forums'] is List) {
      fids = List<String>.from(json['forums']);
    }

    return Category(
      fid: json['fid']?.toString() ?? '',
      name: json['name']?.toString() ?? '', // 强制转 String，防止 null
      forumIds: fids,
    );
  }
}

class Forum {
  final String fid;
  final String name;
  final String threads;
  final String posts;
  final String description;
  final String todayposts;
  final String? icon;
  Forum({
    required this.icon,
    required this.fid,
    required this.name,
    required this.threads,
    required this.posts,
    required this.description,
    required this.todayposts,
  });

  factory Forum.fromJson(Map<String, dynamic> json) {
    return Forum(
      fid: json['fid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      icon: json['icon'] as String?,
      threads: json['threads']?.toString() ?? '0', // 即使是 int 也能转 string
      posts: json['posts']?.toString() ?? '0',
      description: json['description']?.toString() ?? '',
      todayposts: json['todayposts']?.toString() ?? '0',
    );
  }
}

class Thread {
  final String tid;
  final String subject;
  final String author;
  final String replies;
  final String views;
  final String readperm;

  Thread({
    required this.tid,
    required this.subject,
    required this.author,
    required this.replies,
    required this.views,
    required this.readperm,
  });

  factory Thread.fromJson(Map<String, dynamic> json) {
    return Thread(
      tid: json['tid']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '无标题',
      author: json['author']?.toString() ?? '匿名',
      replies: json['replies']?.toString() ?? '0',
      views: json['views']?.toString() ?? '0',
      readperm: json['readperm']?.toString() ?? '0',
    );
  }
}

class PostInfo {
  final String pid;
  final String author;
  final String avatarUrl;
  final String time;
  final String contentHtml;

  PostInfo({
    required this.pid,
    required this.author,
    required this.avatarUrl,
    required this.time,
    required this.contentHtml,
  });
}

class BookmarkItem {
  final String tid;
  final String subject;
  final String author;
  final String authorId;
  final int page;
  final String savedTime;
  final bool isNovelMode;
  final String? targetPid;
  final String? targetFloor;

  BookmarkItem({
    required this.tid,
    required this.subject,
    required this.author,
    required this.authorId,
    required this.page,
    required this.savedTime,
    this.isNovelMode = false,
    this.targetPid,
    this.targetFloor,
  });

  Map<String, dynamic> toJson() => {
    'tid': tid,
    'subject': subject,
    'author': author,
    'authorId': authorId,
    'page': page,
    'savedTime': savedTime,
    'isNovelMode': isNovelMode,
    'targetPid': targetPid,
    'targetFloor': targetFloor,
  };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      tid: json['tid'] ?? "",
      subject: json['subject'] ?? "",
      author: json['author'] ?? "",
      authorId: json['authorId'] ?? "",
      page: json['page'] ?? 1,
      savedTime: json['savedTime'] ?? "",
      isNovelMode: json['isNovelMode'] ?? false,
      targetPid: json['targetPid'],
      targetFloor: json['targetFloor'],
    );
  }
}
// lib/forum_model.dart 的最底部

// 【核心修复】定义一个全局单例的缓存管理器
// 这样我们在 ThreadDetailPage 里用它存图，在 ProfilePage 里也能调用它清缓存
final globalImageCache = CacheManager(
  Config(
    'gn_forum_imageCache_v2', // 换个名字，避免和旧的冲突
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 1000,
  ),
);
