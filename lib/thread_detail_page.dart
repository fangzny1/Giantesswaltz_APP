import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:giantesswaltz_app/cloudflare_solver.dart';
import 'package:giantesswaltz_app/history_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart'; // 现在已正确使用
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'general_webview_page.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as html_dom; // 保持这个，用于类型
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
  // 【新增】清洗时间字符串
  String _formatTime(String time) {
    // 替换 &nbsp; 为普通空格
    return time
        .replaceAll('&nbsp;', ' ')
        .replaceAll('<span title="', '') // 有时候 API 会返回带 span 的复杂格式
        .replaceAll('">', ' ')
        .replaceAll('</span>', '');
  }

  // 【新增】定义一个内部显示的标题变量
  late String _displaySubject;

  late AutoScrollController _scrollController;
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  bool _hasPerformedInitialJump = false;
  double _lineHeight = 1.4; // 默认行高从 1.8 调小到 1.4
  List<PostItem> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isLoadingPrev = false;

  int _ppp = 10; // 每页显示贴数，默认10，从API获取
  int _currentVisibleFloor = 1; // 当前视口最上方显示的楼层号
  bool _isJumping = false; // 是否正在执行跨页跳转

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
  late int _maxPage; // 【新增】记录当前列表加载的最大页码
  int _targetPage = 1;
  int _totalPages = 1;

  String? _landlordUid;
  String? _fid;
  String? _formhash;
  String? _posttime;
  int _postMinChars = 0;
  int _postMaxChars = 0;
  String _userCookies = "";
  int _totalPostsCount = 0; // 全局变量
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
    _maxPage = widget.initialPage; // 【新增】
    _targetPage = widget.initialPage;
    // 初始时使用传进来的标题（可能是“跳转中...”，也可能是正常的标题）
    _displaySubject = widget.subject;

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

  // ==========================================
  // 【核心修改】增加 isRetry 参数，实现自动续命重试
  // ==========================================
  Future<void> _loadPage(
    int page, {
    bool resetScroll = false,
    bool isRetry = false,
  }) async {
    _targetPage = page;
    // 如果不是重试状态，才显示加载圈，避免重试时闪烁
    if (mounted && !isRetry) setState(() => _isLoading = true);

    // 1. 优先读取离线缓存（保持原逻辑，提升体验）
    // 注意：如果是重试，说明网络可能通了但Cookie不对，此时不要读缓存，强制走网络
    if (!isRetry) {
      String? localData = await OfflineManager().readPage(widget.tid, page);
      if (localData != null) {
        print("📦 [Offline] 发现本地持久缓存，优先渲染");
        try {
          _processApiResponse(jsonDecode(localData));
          if (mounted) setState(() => _isLoading = false);
        } catch (_) {}
      }
    }

    String url =
        '${currentBaseUrl.value}api/mobile/index.php?version=4&module=viewthread&tid=${widget.tid}&page=$page';
    if (_isOnlyLandlord && _landlordUid != null)
      url += '&authorid=$_landlordUid';

    try {
      // 2. 发起网络请求
      String responseBody = await HttpService().getHtml(url);
      // 如果返回的还是 HTML（说明自愈失败了）
      if (responseBody.trim().startsWith('<!DOCTYPE') ||
          responseBody.contains('<html')) {
        setState(() {
          _isLoading = false;
          _posts = []; // 清空，触发显示“加载失败”的 UI
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Session 同步失败，请尝试下拉刷新或重新登录")),
        );
        return;
      }
      // 在 _loadPage 内部
      if (responseBody.contains("to_login")) {
        setState(() {
          _isLoading = false;
          _posts = []; // 依然保持空，但我们要修改 build 函数来显示登录引导
        });

        // 弹窗提示，并直接跳转
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("登录已过期，请重新登录以继续阅读")));

        // 延迟一下直接弹回登录
        Future.delayed(const Duration(milliseconds: 500), () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (c) => const LoginPage()),
          ).then((val) {
            if (val == true) _loadPage(1); // 登录成功回来刷新
          });
        });
        return;
      }
      // 3. 检查是否被 Cloudflare 拦截
      if (responseBody.contains('<!DOCTYPE html') ||
          responseBody.contains('<html')) {
        // 如果是 HTML，说明可能撞盾了，或者 Cookie 失效导致返回了网页版错误页
        if (!isRetry) {
          print("🚨 [AutoRetry] 检测到 HTML 响应（可能是失效或撞盾），尝试自动续命...");
          await _performAutoRevive(); // 执行续命
          return _loadPage(
            page,
            resetScroll: resetScroll,
            isRetry: true,
          ); // 递归重试
        }
        throw "Cloudflare Intercepted";
      }

      // 4. 清洗 JSON
      responseBody = responseBody.trim();
      if (responseBody.startsWith('"') && responseBody.endsWith('"')) {
        responseBody = responseBody
            .substring(1, responseBody.length - 1)
            .replaceAll('\\"', '"')
            .replaceAll('\\\\', '\\');
      }

      final data = jsonDecode(responseBody);

      // 5. 【关键】检查 API 是否返回了“需要登录”或错误
      // 很多时候服务器不报错，而是返回 Variables 为 null
      if (data['Variables'] == null) {
        if (!isRetry) {
          print("🚨 [AutoRetry] 数据解析为空（Variables=null），Cookie 可能过期，尝试自动续命...");
          await _performAutoRevive();
          return _loadPage(page, resetScroll: resetScroll, isRetry: true);
        }
      }

      // 如果有明确的 Message 报错
      if (data['Message'] != null && data['Variables'] == null) {
        String msg = data['Message']['messagestr'] ?? "";
        // 如果错误是“未定义操作”或者“需要登录”，尝试自动修复
        if (!isRetry) {
          print("🚨 [AutoRetry] API 返回错误: $msg，尝试自动续命...");
          await _performAutoRevive();
          return _loadPage(page, resetScroll: resetScroll, isRetry: true);
        }
        _handleLoginExpired(msg);
        return;
      }

      // 6. 成功获取数据
      _currentRawJson = responseBody;
      _processApiResponse(data);

      if (resetScroll && _scrollController.hasClients)
        _scrollController.jumpTo(0);
    } catch (e) {
      print("❌ 网络请求失败: $e");

      // 7. 捕获异常时的自动重试
      if (!isRetry) {
        print("🚨 [AutoRetry] 发生异常，尝试死马当活马医（续命重试）...");
        await _performAutoRevive();
        return _loadPage(page, resetScroll: resetScroll, isRetry: true);
      }

      if (e.toString().contains("Cloudflare") ||
          e.toString().contains("Intercepted")) {
        bool solved = await CloudflareSolver.show(context);
        if (solved) _loadPage(page);
      } else {
        if (_posts.isEmpty && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("加载失败，请下拉刷新或检查网络")));
        }
      }
      // 如果抛出了异常
      setState(() {
        _isLoading = false;
        _posts = []; // 确保列表为空
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 【新增】辅助方法：执行自动续命
  Future<void> _performAutoRevive() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("连接失效，正在自动修复..."),
          duration: Duration(milliseconds: 1000),
        ),
      );
    }
    // 调用 HttpService 的全局续命方法
    await HttpService().reviveSession();
    // 重新读取本地 Cookie 到内存
    await _loadLocalCookie();
  }

  void _processApiResponse(dynamic data) {
    final vars = data['Variables'];
    if (vars == null) return;

    _fid = vars['fid']?.toString();
    _formhash = vars['formhash']?.toString();

    // 更新每页数量
    if (vars['ppp'] != null) {
      _ppp = int.tryParse(vars['ppp'].toString()) ?? 10;
    }

    if (vars['postminchars'] != null) {
      _postMinChars = int.tryParse(vars['postminchars'].toString()) ?? 0;
    }

    final threadInfo = vars['thread'];
    if (threadInfo != null) {
      // --- 【核心修复代码：更新标题】 ---
      // 1. 【关键步骤】先从 JSON 里把真正的标题拿出来
      String realSubject = threadInfo['subject']?.toString() ?? widget.subject;
      String authorName = threadInfo['author']?.toString() ?? "未知";
      _totalPostsCount =
          (int.tryParse(threadInfo['allreplies']?.toString() ?? '0') ?? 0) + 1;

      if (realSubject != null && realSubject.isNotEmpty) {
        setState(() {
          _displaySubject = realSubject;
        });
      }

      int allReplies =
          int.tryParse(threadInfo['allreplies']?.toString() ?? '0') ?? 0;
      int ppp = int.tryParse(vars['ppp']?.toString() ?? '10') ?? 10;
      _totalPages = ((allReplies + 1) / ppp).ceil();
      // ===========================
      // 【新增】在这里加入历史记录保存
      // ===========================

      // 这里的 addHistory 是 fire-and-forget (不需 await)，不阻塞界面渲染
      HistoryManager.addHistory(
        widget.tid,
        realSubject ?? widget.subject,
        authorName,
      );
      print("📝 已添加历史记录: ${widget.subject}");
      // ===========================
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
        String fileHtml = ""; // 【新增】专门存放普通文件的 HTML

        attachments.forEach((key, attach) {
          // Discuz API 中，isimage 为 "1" 或 "-1" 是图片，"0" 是普通文件
          String isImage = attach['isimage']?.toString() ?? "0";
          String fullUrl = "${attach['url']}${attach['attachment']}";

          if (isImage == "1" || isImage == "-1") {
            // 是图片，照常拼接
            attachHtml += '<img src="$fullUrl" style="max-width:100%;" /><br/>';
          } else {
            // 【新增】是普通附件 (如 txt, zip 等)
            String filename = attach['filename']?.toString() ?? "未知附件";
            String size = attach['attachsize']?.toString() ?? "未知大小";
            // 我们塞入一个自定义的 <gn-file> 标签，等下让 Flutter 把它变成漂亮的按钮
            fileHtml +=
                '<gn-file url="$fullUrl" name="$filename" size="$size"></gn-file><br/>';
          }
        });
        content += attachHtml + fileHtml; // 合并图片和附件
      }

      newPosts.add(
        PostItem(
          pid: pid,
          author: p['author']?.toString() ?? "匿名",
          authorId: authorId,
          avatarUrl:
              "${currentBaseUrl.value}uc_server/avatar.php?uid=$authorId&size=middle",
          time: _formatTime(p['dateline']?.toString() ?? ""),
          contentHtml: _cleanApiHtml(content),
          floor: "${p['number']}楼",
          device: "",
        ),
      );
    }

    setState(() {
      if (_posts.isEmpty) {
        // 这是刚进页面或者发生了大跨度跳转（UI层的对话框跳转清空了_posts）
        _posts = newPosts;
        _minPage = _targetPage;
        _maxPage = _targetPage;
      } else if (_targetPage < _minPage) {
        // 向上加载（加载上一页），插入到最前面
        newPosts.removeWhere(
          (p) => _posts.any((old) => old.pid == p.pid),
        ); // 终极防御：绝不塞入重复PID
        _posts.insertAll(0, newPosts);
        _minPage = _targetPage;
      } else if (_targetPage > _maxPage) {
        // 向下加载（加载下一页），追加到最后面
        for (var p in newPosts) {
          if (!_posts.any((old) => old.pid == p.pid)) _posts.add(p);
        }
        _maxPage = _targetPage;
      } else {
        // 加载了列表范围中间的页（比如刷新、异常重试时），安全合并即可，不修改min/max
        for (var p in newPosts) {
          if (!_posts.any((old) => old.pid == p.pid)) _posts.add(p);
        }
      }
      _isLoadingPrev = false; // 确保清除加载状态
      _isLoadingMore = false;
    });

    if (widget.initialTargetFloor != null || widget.initialTargetPid != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _scrollToTargetFloor();
      });
    }
  }

  String _cleanApiHtml(String html) {
    // 【核心修复】处理双重转义的 HTML 实体
    // 将 &amp;quot; 还原为真正的引号，或者至少还原为 &quot; 供下层解析
    // 这里我们直接还原成字符，效率最高
    html = html
        .replaceAll('&amp;quot;', '"')
        .replaceAll('&amp;amp;', '&')
        .replaceAll('&amp;lt;', '<')
        .replaceAll('&amp;gt;', '>')
        .replaceAll('&amp;nbsp;', ' ');
    // 处理正常的转义（如果是单层转义，有些组件可能也识别不佳，可以顺手做了）
    html = html.replaceAll('&quot;', '"');

    return html
        .replaceAll('src="static/', 'src="${currentBaseUrl.value}static/')
        .replaceAll(
          'src="data/attachment/',
          'src="${currentBaseUrl.value}data/attachment/',
        )
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
        _lineHeight = prefs.getDouble('reader_line_height') ?? 1.4;
      });
    }
  }

  Future<void> _saveSettings(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader_line_height', _lineHeight);

    await prefs.setInt('reader_bg_color', color.toARGB32());
  }

  Future<void> _handleRecommend() async {
    if (_formhash == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("数据未加载完，请稍后")));
      return;
    }

    // 【核心修复】使用网页版的接口，而不是 API
    // 这里的 hash 是 formhash，tid 是帖子 ID
    final url =
        '${currentBaseUrl.value}forum.php?mod=misc&action=recommend&do=add&tid=${widget.tid}&hash=$_formhash&inajax=1';

    try {
      // 发起请求
      final resp = await HttpService().getHtml(url);
      print(resp);
      // Discuz 返回的是 XML 或者是纯文本提示
      // 常见的成功提示包含 "succeed" 或 "已评价"
      if (resp.contains("succeed") ||
          resp.contains("已评价") ||
          resp.contains("指数") ||
          resp.contains("成功")) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("👍 点赞/顶帖成功！")));
      } else if (resp.contains("不能")) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("你已经点过赞了")));
      } else {
        // 提取错误信息 (CDATA)
        String err = "操作失败";
        if (resp.contains("CDATA[")) {
          err = RegExp(r'CDATA\[(.*?)\]').firstMatch(resp)?.group(1) ?? err;
        }
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("网络请求失败")));
    }
  }

  void _handleEdgePaging() {
    if (_isLoading || _isScrubbingScroll || !_scrollController.hasClients)
      return;
    final position = _scrollController.position;
    final now = DateTime.now();
    if (now.difference(_lastAutoPageTurn).inMilliseconds < 800) return;

    if (position.pixels >= position.maxScrollExtent - 50) {
      // 【修改点】滑动到底部时，对比 _maxPage
      if (_maxPage < _totalPages) {
        _lastAutoPageTurn = now;
        if (!_isLoadingMore) setState(() => _isLoadingMore = true);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadPage(_maxPage + 1), // 加载底部以下的页
        );
      }
    }
  }

  void _loadNext() {
    if (_isLoading || _isLoadingMore) return;
    // 【修改点】向下加载永远比对 _maxPage
    if (_maxPage >= _totalPages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已经是最后一页了")));
      return;
    }
    setState(() => _isLoadingMore = true);
    _loadPage(_maxPage + 1); // 加载底部以下的页
  }

  void _loadPrev() {
    if (_isLoading || _isLoadingPrev) return;
    // 【修改点】向上加载永远比对 _minPage
    if (_minPage <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已经是第一页了")));
      return;
    }
    setState(() => _isLoadingPrev = true);
    _loadPage(_minPage - 1); // 加载顶部以上的页
  }

  void _onReply(String? pid) {
    // 1. 检查必要参数
    if (_fid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("缺少版块ID，请刷新重试")));
      return;
    }

    // 2. 构建基础 URL
    // 使用 currentBaseUrl.value 获取当前域名
    String baseUrl = currentBaseUrl.value;
    String targetUrl =
        "${baseUrl}forum.php?mod=post&action=reply&fid=$_fid&tid=${widget.tid}";

    // 3. 【关键】如果是引用回复 (点击了某楼层)
    if (pid != null && pid.isNotEmpty) {
      // 加上 repquote 参数，这样服务器才知道你在回复谁
      targetUrl += "&repquote=$pid&extra=page%3D1&page=1";
    }

    // 4. 加上 mobile=no 确保加载电脑版页面（方便嗅探脚本工作）
    targetUrl += "&mobile=no";

    print("🚀 [Detail] 准备跳转回复页: $targetUrl");

    // 5. 跳转
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReplyNativePage(
          targetUrl: targetUrl, // 把拼好的 URL 传进去，不要传空字符串了
          fid: _fid!,
          tid: widget.tid,
          userCookies: _userCookies,
          baseUrl: baseUrl,
        ),
      ),
    ).then((success) {
      // 发送成功后刷新列表
      if (success == true) {
        _loadPage(_totalPages > 0 ? _totalPages : _targetPage);
      }
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
    if (_landlordUid == null && _posts.isNotEmpty) {
      _landlordUid = _posts.first.authorId;
    }
    if (_landlordUid == null) return;

    setState(() {
      _isOnlyLandlord = !_isOnlyLandlord;
      _posts = []; // 清空数据
      _targetPage = 1; // 重置到第一页
      _minPage = 1;
      _isLoading = true;
      _hasPerformedInitialJump = false;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _loadPage(1, resetScroll: true);
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
      if (_isFavorited && _favid != null) {
        // ==========================================
        // 【核心修复】取消收藏必须用 POST 和 formhash
        // ==========================================
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("正在取消收藏...")));

        final String url =
            "${currentBaseUrl.value}home.php?mod=spacecp&ac=favorite&op=delete&favid=$_favid&type=all&inajax=1";

        // 构造和 favorite_page 一模一样的表单数据
        var formData = FormData.fromMap({
          'referer':
              '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me',
          'deletesubmit': 'true',
          'deletesubmitbtn': 'true',
          'formhash': _formhash ?? "", // 使用详情页自带的 formhash
          'handlekey': 'a_delete_$_favid',
        });

        var response = await Dio().post(
          url,
          data: formData,
          options: Options(
            headers: {
              'Cookie': _userCookies,
              'User-Agent': kUserAgent,
              'Referer':
                  '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me',
            },
          ),
        );

        String respStr = response.data.toString();
        if (respStr.contains("succeed") ||
            respStr.contains("成功") ||
            respStr.contains("删除")) {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("已取消收藏")));
            setState(() {
              _isFavorited = false;
              _favid = null; // 删掉后清空凭证
            });
          }
        } else {
          throw "服务器未返回成功标志";
        }
      } else {
        // ==========================================
        // 原有的添加收藏逻辑
        // ==========================================
        final String? addUrl = await _fetchFavoriteAddUrl();
        if (addUrl == null) return;
        await HttpService().getHtml(addUrl);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("已收藏")));
          // 关键：收藏成功后，重新查一遍列表，把刚刚生成的 favid 拿过来，以便后续可以立刻取消
          _refreshFavoriteStatus();
        }
      }
    } catch (e) {
      print("收藏操作异常: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("操作失败，请检查网络")));
      }
    }
  }

  Future<String?> _fetchFavoriteAddUrl() async {
    if (_formhash == null) return null;
    return "${currentBaseUrl.value}home.php?mod=spacecp&ac=favorite&type=thread&id=${widget.tid}&formhash=$_formhash";
  }

  Future<void> _refreshFavoriteStatus() async {
    if (_userCookies.isEmpty) return;
    try {
      final String html = await HttpService().getHtml(
        '${currentBaseUrl.value}home.php?mod=space&do=favorite&view=me&mobile=no',
      );
      if (html.contains('tid=${widget.tid}')) {
        // 【核心修复】不仅要点亮星星，还要把这个帖子的 favid 偷出来用于取消
        var document = html_parser.parse(html);
        var items = document.querySelectorAll('ul[id="favorite_ul"] li');

        for (var item in items) {
          var link = item.querySelector('a[href*="tid=${widget.tid}"]');
          if (link != null) {
            var delLink = item.querySelector('a[href*="op=delete"]');
            if (delLink != null) {
              String delHref = delLink.attributes['href'] ?? "";
              var match = RegExp(r'favid=(\d+)').firstMatch(delHref);
              if (match != null) {
                if (mounted) {
                  setState(() {
                    _isFavorited = true;
                    _favid = match.group(1);
                  });
                }
                print("🔍 [Detail] 成功获取当前帖子的 favid: $_favid");
                break;
              }
            }
          }
        }
      } else {
        if (mounted) setState(() => _isFavorited = false);
      }
    } catch (_) {}
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
                  if (summary.length > 30) {
                    summary = "${summary.substring(0, 30)}...";
                  }
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
                      int pageToSave = _targetPage;
                      final m = RegExp(r'(\\d+)').firstMatch(post.floor);
                      if (m != null) {
                        int floorNum = int.tryParse(m.group(1)!) ?? 0;
                        if (floorNum > 0) {
                          pageToSave = ((floorNum - 1) ~/ 10) + 1;
                        }
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
    if (jsonStr != null) jsonList = jsonDecode(jsonStr);

    String subjectSuffix = _isNovelMode ? " (小说)" : "";
    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: _displaySubject.replaceAll(" (小说)", "") + subjectSuffix,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "界面排版",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 1. 字体大小调节
                  _buildSettingRow(
                    icon: Icons.text_fields,
                    label: "文字大小",
                    valueText: "${_fontSize.toInt()}",
                    child: Slider(
                      value: _fontSize,
                      min: 14,
                      max: 30,
                      onChanged: (v) {
                        setSheetState(() => _fontSize = v); // 更新弹窗内部 UI
                        setState(() => _fontSize = v); // 更新底部帖子列表 UI
                      },
                      onChangeEnd: (v) =>
                          _saveSettings(_readerBgColor), // 停止滑动时保存
                    ),
                  ),

                  // 2. 行间距调节
                  _buildSettingRow(
                    icon: Icons.format_line_spacing,
                    label: "行间距离",
                    valueText: _lineHeight.toStringAsFixed(1),
                    child: Slider(
                      value: _lineHeight,
                      min: 1.0,
                      max: 2.2,
                      onChanged: (v) {
                        setSheetState(() => _lineHeight = v);
                        setState(() => _lineHeight = v);
                      },
                      onChangeEnd: (v) => _saveSettings(_readerBgColor),
                    ),
                  ),

                  // 3. 仅在阅读模式/小说模式显示背景切换
                  if (_isReaderMode || _isNovelMode) ...[
                    const Divider(height: 30),
                    const Text(
                      "背景主题",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildColorBtn(Colors.white, Colors.black87, "白昼"),
                        _buildColorBtn(
                          const Color(0xFFFAF9DE),
                          Colors.black87,
                          "护眼",
                        ),
                        _buildColorBtn(
                          const Color(0xFFC7EDCC),
                          Colors.black87,
                          "豆沙",
                        ),
                        _buildColorBtn(
                          const Color(0xFF1A1A1A),
                          Colors.white70,
                          "夜间",
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 设置项的通用行布局，让 UI 更好看
  Widget _buildSettingRow({
    required IconData icon,
    required String label,
    required String valueText,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
          Expanded(child: child),
          SizedBox(
            width: 35,
            child: Text(
              valueText,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
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

  void _updateCurrentFloorValue() {
    // 如果正在拖动滑块，或者列表为空，就不计算了
    if (!_scrollController.hasClients || _posts.isEmpty || _isScrubbingScroll)
      return;

    double offset = _scrollController.offset;
    double maxScroll = _scrollController.position.maxScrollExtent;
    // 简单的线性插值计算
    double scrollPercent = (offset / maxScroll).clamp(0.0, 1.0);

    // 当前页的起始楼层 (例如第2页开始就是11楼)
    int startFloor = (_targetPage - 1) * 10;

    // 估算当前看的是第几条 post
    int currentPostIndex = (scrollPercent * _posts.length).round();

    // 最终结果：起始楼层 + 当前页偏移
    int floorOnScreen = startFloor + currentPostIndex;

    // 更新 Slider 变量
    if ((_dragValue ?? 0).round() != floorOnScreen) {
      setState(() {
        _dragValue = floorOnScreen.toDouble().clamp(
          0.0,
          (_totalPostsCount - 1).toDouble(),
        );
      });
    }
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
          // --- 【新增】实时更新进度条值的逻辑 ---
          // 当用户停止滚动或者正在滚动时，计算当前大概在第几楼
          if (notification is ScrollUpdateNotification) {
            _updateCurrentFloorValue();
          }
          return true;
        },
        child: GestureDetector(
          onTap: () {
            // 如果你觉得点击整个屏幕任何地方都全屏不合理
            // 我们可以加一个判断：只有小说模式/纯净模式下，且点击位置不是顶部，才切换显隐
            setState(() {
              _isBarsVisible = !_isBarsVisible;
              if (_isBarsVisible) {
                _hideController.forward();
              } else {
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
                      // 【修改点】将 widget.subject 换成 _displaySubject
                      title: Text(
                        _displaySubject,
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
        elevation: 20,
        color: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // === 第一部分：进度条 ===
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4.0,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16.0,
                          ),
                          activeTrackColor: Theme.of(context).primaryColor,
                          inactiveTrackColor: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.2),
                        ),
                        child: AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, child) {
                            // 1. 计算总楼层数 (如果还没加载到总数，暂用当前列表长度)
                            int totalCount = _totalPostsCount > 0
                                ? _totalPostsCount
                                : (_posts.isNotEmpty ? _posts.length : 1);

                            // 2. 确保滑块值在合法范围内
                            double uiVal = (_dragValue ?? 0.0).clamp(
                              0.0,
                              (totalCount - 1).toDouble(),
                            );

                            return Slider(
                              value: uiVal,
                              min: 0.0,
                              max: (totalCount - 1).toDouble(),
                              divisions: totalCount > 1 ? totalCount - 1 : 1,
                              label: "${uiVal.round() + 1}楼",
                              onChangeStart: (v) => setState(() {
                                _isScrubbingScroll = true;
                                _dragValue = v;
                              }),
                              onChanged: (v) {
                                // 拖动时只更新 UI，不触发加载
                                setState(() => _dragValue = v);
                              },
                              onChangeEnd: (v) {
                                setState(() => _isScrubbingScroll = false);

                                // 【这里定义 targetFloor，解决了你的报错】
                                int targetFloor = v.round() + 1;

                                // 估算目标页码 (Discuz 默认每页 10 楼)
                                int ppp = 10;
                                int jumpToPage =
                                    ((targetFloor - 1) / ppp).floor() + 1;

                                print(
                                  "🎯 跳转目标: $targetFloor楼 -> 第 $jumpToPage 页",
                                );

                                if (jumpToPage != _targetPage) {
                                  // 情况 A：跨页跳转 -> 清空数据，重新加载那一页
                                  setState(() {
                                    _posts = []; // 清空防跳变
                                    _isLoading = true;
                                  });
                                  // 重置滚动位置到顶部
                                  if (_scrollController.hasClients)
                                    _scrollController.jumpTo(0);

                                  _loadPage(jumpToPage, resetScroll: true);
                                } else {
                                  // 情况 B：就在当前页 -> 寻找对应的楼层并滚动
                                  int indexInList = _posts.indexWhere((p) {
                                    // 提取楼层号里的数字进行比对
                                    String rawFloor = p.floor.replaceAll(
                                      RegExp(r'[^0-9]'),
                                      '',
                                    );
                                    return rawFloor == targetFloor.toString();
                                  });

                                  if (indexInList != -1) {
                                    _scrollController.scrollToIndex(
                                      indexInList,
                                      preferPosition: AutoScrollPosition.begin,
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                    );
                                  } else {
                                    // 如果没找到（可能是还没加载完），简单跳到顶部或底部
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("该楼层在当前页未找到，可能已被屏蔽"),
                                      ),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    // 页码显示
                    TextButton.icon(
                      icon: const Icon(
                        Icons.import_contacts,
                        size: 14,
                        color: Colors.grey,
                      ),
                      label: Text(
                        "$_targetPage / $_totalPages",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: _showPageJumpDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),

              // 分割线
              Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withOpacity(0.1),
              ),

              // === 第二部分：操作按钮 (保持不变) ===
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _onReply(null),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.4),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit,
                                size: 16,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "回复楼主...",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.thumb_up_alt_outlined),
                      iconSize: 22,
                      tooltip: "支持/顶帖",
                      onPressed: _handleRecommend,
                    ),
                    IconButton(
                      icon: Icon(
                        _isFavorited
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                      ),
                      color: _isFavorited ? Colors.amber : null,
                      iconSize: 26,
                      tooltip: "收藏",
                      onPressed: _handleFavorite,
                    ),
                    IconButton(
                      icon: const Icon(Icons.grid_view_rounded),
                      iconSize: 22,
                      onPressed: _toggleFab,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadAllPages() async {
    if (_totalPages <= 0) return;
    if (_isFabOpen) _toggleFab();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  "请选择保存方式",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.code, color: Colors.blue),
                title: const Text("离线 JSON 数据"),
                subtitle: const Text("保存整本文字内容，支持 App 内断网阅读"),
                onTap: () {
                  Navigator.pop(ctx);
                  _startRealBatchDownload(); // 之前的批量下载逻辑
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text("生成/预览 网页打印版"),
                subtitle: const Text("适合导出 PDF 或直接打印"),
                onTap: () {
                  Navigator.pop(ctx);
                  // 构造打印页面链接
                  String printableUrl =
                      '${currentBaseUrl.value}forum.php?mod=viewthread&action=printable&tid=${widget.tid}';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => GeneralWebViewPage(
                        url: printableUrl,
                        title: "打印预览 (可保存为PDF)",
                        isPrintMode: true, // 【关键】这是打印模式，需要注入 CSS 美化
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 【新增】批量下载所有页面 (只存JSON，不存图)
  // ==========================================
  Future<void> _startRealBatchDownload() async {
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
            '${currentBaseUrl.value}api/mobile/index.php?version=4&module=viewthread&tid=${widget.tid}&page=$i';
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
          // 【修复后的只看楼主按钮】
          _buildFabItem(
            icon: _isOnlyLandlord ? Icons.people_outline : Icons.person_outline,
            label: _isOnlyLandlord ? "看全部回帖" : "只看楼主",
            color: _isOnlyLandlord ? Colors.orange : null,
            onTap: _toggleOnlyLandlord,
          ),
          const SizedBox(height: 12),
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
                  // 【核心修复】使用 _displaySubject
                  subject: _displaySubject,
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

          const SizedBox(height: 12),
          _buildFabItem(
            icon: Icons.settings,
            label: "设置",
            onTap: _showDisplaySettings,
          ),
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
                      // 【修改点】包裹 Hero
                      child: Hero(
                        tag:
                            "avatar_${post.authorId}_${post.pid}", // 关键：加上 pid 保证唯一
                        child: CircleAvatar(
                          backgroundImage: NetworkImage(post.avatarUrl),
                          radius: 18,
                        ),
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
                    textStyle: TextStyle(
                      fontSize: _fontSize - 2,
                      height: _lineHeight,
                      // 确保基础颜色跟随主题
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black87,
                    ),

                    // ==================== 1. 样式构建器 (解决背景和文字冲突) ====================
                    customStylesBuilder: (element) {
                      bool isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      String style = element.attributes['style'] ?? '';
                      String parentStyle =
                          element.parent?.attributes['style'] ?? '';

                      // A. 针对问卷外层 div (通过包含 d4ebfa 字符串精准识别)
                      if (element.localName == 'div' &&
                          style.contains('d4ebfa')) {
                        if (_isReaderMode || _isNovelMode)
                          return {'display': 'none'};

                        if (isDark) {
                          return {
                            'background-color': '#121212', // 强制改为纯黑或深灰
                            'color': '#FFFFFF', // 强制文字为白色
                            'border': '1px solid #333333',
                            'border-radius': '10px',
                            'padding': '15px',
                            'display': 'block',
                          };
                        }
                        return {'border-radius': '10px', 'padding': '15px'};
                      }

                      if (element.localName == 'h3') {
                        final parentBg =
                            element.parent?.attributes['background-color'];
                        if (parentBg == '#d4ebfa') {
                          return {
                            'color': isDark
                                ? '#FFFFFF !important'
                                : '#111111 !important',
                            'font-weight': 'bold !important',
                            'font-size': '16px !important',
                            'margin': '0 0 12px 0 !important',
                            'text-align': 'center !important',
                          };
                        }
                      }

                      return null;
                    },

                    // ==================== 2. 组件构建器 (解决图标和按钮) ====================
                    customWidgetBuilder: (element) {
                      // ---> 【新增】解析普通附件并生成下载卡片 <---
                      if (element.localName == 'gn-file') {
                        String url = element.attributes['url'] ?? '';
                        String name = element.attributes['name'] ?? '附件';
                        String size = element.attributes['size'] ?? '';

                        bool isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              // 调用系统外部浏览器下载，这样会自动保存到手机的 Downloads 目录
                              if (url.isNotEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("正在调用系统下载: $name")),
                                );
                                await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2C2C2C)
                                    : Colors.blueGrey.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.blueGrey.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // 附件图标
                                  Icon(
                                    name.endsWith('.txt')
                                        ? Icons.description_outlined
                                        : Icons.folder_zip_outlined,
                                    size: 36,
                                    color: isDark
                                        ? Colors.blue[300]
                                        : Colors.blue[700],
                                  ),
                                  const SizedBox(width: 12),
                                  // 文件名和大小
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          size,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 下载按钮
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.blue[900]?.withOpacity(0.5)
                                          : Colors.blue[50],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.download,
                                      size: 20,
                                      color: isDark
                                          ? Colors.blue[200]
                                          : Colors.blue[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // 屏蔽那个破损的 favicon.ico 图标
                      if (element.localName == 'img') {
                        String src = element.attributes['src'] ?? '';
                        if (src.contains('favicon.ico'))
                          return const SizedBox.shrink();
                        if (src.isNotEmpty) return _buildClickableImage(src);
                      }

                      // 将 iframe 转换为 MD3 风格按钮
                      if (element.localName == 'iframe') {
                        if (_isReaderMode || _isNovelMode)
                          return const SizedBox.shrink();

                        bool isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 15),
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              String? src = element.attributes['src'];
                              String finalUrl = (src == null || src.isEmpty)
                                  ? "${currentBaseUrl.value}plugin.php?id=cxpform:style2&form_id=35&type=iframe&tid=${widget.tid}"
                                  : (src.startsWith('http')
                                        ? src
                                        : "${currentBaseUrl.value}$src");

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GeneralWebViewPage(
                                    url: finalUrl,
                                    title: "参与问卷",
                                    isPrintMode: false,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.check_box_outlined,
                              color: isDark
                                  ? Colors.blue[200]
                                  : Colors.blue[700],
                            ),
                            label: const Text("点击此处参与读者问卷"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? const Color(0xFF262626)
                                  : Colors.blue[50],
                              foregroundColor: isDark
                                  ? Colors.blue[100]
                                  : Colors.blue[900],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.blue[100]!,
                                ),
                              ),
                              elevation: 0,
                            ),
                          ),
                        );
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
                height: _lineHeight,
                color: _readerTextColor,
                fontFamily: "Serif",
              ),

              // 【核心修复】在阅读模式下彻底隐藏问卷
              customStylesBuilder: (element) {
                // 如果是问卷的那个蓝色 div 容器，直接隐藏
                if (element.localName == 'div' &&
                    (element.attributes['style']?.contains('#d4ebfa') ??
                        false)) {
                  return {'display': 'none'};
                }
                return null;
              },

              customWidgetBuilder: (ele) {
                // 阅读模式下 iframe 也不渲染
                if (ele.localName == 'iframe') return const SizedBox.shrink();

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

  // 【新增】智能 Header 生成器
  Map<String, String> _getHeadersForUrl(String url) {
    // 1. 获取当前论坛的主机名 (如 giantesswaltz.org)
    String currentHost = Uri.parse(currentBaseUrl.value).host;

    // 2. 判断是否是站内图片
    // 如果 URL 包含当前域名，或者是相对路径（不以 http 开头），或者是备用域名
    bool isInternal =
        url.contains(currentHost) ||
        !url.startsWith('http') ||
        url.contains('giantesswaltz.org') ||
        url.contains('gtswaltz.org');

    if (isInternal) {
      // 站内图片：全副武装
      return {
        'Cookie': _userCookies,
        'User-Agent': kUserAgent,
        'Referer': currentBaseUrl.value,
      };
    } else {
      // 站外图片：净身出户 (只带 UA，防止被对方防盗链策略拦截)
      return {'User-Agent': kUserAgent};
    }
  }

  Widget _buildClickableImage(String url) {
    if (url.isEmpty) return const SizedBox();

    // 1. 处理相对路径
    String fullUrl = url.startsWith('http')
        ? url
        : "${currentBaseUrl.value}$url";

    // 2. 【核心修复】彻底清洗 HTML 实体转义
    // 有时候会遇到 &amp;amp; 这种多重转义，循环替换直到没有为止
    while (fullUrl.contains('&amp;')) {
      fullUrl = fullUrl.replaceAll('&amp;', '&');
    }

    // 3. 【新增优化】针对部分外链，去掉 URL 参数以获取高清原图
    // 逻辑：如果是外链，且包含 ?，尝试去掉 ? 后面的内容
    String currentHost = Uri.parse(currentBaseUrl.value).host;
    bool isInternal =
        fullUrl.contains(currentHost) ||
        fullUrl.contains('giantesswaltz.org') ||
        fullUrl.contains('gtswaltz.org');

    if (!isInternal && fullUrl.contains('?')) {
      // 这里的逻辑是：如果 URL 看起来像是一个图片文件 (.jpg, .png)，后面跟了参数，就去掉参数
      // 这样可以解决 natalie.mu 等网站缩略图参数报错的问题，也能拿到更高清的图
      String urlNoParams = fullUrl.split('?').first;
      String ext = urlNoParams.toLowerCase();
      if (ext.endsWith('.jpg') ||
          ext.endsWith('.png') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.gif') ||
          ext.endsWith('.webp')) {
        print("✂️ [Image] 自动剥离外链参数，获取原图: $urlNoParams");
        fullUrl = urlNoParams;
      }
    }

    // 4. 获取动态 Header (上一轮加的逻辑)
    Map<String, String> dynamicHeaders = _getHeadersForUrl(fullUrl);

    return Hero(
      tag: fullUrl, // 使用 URL 作为唯一 Tag
      child: RetryableImage(
        imageUrl: fullUrl,
        cacheManager: globalImageCache,
        headers: dynamicHeaders,
        onTap: (u) => Navigator.push(
          context,
          // 下面这行稍微改一下，把 MaterialPageRoute 改成 PageRouteBuilder 会更丝滑，不过默认的也行
          MaterialPageRoute(
            builder: (c) =>
                ImagePreviewPage(imageUrl: u, headers: dynamicHeaders),
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
            // 【新增调试逻辑】
            return InkWell(
              onTap: () async {
                try {
                  // 1. 尝试找到本地缓存的文件路径
                  var fileInfo = await widget.cacheManager.getFileFromCache(
                    url,
                  );
                  if (fileInfo != null) {
                    File badFile = fileInfo.file;
                    // 2. 读取文件开头的一部分内容（通常前100个字符就能看出是不是HTML）
                    String content = await badFile.readAsString();
                    print("⚠️ [Image Debug] 发现坏图文件！内容预览:");
                    print("----------------------------------");
                    print(
                      content.length > 200
                          ? content.substring(0, 200)
                          : content,
                    );
                    print("----------------------------------");

                    if (content.contains("<!DOCTYPE html") ||
                        content.contains("<html")) {
                      print("💡 结论：下载到的是网页（防火墙拦截页），不是图片。");
                    } else if (content.contains("messageval")) {
                      print("💡 结论：下载到的是 JSON 报错信息（可能掉登录了）。");
                    }
                  } else {
                    print("🚨 [Image Debug] 本地竟然没找到缓存文件？");
                  }
                } catch (e) {
                  print("🛠️ [Image Debug] 读取坏图文件失败（可能是二进制流）: $e");
                }

                // 执行清理并重试（保持你之前的清理代码）
                await widget.cacheManager.removeFile(widget.imageUrl);
                await CachedNetworkImage.evictFromCache(widget.imageUrl);
                setState(() => _retryCount++);
              },
              child: Container(
                height: 120,
                width: double.infinity,
                color: Colors.red.withOpacity(0.1),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bug_report, color: Colors.red),
                    Text("加载失败：可能是网络被拦截\n点击尝试重连", textAlign: TextAlign.center),
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
