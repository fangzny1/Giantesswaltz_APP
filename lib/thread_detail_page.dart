import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart'; // 现在已正确使用
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'login_page.dart';
import 'user_detail_page.dart';
import 'forum_model.dart';
import 'http_service.dart';
import 'reply_native_page.dart';
import 'image_preview_page.dart';
import 'offline_manager.dart';

// ==========================================
// 1. 数据模型定义
// ==========================================
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

// ==========================================
// 2. 主页面
// ==========================================
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
    with TickerProviderStateMixin {
  late AutoScrollController _scrollController;
  bool _hasPerformedInitialJump = false;

  List<PostItem> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isLoadingPrev = false;

  bool _isOnlyLandlord = false;
  bool _isReaderMode = false;
  bool _isNovelMode = false;
  bool _isFabOpen = false;
  bool _isFavorited = false;
  String? _favid;

  double _fontSize = 18.0;
  Color _readerBgColor = const Color(0xFFFAF9DE);
  Color _readerTextColor = Colors.black87;

  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;
  late AnimationController _hideController;
  bool _isBarsVisible = true;

  late int _minPage;
  int _targetPage = 1;
  int _totalPages = 1;

  String? _landlordUid;
  String? _fid;
  String? _formhash;
  String? _posttime;
  int _postMinChars = 0;
  int _postMaxChars = 0;
  String _userCookies = "";

  String? _currentRawJson;

  final Map<String, GlobalKey> _floorKeys = {};
  final Map<String, GlobalKey> _pidKeys = {};

  DateTime _lastAutoPageTurn = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isScrubbingScroll = false;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _minPage = widget.initialPage;
    _targetPage = widget.initialPage;

    _scrollController = AutoScrollController(
      viewportBoundaryGetter: () =>
          Rect.fromLTRB(0, 0, 0, MediaQuery.of(context).padding.bottom),
      axis: Axis.vertical,
      suggestedRowHeight: 200,
    );

    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _hideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    _loadSettings();

    if (widget.initialNovelMode) {
      _isNovelMode = true;
      _isOnlyLandlord = true;
      _isReaderMode = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (widget.initialAuthorId != null &&
          widget.initialAuthorId!.isNotEmpty) {
        _landlordUid = widget.initialAuthorId;
      }
    }

    _loadLocalCookie().then((_) {
      _loadPage(_targetPage, resetScroll: true);
      _refreshFavoriteStatus();
    });

    _scrollController.addListener(_handleEdgePaging);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    _fabAnimationController.dispose();
    _hideController.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int page, {bool resetScroll = false}) async {
    _targetPage = page;
    if (mounted) setState(() => _isLoading = true);

    // 1. 优先展示 SharedPreferences 的临时缓存 (秒开)
    final prefs = await SharedPreferences.getInstance();
    final String tempCacheKey = 'thread_temp_cache_${widget.tid}_$page';
    final String? tempCache = prefs.getString(tempCacheKey);
    if (tempCache != null && _posts.isEmpty) {
      try {
        _processApiResponse(jsonDecode(tempCache));
      } catch (_) {}
    }

    String url =
        '${kBaseUrl}api/mobile/index.php?version=4&module=viewthread&tid=${widget.tid}&page=$page';
    if (_isOnlyLandlord && _landlordUid != null)
      url += '&authorid=$_landlordUid';

    try {
      // 2. 尝试网络请求
      String responseBody = await HttpService().getHtml(url);

      if (responseBody.startsWith('"') && responseBody.endsWith('"')) {
        responseBody = jsonDecode(responseBody);
      }
      final data = jsonDecode(responseBody);

      // 检查登录过期
      if (data['Message'] != null &&
          data['Message']['messageval'] == 'to_login') {
        throw "Login Expired"; // 抛出异常，进入 catch 尝试读取离线
      }

      // 网络成功：更新缓存和界面
      await prefs.setString(tempCacheKey, responseBody);
      _currentRawJson = responseBody;
      _processApiResponse(data);

      if (resetScroll && _scrollController.hasClients)
        _scrollController.jumpTo(0);
    } catch (e) {
      print("⚠️ 网络请求失败: $e，尝试读取离线缓存...");

      // 3. 【核心修复】网络失败，尝试读取 "OfflineManager" (Documents目录)
      String? offlineData = await OfflineManager().readPage(widget.tid, page);

      if (offlineData != null && offlineData.isNotEmpty) {
        print("✅ 成功读取离线文件");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("当前无网络，已加载离线存档")));
        }
        try {
          _currentRawJson = offlineData; // 赋值给这个，确保可以再次保存
          final data = jsonDecode(offlineData);
          _processApiResponse(data); // 解析显示
        } catch (err) {
          print("❌ 离线数据解析失败: $err");
        }
      } else {
        print("❌ 本地无离线文件");
        // 只有在没数据的时候才提示错误
        if (_posts.isEmpty && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("加载失败，且无本地缓存")));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _isLoadingPrev = false;
        });
      }
    }
  }

  void _processApiResponse(dynamic data) {
    final vars = data['Variables'];
    if (vars == null) return;

    _fid = vars['fid']?.toString();
    _formhash = vars['formhash']?.toString();

    if (vars['postminchars'] != null) {
      _postMinChars = int.tryParse(vars['postminchars'].toString()) ?? 0;
    }

    final threadInfo = vars['thread'];
    if (threadInfo != null) {
      if (_landlordUid == null) {
        _landlordUid = threadInfo['authorid']?.toString();
      }
      int allReplies =
          int.tryParse(threadInfo['allreplies']?.toString() ?? '0') ?? 0;
      int ppp = int.tryParse(vars['ppp']?.toString() ?? '10') ?? 10;
      _totalPages = ((allReplies + 1) / ppp).ceil();
    }

    var rawPostList = vars['postlist'];
    Iterable items = [];
    if (rawPostList is List) {
      items = rawPostList;
    } else if (rawPostList is Map) {
      items = rawPostList.values;
    }

    List<PostItem> newPosts = [];
    for (var p in items) {
      String pid = p['pid']?.toString() ?? "";
      String authorId = p['authorid']?.toString() ?? "";

      if (_landlordUid == null && (p['first'] == "1" || p['first'] == 1)) {
        _landlordUid = authorId;
      }

      String content = p['message']?.toString() ?? "";

      if (p['attachments'] != null && p['attachments'] is Map) {
        Map<String, dynamic> attachments = Map<String, dynamic>.from(
          p['attachments'],
        );
        String attachHtml = "<br/>";
        attachments.forEach((key, attach) {
          String fullImgUrl = "${attach['url']}${attach['attachment']}";
          attachHtml +=
              '<img src="$fullImgUrl" style="max-width:100%;" /><br/>';
        });
        content += attachHtml;
      }

      newPosts.add(
        PostItem(
          pid: pid,
          author: p['author']?.toString() ?? "匿名",
          authorId: authorId,
          avatarUrl:
              "${kBaseUrl}uc_server/avatar.php?uid=$authorId&size=middle",
          time: p['dateline']?.toString() ?? "",
          contentHtml: _cleanApiHtml(content),
          floor: "${p['number']}楼",
          device: "",
        ),
      );
    }

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
      }
    });

    if (widget.initialTargetFloor != null || widget.initialTargetPid != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _scrollToTargetFloor();
      });
    }
  }

  String _cleanApiHtml(String html) {
    return html
        .replaceAll('src="static/', 'src="${kBaseUrl}static/')
        .replaceAll('src="data/attachment/', 'src="${kBaseUrl}data/attachment/')
        .replaceAll('\r\n', '<br/>')
        .replaceAll('\n', '<br/>');
  }

  void _handleLoginExpired(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("提示: $message"),
        action: SnackBarAction(
          label: "去登录",
          onPressed: () async {
            final bool? success = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
            );
            if (success == true) {
              _loadLocalCookie();
              _loadPage(_targetPage);
            }
          },
        ),
      ),
    );
  }

  Future<void> _loadLocalCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final String saved = prefs.getString('saved_cookie_string') ?? "";
    if (mounted) setState(() => _userCookies = saved);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int? colorVal = prefs.getInt('reader_bg_color');
    if (colorVal != null) {
      setState(() {
        _readerBgColor = Color(colorVal);
        _readerTextColor = (_readerBgColor.computeLuminance() < 0.5)
            ? Colors.white70
            : Colors.black87;
      });
    }
  }

  Future<void> _saveSettings(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader_bg_color', color.toARGB32());
  }

  void _handleEdgePaging() {
    if (_isLoading || _isScrubbingScroll || !_scrollController.hasClients)
      return;
    final position = _scrollController.position;
    final now = DateTime.now();
    if (now.difference(_lastAutoPageTurn).inMilliseconds < 800) return;

    if (position.pixels >= position.maxScrollExtent - 50) {
      if (_targetPage < _totalPages) {
        _lastAutoPageTurn = now;
        if (!_isLoadingMore) setState(() => _isLoadingMore = true);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadPage(_targetPage + 1),
        );
      }
    }
  }

  void _loadNext() {
    if (_isLoading || _isLoadingMore) return;
    if (_targetPage >= _totalPages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已经是最后一页了")));
      return;
    }
    setState(() => _isLoadingMore = true);
    _loadPage(_targetPage + 1);
  }

  void _loadPrev() {
    if (_isLoading || _isLoadingPrev) return;
    if (_targetPage <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已经是第一页了")));
      return;
    }
    setState(() => _isLoadingPrev = true);
    _loadPage(_targetPage - 1);
  }

  void _onReply(String? pid) {
    if (_fid == null || _formhash == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("缺少必要信息，请刷新重试")));
      return;
    }
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
          baseUrl: kBaseUrl,
          userCookies: _userCookies,
        ),
      ),
    ).then((success) {
      if (success == true)
        _loadPage(_totalPages > 0 ? _totalPages : _targetPage);
    });
  }

  Future<void> _scrollToTargetFloor() async {
    if (_posts.isEmpty || _hasPerformedInitialJump) return;
    int targetIndex = -1;
    if (widget.initialTargetPid != null) {
      targetIndex = _posts.indexWhere((p) => p.pid == widget.initialTargetPid);
    }
    if (targetIndex == -1 && widget.initialTargetFloor != null) {
      String targetNum = widget.initialTargetFloor!.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      targetIndex = _posts.indexWhere(
        (p) => p.floor.replaceAll(RegExp(r'[^0-9]'), '') == targetNum,
      );
    }
    if (targetIndex != -1) {
      await _scrollController.scrollToIndex(
        targetIndex,
        preferPosition: AutoScrollPosition.begin,
        duration: const Duration(milliseconds: 500),
      );
      _hasPerformedInitialJump = true;
    } else {
      if (!_isLoading && !_isLoadingMore && _targetPage < _totalPages)
        _loadNext();
    }
  }

  void _toggleNovelMode() {
    if (_landlordUid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("正在获取楼主信息，请稍候...")));
      return;
    }
    setState(() {
      _isNovelMode = !_isNovelMode;
      if (_isNovelMode) {
        _isOnlyLandlord = true;
        _isReaderMode = true;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _targetPage = 1;
      } else {
        _isOnlyLandlord = false;
        _isReaderMode = false;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      _posts.clear();
      _pidKeys.clear();
      _floorKeys.clear();
      _totalPages = 1;
      _isLoading = true;
      if (_isFabOpen) _toggleFab();
      _loadPage(_targetPage);
    });
  }

  void _toggleReaderMode() {
    setState(() {
      _isReaderMode = !_isReaderMode;

      if (_isReaderMode) {
        // 进入纯净模式：隐藏状态栏 (全屏)
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _isBarsVisible = false;
        _hideController.reverse(); // 隐藏底部栏
      } else {
        // 退出纯净模式：显示状态栏 (边缘到边缘)
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _isBarsVisible = true;
        _hideController.forward(); // 显示底部栏
      }
    });
    // 关闭菜单
    if (_isFabOpen) _toggleFab();
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
      if (!_isOnlyLandlord) _isNovelMode = false;
      if (_isOnlyLandlord) _targetPage = 1;
      _posts.clear();
      _pidKeys.clear();
      _floorKeys.clear();
      _minPage = _targetPage;
      _totalPages = 1;
      _isLoading = true;
      _toggleFab();
    });
    _loadPage(_targetPage);
  }

  void _toggleFab() {
    setState(() {
      _isFabOpen = !_isFabOpen;
      if (_isFabOpen)
        _fabAnimationController.forward();
      else
        _fabAnimationController.reverse();
    });
  }

  Future<void> _handleFavorite() async {
    _toggleFab();
    if (_userCookies.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先登录")));
      return;
    }
    try {
      String url;
      if (_isFavorited && _favid != null) {
        url =
            "${kBaseUrl}home.php?mod=spacecp&ac=favorite&op=delete&favid=$_favid&type=all";
      } else {
        final String? addUrl = await _fetchFavoriteAddUrl();
        if (addUrl == null) return;
        url = addUrl;
      }
      await HttpService().getHtml(url);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_isFavorited ? "已取消收藏" : "已收藏")));
        _refreshFavoriteStatus();
      }
    } catch (_) {}
  }

  Future<String?> _fetchFavoriteAddUrl() async {
    if (_formhash == null) return null;
    return "${kBaseUrl}home.php?mod=spacecp&ac=favorite&type=thread&id=${widget.tid}&formhash=$_formhash";
  }

  Future<void> _refreshFavoriteStatus() async {
    if (_userCookies.isEmpty) return;
    try {
      final String html = await HttpService().getHtml(
        '${kBaseUrl}home.php?mod=space&do=favorite&view=me&mobile=no',
      );
      if (html.contains('tid=${widget.tid}')) {
        setState(() => _isFavorited = true);
      }
    } catch (_) {}
  }

  void _showSaveBookmarkDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "保存当前进度",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: const Text("确认保存"),
              leading: const Icon(Icons.save),
              onTap: () {
                String floor = _posts.isNotEmpty ? _posts.last.floor : "1楼";
                String? pid = _posts.isNotEmpty ? _posts.last.pid : null;
                _saveBookmarkWithFloor(floor, _targetPage, pid: pid);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
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
    if (jsonStr != null) jsonList = jsonDecode(jsonStr);

    String subjectSuffix = _isNovelMode ? " (小说)" : "";
    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: widget.subject.replaceAll(" (小说)", "") + subjectSuffix,
      author: _posts.isNotEmpty ? _posts.first.author : "未知",
      authorId: _landlordUid ?? "",
      page: pageToSave,
      savedTime:
          "${DateTime.now().toString().substring(5, 16)} · 读至 $floorName",
      isNovelMode: _isNovelMode,
      targetPid: pid,
      targetFloor: floorName,
    );

    jsonList.removeWhere((e) => e['tid'] == widget.tid);
    jsonList.insert(0, newMark.toJson());
    await prefs.setString('local_bookmarks', jsonEncode(jsonList));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("已保存：第 $pageToSave 页 - $floorName")),
      );
  }

  void _showDisplaySettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setS) => Container(
          padding: const EdgeInsets.all(20),
          height: 320,
          child: Column(
            children: [
              const Text("字体大小", style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: _fontSize,
                min: 12,
                max: 30,
                divisions: 18,
                label: _fontSize.toString(),
                onChanged: (v) {
                  setS(() => _fontSize = v);
                  setState(() => _fontSize = v);
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildColorBtn(Colors.white, Colors.black87, "白昼"),
                  _buildColorBtn(const Color(0xFFFAF9DE), Colors.black87, "护眼"),
                  _buildColorBtn(const Color(0xFF1A1A1A), Colors.white70, "夜间"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    _toggleFab();
  }

  Widget _buildColorBtn(Color bg, Color text, String label) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _readerBgColor = bg;
          _readerTextColor = text;
        });
        _saveSettings(bg);
        Navigator.pop(context);
      },
      child: CircleAvatar(
        backgroundColor: bg,
        child: Text(label, style: TextStyle(color: text, fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor = _isReaderMode
        ? _readerBgColor
        : Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: bgColor,
      // 【核心修复】纯净模式下，让内容延伸到状态栏后面，解决顶部大白条问题
      extendBodyBehindAppBar: _isReaderMode,
      // 防止键盘弹出挤压布局
      resizeToAvoidBottomInset: false,

      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.reverse &&
              _isBarsVisible) {
            setState(() {
              _isBarsVisible = false;
              _hideController.reverse();
            });
          } else if (notification.direction == ScrollDirection.forward &&
              !_isBarsVisible) {
            setState(() {
              _isBarsVisible = true;
              _hideController.forward();
            });
          }
          return true;
        },
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isBarsVisible = !_isBarsVisible;
              if (_isBarsVisible) {
                // 退出纯净模式时，显示状态栏
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                _hideController.forward();
              } else {
                // 进入纯净模式时，隐藏状态栏
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky,
                );
                _hideController.reverse();
              }
            });
          },
          child: Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                cacheExtent: 2000.0,
                // 【核心修复】阅读模式下增加顶部 Padding，防止文字被刘海屏遮挡
                // 普通模式下由 SliverAppBar 占据顶部，不需要 padding
                slivers: [
                  if (!_isReaderMode)
                    SliverAppBar(
                      floating: true,
                      pinned: false,
                      snap: true,
                      title: Text(
                        widget.subject,
                        style: const TextStyle(fontSize: 16),
                      ),
                      centerTitle: false,
                      elevation: 0,
                      backgroundColor: bgColor,
                      surfaceTintColor: Colors.transparent,
                    ),

                  // 阅读模式给一点顶部内边距
                  if (_isReaderMode)
                    SliverPadding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top,
                      ),
                    ),

                  if (_isReaderMode)
                    _buildReaderSliver()
                  else
                    _buildNativeSliver(),
                ],
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomControlBar(),
              ),
              if (_isFabOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _toggleFab,
                    child: Container(color: Colors.black54),
                  ),
                ),
              _buildFabMenu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControlBar() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_hideController),
      child: Material(
        elevation: 16,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            height: 60,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isFabOpen ? Icons.close : Icons.menu),
                  onPressed: _toggleFab,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6.0,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10.0,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 20.0,
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: _scrollController,
                      builder: (context, child) {
                        int count = _posts.length;
                        if (count == 0)
                          return const Slider(value: 0, onChanged: null);
                        double uiVal =
                            (_isScrubbingScroll && _dragValue != null)
                            ? _dragValue!
                            : (_dragValue ?? 0.0).clamp(
                                0.0,
                                (count - 1).toDouble(),
                              );
                        return Slider(
                          value: uiVal,
                          min: 0.0,
                          max: (count - 1).toDouble(),
                          divisions: count > 1 ? count - 1 : 1,
                          label: "${uiVal.round() + 1}楼",
                          onChangeStart: (v) => setState(() {
                            _isScrubbingScroll = true;
                            _dragValue = v;
                          }),
                          onChanged: (v) {
                            setState(() => _dragValue = v);
                            _scrollController.scrollToIndex(
                              v.round(),
                              preferPosition: AutoScrollPosition.begin,
                              duration: const Duration(milliseconds: 50),
                            );
                          },
                          onChangeEnd: (v) {
                            setState(() => _isScrubbingScroll = false);
                            _scrollController.scrollToIndex(
                              v.round(),
                              preferPosition: AutoScrollPosition.begin,
                              duration: const Duration(milliseconds: 300),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.import_contacts, size: 16),
                  label: Text("$_targetPage / $_totalPages"),
                  onPressed: _showPageJumpDialog,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 【新增】批量下载所有页面 (只存JSON，不存图)
  // ==========================================
  Future<void> _downloadAllPages() async {
    // 1. 基础检查
    if (_totalPages <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("无法获取总页数，请刷新后重试")));
      return;
    }

    // 关闭悬浮菜单
    if (_isFabOpen) _toggleFab();

    // 2. 显示进度弹窗
    int successCount = 0;
    bool isCancelled = false;

    await showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 3. 启动后台下载循环 (只在第一次构建时触发)
            if (successCount == 0 && !isCancelled) {
              _startBatchDownload(
                onProgress: (count) {
                  // 更新弹窗进度
                  if (context.mounted) {
                    setDialogState(() {
                      successCount = count;
                    });
                  }
                },
                onFinished: () {
                  if (context.mounted) Navigator.pop(context); // 下载完自动关闭
                },
              );
            }

            return AlertDialog(
              title: const Text("正在离线整贴"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: successCount / _totalPages),
                  const SizedBox(height: 15),
                  Text("正在下载: 第 $successCount / $_totalPages 页"),
                  const SizedBox(height: 5),
                  const Text(
                    "只保存文字数据，不包含图片",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isCancelled = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text("取消"),
                ),
              ],
            );
          },
        );
      },
    );

    // 4. 结果提示
    if (mounted) {
      if (isCancelled) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("下载已取消")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ 成功离线 $successCount / $_totalPages 页")),
        );
      }
    }
  }

  // 内部下载循环逻辑
  void _startBatchDownload({
    required Function(int) onProgress,
    required Function() onFinished,
  }) async {
    final offlineMgr = OfflineManager();

    // 循环下载每一页
    for (int i = 1; i <= _totalPages; i++) {
      try {
        // 构造 API 地址
        String url =
            '${kBaseUrl}api/mobile/index.php?version=4&module=viewthread&tid=${widget.tid}&page=$i';
        if (_isOnlyLandlord && _landlordUid != null) {
          url += '&authorid=$_landlordUid';
        }

        // 请求数据
        String responseBody = await HttpService().getHtml(url);

        // 处理 Dio 可能返回的引号包裹
        if (responseBody.startsWith('"') && responseBody.endsWith('"')) {
          responseBody = jsonDecode(responseBody);
        }

        // 验证数据有效性 (简单验证)
        if (!responseBody.contains('Variables')) {
          print("第 $i 页数据异常，跳过");
          continue;
        }

        // 保存到本地 (覆盖模式，不滚雪球)
        await offlineMgr.savePage(
          tid: widget.tid,
          page: i,
          subject: widget.subject,
          author: _posts.isNotEmpty ? _posts[0].author : "未知", // 使用第一页的作者名
          authorId: _landlordUid ?? "",
          jsonContent: responseBody,
        );

        // 回调进度
        onProgress(i);
      } catch (e) {
        print("❌ 第 $i 页下载失败: $e");
        // 即使失败也继续下载下一页，不中断
      }
    }

    // 全部结束
    onFinished();
  }

  Widget _buildFabMenu() {
    if (!_isFabOpen) return const SizedBox();
    return Positioned(
      right: 16,
      bottom: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 【核心修改】改为整贴下载按钮
          _buildFabItem(
            icon: Icons.cloud_download,
            label: "离线整本 ($_totalPages页)", // 提示总页数
            color: Colors.green,
            onTap: _downloadAllPages, // 直接调用上面的批量下载函数
          ),
          const SizedBox(height: 12),
          _buildFabItem(
            icon: Icons.refresh,
            label: "刷新",
            onTap: () {
              setState(() {
                _isLoading = true;
                _posts.clear();
              });
              _loadPage(_targetPage);
              _toggleFab();
            },
          ),
          const SizedBox(height: 12),
          _buildFabItem(
            icon: Icons.download_for_offline,
            label: "离线保存",
            color: Colors.green,
            onTap: () async {
              _toggleFab();
              if (_currentRawJson != null) {
                await OfflineManager().savePage(
                  tid: widget.tid,
                  page: _targetPage,
                  subject: widget.subject,
                  author: _posts.isNotEmpty ? _posts[0].author : "未知",
                  authorId: _landlordUid ?? "",
                  jsonContent: _currentRawJson!,
                );
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("✅ 已保存到离线列表")));
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("页面未加载完成")));
              }
            },
          ),
          const SizedBox(height: 12),
          _buildFabItem(
            icon: Icons.bookmark_add,
            label: "书签",
            onTap: () {
              _toggleFab();
              _showSaveBookmarkDialog();
            },
          ),
          const SizedBox(height: 12),
          // 【新增】收藏按钮
          _buildFabItem(
            icon: _isFavorited ? Icons.star : Icons.star_border,
            label: _isFavorited ? "已收藏" : "收藏",
            color: _isFavorited ? Colors.yellow[700] : null,
            onTap: _handleFavorite,
          ),
          const SizedBox(height: 12),
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
          _buildFabItem(
            icon: _isNovelMode ? Icons.auto_stories : Icons.menu_book,
            label: _isNovelMode ? "退出小说" : "小说模式",
            color: _isNovelMode ? Colors.purpleAccent : null,
            onTap: _toggleNovelMode,
          ),
          if (_isReaderMode) ...[
            const SizedBox(height: 12),
            _buildFabItem(
              icon: Icons.settings,
              label: "设置",
              onTap: _showDisplaySettings,
            ),
          ],
        ],
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
            backgroundColor: color,
            child: Icon(icon),
          ),
        ],
      ),
    );
  }

  void _showPageJumpDialog() {
    int dialogPage = _targetPage;
    final TextEditingController pageController = TextEditingController(
      text: _targetPage.toString(),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                height: 280,
                child: Column(
                  children: [
                    const Text(
                      "快速翻页",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: dialogPage.toDouble().clamp(
                        1.0,
                        _totalPages.toDouble(),
                      ),
                      min: 1.0,
                      max: _totalPages.toDouble(),
                      divisions: _totalPages > 1 ? _totalPages : 1,
                      label: "$dialogPage",
                      onChanged: (v) {
                        setStateDialog(() {
                          dialogPage = v.toInt();
                          pageController.text = dialogPage.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: dialogPage > 1
                              ? () {
                                  setStateDialog(() {
                                    dialogPage--;
                                    pageController.text = dialogPage.toString();
                                  });
                                }
                              : null,
                          child: const Text("上一页"),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: pageController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onSubmitted: (v) {
                              int? p = int.tryParse(v);
                              if (p != null && p >= 1 && p <= _totalPages)
                                setStateDialog(() => dialogPage = p);
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: dialogPage < _totalPages
                              ? () {
                                  setStateDialog(() {
                                    dialogPage++;
                                    pageController.text = dialogPage.toString();
                                  });
                                }
                              : null,
                          child: const Text("下一页"),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          if (dialogPage != _targetPage) {
                            setState(() {
                              _targetPage = dialogPage;
                              _posts.clear();
                              _isLoading = true;
                            });
                            _loadPage(_targetPage);
                          }
                        },
                        child: const Text("跳转"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNativeSliver() {
    if (_isLoading && _posts.isEmpty)
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    if (!_isLoading && _posts.isEmpty)
      return const SliverFillRemaining(child: Center(child: Text("暂无内容")));
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index == 0 && _targetPage > 1) {
            // 【修复】上一页按钮
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.arrow_upward),
                  label: Text("加载上一页 (第 ${_targetPage - 1} 页)"),
                  onPressed: _loadPrev,
                ),
              ),
            );
          }
          int postIndex = (_targetPage > 1) ? index - 1 : index;
          if (postIndex >= _posts.length) return _buildFooter();
          return _buildPostCard(_posts[postIndex]);
        }, childCount: _posts.length + (_targetPage > 1 ? 2 : 1)),
      ),
    );
  }

  Widget _buildReaderSliver() {
    // 简化的阅读模式
    if (_isLoading && _posts.isEmpty)
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index == _posts.length) return _buildFooter();
          return _buildReaderCard(_posts[index]);
        }, childCount: _posts.length + 1),
      ),
    );
  }

  Widget _buildFooter() {
    if (_targetPage < _totalPages) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: _isLoadingMore
              ? const CircularProgressIndicator()
              : TextButton(onPressed: _loadNext, child: const Text("加载下一页")),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(30),
      child: Center(
        child: Text("--- 全文完 ---", style: TextStyle(color: Colors.grey)),
      ),
    );
  }

  Widget _buildPostCard(PostItem post) {
    int index = _posts.indexOf(post);
    final GlobalKey anchorKey = _pidKeys.putIfAbsent(
      post.pid,
      () => GlobalKey(),
    );
    _floorKeys[post.floor] = anchorKey;
    final isLandlord = post.authorId == _landlordUid;

    return AutoScrollTag(
      key: ValueKey(index),
      controller: _scrollController,
      index: index,
      child: Container(
        key: anchorKey,
        child: Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _jumpToUser(post),
                      child: CircleAvatar(
                        backgroundImage: NetworkImage(post.avatarUrl),
                        radius: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                post.author,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isLandlord)
                                Container(
                                  margin: const EdgeInsets.only(left: 5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    "楼主",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            "${post.floor} · ${post.time}",
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.reply,
                        size: 20,
                        color: Colors.grey,
                      ),
                      onPressed: () => _onReply(post.pid),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectionArea(
                  child: HtmlWidget(
                    post.contentHtml,
                    textStyle: const TextStyle(fontSize: 16, height: 1.6),
                    customWidgetBuilder: (ele) {
                      if (ele.localName == 'img') {
                        String src = ele.attributes['src'] ?? '';
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderCard(PostItem post) {
    int index = _posts.indexOf(post);
    final GlobalKey anchorKey = _pidKeys.putIfAbsent(
      post.pid,
      () => GlobalKey(),
    );
    return AutoScrollTag(
      key: ValueKey(index),
      controller: _scrollController,
      index: index,
      child: Container(
        key: anchorKey,
        margin: const EdgeInsets.only(bottom: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  post.floor,
                  style: TextStyle(
                    color: _readerTextColor.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                Text(
                  "第 $_targetPage 页",
                  style: TextStyle(
                    color: _readerTextColor.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
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
              customWidgetBuilder: (ele) {
                if (ele.localName == 'img') {
                  String src = ele.attributes['src'] ?? '';
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
    );
  }

  Widget _buildClickableImage(String url) {
    if (url.isEmpty) return const SizedBox();
    String fullUrl = url.startsWith('http') ? url : "$kBaseUrl$url";
    return RetryableImage(
      imageUrl: fullUrl,
      cacheManager: globalImageCache,
      headers: {
        'Cookie': _userCookies,
        'User-Agent': kUserAgent,
        'Referer': kBaseUrl,
      },
      onTap: (u) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => ImagePreviewPage(
            imageUrl: u,
            headers: {'Cookie': _userCookies, 'User-Agent': kUserAgent},
          ),
        ),
      ),
    );
  }

  Future<void> _launchURL(String? url) async {
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _jumpToUser(PostItem post) {
    if (post.authorId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => UserDetailPage(
            uid: post.authorId,
            username: post.author,
            avatarUrl: post.avatarUrl,
          ),
        ),
      );
    }
  }
}

// ==========================================
// 3. 重试图片组件 (放在最后)
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
  int _retryCount = 0;

  @override
  Widget build(BuildContext context) {
    String finalUrl = widget.imageUrl;
    if (_retryCount > 0)
      finalUrl =
          "$finalUrl${finalUrl.contains('?') ? '&' : '?'}retry=$_retryCount";

    return GestureDetector(
      onTap: () => widget.onTap(widget.imageUrl),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: CachedNetworkImage(
          key: ValueKey("${widget.imageUrl}_$_retryCount"),
          imageUrl: finalUrl,
          cacheManager: widget.cacheManager,
          httpHeaders: widget.headers,
          fit: BoxFit.contain,
          placeholder: (context, url) => Container(
            height: 200,
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (ctx, url, error) {
            return InkWell(
              onTap: () async {
                await CachedNetworkImage.evictFromCache(widget.imageUrl);
                await widget.cacheManager.removeFile(widget.imageUrl);
                setState(() => _retryCount++);
              },
              child: Container(
                height: 120,
                width: double.infinity,
                color: Colors.grey[300],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "加载失败，点击重试 (${_retryCount})",
                      style: const TextStyle(color: Colors.blue),
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
