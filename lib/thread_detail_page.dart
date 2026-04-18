import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:giantesswaltz_app/cloudflare_solver.dart';
import 'package:giantesswaltz_app/gallery_reader_page.dart';
import 'package:giantesswaltz_app/history_manager.dart';
import 'package:giantesswaltz_app/ultra_reader_page.dart';
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
import 'package:share_plus/share_plus.dart';

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
  final int page; // 【新增】该楼层所归属的原帖真实页码
  final List<String> tags; // 【新增】标签列表
  final List<Map<String, String>> metadata; // 【新增】用于存放原作信息等键值对
  PostItem({
    required this.pid,
    required this.author,
    required this.authorId,
    required this.avatarUrl,
    required this.time,
    required this.contentHtml,
    required this.floor,
    required this.device,
    required this.page,
    this.tags = const [], // 默认为空
    this.metadata = const [], // 默认为空
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
  int? _pendingFloorJump; // 记录需要“空降”的目标楼层号
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
  bool _isNoImageMode = false; // 【新增】无图模式开关
  late int _minPage;
  late int _maxPage; // 【新增】记录当前列表加载的最大页码
  int _targetPage = 1;
  int _totalPages = 1;

  bool _showSideSlider = false; // 是否显示侧边滑动条

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

  // 【新增】用于物理锚点定位
  double _exactFloor = 1.0; // 精确到小数点的当前楼层（如 3.5 代表第3楼看了一半）
  double _internalFraction = 0.0; // 记录楼层内部的百分比进度
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
  // 【新增】高级悬浮提示框 (Toast)
  // ==========================================
  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        // 【核心控制】调整 bottom 的值可以控制它悬浮的高度，left/right 控制宽度
        margin: const EdgeInsets.only(bottom: 120, left: 60, right: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary.withOpacity(0.85),
        duration: const Duration(seconds: 2),
        elevation: 0,
      ),
    );
  }

  // 【核心修复】修改为基于真实页码的分页控制
  Future<void> _loadPage(int reqPage, {bool resetScroll = false}) async {
    if (mounted) setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final String tempCacheKey = 'thread_temp_cache_${widget.tid}_$reqPage';
    final String? tempCache = prefs.getString(tempCacheKey);
    if (tempCache != null && _posts.isEmpty) {
      try {
        _processApiResponse(jsonDecode(tempCache), reqPage);
      } catch (_) {}
    }

    // 关键改变：任何模式下请求始终全量请求（不加 authorid），以保留完整的 API 原始分页和准确的页码！
    String url =
        '${currentBaseUrl.value}api/mobile/index.php?version=4&module=viewthread&tid=${widget.tid}&page=$reqPage';

    try {
      String responseBody = await HttpService().getHtml(url);

      responseBody = responseBody.trim();
      if (responseBody.startsWith('"') && responseBody.endsWith('"')) {
        responseBody = jsonDecode(responseBody);
      }

      final data = jsonDecode(responseBody);

      if (data['Message'] != null && data['Variables'] == null) {
        _handleLoginExpired(data['Message']['messagestr']);
        return;
      }

      await prefs.setString(tempCacheKey, responseBody);
      _currentRawJson = responseBody;
      _processApiResponse(data, reqPage);

      if (resetScroll && _scrollController.hasClients)
        _scrollController.jumpTo(0);
    } catch (e) {
      print("❌ API 请求或解析失败: $e");
      String? offlineData = await OfflineManager().readPage(
        widget.tid,
        reqPage,
      );
      if (offlineData != null && offlineData.isNotEmpty) {
        try {
          _currentRawJson = offlineData;
          _processApiResponse(jsonDecode(offlineData), reqPage);
        } catch (err) {
          print("❌ 离线数据解析失败: $err");
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 【新增】辅助方法：执行自动续命
  Future<void> _performAutoRevive() async {
    if (mounted) {
      _showToast("连接失效，正在自动修复...");
    }
    // 调用 HttpService 的全局续命方法
    await HttpService().reviveSession();
    // 重新读取本地 Cookie 到内存
    await _loadLocalCookie();
  }

  void _processApiResponse(dynamic data, int reqPage) {
    if (data == null || data['Variables'] == null) return;
    final vars = data['Variables'];

    String sortHtml = "";
    // --- 【修改点】：提取纯净的标签数据，不再拼接 HTML ---
    List<String> extractedTags = [];
    List<Map<String, String>> extractedMetadata = [];
    if (vars['threadsortshow'] != null &&
        vars['threadsortshow']['optionlist'] != null) {
      var optionList = vars['threadsortshow']['optionlist'];
      if (optionList is List && optionList.isNotEmpty) {
        for (var option in optionList) {
          String title = option['title']?.toString() ?? "";
          String rawValue = option['value']?.toString() ?? "";
          String type = option['type']?.toString() ?? ""; // 获取字段类型

          if (title.isEmpty || rawValue.trim().isEmpty || rawValue == "&nbsp;")
            continue;

          // 1. 如果是 checkbox 或 radio，提取为彩色小标签
          if (type == 'checkbox' || type == 'radio' || type == 'select') {
            var parts = rawValue
                .split(RegExp(r'(&nbsp;|\s+)'))
                .where((t) => t.trim().isNotEmpty);
            extractedTags.addAll(parts);
          }
          // 2. 剩下的 text, url, textarea 全部提取为附加信息表
          else {
            extractedMetadata.add({'title': title, 'value': rawValue});
          }
        }
      }
    }
    // ------------------------------------------------

    var rawPostList = vars['postlist'];
    Iterable items = [];
    if (rawPostList is List) {
      items = rawPostList;
    } else if (rawPostList is Map) {
      items = rawPostList.values;
    }

    if (items.isEmpty) {
      if (_posts.isNotEmpty) return;
    }

    _fid = vars['fid']?.toString();
    _formhash = vars['formhash']?.toString();

    final threadInfo = vars['thread'];
    if (threadInfo != null) {
      // --- 【新增：记录足迹逻辑】 ---
      // 只有在加载第一页（或初次进入）时记录，避免翻页重复记录
      if (reqPage == widget.initialPage && _posts.isEmpty) {
        String finalSubject =
            threadInfo['subject']?.toString() ?? widget.subject;
        String finalAuthor = threadInfo['author']?.toString() ?? "未知";

        // 调用你的历史管理器（确保已经 import 'history_manager.dart'）
        HistoryManager.addHistory(widget.tid, finalSubject, finalAuthor);

        // 顺便更新下页面显示的标题，防止有些链接进来的帖子没带标题
        if (mounted && _displaySubject != finalSubject) {
          setState(() {
            _displaySubject = finalSubject;
          });
        }
      }
      if (_landlordUid == null)
        _landlordUid = threadInfo['authorid']?.toString();
      int maxPos =
          int.tryParse(threadInfo['maxposition']?.toString() ?? '0') ?? 0;
      int allReplies =
          int.tryParse(threadInfo['allreplies']?.toString() ?? '0') ?? 0;
      int ppp = int.tryParse(vars['ppp']?.toString() ?? '10') ?? 10;
      // 【核心修复】读取实际的每页贴数，不再默认 10

      _ppp = int.tryParse(vars['ppp']?.toString() ?? '10') ?? 10;
      _totalPages = ((allReplies + 1) / ppp).ceil();
      if (_totalPages < 1) _totalPages = 1;
    }

    int apiPage = int.tryParse(vars['page']?.toString() ?? '') ?? reqPage;

    List<PostItem> newPosts = [];

    for (var p in items) {
      // 【核心修复】纯前端过滤楼主！保持原贴结构不变。
      if (_isOnlyLandlord && _landlordUid != null) {
        if (p['authorid'].toString() != _landlordUid) continue;
      }

      String content = p['message']?.toString() ?? "";

      if (p['first'] == "1" || p['first'] == 1) {
        if (sortHtml.isNotEmpty) content = sortHtml + content;
      }

      String cleanTime =
          p['dateline']?.toString().replaceAll('&nbsp;', ' ') ?? "";

      if (p['attachments'] != null && p['attachments'] is Map) {
        Map<String, dynamic> attachments = Map<String, dynamic>.from(
          p['attachments'],
        );
        String attachHtml = "<br/>";
        attachments.forEach((key, attach) {
          String fullUrl = "${attach['url']}${attach['attachment']}";

          // 【核心修复】更加健壮的图片判断逻辑
          // 1. isimage 只要不是 "0" (Discuz中 -1, 1 都是图)
          // 2. 或者 attachimg 字段标记为 "1"
          bool isImg =
              (attach['isimage'] != "0" && attach['isimage'] != 0) ||
              (attach['attachimg'] == "1" || attach['attachimg'] == 1);

          if (isImg) {
            // 如果判定是图片，使用 img 标签渲染
            attachHtml += '<img src="$fullUrl" style="max-width:100%;" /><br/>';
          } else {
            // 否则才识别为普通文件附件
            String fileName = attach['filename'] ?? "未知文件";
            String fileSize = attach['attachsize'] ?? "";
            attachHtml +=
                '<gn-file url="$fullUrl" name="$fileName" size="$fileSize"></gn-file><br/>';
          }
        });
        content += attachHtml;
      }

      newPosts.add(
        PostItem(
          pid: p['pid'].toString(),
          author: p['author'].toString(),
          authorId: p['authorid'].toString(),
          avatarUrl:
              "${currentBaseUrl.value}uc_server/avatar.php?uid=${p['authorid']}&size=middle",
          time: cleanTime,
          contentHtml: _cleanApiHtml(content),
          floor: "${p['number']}楼",
          device: "",
          page: apiPage, // 必须记录下楼层所在的原始分页页码！
          // 【新增】：只有 1 楼 (楼主) 带有标签
          tags: (p['first'] == "1" || p['first'] == 1) ? extractedTags : [],
          metadata: (p['first'] == "1" || p['first'] == 1)
              ? extractedMetadata
              : [], // 【新增】
        ),
      );
    }

    if (mounted) {
      setState(() {
        // 【关键】必须在 setState 块的最后释放锁
        _isLoadingMore = false;
        _isLoadingPrev = false;
        _isLoading = false;

        if (_posts.isEmpty) {
          // 情况 A: 第一次进入或者刚刚执行了清空跳转
          _posts = newPosts;
          _minPage = reqPage; // 【关键】初始化最小页码
          _maxPage = reqPage; // 【关键】初始化最大页码
        } else if (reqPage == _maxPage + 1) {
          // 情况 B: 向下自动翻页
          for (var p in newPosts) {
            if (!_posts.any((old) => old.pid == p.pid)) _posts.add(p);
          }
          _maxPage = reqPage;
        } else if (reqPage == _minPage - 1) {
          // 情况 C: 向上加载上一页
          var toInsert = newPosts
              .where((p) => !_posts.any((old) => old.pid == p.pid))
              .toList();
          _posts.insertAll(0, toInsert);
          _minPage = reqPage;
        }
        // 【核心修复】：如果有还没执行的定位指令，等列表渲染完（100ms）后飞过去
        if (_pendingFloorJump != null) {
          Future.delayed(const Duration(milliseconds: 100), () {
            _doPreciseScroll(_pendingFloorJump!, fraction: _internalFraction);
          });
        }
      });
    }
  }

  // 【新增】：智能标签构建器
  Widget _buildTagChip(String tag) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 重口类型 (猛男粉)
    final pinkTags = ['猎奇', '番茄酱', '入菊', '气味', '排泄', '消化', 'futa', 'GC', 'GT'];
    // 清新类型 (青绿色)
    final tealTags = ['巨大娘', '缩小人', '缩小女', 'Growth', '变物', '温柔', '其他'];

    Color baseColor;
    bool isOutline = false; // 是否是线框样式（用于 AI、字数等元数据）

    if (pinkTags.any((e) => tag.contains(e))) {
      baseColor = const Color(0xFFFF66A1); // 猛男粉
    } else if (tealTags.any((e) => tag.contains(e)) ||
        RegExp(r'^\+\d+$').hasMatch(tag)) {
      baseColor = const Color(0xFF58C9B9); // 清新绿 (包含 +1, +7 这种)
    } else if (tag.contains('AI') || tag.endsWith('字')) {
      baseColor = isDark ? Colors.grey[400]! : Colors.black87;
      isOutline = true; // 元数据用线框
    } else {
      baseColor = const Color(0xFFFF7A59); // 活力橙 (各种中度XP默认颜色)
    }

    // 1. 线框样式 (如 AI生成, 56K字)
    if (isOutline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: baseColor, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tag,
          style: TextStyle(
            color: baseColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
      );
    }

    // 2. 暗黑模式适配：半透明底 + 彩色高亮字 (不刺眼，极具现代感)
    if (isDark) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: baseColor.withOpacity(0.15),
          border: Border.all(color: baseColor.withOpacity(0.3), width: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tag,
          style: TextStyle(
            color: baseColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
      );
    }

    // 3. 白天模式适配：实心底 + 纯白字 (完美还原网页原版)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }

  // 【新增】：构建精美的原作/附加信息卡片
  Widget _buildMetadataCard(List<Map<String, String>> metadata) {
    if (metadata.isEmpty) return const SizedBox.shrink();

    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 动态计算适配颜色
    Color bgColor = isDark
        ? const Color(0xFF222222)
        : Colors.blueGrey.withOpacity(0.05);
    Color borderColor = isDark
        ? const Color(0xFF333333)
        : Colors.blueGrey.withOpacity(0.2);
    Color headerBgColor = isDark
        ? const Color(0xFF2A2A2A)
        : Colors.blueGrey.withOpacity(0.12);
    Color titleColor = isDark ? Colors.grey[500]! : Colors.grey[700]!;
    Color textColor = isDark ? Colors.grey[300]! : Colors.grey[800]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部标题栏
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: headerBgColor,
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark ? Colors.blue[300] : Colors.blue[800],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "附加信息",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? Colors.blue[100] : Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
            // 信息列表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                children: metadata.map((item) {
                  bool isLast = metadata.last == item;
                  return Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧属性名
                          SizedBox(
                            width: 80,
                            child: Text(
                              item['title'] ?? "",
                              style: TextStyle(color: titleColor, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 右侧属性值 (支持解析 HTML 链接)
                          Expanded(
                            child: HtmlWidget(
                              item['value'] ?? "",
                              textStyle: TextStyle(
                                fontSize: 13,
                                color: textColor,
                              ),
                              // 强制清除多余的外边距，让排版更紧凑
                              customStylesBuilder: (element) => {
                                'margin': '0',
                                'padding': '0',
                              },
                              onTapUrl: (url) async {
                                await _launchURL(url);
                                return true;
                              },
                            ),
                          ),
                        ],
                      ),
                      if (!isLast)
                        Divider(
                          color: isDark ? Colors.white12 : Colors.black12,
                          height: 16,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
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

    if (mounted) {
      setState(() {
        // 1. 【核心修复】无图模式独立读取，不受背景色影响
        _isNoImageMode = prefs.getBool('no_image_mode') ?? false;

        // 2. 行高也独立读取
        _lineHeight = prefs.getDouble('reader_line_height') ?? 1.4;

        // 3. 背景色单独判断
        int? colorVal = prefs.getInt('reader_bg_color');
        if (colorVal != null) {
          _readerBgColor = Color(colorVal);
          _readerTextColor = (_readerBgColor.computeLuminance() < 0.5)
              ? Colors.white70
              : Colors.black87;
        }
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
        if (mounted) _showToast("👍 点赞/顶帖成功！");
      } else if (resp.contains("不能")) {
        if (mounted) _showToast("你已经点过赞了");
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
    // 如果已经加载完了，或者正在加载中，直接拦截
    if (_isLoading ||
        _isLoadingMore ||
        _isLoadingPrev ||
        !_scrollController.hasClients)
      return;

    final position = _scrollController.position;

    // 距离底部 100 像素时触发加载
    if (position.pixels >= position.maxScrollExtent - 100) {
      if (_maxPage < _totalPages) {
        // 1. 先加锁
        setState(() => _isLoadingMore = true);

        // 2. 延迟执行加载，给 UI 一点缓冲时间
        Future.delayed(const Duration(milliseconds: 100), () {
          _loadPage(_maxPage + 1);
        });
      }
    }
  }

  void _loadNext() {
    if (_isLoading || _isLoadingMore) return;
    // 【修改点】向下加载永远比对 _maxPage
    if (_maxPage >= _totalPages) {
      _showToast("已经是最后一页了");
      return;
    }
    setState(() => _isLoadingMore = true);
    _loadPage(_maxPage + 1); // 加载底部以下的页
  }

  void _loadPrev() {
    if (_isLoading || _isLoadingPrev) return;
    // 【修改点】向上加载永远比对 _minPage
    if (_minPage <= 1) {
      _showToast("已经是第一页了");
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

  // ==========================================
  // 【新增】调用系统原生分享帖子链接
  // ==========================================
  void _shareThread() {
    // 构造当前帖子的完整网页链接
    final String url =
        "${currentBaseUrl.value}forum.php?mod=viewthread&tid=${widget.tid}";

    // 调用原生分享
    Share.share(
      '分享来自 GiantessWaltz 的帖子：\n《${widget.subject}》\n链接：$url',
      subject: widget.subject, // 邮件分享时会作为标题
    );
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
        _showToast("正在取消收藏...");

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

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "无图模式 (省流)",
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      "开启后帖子内图片将被替换为点击加载",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    value: _isNoImageMode,
                    activeColor: Theme.of(context).primaryColorLight,
                    onChanged: (val) async {
                      setSheetState(() => _isNoImageMode = val);
                      setState(() => _isNoImageMode = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('no_image_mode', val);
                    },
                  ),
                  // 【新增】无图模式开关
                  const Divider(height: 20),

                  // ====== 【新增：沉浸画廊模式入口】 ======
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.collections,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: const Text(
                      "画廊阅读模式 (沉浸看图)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      "提取全帖图片，支持左右翻页与双指缩放",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context); // 先关闭底部弹窗
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => GalleryReaderPage(
                            tid: widget.tid,
                            title: _displaySubject,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 10),
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

  // 【核心黑科技】：完全脱离高度计算，只扫描屏幕内渲染的楼层
  void _updateCurrentFloorValue() {
    // 如果正在拖动侧边条、正在加载、或者控制器还没准备好，不执行扫描
    if (!_scrollController.hasClients ||
        _posts.isEmpty ||
        _isScrubbingScroll ||
        _isLoadingMore ||
        _isLoadingPrev)
      return;

    // 视线基准线：屏幕顶部往下 100 像素的位置
    final double anchorY = MediaQuery.of(context).padding.top + 100.0;

    int? activeFloor;
    double activeFraction = 0.0;

    for (int i = 0; i < _posts.length; i++) {
      final key = _pidKeys[_posts[i].pid];
      if (key == null || key.currentContext == null) continue;

      // 关键修复：先获取 RenderObject
      final dynamic renderObject = key.currentContext!.findRenderObject();

      // 检查是否为 RenderBox 且已经完成排版
      if (renderObject is RenderBox && renderObject.hasSize) {
        // 获取组件相对于屏幕顶部的 y 坐标
        double y = renderObject.localToGlobal(Offset.zero).dy;
        double h = renderObject.size.height;

        // 判断该楼层是否跨过了我们的“视线基准线”
        if (y <= anchorY) {
          activeFloor =
              int.tryParse(_posts[i].floor.replaceAll(RegExp(r'[^0-9]'), '')) ??
              (i + 1);
          // 算出在这一楼内部滑过了多少比例
          activeFraction = ((anchorY - y) / h).clamp(0.0, 1.0);
        } else {
          // 如果这层楼还在基准线下面，说明前面的已经是我们要找的了
          break;
        }
      }
    }

    if (activeFloor != null) {
      double newExactFloor = activeFloor + activeFraction;

      // 【防抖】：进度变化超过 0.01 (1%) 时才更新界面，保证性能
      if ((newExactFloor - _exactFloor).abs() > 0.01) {
        setState(() {
          _exactFloor = newExactFloor;

          // 顺便根据当前楼层计算出页码，自动更新底部页码显示
          int pageOnScreen = ((activeFloor! - 1) / _ppp).floor() + 1;
          if (_targetPage != pageOnScreen) {
            _targetPage = pageOnScreen;
          }
        });
      }
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
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            // 【新增】：当屏幕正常滑动时，启动扫描仪
            if (!_isScrubbingScroll) {
              _updateCurrentFloorValue();
            }
            return false; // 继续向上传递事件
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
                  // 【核心修复1】：当呼出侧边条时，彻底锁死底层滚动，防止手势被抢走！
                  physics: _showSideSlider
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
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
                // 2. 【核心修复】右侧滑动条层 (放在 CustomScrollView 之后，它就会浮在上面)
                if (_showSideSlider)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _showSideSlider = false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        color: Colors.black26,
                        child: Stack(
                          children: [
                            Positioned(
                              right: 25,
                              top: MediaQuery.of(context).size.height * 0.15,
                              bottom: MediaQuery.of(context).size.height * 0.15,
                              child: GestureDetector(
                                onTap: () {},
                                onVerticalDragUpdate: (details) {
                                  // 1. 获取屏幕总尺寸
                                  final double screenHeight = MediaQuery.of(
                                    context,
                                  ).size.height;

                                  // 2. 定义条子的物理边界（必须与 Positioned 的定义的 0.15 和 0.15 一致）
                                  double barTop = screenHeight * 0.15;
                                  double barBottom = screenHeight * 0.85;
                                  double barHeight = barBottom - barTop;

                                  // 3. 使用【绝对坐标】计算手指在条子内的位置
                                  // 手指位置减去条子顶部位置 = 手指在条子内的相对高度
                                  double fingerY = details.globalPosition.dy;
                                  double relativeY = (fingerY - barTop).clamp(
                                    0.0,
                                    barHeight,
                                  );

                                  // 4. 算出比例：0.0 代表最顶端，1.0 代表最底端
                                  double percent = relativeY / barHeight;

                                  setState(() {
                                    _isScrubbingScroll = true;
                                    // 5. 映射楼层：向下划 percent 增加，楼层增加
                                    _exactFloor =
                                        1 + (percent * (_totalPostsCount - 1));
                                  });
                                },
                                onVerticalDragEnd: (_) {
                                  int targetFloor = _exactFloor.round();
                                  int jumpToPage =
                                      ((targetFloor - 1) / _ppp).floor() + 1;
                                  setState(() {
                                    _isScrubbingScroll = false;
                                    _pendingFloorJump = targetFloor;
                                    _showSideSlider = false;
                                  });
                                  if (jumpToPage >= _minPage &&
                                      jumpToPage <= _maxPage) {
                                    _doPreciseScroll(targetFloor);
                                  } else {
                                    setState(() {
                                      _posts = [];
                                      _isLoading = true;
                                    });
                                    _loadPage(jumpToPage, resetScroll: true);
                                  }
                                },
                                child: Container(
                                  width: 55,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      const BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 6,
                                      height: double.infinity,
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 30,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          // 算出百分比
                                          double p = (_totalPostsCount > 1)
                                              ? (_exactFloor - 1) /
                                                    (_totalPostsCount - 1)
                                              : 0.0;
                                          return Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Positioned(
                                                // 【关键修正】：top 随 p 增大而增大，即向下走
                                                top:
                                                    p * constraints.maxHeight -
                                                    8,
                                                left: -5,
                                                child: CircleAvatar(
                                                  radius: 8,
                                                  backgroundColor: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 侧边气泡提示
                            if (_isScrubbingScroll && _posts.isNotEmpty)
                              Builder(
                                builder: (context) {
                                  int safeIndex = (_exactFloor.round() - 1)
                                      .clamp(0, _posts.length - 1);
                                  double p = (_totalPostsCount > 1)
                                      ? (_exactFloor - 1) /
                                            (_totalPostsCount - 1)
                                      : 0.0;

                                  // 气泡的垂直位置计算
                                  double barTop =
                                      MediaQuery.of(context).size.height * 0.15;
                                  double barHeight =
                                      MediaQuery.of(context).size.height * 0.7;

                                  return Positioned(
                                    right: 90,
                                    // 【关键修正】：气泡位置也必须随 p 增大而增大（向下走）
                                    top: barTop + (p * barHeight) - 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          const BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _posts[safeIndex].floor,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _doPreciseScroll(int floorNumber, {double fraction = 0.0}) async {
    // 在内存列表中找到最接近目标楼层的索引
    int indexInList = _posts.indexWhere((p) {
      String raw = p.floor.replaceAll(RegExp(r'[^0-9]'), '');
      return int.parse(raw) >= floorNumber;
    });

    if (indexInList != -1) {
      // 第一步：先跳到该楼层的头部
      await _scrollController.scrollToIndex(
        indexInList,
        preferPosition: AutoScrollPosition.begin,
        duration: const Duration(milliseconds: 300),
      );

      // 第二步：执行楼层内的小数微调
      if (fraction > 0.01) {
        // 给 HTML 渲染留出 100ms 的响应时间
        await Future.delayed(const Duration(milliseconds: 100));

        // 获取刚才跳到的组件高度，进行二次位移
        final key = _pidKeys[_posts[indexInList].pid];
        if (key != null && key.currentContext != null) {
          final box = key.currentContext!.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            // 计算基于该楼层高度的偏移量
            double extraOffset = box.size.height * fraction;

            _scrollController.animateTo(
              _scrollController.offset + extraOffset,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      }
      // 定位完成，清除待处理指令
      _pendingFloorJump = null;
    }
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
              // === 第一部分：本页精准进度条 ===
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
                        // 【核心】：AnimatedBuilder 实时监听当前页的像素滚动
                        child: AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, child) {
                            double currentOffset = 0.0;
                            double maxScroll = 0.01; // 防除0报错

                            // 获取当前页的真实高度
                            if (_scrollController.hasClients &&
                                _scrollController
                                    .position
                                    .hasContentDimensions) {
                              currentOffset = _scrollController.offset;
                              maxScroll =
                                  _scrollController.position.maxScrollExtent;
                              if (maxScroll <= 0) maxScroll = 0.01;
                            }

                            // 算出百分比
                            int percent = ((currentOffset / maxScroll) * 100)
                                .clamp(0, 100)
                                .toInt();

                            return Slider(
                              value: currentOffset.clamp(0.0, maxScroll),
                              min: 0.0,
                              max: maxScroll,
                              label: "$percent%",
                              onChanged: (v) {
                                // 【丝滑拖拽】：直接 jumpTo，页面死死跟着手指走，绝对不会抽搐！
                                if (_scrollController.hasClients) {
                                  _scrollController.jumpTo(v);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // 【新增】：当前页阅读百分比显示
                    AnimatedBuilder(
                      animation: _scrollController,
                      builder: (context, child) {
                        double currentOffset = 0.0;
                        double maxScroll = 0.01;
                        if (_scrollController.hasClients &&
                            _scrollController.position.hasContentDimensions) {
                          currentOffset = _scrollController.offset;
                          maxScroll =
                              _scrollController.position.maxScrollExtent;
                          if (maxScroll <= 0) maxScroll = 0.01;
                        }
                        int percent = ((currentOffset / maxScroll) * 100)
                            .clamp(0, 100)
                            .toInt();

                        return SizedBox(
                          width: 45,
                          child: Text(
                            "$percent%",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),

                    // 【右侧按钮】：不再呼出侧边条，而是呼出全局跳页菜单！
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
                      // 点击这个按钮，弹出大跳跃菜单
                      onPressed: _showPageJumpDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withOpacity(0.1),
              ),

              // === 第二部分：操作按钮 (回复、点赞、收藏等保持不变) ===
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
          // 在 _buildFabMenu 列表里添加
          _buildFabItem(
            icon: Icons.share_outlined,
            label: "分享帖子",
            color: Colors.blueAccent,
            onTap: () {
              _toggleFab(); // 关闭菜单
              _shareThread(); // 触发分享
            },
          ),
          const SizedBox(height: 12),
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
            icon: Icons.auto_stories_rounded, // 使用一个更高级的书本图标
            label: "超级全量模式",
            color: Colors.deepOrange,
            onTap: () {
              _toggleFab(); // 关闭菜单
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) =>
                      UltraReaderPage(tid: widget.tid, title: _displaySubject),
                ),
              );
            },
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

  // 现代感十足的骨架屏加载样式
  Widget _buildLoadingSkeleton() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    return SliverList(
      delegate: SliverChildBuilderDelegate((ctx, index) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: baseColor, radius: 18), // 模拟头像
                  const SizedBox(width: 12),
                  Container(width: 100, height: 12, color: baseColor), // 模拟用户名
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 14,
                color: baseColor,
              ), // 模拟文字第一行
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 14,
                color: baseColor,
              ), // 模拟文字第二行
              const SizedBox(height: 8),
              Container(width: 200, height: 14, color: baseColor), // 模拟文字第三行
              const SizedBox(height: 20),
              Divider(color: baseColor.withOpacity(0.2)),
            ],
          ),
        );
      }, childCount: 5), // 默认显示5个骨架
    );
  }

  Widget _buildNativeSliver() {
    if (_isLoading && _posts.isEmpty) return _buildLoadingSkeleton();
    if (!_isLoading && _posts.isEmpty)
      return const SliverFillRemaining(child: Center(child: Text("暂无内容")));

    // 我们不再使用单个 SliverList，而是手动拼接所有的 Sliver
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 100),
      sliver: SliverMainAxisGroup(
        // 使用这个组件把多个 Sliver 组合起来
        slivers: [
          // 1. “加载上一页” 按钮
          if (_minPage > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_upward),
                    label: Text("加载上一页 (第 ${_minPage - 1} 页)"),
                    onPressed: _loadPrev,
                  ),
                ),
              ),
            ),

          // 2. 核心：遍历每一个回帖，将每个回帖转化为一组独立的 Sliver
          ..._posts.expand((post) => _buildPostSlivers(post)).toList(),

          // 3. 底部加载更多
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }

  Widget _buildThumbnailFileCard(String url, String keyName) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        onTap: () {
          // 点击依然可以进预览页看图
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => ImagePreviewPage(
                imageUrl: url,
                headers: _getHeadersForUrl(url),
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.teal.withOpacity(0.1)
                : Colors.teal.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.image_search, color: Colors.teal, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "预览缩略图 ($keyName.png)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.teal,
                      ),
                    ),
                    const Text(
                      "点击解析并查看原图",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExternalThumbnailCard(String url, String key) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: InkWell(
        onTap: () async {
          // 直接唤起系统外部浏览器
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.blueGrey.withOpacity(0.1)
                : Colors.blueGrey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.blueGrey.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.handyman_outlined,
                    color: Colors.blueGrey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "帖子缩略图 (二进制数据)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark
                          ? Colors.blueGrey[200]
                          : Colors.blueGrey[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "由于论坛机制，此图片无法在 App 内直接预览。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                "操作：点击在浏览器打开 -> 另存为文件 -> 将后缀名由 .txt 改为 .png 即可查看。",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Center(
                  child: Text(
                    "在外部浏览器中打开并解析",
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPostSlivers(PostItem post) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isLandlord = post.authorId == _landlordUid;
    // 【修复】：在这里直接定义，并在下面 key: anchorKey 使用
    final GlobalKey localAnchorKey = _pidKeys.putIfAbsent(
      post.pid,
      () => GlobalKey(),
    );
    int postIndex = _posts.indexOf(post);
    // 字符串清洗（防止黑色字体在暗黑模式看不见）
    String finalHtml = post.contentHtml;
    if (isDark) {
      finalHtml = finalHtml
          .replaceAll('color:rgb(0, 0, 0)', 'color:#E0E0E0')
          .replaceAll('color: rgb(0, 0, 0)', 'color:#E0E0E0')
          .replaceAll('color:#000000', 'color:#E0E0E0')
          .replaceAll('color="#000000"', 'color="#E0E0E0"')
          .replaceAll('color="#000"', 'color="#E0E0E0"');
    }

    return [
      // A. 头部：作者信息、标签、头像 (SliverToBoxAdapter)
      SliverToBoxAdapter(
        child: AutoScrollTag(
          key: ValueKey(post.pid), // 必须是唯一的
          controller: _scrollController,
          index: postIndex, // 定位的核心索引
          child: Container(
            key: localAnchorKey, // ✅ 钥匙挂在这里！Container 是标准的 RenderBox
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            color: Theme.of(context).cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _jumpToUser(post),
                      child: Hero(
                        tag: "avatar_${post.authorId}_${post.pid}",
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
                if (post.metadata.isNotEmpty) _buildMetadataCard(post.metadata),
                if (post.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: post.tags.map((t) => _buildTagChip(t)).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),

      // B. 核心：正文内容 (利用 sliverList 模式实现回帖内部的懒加载)
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: HtmlWidget(
          finalHtml,
          renderMode: RenderMode.sliverList, // 保持高性能懒加载
          textStyle: TextStyle(
            fontSize: _fontSize - 2,
            height: _lineHeight,
            color: isDark ? Colors.white70 : Colors.black87,
          ),

          // 【核心修复：重新注入图片点击和附件识别逻辑】
          customWidgetBuilder: (element) {
            // 1. 处理图片点击预览
            if (element.localName == 'img') {
              String src = element.attributes['src'] ?? '';
              // 【核心修改】：遇到这种难搞的缩略图，直接转为“外部下载卡片”
              if (src.contains('mod=image')) {
                // 1. 强力清洗链接
                String cleanedUrl = src;
                while (cleanedUrl.contains('&amp;'))
                  cleanedUrl = cleanedUrl.replaceAll('&amp;', '&');
                if (!cleanedUrl.startsWith('http'))
                  cleanedUrl = "${currentBaseUrl.value}$cleanedUrl";

                // 2. 提取 Key 方便用户对照
                var keyMatch = RegExp(
                  r'key=([a-zA-Z0-9]+)',
                ).firstMatch(cleanedUrl);
                String keyName = keyMatch?.group(1) ?? "unknown";

                // 返回一个纯粹的“外部工具卡片”
                return _buildExternalThumbnailCard(cleanedUrl, keyName);
              }

              if (src.contains('favicon.ico'))
                return const SizedBox.shrink(); // 屏蔽小图标
              if (src.isNotEmpty) return _buildClickableImage(src); // 调用下方的预览逻辑
            }

            // 2. 处理之前写的 gn-file 附件卡片
            if (element.localName == 'gn-file') {
              String url = element.attributes['url'] ?? '';
              String name = element.attributes['name'] ?? '附件';
              String size = element.attributes['size'] ?? '';
              return _buildFileAttachmentCard(url, name, size); // 建议封装一下
            }

            // 3. 处理 iframe 问卷
            if (element.localName == 'iframe') {
              // ... 原有的 iframe 按钮逻辑 ...
            }
            return null;
          },

          customStylesBuilder: (element) {
            // 保持背景色清理逻辑
            if (isDark) {
              String style = element.attributes['style'] ?? '';
              if (style.contains('background-color') ||
                  style.contains('background:')) {
                return {
                  'background-color': 'transparent !important',
                  'color': '#E0E0E0 !important',
                };
              }
            }
            return null;
          },

          // 处理网页链接点击
          onTapUrl: (url) async {
            await _launchURL(url);
            return true;
          },
        ),
      ),

      // C. 底部：装饰和间距
      SliverToBoxAdapter(
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
                width: 8,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // 【新增】：专门负责渲染文件附件卡片的方法，解决报错
  Widget _buildFileAttachmentCard(String url, String name, String size) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          // 调用系统外部浏览器下载
          if (url.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("正在调用系统下载: $name")));
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
              color: isDark ? Colors.white12 : Colors.blueGrey.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              // 附件图标
              Icon(
                name.toLowerCase().endsWith('.txt')
                    ? Icons.description_outlined
                    : name.toLowerCase().contains('.zip') ||
                          name.toLowerCase().contains('.7z') ||
                          name.toLowerCase().contains('.rar')
                    ? Icons.folder_zip_outlined
                    : Icons.insert_drive_file_outlined,
                size: 36,
                color: isDark ? Colors.blue[300] : Colors.blue[700],
              ),
              const SizedBox(width: 12),
              // 文件名和大小
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              // 下载图标
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
                  color: isDark ? Colors.blue[200] : Colors.blue[800],
                ),
              ),
            ],
          ),
        ),
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
    String finalHtml = post.contentHtml;

    if (isDark) {
      finalHtml = finalHtml
          .replaceAll('color:rgb(0, 0, 0)', 'color:#E0E0E0')
          .replaceAll('color: rgb(0, 0, 0)', 'color:#E0E0E0')
          .replaceAll('color:#000000', 'color:#E0E0E0')
          .replaceAll('color="#000000"', 'color="#E0E0E0"')
          .replaceAll('color="#000"', 'color="#E0E0E0"');
    }

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
                // 【新增】：渲染原作/附加信息卡片（会显示在标签云上方）
                if (post.metadata.isNotEmpty) _buildMetadataCard(post.metadata),
                // 【新增】：如果这层楼有标签，就把它渲染出来！
                if (post.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 6, // 标签之间的横向间距
                      runSpacing: 6, // 标签换行后的纵向间距
                      children: post.tags.map((t) => _buildTagChip(t)).toList(),
                    ),
                  ),

                SelectionArea(
                  child: // 在 _buildPostCard 和 _buildReaderCard 里面
                  HtmlWidget(
                    finalHtml,
                    textStyle: TextStyle(
                      fontSize: _fontSize - 2, // 或者是 _fontSize
                      height: _lineHeight,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    // ==================== 1. 样式构建器 (解决背景和文字冲突) ====================
                    customStylesBuilder: (element) {
                      bool isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      String style = element.attributes['style'] ?? '';
                      String parentStyle =
                          element.parent?.attributes['style'] ?? '';

                      // 【核心修复：暗黑模式强除背景】
                      if (isDark) {
                        // 检查元素是否有显式的 style 包含背景色
                        String style = element.attributes['style'] ?? '';
                        if (style.contains('background-color') ||
                            element.attributes.containsKey('bgcolor')) {
                          // 强制背景透明，并确保文字颜色是浅色以防原本是黑色文字
                          return {
                            'background-color': 'transparent !important',
                            'color': '#E0E0E0 !important',
                          };
                        }
                      }
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
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ====== 【核心且绝对安全的修复】 ======
    String finalHtml = post.contentHtml;
    if (isDark) {
      finalHtml = finalHtml
          .replaceAll('color:rgb(0, 0, 0)', 'color:#E0E0E0')
          .replaceAll('color: rgb(0, 0, 0)', 'color:#E0E0E0')
          .replaceAll('color:#000000', 'color:#E0E0E0')
          .replaceAll('color="#000000"', 'color="#E0E0E0"')
          .replaceAll('color="#000"', 'color="#E0E0E0"');
    }
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
              finalHtml,
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
    // 如果是备用站
    if (url.contains('gtswaltz.org')) {
      return {
        'Cookie': _userCookies,
        'User-Agent': kUserAgent,
        'Referer': "https://gtswaltz.org/", // 备用站强制要求 Referer 是自己
        'Connection': 'keep-alive', // 保持连接，不重新握手
      };
    }

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
    // ==========================================
    // 【新增】无图模式拦截
    // ==========================================
    if (_isNoImageMode) {
      bool isDark = Theme.of(context).brightness == Brightness.dark;
      return InkWell(
        onTap: () {
          // 点击依然可以强制查看大图
          Map<String, String> dynamicHeaders = _getHeadersForUrl(fullUrl);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) =>
                  ImagePreviewPage(imageUrl: fullUrl, headers: dynamicHeaders),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: const Column(
            children: [
              Icon(Icons.image_not_supported, color: Colors.grey, size: 28),
              SizedBox(height: 8),
              Text(
                "无图模式已开启 (点击强制查看)",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
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
    if (_retryCount > 0) {
      finalUrl += (finalUrl.contains('?') ? '&' : '?') + 'retry=$_retryCount';
    }

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

          // 【核心修复】删掉 memCacheWidth 和 maxWidthDiskCache！！！
          // 让 Flutter 用底层的 C++ 引擎直接光速解码原图
          placeholder: (ctx, url) => Container(
            height: 150,
            color: Colors.grey.withOpacity(0.1),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (ctx, url, error) {
            return InkWell(
              onTap: () async {
                await widget.cacheManager.removeFile(widget.imageUrl);
                await CachedNetworkImage.evictFromCache(widget.imageUrl);
                if (mounted) {
                  setState(() => _retryCount++);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("已清理该图片坏块，正在重连..."),
                      duration: Duration(milliseconds: 800),
                    ),
                  );
                }
              },
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "图片加载失败（可能是网络拦截）",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      "点击强制重新下载 ($_retryCount)",
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
