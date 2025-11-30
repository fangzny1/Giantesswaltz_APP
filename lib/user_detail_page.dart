import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'login_page.dart';
import 'thread_detail_page.dart';

class UserThreadItem {
  final String tid;
  final String subject;
  final String forumName;
  final String dateline;
  final String views;
  final String replies;

  UserThreadItem({
    required this.tid,
    required this.subject,
    required this.forumName,
    required this.dateline,
    required this.views,
    required this.replies,
  });
}

class UserDetailPage extends StatefulWidget {
  final String? uid;
  final String username;
  final String? avatarUrl;

  const UserDetailPage({
    super.key,
    this.uid,
    required this.username,
    this.avatarUrl,
  });

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  late final WebViewController _hiddenController;
  final ScrollController _scrollController = ScrollController();

  List<UserThreadItem> _threads = [];

  bool _isFirstLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  String _errorMsg = "";
  int _currentPage = 1;
  int _targetPage = 1; // 记录当前正在请求的目标页码

  final String _baseUrl = "https://www.giantessnight.com/gnforum2012/";

  @override
  void initState() {
    super.initState();
    _initWebView();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
            _parseUserData();
          },
        ),
      );

    _loadPage(1);
  }

  void _loadPage(int page) {
    if (!_hasMore && page > 1) return;

    _targetPage = page;
    String url;

    // 构建分页 URL：&page=X
    if (widget.uid != null && widget.uid!.isNotEmpty) {
      url =
          '${_baseUrl}home.php?mod=space&uid=${widget.uid}&do=thread&view=me&from=space&mobile=no&page=$page';
    } else {
      url =
          '${_baseUrl}home.php?mod=space&username=${Uri.encodeComponent(widget.username)}&do=thread&view=me&from=space&mobile=no&page=$page';
    }

    print("🚀 加载用户主题第 $page 页: $url");
    _hiddenController.loadRequest(Uri.parse(url));
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore || _isFirstLoading) return;
    setState(() {
      _isLoadingMore = true;
    });
    _loadPage(_currentPage + 1);
  }

  Future<void> _parseUserData() async {
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
      List<UserThreadItem> newThreads = [];

      // Discuz 用户页列表解析
      var rows = document.querySelectorAll('form[id^="delform"] table tr');

      for (var row in rows) {
        try {
          if (row.className.contains('th')) continue;

          var titleNode = row.querySelector('th a');
          if (titleNode == null) continue;

          String subject = titleNode.text.trim();
          String href = titleNode.attributes['href'] ?? "";
          // 提取 TID
          RegExp tidReg = RegExp(r'tid=(\d+)');
          String tid = tidReg.firstMatch(href)?.group(1) ?? "";

          if (tid.isEmpty) continue;

          var forumNode = row.querySelector('a.xg1');
          String forumName = forumNode?.text.trim() ?? "未知板块";

          var numNode = row.querySelector('td.num');
          String replies = numNode?.querySelector('a')?.text ?? "0";
          String views = numNode?.querySelector('em')?.text ?? "0";

          var dateNode =
              row.querySelector('td.by em span') ??
              row.querySelector('td.by em');
          String dateline = dateNode?.text.trim() ?? "";

          newThreads.add(
            UserThreadItem(
              tid: tid,
              subject: subject,
              forumName: forumName,
              dateline: dateline,
              views: views,
              replies: replies,
            ),
          );
        } catch (e) {
          continue;
        }
      }

      if (mounted) {
        setState(() {
          if (_targetPage == 1) {
            _threads = newThreads;
            _currentPage = 1;
          } else {
            // 翻页追加逻辑 (去重)
            bool hasNew = false;
            for (var t in newThreads) {
              if (!_threads.any((old) => old.tid == t.tid)) {
                _threads.add(t);
                hasNew = true;
              }
            }
            if (hasNew) _currentPage = _targetPage;
          }

          // Discuz 用户页每页通常也是 20 条，如果少于 5 条，说明没数据了
          if (newThreads.length < 5) {
            _hasMore = false;
          }

          _isFirstLoading = false;
          _isLoadingMore = false;
          _errorMsg = "";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _isFirstLoading = false;
          if (_currentPage == 1) _errorMsg = "解析失败";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController, // 绑定滚动控制器
            slivers: [
              SliverAppBar.large(
                title: Text("${widget.username} 的主题"),
                actions: [
                  if (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: CircleAvatar(
                        backgroundImage: NetworkImage(widget.avatarUrl!),
                      ),
                    ),
                ],
              ),

              if (_isFirstLoading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),

              if (_threads.isEmpty && !_isFirstLoading)
                SliverFillRemaining(
                  child: Center(
                    child: Text(_errorMsg.isNotEmpty ? _errorMsg : "没有找到公开的主题"),
                  ),
                ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _threads.length) return _buildFooter();
                    final item = _threads[index];
                    return _buildThreadTile(item);
                  },
                  childCount: _threads.length + 1, // +1 给 footer
                ),
              ),
            ],
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

  Widget _buildFooter() {
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      if (_threads.isEmpty) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text("--- 没有更多了 ---", style: TextStyle(color: Colors.grey)),
        ),
      );
    }
  }

  Widget _buildThreadTile(UserThreadItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ThreadDetailPage(tid: item.tid, subject: item.subject),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.forumName,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.dateline,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.remove_red_eye,
                    size: 12,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    item.views,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    item.replies,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
