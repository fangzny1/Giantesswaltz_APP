import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_giantessnight_1/image_preview_page.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 建议引入这个库
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
  final bool initialNovelMode;
  final String? initialAuthorId;
  const ThreadDetailPage({
    super.key,
    required this.tid,
    required this.subject,
    this.initialPage = 1,
    this.initialNovelMode = false,
    this.initialAuthorId,
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
  final String _baseUrl = "https://www.giantessnight.com/gnforum2012/";
  String _userCookies = "";

  // 自定义缓存管理器（保存7天，最多500张图）
  final customCacheManager = CacheManager(
    Config(
      'gn_forum_imageCache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 500,
    ),
  );

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
    _loadLocalCookie();
    _loadSettings(); // 【新增】加载背景色设置
    if (widget.initialNovelMode) {
      _isNovelMode = true;
      _isOnlyLandlord = true;
      _isReaderMode = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // 【关键】如果有传入楼主ID，直接赋值！
      // 这样 _loadPage 发送请求时就会带上 &authorid=xxx，服务器就能返回正确的页码
      if (widget.initialAuthorId != null &&
          widget.initialAuthorId!.isNotEmpty) {
        _landlordUid = widget.initialAuthorId;
      }
    }

    _initWebView();
    _initFavCheck();
    _scrollController.addListener(_onScroll);
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
    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
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
    _hiddenController.loadRequest(
      Uri.parse(url),
      headers: {
        'Cookie': _userCookies, // 带上！
        'User-Agent': kUserAgent,
      },
    );
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
                      // 【核心逻辑】保存选中的这一楼
                      // 我们假设每一页有 10 楼（Discuz 默认），反推页码
                      // 但为了稳妥，我们直接保存当前加载到的最大页码 _maxPage
                      // 或者，如果你希望保存这个楼层所在的具体位置，需要后端支持，这里我们先保存 _maxPage
                      // 这样下次进来，至少能保证这一楼是加载出来的
                      _saveBookmarkWithFloor(post.floor, _maxPage);
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

  Future<void> _saveBookmarkWithFloor(String floorName, int pageToSave) async {
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

  Future<void> _saveBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('local_bookmarks');
    List<dynamic> jsonList = [];
    if (jsonStr != null && jsonStr.startsWith("["))
      jsonList = jsonDecode(jsonStr);

    // 【优化】书签标题加上模式标识
    String subjectSuffix = _isNovelMode ? " (小说模式)" : "";

    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: widget.subject,
      author: _posts.isNotEmpty ? _posts.first.author : "未知",
      authorId: _landlordUid ?? "",
      page: _maxPage,
      savedTime: DateTime.now().toString().substring(0, 16),
      isNovelMode: _isNovelMode,
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
      // 如果手动切换只看楼主，退出小说模式状态（逻辑上解耦）
      if (!_isOnlyLandlord) _isNovelMode = false;

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

  // ... _parseFavList 保持不变 (略，为了节省篇幅，逻辑未变)
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

  // 【核心升级】使用 CachedNetworkImage + 弱网点击重试
  Widget _buildClickableImage(String url) {
    if (url.isEmpty) return const SizedBox();

    String fullUrl = url;
    if (!fullUrl.startsWith('http')) {
      String base = _baseUrl.endsWith('/') ? _baseUrl : "$_baseUrl/";
      String path = fullUrl.startsWith('/') ? fullUrl.substring(1) : fullUrl;
      fullUrl = base + path;
    }

    // 使用我们新写的 State 组件
    return RetryableImage(
      imageUrl: fullUrl,
      cacheManager: customCacheManager,
      headers: {
        'Cookie': _userCookies,
        'User-Agent': kUserAgent,
        'Referer': _baseUrl,
        'Accept':
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      },
      // 点击预览逻辑
      onTap: (previewUrl) {
        // 跳转到我们之前写的 ImagePreviewPage
        // 注意：这里要引入 image_preview_page.dart
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewPage(
              imageUrl: previewUrl,
              headers: {
                'Cookie': _userCookies,
                'User-Agent': kUserAgent,
                'Referer': _baseUrl,
              },
            ),
          ),
        );
      },
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
          NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              if (_isReaderMode) return []; // 阅读模式隐藏 AppBar
              return [
                SliverAppBar(
                  floating: false,
                  pinned: false,
                  snap: false,
                  title: Text(
                    widget.subject,
                    style: const TextStyle(fontSize: 16),
                  ),
                  centerTitle: false,
                  elevation: 0,
                  backgroundColor: bgColor,
                  surfaceTintColor: Colors.transparent,
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
        opacity: (_isReaderMode && !_isFabOpen) ? 0.3 : 1.0, // 阅读模式下半透明
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
                label: "保存进度", // 改个名
                onTap: () {
                  _toggleFab(); // 先关菜单
                  _showSaveBookmarkDialog(); // 弹窗选楼层
                },
              ),
              const SizedBox(height: 12),
              _buildFabItem(
                icon: _isNovelMode ? Icons.auto_stories : Icons.menu_book,
                label: _isNovelMode ? "退出小说" : "小说模式", // 【核心功能入口】
                color: _isNovelMode ? Colors.purpleAccent : null,
                onTap: _toggleNovelMode,
              ),
              const SizedBox(height: 12),
              if (!_isNovelMode) ...[
                // 小说模式下不显示这些多余按钮
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
                  ? Colors.grey.withOpacity(0.8)
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
                  if (isDarkMode && element.attributes.containsKey('style')) {
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
    );
  }

  Widget _buildReaderMode() {
    if (_posts.isEmpty) return const Center(child: Text("加载中..."));

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
                        'background-color': 'rgba(255, 255, 255, 0.1)', // 半透明白
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
          );
        },
      ),
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
          errorWidget: (context, url, error) {
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
