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
