import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'forum_model.dart';
import 'http_service.dart';

/// 四类未读提醒计数（论坛每个移动端 API 响应都白送这个块）。
class NoticeCounts {
  final int newpush;
  final int newpm;
  final int newprompt;
  final int newmypost;

  const NoticeCounts({
    this.newpush = 0,
    this.newpm = 0,
    this.newprompt = 0,
    this.newmypost = 0,
  });

  int get total => newpush + newpm + newprompt + newmypost;
  bool get hasUnread => total > 0;
}

/// 纯解析：从任意移动端 API 响应的 Variables 提取 notice。
NoticeCounts parseNotice(dynamic variables) {
  try {
    final n = variables?['notice'];
    if (n is Map) {
      return NoticeCounts(
        newpush: int.tryParse(n['newpush']?.toString() ?? '') ?? 0,
        newpm: int.tryParse(n['newpm']?.toString() ?? '') ?? 0,
        newprompt: int.tryParse(n['newprompt']?.toString() ?? '') ?? 0,
        newmypost: int.tryParse(n['newmypost']?.toString() ?? '') ?? 0,
      );
    }
  } catch (_) {}
  return const NoticeCounts();
}

/// 全局未读计数（导航栏角标等订阅它）。
final ValueNotifier<NoticeCounts> globalNoticeCounts =
    ValueNotifier(const NoticeCounts());

/// 用最轻的 forumindex 响应刷新未读计数。
Future<void> refreshNoticeCounts() async {
  try {
    final raw = await HttpService()
        .getHtml('${currentBaseUrl.value}api/mobile/index.php?version=4&module=forumindex');
    final vars = _decodeApiJson(raw)?['Variables'];
    if (vars != null) globalNoticeCounts.value = parseNotice(vars);
  } catch (_) {}
}

Map<String, dynamic>? _decodeApiJson(String raw) {
  var s = raw.trim();
  if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s);
  try {
    return jsonDecode(s) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// 热帖（module=hotthread 数据条目）。
class HotThread {
  final String tid;
  final String subject;
  final String author;
  final String authorId;
  final int views;
  final int replies;
  final int maxPosition; // 总楼层
  final int heats;
  final bool digest; // 精华
  final bool hasAttachment;
  final bool istoday;
  final String lastposter;

  const HotThread({
    required this.tid,
    required this.subject,
    required this.author,
    required this.authorId,
    required this.views,
    required this.replies,
    required this.maxPosition,
    required this.heats,
    required this.digest,
    required this.hasAttachment,
    required this.istoday,
    required this.lastposter,
  });
}

/// 纯解析：module=hotthread 的 JSON。
List<HotThread> parseHotThreads(String json) {
  final vars = _decodeApiJson(json)?['Variables'];
  final rawList = vars?['data'];
  final items = rawList is List
      ? rawList
      : (rawList is Map ? rawList.values.toList() : const []);
  final out = <HotThread>[];
  for (final t in items) {
    try {
      out.add(HotThread(
        tid: t['tid']?.toString() ?? '',
        subject: t['subject']?.toString() ?? '',
        author: t['author']?.toString() ?? '',
        authorId: t['authorid']?.toString() ?? '',
        views: int.tryParse(t['views']?.toString() ?? '') ?? 0,
        replies: int.tryParse(t['replies']?.toString() ?? '') ?? 0,
        maxPosition: int.tryParse(t['maxposition']?.toString() ?? '') ?? 0,
        heats: int.tryParse(t['heats']?.toString() ?? '') ?? 0,
        digest: t['digest']?.toString() != '0' && t['digest'] != null,
        hasAttachment: t['attachment']?.toString() == '1',
        istoday: t['istoday']?.toString() == '1' || t['istoday'] == true,
        lastposter: t['lastposter']?.toString() ?? '',
      ));
    } catch (_) {}
  }
  return out;
}

/// 新帖导读条目（forum.php?mod=guide&view=new）。
class GuideEntry {
  final String tid;
  final String subject;
  final String author;
  final String time;
  final int views;
  final int replies;

  const GuideEntry({
    required this.tid,
    required this.subject,
    required this.author,
    required this.time,
    required this.views,
    required this.replies,
  });
}

/// 纯解析：新帖导读 HTML 的 normalthread 行。
List<GuideEntry> parseGuideNew(String html) {
  final marker = RegExp(r'normalthread_(\d+)');
  final ms = marker.allMatches(html).toList();
  final out = <GuideEntry>[];
  for (var i = 0; i < ms.length; i++) {
    final start = ms[i].end;
    final end =
        i + 1 < ms.length ? ms[i + 1].start : min(start + 3000, html.length);
    final row = html.substring(start, end);
    final title =
        RegExp(r'class="tit xst"[^>]*>([^<]+)</a>').firstMatch(row)?.group(1);
    if (title == null) continue;
    try {
      out.add(GuideEntry(
        tid: ms[i].group(1)!,
        subject: _decodeEntities(title.trim()),
        author: _decodeEntities(
            RegExp(r'class="aor">\s*<a[^>]*>([^<]+)</a>')
                    .firstMatch(row)
                    ?.group(1) ??
                ''),
        time: RegExp(r'title="(\d{4}-\d{1,2}-\d{1,2})"')
                .firstMatch(row)
                ?.group(1) ??
            '',
        views: int.tryParse(
                RegExp(r'class="vie">\s*(\d+)</em>').firstMatch(row)?.group(1) ??
                    '') ??
            0,
        replies: int.tryParse(
                RegExp(r'class="rey">\s*(\d+)</em>').firstMatch(row)?.group(1) ??
                    '') ??
            0,
      ));
    } catch (_) {}
  }
  return out;
}

/// 好友条目（module=friend）。
class FriendEntry {
  final String uid;
  final String username;
  final String avatar;

  const FriendEntry({required this.uid, required this.username, this.avatar = ''});
}

/// 纯解析：module=friend 的 JSON（对空列表/Map/List 三种形态容错）。
List<FriendEntry> parseFriends(String json) {
  final vars = _decodeApiJson(json)?['Variables'];
  final raw = vars?['list'];
  final items = raw is List
      ? raw
      : (raw is Map ? raw.values.toList() : const []);
  final out = <FriendEntry>[];
  for (final p in items) {
    if (p is! Map) continue;
    try {
      final uid = p['uid']?.toString() ?? '';
      final name =
          (p['username'] ?? p['name'] ?? '').toString();
      if (uid.isEmpty && name.isEmpty) continue;
      out.add(FriendEntry(
        uid: uid,
        username: name,
        avatar: (p['avatar'] ?? '').toString(),
      ));
    } catch (_) {}
  }
  return out;
}

/// 异步抓取：热帖 / 导读 / 好友。
Future<List<HotThread>> fetchHotThreads() async {
  final raw = await HttpService()
      .getHtml('${currentBaseUrl.value}api/mobile/index.php?version=4&module=hotthread');
  return parseHotThreads(raw);
}

Future<List<GuideEntry>> fetchGuideNew() async {
  final raw = await HttpService().getHtml(
      '${currentBaseUrl.value}forum.php?mod=guide&view=new&mobile=no');
  return parseGuideNew(raw);
}

Future<List<FriendEntry>> fetchFriends(String uid) async {
  // uid 为空 = 查自己（论坛 API 原生支持）
  final raw = await HttpService().getHtml(
      '${currentBaseUrl.value}api/mobile/index.php?version=4&module=friend'
      '${uid.isEmpty ? '' : '&uid=$uid'}');
  return parseFriends(raw);
}

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"');

/// 导航栏/入口用的小角标。
class NoticeBadge extends StatelessWidget {
  final Widget child;
  const NoticeBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NoticeCounts>(
      valueListenable: globalNoticeCounts,
      builder: (context, counts, _) => Badge(
        isLabelVisible: counts.total > 0,
        label: Text(counts.total > 99 ? '99+' : '${counts.total}'),
        child: child,
      ),
    );
  }
}
