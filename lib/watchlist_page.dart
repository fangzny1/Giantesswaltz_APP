import 'dart:io';

import 'package:flutter/material.dart';
import 'main.dart';

import 'thread_detail_page.dart';
import 'thread_watch_store.dart';

/// 追更（订阅）列表：看谁更新了新楼层，直达新楼。
class WatchListPage extends StatefulWidget {
  const WatchListPage({super.key});

  @override
  State<WatchListPage> createState() => _WatchListPageState();
}

class _WatchListPageState extends State<WatchListPage> {
  List<WatchEntry> _entries = [];
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ThreadWatchStore.load();
    if (mounted) {
      setState(() {
        _entries = list;
        _loading = false;
      });
    }
  }

  Future<void> _checkUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final positions = await fetchMaxPositions(_entries.map((e) => e.tid));
      for (final tid in positions.keys) {
        await ThreadWatchStore.updateLatest(tid, positions[tid]!);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _open(WatchEntry e) {
    // 直达上次读到的下一楼（若已读完则进首楼）；打开即视为已读
    final target = e.seenMaxPosition > 0 && e.newFloors > 0
        ? e.seenMaxPosition + 1
        : null;
    ThreadWatchStore.markSeen(e.tid).then((_) => _load());
    adaptivePush(
      context,
      ThreadDetailPage(
        tid: e.tid,
        subject: e.subject,
        initialTargetFloor: target?.toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
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
            title: const Text("追更订阅"),
            backgroundColor: useTransparent ? Colors.transparent : null,
            elevation: useTransparent ? 0 : null,
            actions: [
              IconButton(
                tooltip: "检查更新",
                icon: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _checking ? null : _checkUpdates,
              ),
            ],
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
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _entries.isEmpty
                          ? const Center(
                              child: Text(
                                "还没有追更的帖子\n在帖子菜单里点「追更」就能订阅更新",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _checkUpdates,
                              child: ListView.builder(
                                itemCount: _entries.length,
                                itemBuilder: (context, i) {
                                  final e = _entries[i];
                                  final n = e.newFloors;
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: n > 0
                                          ? Text("$n",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold))
                                          : const Icon(Icons.bookmark_added,
                                              size: 18),
                                    ),
                                    title: Text(e.subject,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      n > 0
                                          ? "更新了 $n 楼 · 点击直达新楼"
                                          : "已追平 · 共 ${e.latestMaxPosition} 楼",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: n > 0
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Colors.grey,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await ThreadWatchStore.remove(e.tid);
                                        await _load();
                                      },
                                    ),
                                    onTap: () => _open(e),
                                  );
                                },
                              ),
                            ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
