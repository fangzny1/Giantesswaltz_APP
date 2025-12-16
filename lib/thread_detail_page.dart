import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_giantessnight_1/image_preview_page.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart'; // Add Dio
import 'package:cached_network_image/cached_network_image.dart'; // 建议引入这个库
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart'; // 引入库
import 'login_page.dart';
import 'user_detail_page.dart';
import 'forum_model.dart';
import 'cache_helper.dart'; // 引入缓存助手
import 'reply_native_page.dart'; // 引入原生回复页面

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
  final bool initialNovelMode;
  final String? initialAuthorId;
  final String? initialTargetFloor;
  final String? initialTargetPid;
  const ThreadDetailPage({
    super.key,
    required this.tid,
    required this.subject,
    this.initialPage = 1,
    this.initialNovelMode = false,
    this.initialAuthorId,
    this.initialTargetFloor,
    this.initialTargetPid,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage>
    with SingleTickerProviderStateMixin {
  WebViewController? _hiddenController;
  WebViewController? _favCheckController;
  // 使用 AutoScrollController 替换原生的 ScrollController
  late AutoScrollController _scrollController;

  List<PostItem> _posts = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isLoadingPrev = false;
  bool _hasMore = true;

  // 功能开关
  bool _isOnlyLandlord = false;
  bool _isReaderMode = false;
  bool _isNovelMode = false; // 【新增】小说模式
  bool _isFabOpen = false;

  bool _isFavorited = false;
  String? _favid;

  double _fontSize = 18.0; // 默认字体调大一点点，适合阅读
  Color _readerBgColor = const Color(0xFFFAF9DE); // 默认羊皮纸
  Color _readerTextColor = Colors.black87;

  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;

  late int _minPage;
  late int _maxPage;
  int _targetPage = 1;

  String? _landlordUid;
  String? _fid; // 板块ID
  String? _formhash; // 表单哈希，用于回复
  String? _posttime;
  int _postMinChars = 0;
  int _postMaxChars = 0;
  final String _baseUrl = "https://www.giantessnight.com/gnforum2012/";
  String _userCookies = "";
  final Map<String, GlobalKey> _floorKeys = {};
  final Map<String, GlobalKey> _pidKeys = {};

  @override
  @override
  void initState() {
    super.initState();
    // 1. 初始化页码：非常关键，要信赖传入的 initialPage
    _minPage = widget.initialPage;
    _maxPage = widget.initialPage;
    _targetPage = widget.initialPage;

    // 初始化 AutoScrollController
    _scrollController = AutoScrollController(
      viewportBoundaryGetter: () =>
          Rect.fromLTRB(0, 0, 0, MediaQuery.of(context).padding.bottom),
      axis: Axis.vertical,
      suggestedRowHeight: 200, // 估算高度
    );

    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _loadSettings();

    // 2. 初始化模式
    if (widget.initialNovelMode) {
      _isNovelMode = true;
      _isOnlyLandlord = true;
      _isReaderMode = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // 3. 楼主ID注入
      if (widget.initialAuthorId != null &&
          widget.initialAuthorId!.isNotEmpty) {
        _landlordUid = widget.initialAuthorId;
      }
    }

    _loadLocalCookie().then((_) {
      _initWebView();
      _initFavCheck(); // 等 Cookie 加载完再初始化
    });
    // scrollListener 保持不变
    _scrollController.addListener(_onScroll);
  }

  // 修改加载逻辑
  void _loadPage(int page) async {
    _targetPage = page;

    // 构造 URL
    String url =
        '${_baseUrl}forum.php?mod=viewthread&tid=${widget.tid}&mobile=no';
    if (_isOnlyLandlord && _landlordUid != null) {
      url += '&authorid=$_landlordUid';
    }
    url += '&page=$page';

    // 1. 尝试读取缓存 (极速加载)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey =
          'thread_cache_${widget.tid}_${page}_${_isOnlyLandlord ? "landlord" : "all"}';
      final cachedHtml = prefs.getString(cacheKey);

      if (cachedHtml != null && cachedHtml.isNotEmpty) {
        // 如果有缓存，立即解析并显示 (优化首屏速度)
        if (mounted) {
          _parseHtmlData(cachedHtml);
        }
      }
    } catch (e) {
      // 忽略缓存读取错误
    }

    // 2. 尝试使用 Dio 请求 (跳过 WebView 渲染，速度快且节省流量)
    bool useWebViewFallback = true;
    try {
      final dio = Dio();
      dio.options.headers['Cookie'] = _userCookies;
      dio.options.headers['User-Agent'] = kUserAgent;
      // 设置超时
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 15);

      // 请求 HTML
      final response = await dio.get<String>(url);

      if (response.statusCode == 200 && response.data != null) {
        String html = response.data!;
        // 简单校验是否是有效的帖子页面
        if (html.contains('id="postlist"') || html.contains('class="pl"')) {
          // 更新缓存
          final prefs = await SharedPreferences.getInstance();
          final cacheKey =
              'thread_cache_${widget.tid}_${page}_${_isOnlyLandlord ? "landlord" : "all"}';
          await prefs.setString(cacheKey, html);

          // 解析数据
          if (mounted) {
            _parseHtmlData(html);
          }
          useWebViewFallback = false; // 成功拿到数据，不需要 WebView
        }
      }
    } catch (e) {
      print("Dio request failed or blocked: $e. Fallback to WebView.");
    }

    // 3. 降级方案：使用 WebView (处理 Cloudflare、复杂 JS 或 Dio 失败的情况)
    if (useWebViewFallback && mounted) {
      // 【关键】使用 ?. 操作符，如果 controller 还没初始化就不执行
      // 配合 headers 注入 Cookie
      _hiddenController?.loadRequest(
        Uri.parse(url),
        headers: {'Cookie': _userCookies, 'User-Agent': kUserAgent},
      );
    }
  }

  Future<void> _loadLocalCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final String saved = prefs.getString('saved_cookie_string') ?? "";
    if (mounted) {
      setState(() {
        _userCookies = saved; // 赋值给全局变量，供图片加载使用
      });
    }
  }

  // 加载用户之前的阅读偏好
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int? colorVal = prefs.getInt('reader_bg_color');
    if (colorVal != null) {
      setState(() {
        _readerBgColor = Color(colorVal);
        // 简单的反色逻辑，如果是深色背景，字变白
        if (_readerBgColor.computeLuminance() < 0.5) {
          _readerTextColor = Colors.white70;
        } else {
          _readerTextColor = Colors.black87;
        }
      });
    }
  }

  // 保存设置
  Future<void> _saveSettings(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader_bg_color', color.value);
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
        _scrollController.position.maxScrollExtent - 800) {
      // 稍微提前一点加载
      _loadNext();
    }
  }

  void _initWebView() {
    // 1. 先创建对象
    final controller = WebViewController(); //

    // 2. 再配置 (这时候 controller 已经存在了，回调里可以用了)
    // 【修复：将级联操作符拆分，避免引用歧义】
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setUserAgent(kUserAgent);
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) async {
          try {
            // 这里现在可以安全使用 controller 了
            final String cookies =
                await controller.runJavaScriptReturningResult(
                      //
                      'document.cookie',
                    )
                    as String;
            String cleanCookies = cookies;
            if (cleanCookies.startsWith('"') && cleanCookies.endsWith('"')) {
              cleanCookies = cleanCookies.substring(1, cleanCookies.length - 1);
            }
            if (mounted) {
              setState(() {
                _userCookies = cleanCookies;
              });
            }
          } catch (e) {
            // Cookie 同步失败
          }
          _parseHtmlData();
        },
      ),
    );
    // 3. 赋值给全局变量并刷新 UI
    setState(() {
      _hiddenController = controller;
    }); //
    _loadPage(_targetPage); //
  }

  void _initFavCheck() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // 如果加载的是收藏列表页，解析它
            if (url.contains("do=favorite")) {
              _parseFavList();
            }
            // 如果是执行删除后的刷新
            else if (url.contains("op=delete") && url.contains("ac=favorite")) {
              // 自动点击“确定删除”按钮
              // 修复: 必须在 _favCheckController (加载收藏页面的WebView) 中执行点击，而不是主 WebView
              _favCheckController?.runJavaScript(
                "var btn = document.querySelector('button[name=\"deletesubmitbtn\"]'); if(btn) btn.click();",
              );
            }
          },
        ),
      );

    // 加载收藏页面 (用于检查当前帖子是否已收藏)
    controller.loadRequest(
      Uri.parse('${_baseUrl}home.php?mod=space&do=favorite&view=me&mobile=no'),
      headers: {'Cookie': _userCookies, 'User-Agent': kUserAgent},
    );

    setState(() {
      _favCheckController = controller;
    });
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

  // 【核心功能】切换小说模式
  void _toggleNovelMode() {
    if (_landlordUid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("正在获取楼主信息，请稍候...")));
      return;
    }

    setState(() {
      _isNovelMode = !_isNovelMode;

      // 开启小说模式 = 开启只看楼主 + 开启阅读模式
      if (_isNovelMode) {
        _isOnlyLandlord = true;
        _isReaderMode = true;
        // 沉浸式状态栏
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

        // 重置列表，重新加载只看楼主的数据
        _posts.clear();
        _pidKeys.clear();
        _floorKeys.clear();
        _minPage = 1;
        _maxPage = 1;
        _targetPage = 1;
        _isLoading = true;
        _loadPage(1);
      } else {
        // 关闭小说模式，恢复普通模式
        _isOnlyLandlord = false;
        _isReaderMode = false;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

        // 重新加载全部回复
        _posts.clear();
        _pidKeys.clear();
        _floorKeys.clear();
        _minPage = 1;
        _maxPage = 1;
        _targetPage = 1;
        _isLoading = true;
        _loadPage(1);
      }
      _toggleFab();
    });
  }

  // 切换普通阅读模式（不强制只看楼主）
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
    _toggleFab(); // 关菜单

    if (_isFavorited) {
      // === 取消收藏逻辑 ===
      if (_favid != null) {
        String delUrl =
            "${_baseUrl}home.php?mod=spacecp&ac=favorite&op=delete&favid=$_favid&type=all";
        // 后台 WebView 去请求删除链接
        _favCheckController?.loadRequest(Uri.parse(delUrl));

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));

        // 3秒后刷新列表确认状态
        Future.delayed(const Duration(seconds: 3), () {
          _favCheckController?.loadRequest(
            Uri.parse(
              '${_baseUrl}home.php?mod=space&do=favorite&view=me&mobile=no',
            ),
            headers: {'Cookie': _userCookies, 'User-Agent': kUserAgent},
          );
        });

        setState(() {
          _isFavorited = false;
          _favid = null;
        });
      }
    } else {
      // === 添加收藏逻辑 ===
      // 借用主 WebView 执行 JS 点击收藏按钮 (因为主 WebView 就在帖子页面)
      _hiddenController?.runJavaScript(
        "if(document.querySelector('#k_favorite')) document.querySelector('#k_favorite').click();",
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已发送收藏请求")));
      setState(() {
        _isFavorited = true;
      });

      // 3秒后刷新收藏列表获取 favid
      Future.delayed(const Duration(seconds: 3), () {
        _favCheckController?.loadRequest(
          Uri.parse(
            '${_baseUrl}home.php?mod=space&do=favorite&view=me&mobile=no',
          ),
          headers: {'Cookie': _userCookies, 'User-Agent': kUserAgent},
        );
      });
    }
  }

  void _showSaveBookmarkDialog() {
    if (_posts.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "选择你读到的楼层进行存档",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  // 倒序显示，因为大家通常是看到最新的（最底下）
                  // 如果想正序（从第1楼开始），就用 final post = _posts[index];
                  final int reverseIndex = _posts.length - 1 - index;
                  final post = _posts[reverseIndex];

                  // 简单的摘要提取
                  String summary = post.contentHtml
                      .replaceAll(RegExp(r'<[^>]*>'), '') // 去掉HTML标签
                      .replaceAll('&nbsp;', ' ')
                      .trim();
                  if (summary.length > 30)
                    summary = "${summary.substring(0, 30)}...";
                  if (summary.isEmpty) summary = "[图片/表情]";

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text(
                        post.floor.replaceAll("楼", ""),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(
                      post.author,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.bookmark_add_outlined),
                    onTap: () {
                      // 解析楼层号并反推页码（Discuz 默认每页10楼）
                      int pageToSave = _maxPage;
                      final m = RegExp(r'(\\d+)').firstMatch(post.floor);
                      if (m != null) {
                        int floorNum = int.tryParse(m.group(1)!) ?? 0;
                        if (floorNum > 0)
                          pageToSave = ((floorNum - 1) ~/ 10) + 1;
                      }
                      _saveBookmarkWithFloor(
                        post.floor,
                        pageToSave,
                        pid: post.pid,
                      );
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveBookmarkWithFloor(
    String floorName,
    int pageToSave, {
    String? pid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('local_bookmarks');
    List<dynamic> jsonList = [];
    if (jsonStr != null && jsonStr.startsWith("["))
      jsonList = jsonDecode(jsonStr);

    String subjectSuffix = _isNovelMode ? " (小说)" : "";

    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: widget.subject.replaceAll(" (小说)", "") + subjectSuffix,
      author: _posts.isNotEmpty ? _posts.first.author : "未知",
      authorId: _landlordUid ?? "",
      page: pageToSave, // 保存当前最大页码
      // 这里的 savedTime 我们利用一下，存入具体的楼层信息，方便列表显示
      savedTime:
          "${DateTime.now().toString().substring(5, 16)} · 读至 $floorName",
      isNovelMode: _isNovelMode,
      targetPid: pid,
      targetFloor: floorName,
    );

    jsonList.removeWhere((e) => e['tid'] == widget.tid);
    jsonList.insert(0, newMark.toJson());
    await prefs.setString('local_bookmarks', jsonEncode(jsonList));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("已保存进度：第 $pageToSave 页 - $floorName")),
      );
    }
  }

  // _saveBookmark unused

  void _toggleOnlyLandlord() {
    if (_landlordUid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("未找到楼主信息")));
      return;
    }
    setState(() {
      _isOnlyLandlord = !_isOnlyLandlord;
      // 如果手动切换只看楼主，退出小说模式状态（逻辑上解耦）
      if (!_isOnlyLandlord) _isNovelMode = false;
      _posts.clear();
      _pidKeys.clear();
      _floorKeys.clear();
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
    if (_favCheckController == null) return;
    try {
      final String rawHtml =
          await _favCheckController!.runJavaScriptReturningResult(
                "document.documentElement.outerHTML",
              )
              as String;

      String cleanHtml = _cleanHtml(rawHtml);
      var document = html_parser.parse(cleanHtml);

      // Discuz 收藏列表通常在 id="favorite_ul"
      var items = document.querySelectorAll('ul[id="favorite_ul"] li');
      String? foundFavid;

      for (var item in items) {
        // 检查有没有当前 TID 的链接
        var link = item.querySelector('a[href*="tid=${widget.tid}"]');
        if (link != null) {
          // 如果找到了，提取 favid (用于删除)
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
    } catch (e) {
      // 收藏解析出错
    }
  }

  // === 核心解析逻辑 ===
  Future<void> _parseHtmlData([String? inputHtml]) async {
    // 允许传入 HTML 字符串（来自 Dio 或 Cache），或者从 WebView 提取
    if (inputHtml == null && _hiddenController == null) return;
    try {
      String rawHtml;
      if (inputHtml != null) {
        rawHtml = inputHtml;
      } else {
        final result = await _hiddenController!.runJavaScriptReturningResult(
          "document.documentElement.outerHTML",
        );
        rawHtml = result as String;
        // WebView 返回的是 JSON 字符串 (带双引号)，需要反序列化
        if (rawHtml.startsWith('"') && rawHtml.endsWith('"')) {
          rawHtml = jsonDecode(rawHtml);
        }
      }

      // 【新增】统一缓存保存逻辑
      // 只有当页面看起来像是正常的帖子页面时才保存
      if (rawHtml.contains('id="postlist"') || rawHtml.contains('class="pl"')) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final cacheKey =
              'thread_cache_${widget.tid}_${_targetPage}_${_isOnlyLandlord ? "landlord" : "all"}';
          await prefs.setString(cacheKey, rawHtml);
        } catch (e) {
          // 缓存保存失败忽略
        }
      }

      String cleanHtml = _cleanHtml(rawHtml);
      var document = html_parser.parse(cleanHtml);

      // 解析 fid
      if (_fid == null) {
        var fidMatch = RegExp(r'fid=(\d+)').firstMatch(cleanHtml);
        if (fidMatch != null) {
          _fid = fidMatch.group(1);
        }
      }

      // 解析 formhash
      if (_formhash == null) {
        // 尝试从 input 标签提取
        var hashMatch = RegExp(
          r'name="formhash" value="([^"]+)"',
        ).firstMatch(cleanHtml);
        if (hashMatch != null) {
          _formhash = hashMatch.group(1);
        } else {
          // 尝试从 URL 参数提取
          hashMatch = RegExp(r'formhash=([a-zA-Z0-9]+)').firstMatch(cleanHtml);
          if (hashMatch != null) {
            _formhash = hashMatch.group(1);
          }
        }
      }

      // 解析 posttime
      if (_posttime == null) {
        var timeMatch = RegExp(
          r'id="posttime" value="(\d+)"',
        ).firstMatch(cleanHtml);
        if (timeMatch != null) {
          _posttime = timeMatch.group(1);
        }
      }

      // Extract min/max chars
      var minCharsMatch = RegExp(
        r"var postminchars = parseInt\('(\d+)'\);",
      ).firstMatch(cleanHtml);
      if (minCharsMatch != null) {
        _postMinChars = int.tryParse(minCharsMatch.group(1)!) ?? 0;
      }
      var maxCharsMatch = RegExp(
        r"var postmaxchars = parseInt\('(\d+)'\);",
      ).firstMatch(cleanHtml);
      if (maxCharsMatch != null) {
        _postMaxChars = int.tryParse(maxCharsMatch.group(1)!) ?? 0;
      }

      // 1. 建立 AID -> 静态 URL 映射
      Map<String, String> aidToStaticUrl = {};
      var attachmentImgs = document.querySelectorAll('img[aid][zoomfile]');
      for (var img in attachmentImgs) {
        String? aid = img.attributes['aid'];
        String? url = img.attributes['zoomfile'];
        if (aid != null && url != null && url.contains("data/attachment")) {
          aidToStaticUrl[aid] = url;
        }
      }
      for (var img in attachmentImgs) {
        String? aid = img.attributes['aid'];
        String? url = img.attributes['file'];
        if (aid != null && url != null && url.contains("data/attachment")) {
          if (!aidToStaticUrl.containsKey(aid)) {
            aidToStaticUrl[aid] = url;
          }
        }
      }

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

          // === 修复：拼接 .pattl 附件区到正文 ===
          var contentNode = div.querySelector('td.t_f');
          String content = contentNode?.innerHtml ?? "";
          var attachmentNode = div.querySelector('.pattl');
          if (attachmentNode != null) {
            content +=
                "<br><div class='attachments'>${attachmentNode.innerHtml}</div>";
          }
          // =================================

          // === 清洗内容 ===
          content = content.replaceAll(r'\n', '<br>');
          content = content.replaceAll('<div class="mbn savephotop">', '<div>');

          // 智能替换图片
          content = content.replaceAllMapped(
            RegExp(r'<img[^>]+>', dotAll: true),
            (match) {
              String imgTag = match.group(0)!;
              String? zoomUrl = RegExp(
                r'zoomfile="([^"]+)"',
              ).firstMatch(imgTag)?.group(1);
              String? fileUrl = RegExp(
                r'file="([^"]+)"',
              ).firstMatch(imgTag)?.group(1);
              String? srcUrl = RegExp(
                r'src="([^"]+)"',
              ).firstMatch(imgTag)?.group(1);

              String? aidFromUrl;
              RegExp aidReg = RegExp(r'aid=(\d+)');
              if (fileUrl != null)
                aidFromUrl = aidReg.firstMatch(fileUrl)?.group(1);
              if (aidFromUrl == null && srcUrl != null)
                aidFromUrl = aidReg.firstMatch(srcUrl)?.group(1);

              String bestUrl = "";

              if (aidFromUrl != null &&
                  aidToStaticUrl.containsKey(aidFromUrl)) {
                bestUrl = aidToStaticUrl[aidFromUrl]!;
              } else if (zoomUrl != null &&
                  zoomUrl.contains("data/attachment")) {
                bestUrl = zoomUrl;
              } else if (fileUrl != null &&
                  fileUrl.contains("data/attachment")) {
                bestUrl = fileUrl;
              } else if (srcUrl != null && srcUrl.contains("data/attachment")) {
                bestUrl = srcUrl;
              } else if (fileUrl != null && fileUrl.isNotEmpty) {
                bestUrl = fileUrl;
              } else if (srcUrl != null && srcUrl.isNotEmpty) {
                if (!srcUrl.contains("loading.gif") &&
                    !srcUrl.contains("none.gif") &&
                    !srcUrl.contains("common.gif")) {
                  bestUrl = srcUrl;
                }
              }

              if (bestUrl.isNotEmpty) {
                bestUrl = bestUrl.replaceAll('&amp;', '&');
                if (bestUrl.contains("mod=image")) {
                  bestUrl = bestUrl.replaceAll(RegExp(r'&mobile=[0-9]+'), '');
                  bestUrl = bestUrl.replaceAll(RegExp(r'&mobile=yes'), '');
                  bestUrl = bestUrl.replaceAll(RegExp(r'&mobile=no'), '');
                  bestUrl = bestUrl.replaceAll('&type=fixnone', '');
                }
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

          // 【核心修复】更严格的到底判断逻辑
          if (!hasNextPage) {
            // 如果网页里没有“下一页”按钮，那肯定到底了
            _hasMore = false;
          } else if (_targetPage >= _maxPage && newPosts.isEmpty) {
            // 如果请求了下一页，但没解析出数据，也算到底了
            _hasMore = false;
          } else if (newPosts.length < 5) {
            // 如果这一页的数据少得可怜（通常 Discuz 一页 10-20 楼），大概率是最后一页
            _hasMore = false;
          } else {
            // 否则才认为还有更多
            _hasMore = true;
          }
          _isLoading = false;
          _isLoadingMore = false;
          _isLoadingPrev = false;
        });
        // 渲染完成后定位到目标楼层
        if (widget.initialTargetFloor != null ||
            widget.initialTargetPid != null) {
          _scrollToTargetFloor();
        }
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _isLoadingPrev = false;
        });
      // 解析异常时不再尝试自动定位
    }
  }

  // 滚动的重试逻辑 (现在使用 scroll_to_index)
  Future<void> _scrollToTargetFloor() async {
    if (_posts.isEmpty) return;

    // 找到目标索引
    int targetIndex = -1;

    // 1. 优先尝试 PID 定位
    if (widget.initialTargetPid != null) {
      targetIndex = _posts.indexWhere((p) => p.pid == widget.initialTargetPid);
    }

    // 2. 降级尝试楼层号定位
    if (targetIndex == -1 && widget.initialTargetFloor != null) {
      targetIndex = _posts.indexWhere(
        (p) => p.floor == widget.initialTargetFloor,
      );
    }

    if (targetIndex != -1) {
      // 稍微延迟一下等待列表构建
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // 这里的 listIndex 其实是 ListView 的 children 索引
      // 但是 AutoScrollTag 是按 index 绑定的，我们需要确保 Tag 的 index 和这里一致
      // 下面构建列表时，我会把 index 设为 post 在 _posts 中的 index，所以这里直接用 targetIndex 即可

      await _scrollController.scrollToIndex(
        targetIndex,
        preferPosition: AutoScrollPosition.begin,
        duration: const Duration(milliseconds: 800),
      );

      // 二次确认 (防止图片加载挤压)
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      await _scrollController.scrollToIndex(
        targetIndex,
        preferPosition: AutoScrollPosition.begin,
        duration: const Duration(milliseconds: 400),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("已定位到上次阅读位置"),
          duration: const Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // 未找到目标楼层/PID
    }
  }

  // 【核心升级】使用 CachedNetworkImage + 弱网点击重试
  Widget _buildClickableImage(String url) {
    if (url.isEmpty) return const SizedBox();
    // ... (URL 补全逻辑保持不变)
    String fullUrl = url;
    if (!fullUrl.startsWith('http')) {
      // ... 省略 URL 补全代码，保持你原来的 ...
      String base = _baseUrl.endsWith('/') ? _baseUrl : "$_baseUrl/";
      String path = fullUrl.startsWith('/') ? fullUrl.substring(1) : fullUrl;
      fullUrl = base + path;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewPage(
              imageUrl: fullUrl,
              headers: {
                'Cookie': _userCookies,
                'User-Agent': kUserAgent,
                'Referer': _baseUrl,
              },
              cacheManager: globalImageCache, // 【修改】传递全局缓存管理器
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: CachedNetworkImage(
          imageUrl: fullUrl,
          cacheManager: globalImageCache, // 【修改】使用全局缓存变量
          // ... (Headers 和 其他逻辑保持不变) ...
          httpHeaders: {
            'Cookie': _userCookies,
            'User-Agent': kUserAgent,
            'Referer': _baseUrl,
            'Accept':
                'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          },
          fit: BoxFit.contain,
          // ... placeholder 和 errorWidget 保持不变 ...
          // 为了节省篇幅，这里 errorWidget 里的 removeFile 也要改成:
          // await globalImageCache.removeFile(url);
          placeholder: (context, url) => Container(
            height: 200,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => InkWell(
            onTap: () async {
              await globalImageCache.removeFile(url); // 【修改】
              if (mounted) setState(() {});
            },
            child: const SizedBox(
              height: 100,
              child: Center(child: Icon(Icons.refresh)),
            ),
          ),
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
              height: 320,
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
                    "背景颜色 (自动保存)",
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
                      ), // 羊皮纸
                      _buildColorBtn(
                        const Color(0xFFC7EDCC),
                        Colors.black87,
                        "豆沙",
                      ), // 护眼绿
                      _buildColorBtn(
                        const Color(0xFF1A1A1A),
                        Colors.white70,
                        "夜间",
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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
    bool isSelected = _readerBgColor.value == bg.value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _readerBgColor = bg;
          _readerTextColor = text;
        });
        _saveSettings(bg); // 保存设置
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
          CustomScrollView(
            controller: _scrollController,
            cacheExtent: 20000,
            slivers: [
              if (!_isReaderMode)
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

              if (_isReaderMode) _buildReaderSliver() else _buildNativeSliver(),
            ],
          ),

          _buildFabMenu(),

          // === 【核心修复】空值保护 ===
          // 只有当 controller 不为空时，才渲染 WebViewWidget
          if (_hiddenController != null)
            SizedBox(
              height: 0,
              width: 0,
              child: WebViewWidget(controller: _hiddenController!), // 加 ! 号
            ),

          if (_favCheckController != null)
            SizedBox(
              height: 0,
              width: 0,
              child: WebViewWidget(controller: _favCheckController!), // 加 ! 号
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
                    _pidKeys.clear();
                    _floorKeys.clear();
                    // 刷新时重置为第一页，或者保持当前页？
                    // 建议重置，防止逻辑混乱
                    _targetPage = 1;
                    _minPage = 1;
                    _maxPage = 1;
                  });
                  _loadPage(1);
                  _toggleFab();
                },
              ),
              const SizedBox(height: 12),

              // === 手动书签 ===
              _buildFabItem(
                icon: Icons.bookmark_add,
                label: "保存进度",
                onTap: () {
                  _toggleFab();
                  _showSaveBookmarkDialog();
                },
              ),
              const SizedBox(height: 12),

              // === 【核心修复】找回消失的收藏按钮 ===
              _buildFabItem(
                icon: _isFavorited ? Icons.star : Icons.star_border,
                label: _isFavorited ? "取消收藏" : "收藏本帖",
                color: _isFavorited
                    ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors
                                .yellow
                                .shade700 // 暗黑模式下使用深一点的黄
                          : Colors
                                .yellow
                                .shade200 // 亮色模式下使用淡一点的黄
                                )
                    : null, // 未收藏时颜色为默认（通常是灰色或主题色）
                onTap: _handleFavorite,
              ),
              const SizedBox(height: 12),

              // ===================================
              _buildFabItem(
                icon: _isNovelMode ? Icons.auto_stories : Icons.menu_book,
                label: _isNovelMode ? "退出小说" : "小说模式",
                color: _isNovelMode ? Colors.purpleAccent : null,
                onTap: _toggleNovelMode,
              ),
              const SizedBox(height: 12),

              // 只有非小说模式才显示“只看楼主”和“纯净阅读”
              if (!_isNovelMode) ...[
                _buildFabItem(
                  icon: _isOnlyLandlord ? Icons.people : Icons.person,
                  label: _isOnlyLandlord ? "看全部" : "只看楼主",
                  color: _isOnlyLandlord ? Colors.orange : null,
                  onTap: _toggleOnlyLandlord,
                ),
                const SizedBox(height: 12),
                _buildFabItem(
                  icon: _isReaderMode ? Icons.view_list : Icons.article,
                  label: _isReaderMode ? "列表" : "纯净阅读",
                  onTap: _toggleReaderMode,
                ),
                const SizedBox(height: 12),
              ],

              if (_isReaderMode) ...[
                _buildFabItem(
                  icon: Icons.settings,
                  label: "设置",
                  onTap: _showDisplaySettings,
                ),
                const SizedBox(height: 12),
              ],
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

  Widget _buildNativeSliver() {
    if (_isLoading && _posts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    bool showPrevBtn = _minPage > 1;

    List<Widget> children = [];

    if (showPrevBtn) {
      children.add(
        Padding(
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
        ),
      );
    }

    for (var post in _posts) {
      children.add(_buildPostCard(post));
      children.add(const SizedBox(height: 8));
    }

    children.add(_buildFooter());

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 100),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
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

  void _onReply(String? pid) {
    if (_fid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("正在加载板块信息，请稍候...")));
      return;
    }

    if (_formhash == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("缺少安全令牌(formhash)，请刷新页面重试")));
      return;
    }

    // 原生回复页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReplyNativePage(
          tid: widget.tid,
          fid: _fid!,
          pid: pid,
          formhash: _formhash!,
          posttime: _posttime,
          minChars: _postMinChars,
          maxChars: _postMaxChars,
          baseUrl: _baseUrl,
          userCookies: _userCookies,
        ),
      ),
    ).then((success) {
      if (success == true) {
        // 刷新页面
        if (_targetPage == _maxPage) {
          _loadPage(_maxPage);
        } else {
          // 如果不在最后一页，询问是否跳转？或者直接跳转到最后一页
          // 这里简单处理：刷新当前页，因为新回复可能在后面
          // 或者直接加载最后一页
          _loadPage(_maxPage);
        }
      }
    });
  }

  Widget _buildPostCard(PostItem post) {
    // 获取当前 post 的索引，用于 AutoScrollTag
    int index = _posts.indexOf(post);

    final GlobalKey anchorKey = _pidKeys.putIfAbsent(
      post.pid,
      () => GlobalKey(),
    );
    _floorKeys[post.floor] = anchorKey;
    final isLandlord = post.authorId == _landlordUid;

    // 使用 AutoScrollTag 包裹
    return AutoScrollTag(
      key: ValueKey(index),
      controller: _scrollController,
      index: index,
      child: Container(
        key: anchorKey,
        child: Card(
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
                    // 回复按钮
                    IconButton(
                      icon: const Icon(Icons.reply, size: 20),
                      onPressed: () => _onReply(post.pid),
                      color: Colors.grey,
                      tooltip: "回复此楼",
                    ),
                  ],
                ),
                // ... 在 _buildPostCard 方法里 ...
                const SizedBox(height: 12),
                SelectionArea(
                  child: HtmlWidget(
                    post.contentHtml,
                    textStyle: const TextStyle(fontSize: 16, height: 1.6),

                    // 【修复版】样式构建器
                    customStylesBuilder: (element) {
                      bool isDarkMode =
                          Theme.of(context).brightness == Brightness.dark;

                      // 1. 处理引用块 (Discuz 的回复框)
                      if (element.localName == 'blockquote' ||
                          element.classes.contains('quote')) {
                        if (isDarkMode) {
                          // 暗黑模式：深灰底 + 白字
                          return {
                            'background-color': '#303030',
                            'color': '#E0E0E0',
                            'border-left': '3px solid #777',
                            'padding': '10px',
                            'margin': '5px 0',
                            'display': 'block', // 强制块级显示
                          };
                        } else {
                          // 日间模式：浅灰底 + 黑字
                          return {
                            'background-color': '#F5F5F5',
                            'color': '#333333',
                            'border-left': '3px solid #DDD',
                            'padding': '10px',
                            'margin': '5px 0',
                            'display': 'block',
                          };
                        }
                      }

                      // 2. 【关键修复】处理暗黑模式下，作者写死的颜色看不见的问题
                      // 我们检查 style 属性字符串，而不是不存在的 .styles 对象
                      if (isDarkMode &&
                          element.attributes.containsKey('style')) {
                        String style = element.attributes['style']!;
                        // 如果包含了 color 设置（比如作者设了黑色），在暗黑模式下强制反转或者清除
                        if (style.contains('color:')) {
                          // 这里简单粗暴一点：如果是暗黑模式，且不是引用块，
                          // 我们可以强制清除背景色，并将字体设为浅色，防止黑底黑字
                          return {
                            'color': '#CCCCCC', // 强制浅灰色字
                            'background-color': 'transparent', // 清除背景
                          };
                        }
                      }

                      return null;
                    },

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
                ),
                // ...
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderSliver() {
    if (_posts.isEmpty) {
      return const SliverFillRemaining(child: Center(child: Text("加载中...")));
    }

    bool showPrevBtn = _minPage > 1;

    List<Widget> children = [];

    if (showPrevBtn) {
      children.add(
        Center(
          child: TextButton(onPressed: _loadPrev, child: const Text("加载上一页")),
        ),
      );
    }

    for (int i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      // 注册 Key，用于自动定位
      final GlobalKey anchorKey = _pidKeys.putIfAbsent(
        post.pid,
        () => GlobalKey(),
      );
      _floorKeys[post.floor] = anchorKey;

      children.add(
        AutoScrollTag(
          key: ValueKey(i),
          controller: _scrollController,
          index: i,
          child: Container(
            key: anchorKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i > 0)
                  Divider(height: 60, color: _readerTextColor.withOpacity(0.1)),

                // 极简信息栏
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      post.floor,
                      style: TextStyle(
                        color: _readerTextColor.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                    if (_isNovelMode)
                      Text(
                        "第 ${_maxPage} 页", // 小说模式显示页码进度
                        style: TextStyle(
                          color: _readerTextColor.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                HtmlWidget(
                  post.contentHtml,
                  textStyle: TextStyle(
                    fontSize: _fontSize,
                    height: 1.8,
                    color: _readerTextColor,
                    fontFamily: "Serif",
                  ),

                  // 【修复点】正确的样式清洗逻辑
                  customStylesBuilder: (element) {
                    // 仅在阅读模式下启用
                    if (_isReaderMode) {
                      // 1. 处理 <font color="..."> 这种老式标签
                      if (element.localName == 'font' ||
                          element.attributes.containsKey('style')) {
                        return {
                          'color': _readerTextColor.toCssColor(),
                          'background-color': 'transparent',
                        };
                      }

                      // 2. 处理 style="..." 属性 (element.attributes 是 Map)
                      if (element.attributes.containsKey('style')) {
                        String style = element.attributes['style']!;
                        // 如果 style 字符串里包含 color 或 background
                        if (style.contains('color') ||
                            style.contains('background')) {
                          return {
                            'color': _readerTextColor.toCssColor(),
                            'background-color': 'transparent',
                          };
                        }
                      }
                    }

                    // 2. 【核心修复】处理引用块
                    if (element.localName == 'blockquote' ||
                        element.classes.contains('quote')) {
                      // 阅读模式下，我们根据背景色深浅来决定引用块颜色
                      // 如果背景很暗（夜间模式），引用块就用深色
                      if (_readerBgColor.computeLuminance() < 0.5) {
                        return {
                          'background-color':
                              'rgba(255, 255, 255, 0.1)', // 半透明白
                          'color': '#E0E0E0',
                          'border-left': '3px solid #777',
                          'padding': '10px',
                        };
                      } else {
                        // 亮色背景（羊皮纸/白昼），引用块用浅色
                        return {
                          'background-color': 'rgba(0, 0, 0, 0.05)', // 半透明黑
                          'color': '#333333',
                          'border-left': '3px solid #999',
                          'padding': '10px',
                        };
                      }
                    }

                    return null;
                  },

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
            ),
          ),
        ),
      );
    }

    children.add(_buildFooter());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
    );
  }
}

extension ColorToCss on Color {
  String toCssColor() {
    return 'rgba($red, $green, $blue, $opacity)';
  }
}

// ==========================================
// 新增：独立的重试图片组件
// ==========================================
class RetryableImage extends StatefulWidget {
  final String imageUrl;
  final BaseCacheManager cacheManager;
  final Map<String, String> headers;
  final Function(String) onTap;

  const RetryableImage({
    super.key,
    required this.imageUrl,
    required this.cacheManager,
    required this.headers,
    required this.onTap,
  });

  @override
  State<RetryableImage> createState() => _RetryableImageState();
}

class _RetryableImageState extends State<RetryableImage> {
  int _retryCount = 0; // 重试计数器

  @override
  Widget build(BuildContext context) {
    // 技巧：每次重试，给 URL 加一个不同的参数，骗过缓存系统
    // 如果 URL 本身有 ? 就加 &t=，否则加 ?t=
    String finalUrl = widget.imageUrl;
    if (_retryCount > 0) {
      final separator = finalUrl.contains('?') ? '&' : '?';
      finalUrl = "$finalUrl${separator}retry=$_retryCount";
    }

    return GestureDetector(
      onTap: () => widget.onTap(widget.imageUrl), // 点击预览时传原图URL
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: CachedNetworkImage(
          // 关键：给 Key 加上计数器，强制组件重建
          key: ValueKey("${widget.imageUrl}_$_retryCount"),
          imageUrl: finalUrl,
          cacheManager: widget.cacheManager,
          httpHeaders: widget.headers,
          fit: BoxFit.contain,

          // 加载中
          placeholder: (context, url) => Container(
            height: 200,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),

          // 加载失败
          errorWidget: (ctx, url, error) {
            return InkWell(
              onTap: () async {
                // 1. 清理旧缓存
                await widget.cacheManager.removeFile(widget.imageUrl);
                // 2. 增加计数器，触发重绘
                setState(() {
                  _retryCount++;
                });
                // 3. 提示
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("正在尝试重新建立连接..."),
                      duration: Duration(milliseconds: 500),
                    ),
                  );
                }
              },
              child: Container(
                height: 120,
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "图片加载失败",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      "点击此处强制刷新 (第$_retryCount次)",
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
