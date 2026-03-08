import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'thread_detail_page.dart';
import 'forum_model.dart';
import 'http_service.dart';
import 'main.dart'; // 访问 currentBaseUrl
import 'dart:io';
// 在顶部 import 区域补充这两个（如果有就不用管）
import 'package:dio/dio.dart';
import 'login_page.dart'; // 访问 kUserAgent

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
  String _formhash = ""; // 【新增】用来保存删除必须的密钥
  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  bool _isFetchingAll = false; // 防止重复并发加载
  // ==========================================
  // 【核心优化】后台自动静默获取所有分页数据
  // ==========================================
  Future<void> _loadFavorites({bool isRetry = false, int startPage = 1}) async {
    if (_isFetchingAll && startPage == 1 && !isRetry) return;
    _isFetchingAll = true;

    if (startPage == 1) {
      setState(() {
        _isLoading = true;
        _errorMsg = "";
        if (!isRetry) _favorites = []; // 重试时不丢失已加载数据
      });
    }

    int currentPage = startPage;
    bool hasNextPage = true;

    while (hasNextPage && mounted) {
      final String url =
          '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me&mobile=no&page=$currentPage';

      try {
        String html = await HttpService().getHtml(url);

        // --- 【新增代码：偷取 formhash】 ---
        if (_formhash.isEmpty) {
          var match = RegExp(
            r'name="formhash" value="([^"]+)"',
          ).firstMatch(html);
          if (match != null) {
            _formhash = match.group(1)!;
          } else {
            var match2 = RegExp(r'formhash=([a-zA-Z0-9]{8})').firstMatch(html);
            if (match2 != null) _formhash = match2.group(1)!;
          }
        }
        // -----------------------------------
        // 1. 检查是否撞到了 Cloudflare
        if (html.contains("challenges.cloudflare.com") ||
            html.contains("Verify you are human")) {
          if (!isRetry) {
            await HttpService().reviveSession();
            _isFetchingAll = false;
            return _loadFavorites(isRetry: true, startPage: currentPage);
          }
          if (currentPage == 1) {
            setState(() {
              _isLoading = false;
              _errorMsg = "当前线路触发了安全验证，请在浏览器或主页强力加载一次。";
            });
          }
          break;
        }

        // 2. 检查是否掉登录
        if (html.contains("尚未登录") ||
            (html.contains("login") && !html.contains("favorite_ul"))) {
          if (!isRetry) {
            print("💨 [Favorite] 检测到登录失效，尝试全局续命...");
            if (currentPage == 1 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("正在同步收藏夹数据..."),
                  duration: Duration(milliseconds: 800),
                ),
              );
            }
            await HttpService().reviveSession();
            _isFetchingAll = false;
            return _loadFavorites(isRetry: true, startPage: currentPage);
          } else {
            if (currentPage == 1) {
              setState(() {
                _isLoading = false;
                _errorMsg = "登录态同步失败，请尝试重新登录";
              });
            }
            break;
          }
        }

        // 3. 数据解析逻辑（融合原 _parseHtml 逻辑，直接追加数据）
        var document = html_parser.parse(html);
        List<FavoriteItem> newItems = [];

        var items = document.querySelectorAll('ul[id="favorite_ul"] li');
        for (var item in items) {
          try {
            var link = item.querySelector('a[href*="tid="]');
            if (link == null) continue;

            String title = link.text.trim();
            String href = link.attributes['href'] ?? "";
            String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";
            String desc = item.querySelector('.xg1')?.text ?? "";
            String favid = "";
            var delLink = item.querySelector('a[href*="op=delete"]');
            if (delLink != null) {
              String delHref = delLink.attributes['href'] ?? "";
              favid =
                  RegExp(r'favid=(\d+)').firstMatch(delHref)?.group(1) ?? "";
            }

            if (tid.isNotEmpty) {
              newItems.add(
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

        // 局部更新 UI 列表
        if (mounted) {
          setState(() {
            _favorites.addAll(newItems);
            if (currentPage == 1) {
              _isLoading = false;
              if (_favorites.isEmpty) _errorMsg = "收藏夹空空如也";
            }
          });
        }

        // 4. 检查是否有下一页
        var nextBtn = document.querySelector('.pg .nxt');
        if (nextBtn != null) {
          currentPage++; // 有下一页，继续 while 循环
          isRetry = false; // 翻页成功后清除重试标记，允许下一页在出错时进行重试
        } else {
          hasNextPage = false; // 到底了，退出循环
        }
      } catch (e) {
        print("❌ 收藏夹加载异常: $e");
        if (!isRetry) {
          await HttpService().reviveSession();
          _isFetchingAll = false;
          return _loadFavorites(isRetry: true, startPage: currentPage);
        }
        if (currentPage == 1 && mounted) {
          setState(() {
            _isLoading = false;
            _errorMsg = "加载失败，请检查网络连接";
          });
        }
        break; // 中断加载循环
      }
    }
    _isFetchingAll = false; // 全部任务完成
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
  // 【优化】通过 POST 提交表单完成删除，并实现本地秒删
  // ==========================================
  Future<void> _deleteFavorite(String favid) async {
    if (favid.isEmpty) return;

    // 依然使用原有 UI 提示
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));

    // 构造请求 URL (保留 inajax=1 返回精简 XML)
    final String url =
        "${currentBaseUrl.value}home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&type=all&inajax=1";

    try {
      // 1. 准备请求头
      final prefs = await SharedPreferences.getInstance();
      String cookie = prefs.getString('saved_cookie_string') ?? "";

      var dio = Dio();

      // 2. 完美模拟你在网页端抓取到的表单 (POST Payload)
      var formData = FormData.fromMap({
        'referer':
            '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me',
        'deletesubmit': 'true',
        'deletesubmitbtn': 'true', // 确认按钮
        'formhash': _formhash, // 最核心的安全密钥
        'handlekey': 'a_delete_$favid',
      });

      // 3. 发送 POST 请求
      var response = await dio.post(
        url,
        data: formData,
        options: Options(
          headers: {
            'Cookie': cookie,
            'User-Agent': kUserAgent,
            'Referer':
                '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me',
          },
        ),
      );

      // 4. 判断并实现 UI 层的“秒删”
      String respStr = response.data.toString();
      // Discuz 成功时通常返回包含 succeed 或 "操作成功" 的数据
      if (respStr.contains("succeed") ||
          respStr.contains("成功") ||
          respStr.contains("删除")) {
        if (mounted) {
          setState(() {
            // 直接在本地列表中剔除这一项，瞬间刷新 UI，再也不用苦等重新加载！
            _favorites.removeWhere((item) => item.favid == favid);
            if (_favorites.isEmpty) _errorMsg = "收藏夹空空如也";
          });
          // 隐藏之前的 SnackBar 并提示成功
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("已取消收藏")));
        }
      } else {
        throw "服务器未返回成功标志";
      }
    } catch (e) {
      print("删除异常: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("取消失败，请检查网络或刷新重试")));
      }
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
