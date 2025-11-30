import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'login_page.dart';
import 'thread_detail_page.dart';

// 简单的收藏模型
class FavoriteItem {
  final String tid;
  final String title;
  final String description;

  FavoriteItem({
    required this.tid,
    required this.title,
    required this.description,
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
        NavigationDelegate(onPageFinished: (url) => _parseFavorites()),
      );

    // 加载收藏夹页面
    _hiddenController.loadRequest(
      Uri.parse(
        'https://www.giantessnight.com/gnforum2012/home.php?mod=space&do=favorite&view=me&mobile=no',
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

          if (tid.isNotEmpty) {
            newList.add(
              FavoriteItem(tid: tid, title: title, description: desc),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("我的收藏")),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _favorites.isEmpty
              ? const Center(child: Text("暂无收藏"))
              : ListView.builder(
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final fav = _favorites[index];
                    return ListTile(
                      leading: const Icon(Icons.star, color: Colors.orange),
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
                    );
                  },
                ),
          SizedBox(
            height: 0,
            width: 0,
            child: WebViewWidget(controller: _hiddenController),
          ),
        ],
      ),
    );
  }
}
