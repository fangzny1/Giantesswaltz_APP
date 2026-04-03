// lib/forum_model.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart'; // 引入这个以使用 ValueNotifier
// const String currentBaseUrl.value = 'https://giantesswaltz.org/';
// const String kCookieDomain = 'giantesswaltz.org';
// const String kBaseDomain = kCookieDomain;
//临时删除旧的常量
import 'package:flutter_cache_manager/src/web/file_service.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. 全局缓存管理器（改为 late 动态初始化）
late CacheManager globalImageCache;

// 【优化】解除图片龟速限制，大幅提升多图加载速度
class PoliteFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    // 只有本站图片做极微小的 50ms 延迟，外链图片全速并发！
    if (url.contains('giantesswaltz.org') || url.contains('gtswaltz.org')) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return super.get(url, headers: headers);
  }
}

// 【修改】将原来的 const 替换为 ValueNotifier，默认是主站
final ValueNotifier<String> currentBaseUrl = ValueNotifier(
  'https://giantesswaltz.org/',
);

// 1. 定义一个带日志的下载服务
class DebugHttpFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    print("🌐 [Image Network] 正在请求图片: $url");
    print("headers: $headers"); // 看看 Cookie 和 Referer 到底带没带对

    final response = await super.get(url, headers: headers);

    // 检查返回的状态码
    print("📥 [Image Network] 服务器响应状态码: ${response.statusCode}");
    if (response.statusCode != 200) {
      print("🚨 [Image Network] 警告：服务器没给图，给了个错误！");
    }
    return response;
  }
}

// 辅助函数：获取当前域名 (去掉 https:// 和 /)
String get currentDomain => Uri.parse(currentBaseUrl.value).host;

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
  final String authorId;
  final String replies;
  final String views;
  final String readperm;
  final String lastpost;
  Thread({
    required this.tid,
    required this.subject,
    required this.author,
    required this.authorId, // 【修复点2】
    required this.replies,
    required this.views,
    required this.readperm,
    this.lastpost = "",
  });

  factory Thread.fromJson(Map<String, dynamic> json) {
    return Thread(
      tid: json['tid']?.toString() ?? '',
      // 【关键映射】API 返回的 JSON 键是全小写的 'authorid'，我们把它赋值给 authorId 变量
      authorId: json['authorid']?.toString() ?? '0',
      subject: json['subject']?.toString() ?? '无标题',
      author: json['author']?.toString() ?? '匿名',
      replies: json['replies']?.toString() ?? '0',
      views: json['views']?.toString() ?? '0',
      readperm: json['readperm']?.toString() ?? '0',
      lastpost: json['lastpost']?.toString() ?? "",
    );
  }
  // 【新增这个方法】用于缓存
  Map<String, dynamic> toJson() => {
    'tid': tid,
    'subject': subject,
    'author': author,
    'replies': replies,
    'lastpost': lastpost,
  };
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

// // 2. 自定义带超时拦截的 HTTP 客户端 (解决弱网无限转圈问题)
// class TimeoutHttpClient extends http.BaseClient {
//   final int timeoutSeconds;
//   final http.Client _inner = http.Client();

//   TimeoutHttpClient(this.timeoutSeconds);

//   @override
//   Future<http.StreamedResponse> send(http.BaseRequest request) {
//     // 强制设置超时时间，如果超时直接掐断，触发图片加载失败(进而显示重试按钮)
//     return _inner.send(request).timeout(Duration(seconds: timeoutSeconds));
//   }
// }

// 3. 初始化缓存引擎 (在 main.dart 启动时调用)
Future<void> initGlobalImageCache() async {
  final prefs = await SharedPreferences.getInstance();

  // 读取用户自定义设置 (默认值: 1000张图, 保留7天, 15秒超时)
  int maxObjects = prefs.getInt('cache_max_objects') ?? 1000;
  int staleDays = prefs.getInt('cache_stale_days') ?? 7;

  globalImageCache = CacheManager(
    Config(
      'gn_forum_imageCache_v5', // 升级到 v5 抛弃之前的旧账
      stalePeriod: Duration(days: staleDays),
      maxNrOfCacheObjects: maxObjects,
    ),
  );
}
