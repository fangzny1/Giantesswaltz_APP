import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 引入其他页面 (确保这些文件存在)
import 'login_page.dart';
import 'user_detail_page.dart';
import 'forum_model.dart';

class PostItem {
  final String pid;
  final String author;
  final String authorId;
  final String avatarUrl;
  final String time;
  final String contentHtml;
  final String floor;
  final String device;

  PostItem({
    required this.pid,
    required this.author,
    required this.authorId,
    required this.avatarUrl,
    required this.time,
    required this.contentHtml,
    required this.floor,
    required this.device,
  });
}

class ThreadDetailPage extends StatefulWidget {
  final String tid;
  final String subject;
  final int initialPage;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    required this.subject,
    this.initialPage = 1,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage>
    with SingleTickerProviderStateMixin {
  late final WebViewController _hiddenController;
  late final WebViewController _favCheckController;

  final ScrollController _scrollController = ScrollController();

  List<PostItem> _posts = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isLoadingPrev = false;
  bool _hasMore = true;

  bool _isOnlyLandlord = false;
  bool _isReaderMode = false;
  bool _isFabOpen = false;

  bool _isFavorited = false;
  String? _favid;

  double _fontSize = 16.0;
  Color _readerBgColor = const Color(0xFFFAF9DE);
  Color _readerTextColor = Colors.black87;

  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;

  late int _minPage;
  late int _maxPage;
  int _targetPage = 1;

  String? _landlordUid;
  final String _baseUrl = "https://www.giantessnight.com/gnforum2012/";

  // 存储 Cookie
  String _userCookies = "";

  @override
  void initState() {
    super.initState();
    _minPage = widget.initialPage;
    _maxPage = widget.initialPage;
    _targetPage = widget.initialPage;

    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _initWebView();
    _initFavCheck();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      _loadNext();
    }
  }

  void _initWebView() {
    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            // 1. 同步 Cookie
            try {
              final String cookies =
                  await _hiddenController.runJavaScriptReturningResult(
                        'document.cookie',
                      )
                      as String;
              String cleanCookies = cookies;
              if (cleanCookies.startsWith('"') && cleanCookies.endsWith('"')) {
                cleanCookies = cleanCookies.substring(
                  1,
                  cleanCookies.length - 1,
                );
              }
              if (mounted) {
                setState(() {
                  _userCookies = cleanCookies;
                });
              }
            } catch (e) {
              print("Cookie 同步失败: $e");
            }
            // 2. 解析
            _parseHtmlData();
          },
        ),
      );
    _loadPage(_targetPage);
  }

  void _initFavCheck() {
    _favCheckController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (url.contains("do=favorite")) {
              _parseFavList();
            } else if (url.contains("op=delete") &&
                url.contains("ac=favorite")) {
              _favCheckController.runJavaScript(
                "var btn = document.querySelector('button[name=\"deletesubmitbtn\"]'); if(btn) btn.click();",
              );
            }
          },
        ),
      );
    _favCheckController.loadRequest(
      Uri.parse('${_baseUrl}home.php?mod=space&do=favorite&view=me&mobile=no'),
    );
  }

  void _loadPage(int page) {
    _targetPage = page;
    String url =
        '${_baseUrl}forum.php?mod=viewthread&tid=${widget.tid}&extra=page%3D1&page=$page&mobile=no';
    if (_isOnlyLandlord && _landlordUid != null)
      url += '&authorid=$_landlordUid';
    print("🚀 加载帖子: 第 $page 页");
    _hiddenController.loadRequest(Uri.parse(url));
  }

  void _loadNext() {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    _loadPage(_maxPage + 1);
  }

  void _loadPrev() {
    if (_isLoading || _isLoadingPrev || _minPage <= 1) return;
    setState(() {
      _isLoadingPrev = true;
    });
    _loadPage(_minPage - 1);
  }

  void _toggleFab() {
    setState(() {
      _isFabOpen = !_isFabOpen;
      if (_isFabOpen) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });
  }

  void _toggleReaderMode() {
    setState(() {
      _isReaderMode = !_isReaderMode;
      if (_isReaderMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
    _toggleFab();
  }

  void _handleFavorite() {
    _toggleFab();
    if (_isFavorited) {
      if (_favid != null) {
        String delUrl =
            "${_baseUrl}home.php?mod=spacecp&ac=favorite&op=delete&favid=$_favid&type=all";
        _favCheckController.loadRequest(Uri.parse(delUrl));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));
        Future.delayed(
          const Duration(seconds: 3),
          () => _favCheckController.reload(),
        );
        setState(() {
          _isFavorited = false;
          _favid = null;
        });
      }
    } else {
      _hiddenController.runJavaScript(
        "if(document.querySelector('#k_favorite')) document.querySelector('#k_favorite').click();",
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已发送收藏请求")));
      setState(() {
        _isFavorited = true;
      });
      Future.delayed(
        const Duration(seconds: 3),
        () => _favCheckController.reload(),
      );
    }
  }

  Future<void> _saveBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('local_bookmarks');
    List<dynamic> jsonList = [];
    if (jsonStr != null && jsonStr.startsWith("["))
      jsonList = jsonDecode(jsonStr);

    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: widget.subject,
      author: _posts.isNotEmpty ? _posts.first.author : "未知",
      page: _maxPage,
      savedTime: DateTime.now().toString().substring(0, 16),
    );

    jsonList.removeWhere((e) => e['tid'] == widget.tid);
    jsonList.insert(0, newMark.toJson());
    await prefs.setString('local_bookmarks', jsonEncode(jsonList));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("进度已保存")));
    }
    _toggleFab();
  }

  void _toggleOnlyLandlord() {
    if (_landlordUid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("未找到楼主信息")));
      return;
    }
    setState(() {
      _isOnlyLandlord = !_isOnlyLandlord;
      _posts.clear();
      _minPage = 1;
      _maxPage = 1;
      _hasMore = true;
      _isLoading = true;
      _targetPage = 1;
      _toggleFab();
    });
    _loadPage(1);
  }

  Future<void> _parseFavList() async {
    try {
      final String rawHtml =
          await _favCheckController.runJavaScriptReturningResult(
                "document.documentElement.outerHTML",
              )
              as String;
      String cleanHtml = _cleanHtml(rawHtml);
      var document = html_parser.parse(cleanHtml);
      var items = document.querySelectorAll('ul[id="favorite_ul"] li');
      String? foundFavid;
      for (var item in items) {
        var link = item.querySelector('a[href*="tid=${widget.tid}"]');
        if (link != null) {
          var delLink = item.querySelector('a[href*="op=delete"]');
          if (delLink != null) {
            String href = delLink.attributes['href'] ?? "";
            String favid =
                RegExp(r'favid=(\d+)').firstMatch(href)?.group(1) ?? "";
            if (favid.isNotEmpty) {
              foundFavid = favid;
              break;
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _isFavorited = (foundFavid != null);
          _favid = foundFavid;
        });
      }
    } catch (e) {}
  }

  // === 核心解析逻辑 ===
  Future<void> _parseHtmlData() async {
    try {
      final String rawHtml =
          await _hiddenController.runJavaScriptReturningResult(
                "document.documentElement.outerHTML",
              )
              as String;
      String cleanHtml = _cleanHtml(rawHtml);
      var document = html_parser.parse(cleanHtml);

      // 【Step 1】 建立 AID -> 静态 URL 映射表
      // Discuz 会在页面底部（ignore_js_op 或 pattl）列出所有附件，
      // 并提供 img[aid] 和 zoomfile (静态链接)
      Map<String, String> aidToStaticUrl = {};

      // 查找所有带有 aid 属性且有 zoomfile 的 img 标签
      var attachmentImgs = document.querySelectorAll('img[aid][zoomfile]');
      for (var img in attachmentImgs) {
        String? aid = img.attributes['aid'];
        String? url = img.attributes['zoomfile'];
        if (aid != null && url != null && url.contains("data/attachment")) {
          aidToStaticUrl[aid] = url;
        }
      }
      // 补充：有时候是 file 属性存静态链
      for (var img in attachmentImgs) {
        String? aid = img.attributes['aid'];
        String? url = img.attributes['file'];
        if (aid != null && url != null && url.contains("data/attachment")) {
          // 如果 zoomfile 没存，用 file 补
          if (!aidToStaticUrl.containsKey(aid)) {
            aidToStaticUrl[aid] = url;
          }
        }
      }

      print("🔎 发现附件静态映射: ${aidToStaticUrl.length} 个");

      List<PostItem> newPosts = [];
      var postDivs = document.querySelectorAll('div[id^="post_"]');

      int floorIndex = (_targetPage - 1) * 10 + 1;

      for (var div in postDivs) {
        try {
          if (div.id.contains("new") || div.id.contains("rate")) continue;
          String pid = div.id.split('_').last;

          var authorNode =
              div.querySelector('.authi .xw1') ?? div.querySelector('.authi a');
          String author = authorNode?.text.trim() ?? "匿名";
          String authorHref = authorNode?.attributes['href'] ?? "";
          String authorId =
              RegExp(r'uid=(\d+)').firstMatch(authorHref)?.group(1) ?? "";

          if (_landlordUid == null && _posts.isEmpty) {
            _landlordUid = authorId;
          }

          var avatarNode = div.querySelector('.avatar img');
          String avatarUrl = avatarNode?.attributes['src'] ?? "";
          if (avatarUrl.isNotEmpty && !avatarUrl.startsWith("http")) {
            avatarUrl = "$_baseUrl$avatarUrl";
          }

          var timeNode = div.querySelector('em[id^="authorposton"]');
          String time = timeNode?.text.replaceAll("发表于 ", "").trim() ?? "";

          var floorNode = div.querySelector('.pi strong a em');
          String floorText = floorNode?.text ?? "${floorIndex++}楼";

          // === 【核心修复】同时获取正文和附件列表 ===
          var contentNode = div.querySelector('td.t_f');
          String content = contentNode?.innerHtml ?? "";

          // 修复：获取手机端上传/未插入正文的图片附件 (.pattl)
          var attachmentNode = div.querySelector('.pattl');
          if (attachmentNode != null) {
            // 将附件列表的 HTML 拼接到正文后面
            content +=
                "<br><div class='attachments'>${attachmentNode.innerHtml}</div>";
          }

          // === Step 2: 内容清洗与链接替换 ===
          content = content.replaceAll(r'\n', '<br>');
          content = content.replaceAll('<div class="mbn savephotop">', '<div>');

          content = content.replaceAllMapped(
            RegExp(r'<img[^>]+>', dotAll: true),
            (match) {
              String imgTag = match.group(0)!;

              // 提取属性
              String? zoomUrl = RegExp(
                r'zoomfile="([^"]+)"',
              ).firstMatch(imgTag)?.group(1);
              String? fileUrl = RegExp(
                r'file="([^"]+)"',
              ).firstMatch(imgTag)?.group(1);
              String? srcUrl = RegExp(
                r'src="([^"]+)"',
              ).firstMatch(imgTag)?.group(1);

              // 尝试提取 AID (从 URL 中提取)
              // 常见的动态链接: forum.php?mod=image&aid=129125&...
              String? aidFromUrl;
              RegExp aidReg = RegExp(r'aid=(\d+)');

              if (fileUrl != null) {
                aidFromUrl = aidReg.firstMatch(fileUrl)?.group(1);
              }
              if (aidFromUrl == null && srcUrl != null) {
                aidFromUrl = aidReg.firstMatch(srcUrl)?.group(1);
              }

              String bestUrl = "";

              // 【策略 1】 如果有 AID 且在静态映射表中存在，直接用静态链接 (100% 解决 WAF/缩略图问题)
              if (aidFromUrl != null &&
                  aidToStaticUrl.containsKey(aidFromUrl)) {
                bestUrl = aidToStaticUrl[aidFromUrl]!;
                // print("✅ 成功替换动态链接 aid=$aidFromUrl -> $bestUrl");
              }
              // 【策略 2】 否则按照优先级寻找静态属性
              else if (zoomUrl != null && zoomUrl.contains("data/attachment")) {
                bestUrl = zoomUrl;
              } else if (fileUrl != null &&
                  fileUrl.contains("data/attachment")) {
                bestUrl = fileUrl;
              } else if (srcUrl != null && srcUrl.contains("data/attachment")) {
                bestUrl = srcUrl;
              }
              // 【策略 3】 实在没办法，只能用动态链接，但要清洗
              else if (fileUrl != null && fileUrl.isNotEmpty) {
                bestUrl = fileUrl;
              } else if (srcUrl != null && srcUrl.isNotEmpty) {
                if (!srcUrl.contains("loading.gif") &&
                    !srcUrl.contains("none.gif") &&
                    !srcUrl.contains("common.gif")) {
                  bestUrl = srcUrl;
                }
              }

              if (bestUrl.isNotEmpty) {
                // 1. 修复 HTML 实体
                bestUrl = bestUrl.replaceAll('&amp;', '&');

                // 2. 清洗动态链接 (强力去毒)
                if (bestUrl.contains("mod=image")) {
                  bestUrl = bestUrl.replaceAll(RegExp(r'&mobile=[0-9]+'), '');
                  bestUrl = bestUrl.replaceAll(RegExp(r'&mobile=yes'), '');
                  bestUrl = bestUrl.replaceAll(RegExp(r'&mobile=no'), '');
                  bestUrl = bestUrl.replaceAll('&type=fixnone', '');
                }

                // 3. 补全路径
                if (!bestUrl.startsWith('http')) {
                  String base = _baseUrl.endsWith('/')
                      ? _baseUrl
                      : "$_baseUrl/";
                  String path = bestUrl.startsWith('/')
                      ? bestUrl.substring(1)
                      : bestUrl;
                  bestUrl = base + path;
                }

                return '<img src="$bestUrl" style="max-width:100%; height:auto; display:block; margin: 8px 0;">';
              }
              return "";
            },
          );

          content = content.replaceAll(
            RegExp(r'<script.*?>.*?</script>', dotAll: true),
            '',
          );
          content = content.replaceAll('ignore_js_op', 'div');

          newPosts.add(
            PostItem(
              pid: pid,
              author: author,
              authorId: authorId,
              avatarUrl: avatarUrl,
              time: time,
              contentHtml: content,
              floor: floorText,
              device: div.innerHtml.contains("来自手机") ? "手机端" : "",
            ),
          );
        } catch (e) {
          continue;
        }
      }

      var nextBtn = document.querySelector('.pg .nxt');
      bool hasNextPage = nextBtn != null;

      if (mounted) {
        setState(() {
          if (_targetPage == widget.initialPage && _posts.isEmpty) {
            _posts = newPosts;
          } else if (_targetPage < _minPage) {
            _posts.insertAll(0, newPosts);
            _minPage = _targetPage;
          } else {
            for (var p in newPosts) {
              if (!_posts.any((old) => old.pid == p.pid)) _posts.add(p);
            }
            if (newPosts.isNotEmpty) _maxPage = _targetPage;
          }

          if (!hasNextPage && _targetPage >= _maxPage) _hasMore = false;
          if (newPosts.isEmpty && _targetPage > 1) _hasMore = false;

          _isLoading = false;
          _isLoadingMore = false;
          _isLoadingPrev = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _isLoadingPrev = false;
        });
    }
  }

  // 使用原生 Image.network 加载
  Widget _buildClickableImage(String url) {
    if (url.isEmpty) return const SizedBox();

    String fullUrl = url;
    if (!fullUrl.startsWith('http')) {
      String base = _baseUrl.endsWith('/') ? _baseUrl : "$_baseUrl/";
      String path = fullUrl.startsWith('/') ? fullUrl.substring(1) : fullUrl;
      fullUrl = base + path;
    }

    return GestureDetector(
      onTap: () => _launchURL(fullUrl),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Image.network(
          fullUrl,
          headers: {
            'Cookie': _userCookies,
            'User-Agent': kUserAgent,
            'Referer': _baseUrl,
            'Accept':
                'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          },
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              height: 200,
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 100,
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, color: Colors.grey),
                  const SizedBox(height: 4),
                  const Text(
                    "图片加载失败(点击浏览器打开)",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _cleanHtml(String raw) {
    String clean = raw;
    if (clean.startsWith('"')) clean = clean.substring(1, clean.length - 1);
    clean = clean
        .replaceAll('\\u003C', '<')
        .replaceAll('\\"', '"')
        .replaceAll('\\\\', '\\');
    return clean;
  }

  Future<void> _launchURL(String? url) async {
    if (url == null || url.isEmpty) return;
    final Uri uri = Uri.parse(url.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {}
  }

  void _showDisplaySettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: 250,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "字体大小",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _fontSize,
                    min: 12.0,
                    max: 30.0,
                    divisions: 18,
                    label: _fontSize.toStringAsFixed(0),
                    onChanged: (val) {
                      setSheetState(() => _fontSize = val);
                      setState(() => _fontSize = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "背景颜色",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildColorBtn(
                        const Color(0xFFFFFFFF),
                        Colors.black87,
                        "白昼",
                      ),
                      _buildColorBtn(
                        const Color(0xFFFAF9DE),
                        Colors.black87,
                        "护眼",
                      ),
                      _buildColorBtn(
                        const Color(0xFF1A1A1A),
                        Colors.white70,
                        "夜间",
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    _toggleFab();
  }

  Widget _buildColorBtn(Color bg, Color text, String label) {
    bool isSelected = _readerBgColor == bg;
    return GestureDetector(
      onTap: () {
        setState(() {
          _readerBgColor = bg;
          _readerTextColor = text;
        });
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey,
                width: 2,
              ),
              shape: BoxShape.circle,
            ),
            child: isSelected ? Icon(Icons.check, color: text) : null,
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _jumpToUser(PostItem post) {
    if (post.authorId.isNotEmpty)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserDetailPage(
            uid: post.authorId,
            username: post.author,
            avatarUrl: post.avatarUrl,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor = Theme.of(context).colorScheme.surface;
    if (_isReaderMode) bgColor = _readerBgColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  floating: false,
                  pinned: false,
                  snap: false,
                  title: Text(
                    widget.subject,
                    style: TextStyle(
                      fontSize: 16,
                      color: _isReaderMode ? _readerTextColor : null,
                    ),
                  ),
                  centerTitle: false,
                  elevation: 0,
                  backgroundColor: bgColor,
                  surfaceTintColor: Colors.transparent,
                  iconTheme: IconThemeData(
                    color: _isReaderMode ? _readerTextColor : null,
                  ),
                ),
              ];
            },
            body: _isReaderMode ? _buildReaderMode() : _buildNativeList(),
          ),
          _buildFabMenu(),
          SizedBox(
            height: 0,
            width: 0,
            child: WebViewWidget(controller: _hiddenController),
          ),
          SizedBox(
            height: 0,
            width: 0,
            child: WebViewWidget(controller: _favCheckController),
          ),
        ],
      ),
    );
  }

  Widget _buildFabMenu() {
    return Positioned(
      right: 16,
      bottom: 32,
      child: Opacity(
        opacity: (_isReaderMode && !_isFabOpen) ? 0.3 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_isFabOpen) ...[
              _buildFabItem(
                icon: Icons.refresh,
                label: "刷新",
                onTap: () {
                  setState(() {
                    _isLoading = true;
                    _posts.clear();
                    _targetPage = 1;
                    _minPage = 1;
                    _maxPage = 1;
                  });
                  _loadPage(1);
                  _toggleFab();
                },
              ),
              const SizedBox(height: 12),
              _buildFabItem(
                icon: Icons.bookmark_add,
                label: "保存进度",
                onTap: _saveBookmark,
              ),
              const SizedBox(height: 12),
              _buildFabItem(
                icon: _isFavorited ? Icons.star : Icons.star_border,
                label: _isFavorited ? "取消收藏" : "收藏本帖",
                color: _isFavorited ? Colors.yellow : null,
                onTap: _handleFavorite,
              ),
              const SizedBox(height: 12),
              if (_isReaderMode) ...[
                _buildFabItem(
                  icon: Icons.settings,
                  label: "阅读设置",
                  onTap: _showDisplaySettings,
                ),
                const SizedBox(height: 12),
              ],
              _buildFabItem(
                icon: _isOnlyLandlord ? Icons.people : Icons.person,
                label: _isOnlyLandlord ? "看全部" : "只看楼主",
                color: _isOnlyLandlord ? Colors.orange : null,
                onTap: _toggleOnlyLandlord,
              ),
              const SizedBox(height: 12),
              _buildFabItem(
                icon: _isReaderMode ? Icons.view_list : Icons.article,
                label: _isReaderMode ? "列表" : "阅读",
                onTap: _toggleReaderMode,
              ),
              const SizedBox(height: 12),
            ],
            FloatingActionButton(
              heroTag: "main_fab",
              onPressed: _toggleFab,
              backgroundColor: _isReaderMode
                  ? Colors.brown.shade300
                  : Theme.of(context).colorScheme.primaryContainer,
              child: AnimatedIcon(
                icon: AnimatedIcons.menu_close,
                progress: _fabAnimation,
                color: _isReaderMode ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFabItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ScaleTransition(
      scale: _fabAnimation,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            heroTag: label,
            onPressed: onTap,
            backgroundColor: color ?? Theme.of(context).colorScheme.surface,
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildNativeList() {
    if (_isLoading && _posts.isEmpty)
      return const Center(child: CircularProgressIndicator());

    bool showPrevBtn = _minPage > 1;
    int count = _posts.length + 1 + (showPrevBtn ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: count,
      separatorBuilder: (ctx, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (showPrevBtn && index == 0) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: _isLoadingPrev
                  ? const CircularProgressIndicator()
                  : TextButton.icon(
                      icon: const Icon(Icons.arrow_upward),
                      label: Text("加载上一页 (第 $_minPage 页之前)"),
                      onPressed: _loadPrev,
                    ),
            ),
          );
        }
        if (index == count - 1) return _buildFooter();

        int postIndex = showPrevBtn ? index - 1 : index;
        return _buildPostCard(_posts[postIndex]);
      },
    );
  }

  Widget _buildFooter() {
    if (_hasMore)
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    return const Padding(
      padding: EdgeInsets.all(30),
      child: Center(
        child: Text("--- 全文完 ---", style: TextStyle(color: Colors.grey)),
      ),
    );
  }

  Widget _buildPostCard(PostItem post) {
    final isLandlord = post.authorId == _landlordUid;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _jumpToUser(post),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: post.avatarUrl.isNotEmpty
                        ? NetworkImage(post.avatarUrl)
                        : null,
                    child: post.avatarUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            onTap: () => _jumpToUser(post),
                            child: Text(
                              post.author,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isLandlord) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "楼主",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        "${post.floor} · ${post.time}",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectionArea(
              child: HtmlWidget(
                post.contentHtml,
                textStyle: const TextStyle(fontSize: 16, height: 1.6),
                customWidgetBuilder: (element) {
                  if (element.localName == 'img') {
                    String src = element.attributes['src'] ?? '';
                    if (src.isNotEmpty) return _buildClickableImage(src);
                  }
                  return null;
                },
                customStylesBuilder: (element) {
                  if (element.localName == 'blockquote')
                    return {
                      'background-color': '#F5F5F5',
                      'border-left': '3px solid #DDD',
                      'padding': '8px',
                    };
                  return null;
                },
                onTapUrl: (url) async {
                  await _launchURL(url);
                  return true;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderMode() {
    if (_posts.isEmpty) return const Center(child: Text("暂无内容"));

    bool showPrevBtn = _minPage > 1;
    int count = _posts.length + 1 + (showPrevBtn ? 1 : 0);

    return Container(
      color: _readerBgColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        itemCount: count,
        itemBuilder: (context, index) {
          if (showPrevBtn && index == 0) {
            return Center(
              child: TextButton(
                onPressed: _loadPrev,
                child: const Text("加载上一页"),
              ),
            );
          }
          if (index == count - 1) return _buildFooter();

          int postIndex = showPrevBtn ? index - 1 : index;
          final post = _posts[postIndex];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (postIndex > 0)
                Divider(height: 40, color: _readerTextColor.withOpacity(0.1)),
              Text(
                "${post.floor} ${post.author}",
                style: TextStyle(
                  color: _readerTextColor.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              HtmlWidget(
                post.contentHtml,
                textStyle: TextStyle(
                  fontSize: _fontSize,
                  height: 1.8,
                  color: _readerTextColor,
                  fontFamily: "Serif",
                ),
                customWidgetBuilder: (element) {
                  if (element.localName == 'img') {
                    String src = element.attributes['src'] ?? '';
                    if (src.isNotEmpty) return _buildClickableImage(src);
                  }
                  return null;
                },
                onTapUrl: (url) async {
                  await _launchURL(url);
                  return true;
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
