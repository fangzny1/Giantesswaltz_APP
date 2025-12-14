// lib/forum_model.dart
class Category {
  final String fid;
  final String name;
  final List<String> forumIds;

  Category({required this.fid, required this.name, required this.forumIds});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      fid: json['fid']?.toString() ?? '',
      name: json['name'] ?? '',
      forumIds: json['forums'] != null ? List<String>.from(json['forums']) : [],
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

  Forum({
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
      name: json['name'] ?? '',
      threads: json['threads']?.toString() ?? '0',
      posts: json['posts']?.toString() ?? '0',
      description: json['description'] ?? '',
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
      subject: json['subject'] ?? '无标题',
      author: json['author'] ?? '匿名',
      replies: json['replies']?.toString() ?? '0',
      views: json['views']?.toString() ?? '0',
      readperm: json['readperm']?.toString() ?? '0',
    );
  }
}

// 帖子详情里的每一楼（包括楼主和回复）
class PostInfo {
  final String pid;
  final String author;
  final String avatarUrl;
  final String time;
  final String contentHtml; // 正文 HTML 内容

  PostInfo({
    required this.pid,
    required this.author,
    required this.avatarUrl,
    required this.time,
    required this.contentHtml,
  });
}
// ... (保留 Category, Forum, Thread, PostInfo)

class BookmarkItem {
  final String tid;
  final String subject;
  final String author;
  final int page; // 看到第几页了
  final String savedTime; // 保存时间
  final String authorId; // 【新增】保存楼主UID
  final bool isNovelMode;
  BookmarkItem({
    required this.tid,
    required this.subject,
    required this.author,
    required this.authorId,
    required this.page,
    required this.savedTime,
    this.isNovelMode = false,
  });

  // 转 JSON 存本地
  Map<String, dynamic> toJson() => {
    'tid': tid,
    'subject': subject,
    'author': author,
    'page': page,

    'savedTime': savedTime,
    'isNovelMode': isNovelMode,
  };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      tid: json['tid'],
      subject: json['subject'],
      author: json['author'],
      authorId: json['authorId'] ?? "", // 【新增】兼容旧数据
      page: json['page'] ?? 1,
      savedTime: json['savedTime'],
      isNovelMode: json['isNovelMode'] ?? false, // 读取状态，兼容旧数据
    );
  }
}
