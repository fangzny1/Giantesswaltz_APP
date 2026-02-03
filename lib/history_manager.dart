import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryItem {
  final String tid;
  final String subject;
  final String author;
  final int timestamp;

  HistoryItem({
    required this.tid,
    required this.subject,
    required this.author,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'tid': tid,
    'subject': subject,
    'author': author,
    'timestamp': timestamp,
  };
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    tid: json['tid'],
    subject: json['subject'],
    author: json['author'],
    timestamp: json['timestamp'],
  );
}

class HistoryManager {
  static const String _key = 'local_history_v2';

  // 保存记录 (自动排重 + 30天清理)
  static Future<void> addHistory(
    String tid,
    String subject,
    String author,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList(_key) ?? [];

    List<HistoryItem> list = rawList
        .map((e) => HistoryItem.fromJson(jsonDecode(e)))
        .toList();

    // 1. 移除旧的相同 TID
    list.removeWhere((item) => item.tid == tid);

    // 2. 插入最前面
    list.insert(
      0,
      HistoryItem(
        tid: tid,
        subject: subject,
        author: author,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // 3. 清理：仅保留最近 30 天 且 最多 200 条
    final thirtyDaysAgo = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    list = list
        .where((item) => item.timestamp > thirtyDaysAgo)
        .take(200)
        .toList();

    await prefs.setStringList(
      _key,
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<List<HistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList(_key) ?? [];
    return rawList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
  }

  static Future<void> deleteItems(Set<String> tids) async {
    final prefs = await SharedPreferences.getInstance();
    List<HistoryItem> list = await getHistory();
    list.removeWhere((item) => tids.contains(item.tid));
    await prefs.setStringList(
      _key,
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
