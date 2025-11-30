import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'login_page.dart';
import 'forum_model.dart';
import 'thread_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final WebViewController _hiddenController;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Thread> _results = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false; // 是否有下一页
  bool _hasSearched = false;
  String _statusMsg = "";

  // 【核心】直接保存“下一页”的完整链接，不再自己拼 URL
  String? _nextPageUrl;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _initWebView() {
    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // 只要页面加载完，不管是不是重定向，直接尝试解析
            // 因为 Discuz 搜索成功后一定会显示结果列表
            _parseSearchResults();
          },
        ),
      );
  }

  void _doSearch() {
    final keyword = _textController.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _statusMsg = "正在搜索...";
      _results.clear();
      _nextPageUrl = null;
      _hasMore = false;
    });

    // 强制 mobile=no 获取电脑版页面 (结构最清晰)
    final url =
        'https://www.giantessnight.com/gnforum2012/search.php?mod=forum&searchsubmit=yes&srchtxt=${Uri.encodeComponent(keyword)}&mobile=no';
    print("🚀 开始搜索: $url");
    _hiddenController.loadRequest(Uri.parse(url));
  }

  void _loadMore() {
    // 如果没有下一页链接，就不加载
    if (_isLoading || _isLoadingMore || !_hasMore || _nextPageUrl == null)
      return;

    setState(() {
      _isLoadingMore = true;
    });

    print("🚀 加载下一页: $_nextPageUrl");
    // 直接加载解析到的下一页链接
    _hiddenController.loadRequest(Uri.parse(_nextPageUrl!));
  }

  Future<void> _parseSearchResults() async {
    try {
      final String rawHtml =
          await _hiddenController.runJavaScriptReturningResult(
                "document.documentElement.outerHTML",
              )
              as String;

      // 清洗 HTML
      String cleanHtml = rawHtml;
      if (cleanHtml.startsWith('"'))
        cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
      cleanHtml = cleanHtml
          .replaceAll('\\u003C', '<')
          .replaceAll('\\"', '"')
          .replaceAll('\\\\', '\\');

      var document = html_parser.parse(cleanHtml);
      List<Thread> newResults = [];

      // 1. 解析结果列表 (li.pbw 是 Discuz 电脑版搜索结果的标准结构)
      var listItems = document.querySelectorAll('li.pbw');

      for (var li in listItems) {
        try {
          var titleNode = li.querySelector('h3.xs3 a');
          if (titleNode == null) continue;

          String title = titleNode.text.trim();
          String href = titleNode.attributes['href'] ?? "";

          // 提取 TID
          RegExp tidReg = RegExp(r'tid=(\d+)');
          String tid = tidReg.firstMatch(href)?.group(1) ?? "";
          if (tid.isEmpty) continue;

          // 简单提取作者 (如果不显示作者也没关系，给个默认值)
          // 这里尝试简单获取，获取不到就用 "搜索结果"
          String author = "搜索结果";
          try {
            var pNode = li.querySelector('p');
            if (pNode != null) {
              // 通常结构是: 时间 - 作者 - 板块
              // 我们简单取文本，不做复杂正则，防止报错
              // 只要不为空就行
              if (pNode.text.length > 5) author = "详情点击查看";
            }
          } catch (e) {}

          newResults.add(
            Thread(
              tid: tid,
              subject: title,
              author: author,
              replies: "",
              views: "",
              readperm: "0",
            ),
          );
        } catch (e) {
          continue;
        }
      }

      // 2. 【核心】解析“下一页”按钮
      // Discuz 的下一页按钮通常是 <a class="nxt" href="...">
      var nextBtn = document.querySelector('.pg .nxt');
      String? nextUrl;

      if (nextBtn != null) {
        String href = nextBtn.attributes['href'] ?? "";
        if (href.isNotEmpty) {
          // 补全域名
          if (!href.startsWith("http")) {
            nextUrl = "https://www.giantessnight.com/gnforum2012/$href";
          } else {
            nextUrl = href;
          }
          // 加上 mobile=no 保证下一页也是电脑版结构
          if (!nextUrl.contains("mobile=no")) {
            nextUrl += "&mobile=no";
          }
        }
      }

      if (mounted) {
        setState(() {
          // 去重追加
          for (var item in newResults) {
            if (!_results.any((r) => r.tid == item.tid)) {
              _results.add(item);
            }
          }

          // 更新下一页状态
          _nextPageUrl = nextUrl;
          _hasMore = (_nextPageUrl != null);

          _isLoading = false;
          _isLoadingMore = false;

          if (_results.isEmpty) _statusMsg = "未找到相关内容，请尝试更换关键词";
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _statusMsg = "解析出错，请重试";
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _textController,
          decoration: const InputDecoration(
            hintText: "搜索帖子...",
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 18),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _doSearch(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          SizedBox(
            height: 0,
            width: 0,
            child: WebViewWidget(controller: _hiddenController),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_hasSearched && _results.isEmpty)
      return Center(child: Text(_statusMsg));
    if (!_hasSearched) return const Center(child: Text("输入关键词搜索论坛内容"));

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == _results.length) {
          // 底部加载条
          return _hasMore
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : (_results.isNotEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            "--- 到底啦 ---",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : const SizedBox());
        }

        final item = _results[index];
        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.search),
            title: Text(
              item.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // 既然作者解析容易出错，我们这里就不显示作者了，或者显示通用文本
            // subtitle: Text(item.author),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ThreadDetailPage(tid: item.tid, subject: item.subject),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
