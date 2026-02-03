import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'forum_model.dart';
import 'thread_detail_page.dart';
import 'dart:io';
import 'main.dart'; // For customWallpaperPath and currentTheme

class BookmarkPage extends StatefulWidget {
  const BookmarkPage({super.key});

  @override
  State<BookmarkPage> createState() => _BookmarkPageState();
}

class _BookmarkPageState extends State<BookmarkPage> {
  List<BookmarkItem> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('local_bookmarks');
    if (jsonStr != null) {
      List<dynamic> list = jsonDecode(jsonStr);
      setState(() {
        _bookmarks = list.map((e) => BookmarkItem.fromJson(e)).toList();
      });
    }
  }

  Future<void> _deleteBookmark(int index) async {
    setState(() {
      _bookmarks.removeAt(index);
    });
    final prefs = await SharedPreferences.getInstance();
    String jsonStr = jsonEncode(_bookmarks.map((e) => e.toJson()).toList());
    await prefs.setString('local_bookmarks', jsonStr);
  }

  // ... 前面的代码不变

  // 【新增】删除确认弹窗
  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("删除书签"),
          content: Text("确定要删除这条阅读记录吗？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () {
                _deleteBookmark(index); // 调用原来的删除逻辑
                Navigator.pop(ctx);
              },
              child: const Text("删除", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        bool useTransparent =
            wallpaperPath != null && transparentBarsEnabled.value;
        return Scaffold(
          backgroundColor: useTransparent ? Colors.transparent : null,
          extendBodyBehindAppBar: useTransparent,
          appBar: AppBar(
            title: const Text("阅读书签"),
            backgroundColor: useTransparent ? Colors.transparent : null,
            elevation: useTransparent ? 0 : null,
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
                        color: isDark
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.3),
                      );
                    },
                  ),
                ),
              SafeArea(
                child: _bookmarks.isEmpty
                    ? const Center(
                        child: Text(
                          "暂无书签",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 10),
                        itemCount: _bookmarks.length,
                        itemBuilder: (context, index) {
                          final item = _bookmarks[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            elevation: 0,
                            color: wallpaperPath != null
                                ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withOpacity(0.7)
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              // 【点击】跳转
                              onTap: () {
                                String? targetFloor;
                                if (item.savedTime.contains("读至 ")) {
                                  targetFloor = item.savedTime
                                      .split("读至 ")
                                      .last;
                                }

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ThreadDetailPage(
                                      tid: item.tid,
                                      subject: item.subject,
                                      initialPage: item.page,
                                      initialNovelMode: item.isNovelMode,
                                      initialAuthorId: item.authorId,
                                      initialTargetFloor:
                                          item.targetFloor ?? targetFloor,
                                      initialTargetPid: item.targetPid,
                                    ),
                                  ),
                                );
                              },
                              // 【长按】删除
                              onLongPress: () => _confirmDelete(index),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          item.isNovelMode
                                              ? Icons.auto_stories
                                              : Icons.article,
                                          color: item.isNovelMode
                                              ? Colors.purpleAccent
                                              : Colors.blueGrey,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.subject,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "第 ${item.page} 页 · ${item.author}",
                                          style: TextStyle(
                                            color: Theme.of(context).hintColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                        // 这里显示我们刚才保存的 "12-14 · 读至 25楼"
                                        Text(
                                          item.savedTime,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).primaryColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
