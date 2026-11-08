import 'dart:io';

import 'package:flutter/material.dart';

import 'forum_extras_api.dart';
import 'main.dart';
import 'thread_detail_page.dart';

/// 发现页：热帖榜（API）+ 新帖导读（网页解析）。
class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  List<HotThread> _hot = [];
  List<GuideEntry> _guide = [];
  bool _hotLoading = true;
  bool _guideLoading = true;
  String _filter = '全部';

  static const _filters = ['全部', '精华', '今日', '含图', '长帖'];

  @override
  void initState() {
    super.initState();
    _loadHot();
    _loadGuide();
  }

  Future<void> _loadHot() async {
    setState(() => _hotLoading = true);
    try {
      final hot = await fetchHotThreads();
      if (mounted) setState(() => _hot = hot);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _hotLoading = false);
    }
  }

  Future<void> _loadGuide() async {
    try {
      final guide = await fetchGuideNew();
      if (mounted) setState(() => _guide = guide);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _guideLoading = false);
    }
  }

  List<HotThread> get _filteredHot {
    switch (_filter) {
      case '精华':
        return _hot.where((t) => t.digest).toList();
      case '今日':
        return _hot.where((t) => t.istoday).toList();
      case '含图':
        return _hot.where((t) => t.hasAttachment).toList();
      case '长帖':
        return _hot.where((t) => t.maxPosition >= 100).toList();
      default:
        return _hot;
    }
  }

  void _openThread(String tid, String subject) {
    adaptivePush(
      context,
      ThreadDetailPage(tid: tid, subject: subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AnimatedBuilder(
        animation:
            Listenable.merge([customWallpaperPath, transparentBarsEnabled]),
        builder: (context, _) {
          final wallpaperPath = customWallpaperPath.value;
          final useTransparent =
              wallpaperPath != null && transparentBarsEnabled.value;
          return Scaffold(
            backgroundColor: wallpaperPath != null
                ? (useTransparent
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surfaceContainerHighest)
                : null,
            extendBodyBehindAppBar: useTransparent,
            appBar: AppBar(
              title: const Text("发现"),
              backgroundColor: useTransparent ? Colors.transparent : null,
              elevation: useTransparent ? 0 : null,
              bottom: const TabBar(tabs: [
                Tab(text: "热帖榜"),
                Tab(text: "新帖导读"),
              ]),
            ),
            body: Stack(
              children: [
                if (wallpaperPath != null)
                  Positioned.fill(
                    child: Image.file(
                      File(wallpaperPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                if (wallpaperPath != null)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.6)
                          : Colors.white.withOpacity(0.3),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: TabBarView(children: [
                      _buildHotTab(),
                      _buildGuideTab(),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHotTab() {
    if (_hotLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadHot,
      child: Column(children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(f),
                    selected: _filter == f,
                    // 【修复】未选中芯片文字用高对比色：白天黑87 / 夜间白70
                    labelStyle: TextStyle(
                      color: _filter == f
                          ? Theme.of(context).colorScheme.primary
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.black87),
                    ),
                    selectedColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.4),
                    ),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredHot.length,
            itemBuilder: (context, i) {
              final t = _filteredHot[i];
              return _cardWrap(
                context,
                ListTile(
                title: Text(t.subject,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  "${t.author} · ${t.replies} 回复 · ${t.views} 浏览"
                  "${t.maxPosition > 0 ? ' · ${t.maxPosition} 楼' : ''}",
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (t.digest)
                      _badge("精华", Colors.orange),
                    if (t.istoday)
                      _badge("今日", Colors.teal),
                    if (t.hasAttachment)
                      _badge("图", Colors.blueGrey),
                  ],
                ),
                  onTap: () => _openThread(t.tid, t.subject),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );

  Widget _buildGuideTab() {
    if (_guideLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadGuide,
      child: ListView.builder(
        itemCount: _guide.length,
        itemBuilder: (context, i) {
          final g = _guide[i];
          return _cardWrap(
            context,
            ListTile(
            title: Text(g.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              "${g.author} · ${g.time}"
              "${g.views > 0 ? ' · ${g.views} 浏览' : ''}"
              "${g.replies > 0 ? ' · ${g.replies} 回复' : ''}",
              style: const TextStyle(fontSize: 12),
            ),
              onTap: () => _openThread(g.tid, g.subject),
            ),
          );
        },
      ),
    );
  }

  /// thread_list_page 同款卡片：壁纸下用 forumCardOpacity 半透明
  Widget _cardWrap(BuildContext context, Widget child) {
    final wallpaperPath = customWallpaperPath.value;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: wallpaperPath != null
          ? Theme.of(context).colorScheme.surfaceContainerLow
              .withOpacity(forumCardOpacity.value)
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: child,
    );
  }
}
