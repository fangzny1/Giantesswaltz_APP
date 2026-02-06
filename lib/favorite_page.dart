import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'login_page.dart';
import 'thread_detail_page.dart';
import 'forum_model.dart';
import 'dart:io';
import 'main.dart'; // 用于访问 customWallpaperPath 和 currentTheme

// 简单的收藏模型
class FavoriteItem {
  final String tid;
  final String title;
  final String description;
  final String favid; // 新增 favid

  FavoriteItem({
    required this.tid,
    required this.title,
    required this.description,
    required this.favid,
  });
}

class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  late final WebViewController _hiddenController;
  List<FavoriteItem> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // 如果是列表页，解析
            if (url.contains("do=favorite")) {
              _parseFavorites();
            }
            // 如果是删除确认页，自动点击确定
            else if (url.contains("op=delete") && url.contains("ac=favorite")) {
              _hiddenController.runJavaScript(
                "var btn = document.querySelector('button[name=\"deletesubmitbtn\"]'); if(btn) btn.click();",
              );
              // 删除后刷新列表
              Future.delayed(const Duration(seconds: 1), () {
                _loadFavorites();
              });
            }
          },
        ),
      );

    _loadFavorites();
  }

  void _loadFavorites() {
    setState(() {
      _isLoading = true;
    });
    _hiddenController.loadRequest(
      Uri.parse(
        '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me&mobile=no',
      ),
    );
  }

  Future<void> _parseFavorites() async {
    try {
      final String rawHtml =
          await _hiddenController.runJavaScriptReturningResult(
                "document.documentElement.outerHTML",
              )
              as String;

      String cleanHtml = rawHtml;
      if (cleanHtml.startsWith('"'))
        cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
      cleanHtml = cleanHtml
          .replaceAll('\\u003C', '<')
          .replaceAll('\\"', '"')
          .replaceAll('\\\\', '\\');

      var document = html_parser.parse(cleanHtml);
      List<FavoriteItem> newList = [];

      // Discuz 收藏列表通常在 ul#favorite_ul li 里面
      var items = document.querySelectorAll('ul[id="favorite_ul"] li');

      for (var item in items) {
        try {
          // 提取标题链接
          var link = item.querySelector('a[href*="tid="]');
          if (link == null) continue;

          String title = link.text.trim();
          String href = link.attributes['href'] ?? "";
          RegExp tidReg = RegExp(r'tid=(\d+)');
          String tid = tidReg.firstMatch(href)?.group(1) ?? "";

          // 提取描述 (收藏时写的备注)
          String desc = item.querySelector('.xg1')?.text ?? "";

          // 提取 favid
          String favid = "";
          var delLink = item.querySelector('a[href*="op=delete"]');
          if (delLink != null) {
            String delHref = delLink.attributes['href'] ?? "";
            RegExp favidReg = RegExp(r'favid=(\d+)');
            favid = favidReg.firstMatch(delHref)?.group(1) ?? "";
          }

          if (tid.isNotEmpty) {
            newList.add(
              FavoriteItem(
                tid: tid,
                title: title,
                description: desc,
                favid: favid,
              ),
            );
          }
        } catch (e) {
          continue;
        }
      }

      if (mounted) {
        setState(() {
          _favorites = newList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  void _showDeleteConfirmDialog(String favid, String title) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("取消收藏"),
          content: Text("确定要取消收藏“$title”吗？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("再想想"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteFavorite(favid);
              },
              child: const Text("确定取消", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _deleteFavorite(String favid) {
    if (favid.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));
    // 构造删除链接
    String url =
        "${currentBaseUrl.value}home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&type=all";
    _hiddenController.loadRequest(Uri.parse(url));
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
            title: const Text("我的收藏"),
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
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _favorites.isEmpty
                    ? const Center(child: Text("暂无收藏"))
                    : ListView.builder(
                        itemCount: _favorites.length,
                        itemBuilder: (context, index) {
                          final fav = _favorites[index];
                          return Card(
                            color: wallpaperPath != null
                                ? Theme.of(context).cardColor.withOpacity(0.7)
                                : null,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            elevation: wallpaperPath != null ? 0 : 1,
                            child: ListTile(
                              leading: const Icon(
                                Icons.star,
                                color: Colors.orange,
                              ),
                              title: Text(
                                fav.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: fav.description.isNotEmpty
                                  ? Text(fav.description)
                                  : null,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ThreadDetailPage(
                                      tid: fav.tid,
                                      subject: fav.title,
                                    ),
                                  ),
                                );
                              },
                              onLongPress: () {
                                if (fav.favid.isNotEmpty) {
                                  _showDeleteConfirmDialog(
                                    fav.favid,
                                    fav.title,
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("无法获取收藏ID，暂不能删除"),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
              SizedBox(
                height: 0,
                width: 0,
                child: WebViewWidget(controller: _hiddenController),
              ),
            ],
          ),
        );
      },
    );
  }
}
