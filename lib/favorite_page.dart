import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'thread_detail_page.dart';
import 'forum_model.dart';
import 'http_service.dart';
import 'main.dart'; // 访问 currentBaseUrl
import 'dart:io';

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
  List<FavoriteItem> _favorites = [];
  bool _isLoading = true;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  // ==========================================
  // 【核心优化】支持自动续命的加载逻辑
  // ==========================================
  Future<void> _loadFavorites({bool isRetry = false}) async {
    setState(() {
      _isLoading = true;
      _errorMsg = "";
    });

    final String url =
        '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me&mobile=no';

    try {
      String html = await HttpService().getHtml(url);

      // 1. 检查是否撞到了 Cloudflare
      if (html.contains("challenges.cloudflare.com") ||
          html.contains("Verify you are human")) {
        // 如果没重试过，尝试续命一下（有时是因为 Cookie 太旧导致 CF 触发）
        if (!isRetry) {
          await HttpService().reviveSession();
          return _loadFavorites(isRetry: true);
        }
        setState(() {
          _isLoading = false;
          _errorMsg = "触发安全验证，请在主页手动刷新";
        });
        return;
      }

      // 2. 检查是否掉登录 (这是你原来的逻辑，我做增强)
      // 如果 HTML 里包含 login 或者没有找到 favorite_ul 列表，通常说明没登录或 Cookie 只有一半
      bool isInvalid =
          html.contains("尚未登录") ||
          html.contains('id="ls_username"') || // 桌面版登录框特征
          (html.contains("login") && !html.contains("favorite_ul"));

      if (isInvalid) {
        if (!isRetry) {
          print("💨 [Favorite] 检测到登录失效，尝试自动续命...");
          // 显示一个小提示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("正在同步收藏夹数据..."),
                duration: Duration(milliseconds: 800),
              ),
            );
          }

          await HttpService().reviveSession();
          // 续命后重试
          return _loadFavorites(isRetry: true);
        } else {
          setState(() {
            _isLoading = false;
            _errorMsg = "登录状态失效，请重新登录";
          });
          return;
        }
      }

      // 3. 解析 HTML
      _parseHtml(html);
    } catch (e) {
      // 网络错误也试一次续命
      if (!isRetry) {
        await HttpService().reviveSession();
        return _loadFavorites(isRetry: true);
      }
      print("❌ 收藏夹加载异常: $e");
      setState(() {
        _isLoading = false;
        _errorMsg = "加载失败，请检查网络";
      });
    }
  }

  void _parseHtml(String html) {
    var document = html_parser.parse(html);
    List<FavoriteItem> newList = [];

    // Discuz 收藏列表通常在 ul#favorite_ul li 里面
    var items = document.querySelectorAll('ul[id="favorite_ul"] li');

    for (var item in items) {
      try {
        var link = item.querySelector('a[href*="tid="]');
        if (link == null) continue;

        String title = link.text.trim();
        String href = link.attributes['href'] ?? "";
        String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";

        // 提取描述
        String desc = item.querySelector('.xg1')?.text ?? "";

        // 提取 favid (取消收藏时需要)
        String favid = "";
        var delLink = item.querySelector('a[href*="op=delete"]');
        if (delLink != null) {
          String delHref = delLink.attributes['href'] ?? "";
          favid = RegExp(r'favid=(\d+)').firstMatch(delHref)?.group(1) ?? "";
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
        if (newList.isEmpty) _errorMsg = "收藏夹空空如也";
      });
    }
  }

  // ==========================================
  // 【优化】删除收藏逻辑
  // ==========================================
  Future<void> _deleteFavorite(String favid) async {
    if (favid.isEmpty) return;

    // 显示简单的加载提示
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));

    // 构造删除 URL
    final String url =
        "${currentBaseUrl.value}home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&type=all&inajax=1";

    try {
      // 发起删除请求
      await HttpService().getHtml(url);
      // 成功后本地刷新
      _loadFavorites();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("删除失败")));
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Scaffold(
          backgroundColor: wallpaperPath != null ? Colors.transparent : null,
          appBar: AppBar(
            title: const Text("我的收藏"),
            backgroundColor: wallpaperPath != null ? Colors.transparent : null,
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
                  child: Container(color: Colors.black.withOpacity(0.5)),
                ),
              ],

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMsg.isNotEmpty && _favorites.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMsg,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _loadFavorites,
                            child: const Text("重试"),
                          ),
                        ],
                      ),
                    )
                  : _buildList(wallpaperPath),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(String? wallpaperPath) {
    return ListView.builder(
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final fav = _favorites[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: wallpaperPath != null ? Colors.white.withOpacity(0.1) : null,
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.orange),
            title: Text(
              fav.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: fav.description.isNotEmpty ? Text(fav.description) : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) =>
                      ThreadDetailPage(tid: fav.tid, subject: fav.title),
                ),
              );
            },
            onLongPress: () => _showDeleteConfirmDialog(fav.favid, fav.title),
          ),
        );
      },
    );
  }
}
