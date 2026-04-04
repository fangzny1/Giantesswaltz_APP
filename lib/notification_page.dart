import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/http_service.dart';
import 'package:giantesswaltz_app/thread_detail_page.dart';
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import 'dart:io';
import 'forum_model.dart';
import 'main.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 提醒数据
  List<dynamic> _notices = [];
  bool _isNoticeLoading = true;

  // 我的主题数据
  List<Thread> _myThreads = [];
  bool _isThreadLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchNotices();
    _fetchMyThreads();
  }

  Future<void> _fetchNotices() async {
    final String url =
        '${currentBaseUrl.value}api/mobile/index.php?version=4&module=mynotelist';
    try {
      String jsonStr = await HttpService().getHtml(url);
      if (jsonStr.startsWith('"')) jsonStr = jsonDecode(jsonStr);
      final data = jsonDecode(jsonStr);
      setState(() {
        _notices = data['Variables']['list'] ?? [];
        _isNoticeLoading = false;
      });
    } catch (_) {
      setState(() => _isNoticeLoading = false);
    }
  }

  Future<void> _fetchMyThreads() async {
    final String url =
        '${currentBaseUrl.value}api/mobile/index.php?version=4&module=mythread';
    try {
      String jsonStr = await HttpService().getHtml(url);
      if (jsonStr.startsWith('"')) jsonStr = jsonDecode(jsonStr);
      final data = jsonDecode(jsonStr);
      final List raw = data['Variables']['data'] ?? [];
      setState(() {
        _myThreads = raw.map((e) => Thread.fromJson(e)).toList();
        _isThreadLoading = false;
      });
    } catch (_) {
      setState(() => _isThreadLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Scaffold(
          // 这里的背景色逻辑要和 main.dart 一致
          backgroundColor: wallpaperPath != null
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(1)
              : null,
          appBar: AppBar(
            backgroundColor: wallpaperPath != null
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(1)
                : null,
            title: const Text("个人消息中心"),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: "提醒消息"),
                Tab(text: "我发表的"),
              ],
            ),
          ),
          body: Stack(
            children: [
              // 1. 壁纸背景
              if (wallpaperPath != null)
                Positioned.fill(
                  child: Image.file(File(wallpaperPath), fit: BoxFit.cover),
                ),

              // 2. 【核心修复】自适应遮罩层 (与 main.dart 同步)
              if (wallpaperPath != null)
                Positioned.fill(
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: currentTheme,
                    builder: (context, mode, _) {
                      bool isDark = mode == ThemeMode.dark;
                      if (mode == ThemeMode.system) {
                        isDark =
                            MediaQuery.of(context).platformBrightness ==
                            Brightness.dark;
                      }
                      return Container(
                        // 白天用白罩，晚上用黑罩
                        color: isDark
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.3),
                      );
                    },
                  ),
                ),

              // 3. 内容层
              TabBarView(
                controller: _tabController,
                children: [
                  _buildNoticeList(wallpaperPath),
                  _buildThreadList(wallpaperPath),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoticeList(String? wallpaperPath) {
    if (_isNoticeLoading)
      return const Center(child: CircularProgressIndicator());
    if (_notices.isEmpty)
      return const Center(
        child: Text("暂无提醒", style: TextStyle(color: Colors.grey)),
      );

    return ListView.builder(
      itemCount: _notices.length,
      itemBuilder: (c, i) {
        final item = _notices[i];
        final noteVar = item['notevar'];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          // 【核心修复】卡片颜色不要写死 white，要随主题变化
          color: wallpaperPath != null
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(0.7)
              : null,
          elevation: 0,
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(
                "${currentBaseUrl.value}uc_server/avatar.php?uid=${item['authorid']}&size=small",
              ),
            ),
            title: Text(
              html_parser.parseFragment(item['note']).text ?? "",
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              DateTime.fromMillisecondsSinceEpoch(
                int.parse(item['dateline']) * 1000,
              ).toString().substring(0, 16),
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () {
              if (noteVar != null) {
                adaptivePush(
                  context,
                  ThreadDetailPage(
                    tid: noteVar['tid'].toString(),
                    subject: noteVar['subject'] ?? "查看帖子",
                    initialTargetPid: noteVar['pid']?.toString(),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildThreadList(String? wallpaperPath) {
    if (_isThreadLoading)
      return const Center(child: CircularProgressIndicator());
    if (_myThreads.isEmpty)
      return const Center(
        child: Text("尚未发表帖子", style: TextStyle(color: Colors.grey)),
      );

    return ListView.builder(
      itemCount: _myThreads.length,
      itemBuilder: (c, i) {
        final t = _myThreads[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          // 同上：自适应卡片颜色
          color: wallpaperPath != null
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(0.7)
              : null,
          elevation: 0,
          child: ListTile(
            title: Text(
              t.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text("回复: ${t.replies} / 阅读: ${t.views}"),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => adaptivePush(
              context,
              ThreadDetailPage(tid: t.tid, subject: t.subject),
            ),
          ),
        );
      },
    );
  }
}
