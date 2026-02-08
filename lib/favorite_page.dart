import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'thread_detail_page.dart';
import 'forum_model.dart';
import 'dart:io';
import 'login_page.dart'; // 引入 kUserAgent
import 'main.dart'; // 用于访问 customWallpaperPath 和 currentTheme

class FavoriteItem {
  final String tid;
  final String title;
  final String description;
  final String favid;

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
  bool _isBlockedByCloudflare = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  // 【核心修复】初始化 WebView 并强力注入 Cookie
  Future<void> _initWebView() async {
    // 1. 获取本地 Cookie
    final prefs = await SharedPreferences.getInstance();
    final String savedCookie = prefs.getString('saved_cookie_string') ?? "";

    // 2. 注入 Cookie 到系统管理器
    if (savedCookie.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      String domain = Uri.parse(currentBaseUrl.value).host;
      List<String> cookieList = savedCookie.split(';');
      for (var c in cookieList) {
        if (c.contains('=')) {
          var kv = c.split('=');
          await cookieManager.setCookie(
            WebViewCookie(
              name: kv[0].trim(),
              value: kv.sublist(1).join('=').trim(),
              domain: domain,
              path: '/',
            ),
          );
        }
      }
      print("🍪 [Favorite] Cookie 已注入: $domain");
    }

    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent) // 必须与登录时一致
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (url.contains("do=favorite")) {
              _parseFavorites();
            } else if (url.contains("op=delete")) {
              _hiddenController.runJavaScript(
                "var btn = document.querySelector('button[name=\"deletesubmitbtn\"]'); if(btn) btn.click();",
              );
              Future.delayed(
                const Duration(seconds: 1),
                () => _loadFavorites(),
              );
            }
          },
        ),
      );

    _loadFavorites();
  }

  void _loadFavorites() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isBlockedByCloudflare = false;
    });

    // 【关键】带上 Header 发起请求
    final prefs = SharedPreferences.getInstance().then((p) {
      String cookie = p.getString('saved_cookie_string') ?? "";
      _hiddenController.loadRequest(
        Uri.parse(
          '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me&mobile=no',
        ),
        headers: {'Cookie': cookie}, // 双重保险
      );
    });
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

      // 检测 Cloudflare 拦截
      if (cleanHtml.contains("challenges.cloudflare.com") ||
          cleanHtml.contains("Just a moment") ||
          cleanHtml.contains("Verify you are human")) {
        print("🛡️ [Favorite] 检测到 Cloudflare 验证");
        if (mounted) {
          setState(() {
            _isBlockedByCloudflare = true;
            _isLoading = false;
          });
        }
        return;
      }

      // 如果通过验证，隐藏 WebView
      if (_isBlockedByCloudflare && mounted) {
        setState(() => _isBlockedByCloudflare = false);
      }

      var document = html_parser.parse(cleanHtml);
      List<FavoriteItem> newList = [];
      var items = document.querySelectorAll('ul[id="favorite_ul"] li');

      for (var item in items) {
        var link = item.querySelector('a[href*="tid="]');
        if (link == null) continue;

        String title = link.text.trim();
        String href = link.attributes['href'] ?? "";
        String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";
        String desc = item.querySelector('.xg1')?.text ?? "";

        String favid = "";
        var delLink = item.querySelector('a[href*="op=delete"]');
        if (delLink != null) {
          favid =
              RegExp(
                r'favid=(\d+)',
              ).firstMatch(delLink.attributes['href'] ?? "")?.group(1) ??
              "";
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
      }

      if (mounted) {
        setState(() {
          _favorites = newList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteConfirmDialog(String favid, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
      ),
    );
  }

  void _deleteFavorite(String favid) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));
    final prefs = await SharedPreferences.getInstance();
    String cookie = prefs.getString('saved_cookie_string') ?? "";
    String url =
        "${currentBaseUrl.value}home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&type=all";
    _hiddenController.loadRequest(Uri.parse(url), headers: {'Cookie': cookie});
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
          appBar: AppBar(
            title: const Text("我的收藏"),
            backgroundColor: useTransparent ? Colors.transparent : null,
            elevation: useTransparent ? 0 : null,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadFavorites,
              ),
            ],
          ),
          body: Stack(
            children: [
              if (wallpaperPath != null) ...[
                Positioned.fill(
                  child: Image.file(File(wallpaperPath), fit: BoxFit.cover),
                ),
                Positioned.fill(
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: currentTheme,
                    builder: (context, mode, _) {
                      bool isDark =
                          mode == ThemeMode.dark ||
                          (mode == ThemeMode.system &&
                              MediaQuery.of(context).platformBrightness ==
                                  Brightness.dark);
                      return Container(
                        color: isDark
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.3),
                      );
                    },
                  ),
                ),
              ],

              // 列表视图
              SafeArea(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _favorites.isEmpty
                    ? Center(
                        child: _isBlockedByCloudflare
                            ? const SizedBox()
                            : const Text("暂无收藏"),
                      )
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
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => ThreadDetailPage(
                                    tid: fav.tid,
                                    subject: fav.title,
                                  ),
                                ),
                              ),
                              onLongPress: () {
                                if (fav.favid.isNotEmpty)
                                  _showDeleteConfirmDialog(
                                    fav.favid,
                                    fav.title,
                                  );
                              },
                            ),
                          );
                        },
                      ),
              ),

              // WebView 层 (平时隐藏，被盾时显示)
              if (_isBlockedByCloudflare)
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 60,
                    ),
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            "检测到安全验证，请点击下方的验证框",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        Expanded(
                          child: WebViewWidget(controller: _hiddenController),
                        ),
                      ],
                    ),
                  ),
                )
              else
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
