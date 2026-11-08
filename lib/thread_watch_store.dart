import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'http_service.dart';
import 'forum_model.dart';

/// 追更（订阅）的帖子。
class WatchEntry {
  final String tid;
  final String subject;
  final int seenMaxPosition; // 已读到的楼层
  final int latestMaxPosition; // 已知的最新楼层
  final int lastChecked; // 上次检查时间

  const WatchEntry({
    required this.tid,
    required this.subject,
    this.seenMaxPosition = 0,
    this.latestMaxPosition = 0,
    this.lastChecked = 0,
  });

  int get newFloors => computeNewFloors(this);

  WatchEntry copyWith({
    int? seenMaxPosition,
    int? latestMaxPosition,
    int? lastChecked,
  }) =>
      WatchEntry(
        tid: tid,
        subject: subject,
        seenMaxPosition: seenMaxPosition ?? this.seenMaxPosition,
        latestMaxPosition: latestMaxPosition ?? this.latestMaxPosition,
        lastChecked: lastChecked ?? this.lastChecked,
      );
}

/// 纯逻辑：新楼层数（永不为负）。
int computeNewFloors(WatchEntry e) {
  final diff = e.latestMaxPosition - e.seenMaxPosition;
  return diff > 0 ? diff : 0;
}

/// 追更存储（SharedPreferences JSON）。
class ThreadWatchStore {
  static const String _key = 'thread_watch_v1';

  static Future<List<WatchEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.values
          .whereType<Map>()
          .map((m) => WatchEntry(
                tid: m['tid']?.toString() ?? '',
                subject: m['subject']?.toString() ?? '',
                seenMaxPosition:
                    int.tryParse(m['seen']?.toString() ?? '') ?? 0,
                latestMaxPosition:
                    int.tryParse(m['latest']?.toString() ?? '') ?? 0,
                lastChecked:
                    int.tryParse(m['checked']?.toString() ?? '') ?? 0,
              ))
          .where((e) => e.tid.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<WatchEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final e in entries)
        e.tid: {
          'tid': e.tid,
          'subject': e.subject,
          'seen': e.seenMaxPosition,
          'latest': e.latestMaxPosition,
          'checked': e.lastChecked,
        },
    };
    await prefs.setString(_key, jsonEncode(map));
  }

  static Future<bool> isWatched(String tid) async =>
      (await load()).any((e) => e.tid == tid);

  /// 追更/取消追更，返回当前是否已追。
  static Future<bool> toggle(String tid, String subject) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.tid == tid);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(WatchEntry(tid: tid, subject: subject));
    }
    await _save(list);
    return idx < 0;
  }

  static Future<void> remove(String tid) async {
    final list = await load()..removeWhere((e) => e.tid == tid);
    await _save(list);
  }

  /// 标记已读到 [position]（默认最新）。
  static Future<void> markSeen(String tid, [int? position]) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.tid == tid);
    if (idx < 0) return;
    final e = list[idx];
    list[idx] = e.copyWith(
      seenMaxPosition: position ?? e.latestMaxPosition,
      lastChecked: DateTime.now().millisecondsSinceEpoch,
    );
    await _save(list);
  }

  static Future<void> updateLatest(String tid, int position) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.tid == tid);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(
      latestMaxPosition: position,
      lastChecked: DateTime.now().millisecondsSinceEpoch,
    );
    await _save(list);
  }
}

/// 检查一批帖子的最新总楼层（module=viewthread 的 thread.maxposition）。
Future<Map<String, int>> fetchMaxPositions(Iterable<String> tids) async {
  final result = <String, int>{};
  for (final tid in tids) {
    try {
      final raw = await HttpService().getHtml(
          '${currentBaseUrl.value}api/mobile/index.php?version=4&module=viewthread&tid=$tid&page=1');
      var s = raw.trim();
      if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s);
      final thread = jsonDecode(s)?['Variables']?['thread'];
      final pos = int.tryParse(thread?['maxposition']?.toString() ?? '');
      if (pos != null) result[tid] = pos;
    } catch (_) {}
  }
  return result;
}
