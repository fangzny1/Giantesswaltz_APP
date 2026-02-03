import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 引入缓存图片

import 'forum_model.dart';
import 'thread_detail_page.dart';
import 'login_page.dart';
import 'main.dart';

// 用户信息模型
class UserProfile {
  final String username;
  final String uid;
  final String groupTitle;
  final String credits; // 总积分
  final Map<String, String> extCredits; // 扩展积分 (威望/金币等)
  final List<String> medalUrls; // 勋章图片链接
  final String bio; // 签名或介绍
  final String sightml; // 签名HTML
  final String postsCount;
  final String threadsCount;
  final String friendsCount;
  final String regDate;

  UserProfile({
    required this.username,
    required this.uid,
    required this.groupTitle,
    required this.credits,
    required this.extCredits,
    required this.medalUrls,
    required this.bio,
    required this.sightml,
    required this.postsCount,
    required this.threadsCount,
    required this.friendsCount,
    required this.regDate,
  });
}

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
  UserProfile? _userProfile; // 新增用户详情数据

  bool _isFirstLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  String _errorMsg = "";
  int _currentPage = 1;
  int _targetPage = 1;

  final String _baseUrl = kBaseUrl;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _scrollController.addListener(_onScroll);

    // 【新增】同时加载用户详细信息
    _loadUserProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _initWebView() {
    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent);

    _loadPage(1);
  }

  // 【新增】加载用户详细信息 (API)
  Future<void> _loadUserProfile() async {
    // API 地址: module=profile
    String url =
        '${_baseUrl}api/mobile/index.php?version=4&module=profile&uid=${widget.uid}';
    print("🚀 加载用户详情: $url");

    try {
      final dio = Dio();
      final prefs = await SharedPreferences.getInstance();
      final String cookie = prefs.getString('saved_cookie_string') ?? "";
      dio.options.headers['Cookie'] = cookie;
      dio.options.headers['User-Agent'] = kUserAgent;

      final response = await dio.get<String>(url);

      if (response.statusCode == 200 && response.data != null) {
        String jsonStr = response.data!;
        if (jsonStr.startsWith('"')) {
          jsonStr = jsonStr
              .substring(1, jsonStr.length - 1)
              .replaceAll('\\"', '"')
              .replaceAll('\\\\', '\\');
        }

        var data = jsonDecode(jsonStr);
        if (data['Variables'] != null && data['Variables']['space'] != null) {
          var space = data['Variables']['space'];
          var extCreditsMap = data['Variables']['extcredits'] ?? {};

          // 解析扩展积分
          Map<String, String> credits = {};
          // 简单解析前几个重要的
          if (extCreditsMap['1'] != null)
            credits['威望'] = space['extcredits1'] ?? '0';
          if (extCreditsMap['2'] != null)
            credits['金币'] = space['extcredits2'] ?? '0';
          if (extCreditsMap['3'] != null)
            credits['贡献'] = space['extcredits3'] ?? '0';

          // 解析勋章
          List<String> medals = [];
          // 如果 API 返回了 medals 数组 (你的 JSON 里是 null，可能需要 specific logic)
          // 暂时留空

          if (mounted) {
            setState(() {
              _userProfile = UserProfile(
                username: space['username'],
                uid: space['uid'],
                groupTitle: space['group']['grouptitle'] ?? "未知用户组",
                credits: space['credits'] ?? "0",
                extCredits: credits,
                medalUrls: medals,
                bio: space['bio'] ?? "",
                sightml: space['sightml'] ?? "",
                postsCount: space['posts'] ?? "0",
                threadsCount: space['threads'] ?? "0",
                friendsCount: space['friends'] ?? "0",
                regDate: space['regdate'] ?? "",
              );
            });
          }
        }
      }
    } catch (e) {
      print("❌ 用户详情加载失败: $e");
    }
  }

  void _loadPage(int page) async {
    if (!_hasMore && page > 1) return;
    _targetPage = page;

    if (mounted)
      setState(() {
        _isLoadingMore = true;
      });

    // 使用网页版抓取主题列表
    String url =
        '${_baseUrl}home.php?mod=space&uid=${widget.uid}&do=thread&view=me&order=dateline&mobile=no&page=$page';

    try {
      final dio = Dio();
      final prefs = await SharedPreferences.getInstance();
      final String cookie = prefs.getString('saved_cookie_string') ?? "";

      dio.options.headers['Cookie'] = cookie;
      dio.options.headers['User-Agent'] = kUserAgent;
      dio.options.connectTimeout = const Duration(seconds: 15);

      final response = await dio.get<String>(url);

      if (response.statusCode == 200 && response.data != null) {
        _parseHtmlData(response.data!);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoadingMore = false;
          _isFirstLoading = false;
          _errorMsg = "网络请求失败";
        });
    }
  }

  void _parseHtmlData(String htmlString) {
    try {
      var document = html_parser.parse(htmlString);
      List<UserThreadItem> newThreads = [];

      // 模式 A：GW (Rabbit 模板)
      var listItems = document.querySelectorAll('.c_threadlist ul li');

      if (listItems.isNotEmpty) {
        for (var li in listItems) {
          try {
            // 修复后的标题查找逻辑
            var titleNode = li.querySelector('.tit > a');
            if (titleNode == null || titleNode.text.trim().isEmpty) {
              var allLinks = li.querySelectorAll('.tit a');
              for (var link in allLinks) {
                if (link.children.any((child) => child.localName == 'img'))
                  continue;
                if (link.text.trim().isNotEmpty) {
                  titleNode = link;
                  break;
                }
              }
            }
            if (titleNode == null) continue;

            String subject = titleNode.text.trim();
            String href = titleNode.attributes['href'] ?? "";

            RegExp tidReg = RegExp(r'tid=(\d+)');
            String tid = tidReg.firstMatch(href)?.group(1) ?? "";
            if (tid.isEmpty) continue;

            String dateline = li.querySelector('.dte')?.text.trim() ?? "";
            String replies =
                li
                    .querySelector('.rep')
                    ?.text
                    .replaceAll(RegExp(r'[^0-9]'), '') ??
                "0";
            String views =
                li
                    .querySelector('.vie')
                    ?.text
                    .replaceAll(RegExp(r'[^0-9]'), '') ??
                "0";

            String forumName = "帖子";
            var catNode =
                li.querySelector('.cat a') ??
                li.querySelector('.sub a[href*="forumdisplay"]');
            if (catNode != null) forumName = catNode.text.trim();

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
      }
      // 模式 B：标准 Discuz (GN)
      else {
        var rows = document.querySelectorAll('form table tr');
        if (rows.isEmpty) rows = document.querySelectorAll('.tl table tr');
        rows = rows
            .where((r) => r.getElementsByTagName('td').isNotEmpty)
            .toList();

        for (var row in rows) {
          try {
            var titleLink =
                row.querySelector('th a[href*="viewthread"]') ??
                row.querySelector('td a[href*="viewthread"]');
            if (titleLink == null) continue;

            String subject = titleLink.text.trim();
            String href = titleLink.attributes['href'] ?? "";
            RegExp tidReg = RegExp(r'tid=(\d+)');
            String tid = tidReg.firstMatch(href)?.group(1) ?? "";
            if (tid.isEmpty) continue;

            String forumName = row.querySelector('a.xg1')?.text.trim() ?? "";
            String replies = "0";
            String views = "0";
            var numTd = row.querySelector('td.num');
            if (numTd != null) {
              replies = numTd.querySelector('a')?.text.trim() ?? "0";
              views = numTd.querySelector('em')?.text.trim() ?? "0";
            }
            String dateline = "";
            var byTd = row.querySelector('td.by');
            if (byTd != null)
              dateline = byTd.text.replaceAll(RegExp(r'\s+'), ' ').trim();

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
      }

      if (mounted) {
        setState(() {
          if (_targetPage == 1) {
            _threads = newThreads;
            _currentPage = 1;
          } else {
            for (var t in newThreads) {
              if (!_threads.any((old) => old.tid == t.tid)) {
                _threads.add(t);
              }
            }
            if (newThreads.isNotEmpty) _currentPage = _targetPage;
          }
          if (newThreads.length < 5) _hasMore = false;
          _isFirstLoading = false;
          _isLoadingMore = false;
          _errorMsg = "";
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkIfNeedLoadMore();
        });
      }
    } catch (e) {
      print("HTML 解析错误: $e");
      if (mounted)
        setState(() {
          _isLoadingMore = false;
          _isFirstLoading = false;
        });
    }
  }

  void _checkIfNeedLoadMore() {
    if (!_hasMore || _isLoadingMore) return;
    if (_scrollController.hasClients) {
      if (_scrollController.position.maxScrollExtent <= 0) {
        _loadMore();
      }
    }
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore || _isFirstLoading) return;
    _loadPage(_currentPage + 1);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Scaffold(
          backgroundColor: wallpaperPath != null
              ? Colors.transparent
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          body: Stack(
            children: [
              if (wallpaperPath != null)
                Positioned.fill(
                  child: Image.file(
                    File(wallpaperPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              if (wallpaperPath != null)
                Positioned.fill(
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: currentTheme,
                    builder: (context, mode, _) {
                      bool isDark = mode == ThemeMode.dark;
                      if (mode == ThemeMode.system) {
                        isDark =
                            MediaQuery.of(context).platformBrightness ==
                            Brightness.dark;
                      }
                      return Container(
                        color: isDark
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.3),
                      );
                    },
                  ),
                ),

              // 使用 NestedScrollView 来实现可折叠的头部
              NestedScrollView(
                controller: _scrollController,
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverAppBar.large(
                      title: Text(_userProfile?.username ?? widget.username),
                      backgroundColor:
                          (wallpaperPath != null &&
                              transparentBarsEnabled.value)
                          ? Colors.transparent
                          : null,
                      actions: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            backgroundImage: () {
                              // 【逻辑优先级修复】
                              // 1. 如果详情页 API 加载出了头像，用 API 的
                              if (_userProfile != null &&
                                  _userProfile!.uid.isNotEmpty) {
                                return NetworkImage(
                                  "${kBaseUrl}uc_server/avatar.php?uid=${_userProfile!.uid}&size=middle",
                                );
                              }
                              // 2. 如果 API 还没好，但搜索页传了头像地址进来，用搜索页的
                              if (widget.avatarUrl != null &&
                                  widget.avatarUrl!.isNotEmpty) {
                                return NetworkImage(widget.avatarUrl!);
                              }
                              // 3. 都没有，返回 null 显示下面的 Icon
                              return null;
                            }(),
                            child:
                                ((_userProfile == null) &&
                                    (widget.avatarUrl == null ||
                                        widget.avatarUrl!.isEmpty))
                                ? const Icon(Icons.person)
                                : null,
                          ),
                        ),
                      ],
                    ),

                    // 【新增】用户信息展示卡片
                    if (_userProfile != null)
                      SliverToBoxAdapter(
                        child: _buildUserProfileCard(context, wallpaperPath),
                      ),
                  ];
                },
                body: _buildThreadList(wallpaperPath),
              ),

              // 后台 WebView 兜底
              SizedBox(
                height: 0,
                width: 0,
                child: WebViewWidget(controller: _hiddenController),
              ),
            ],
          ),
        );
      },
    );
  }

  // 1. 在 _UserDetailPageState 类里添加这两个工具方法
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  Color? _extractColor(String html) {
    // 匹配 color="#009900" 或 color=#009900
    RegExp reg = RegExp(r'color="?#([0-9a-fA-F]{6})"?');
    var match = reg.firstMatch(html);
    if (match != null) {
      return Color(int.parse("0xFF${match.group(1)}"));
    }
    return null;
  }

  // 2. 替换你刚才提供的那个 _buildUserProfileCard 方法
  Widget _buildUserProfileCard(BuildContext context, String? wallpaperPath) {
    if (_userProfile == null) return const SizedBox();

    final theme = Theme.of(context);
    final cardColor = wallpaperPath != null
        ? theme.cardColor.withOpacity(0.8)
        : theme.cardColor;

    // 解析颜色和纯文字标题
    final String rawTitle = _userProfile!.groupTitle;
    final String cleanTitle = _stripHtml(rawTitle);
    final Color? groupColor = _extractColor(rawTitle);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 第一部分：使用 Wrap 防止溢出 ---
              Wrap(
                spacing: 8, // 水平间距
                runSpacing: 4, // 垂直间距（换行时）
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    label: Text(cleanTitle),
                    // 如果 HTML 里有颜色，就用那个颜色；否则用默认主题色
                    backgroundColor:
                        groupColor?.withOpacity(0.2) ??
                        theme.colorScheme.tertiaryContainer,
                    side: groupColor != null
                        ? BorderSide(color: groupColor)
                        : null,
                    avatar: Icon(
                      Icons.verified_user,
                      size: 16,
                      color:
                          groupColor ?? theme.colorScheme.onTertiaryContainer,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color:
                          groupColor ?? theme.colorScheme.onTertiaryContainer,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    "UID: ${_userProfile!.uid}",
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  // 注册日期通常较长，会自动换行到下一行
                  Text(
                    "注册: ${_userProfile!.regDate}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // --- 第二部分：积分数据 ---
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildStatItem("积分", _userProfile!.credits),
                    _buildStatItem("帖子", _userProfile!.postsCount),
                    _buildStatItem("主题", _userProfile!.threadsCount),
                    ..._userProfile!.extCredits.entries.map(
                      (e) => _buildStatItem(e.key, e.value),
                    ),
                  ],
                ),
              ),

              // --- 第三部分：个人简介 ---
              if (_userProfile!.bio.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  "简介",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                // 使用 SelectableText 防止文字太长且无法复制
                SelectableText(
                  _userProfile!.bio,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildThreadList(String? wallpaperPath) {
    if (_isFirstLoading)
      return const Center(child: CircularProgressIndicator());
    if (_threads.isEmpty)
      return Center(child: Text(_errorMsg.isNotEmpty ? _errorMsg : "这里空空如也"));

    return ListView.builder(
      // key: PageStorageKey('user_threads'), // 可选：保持滚动位置
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: _threads.length + 1,
      itemBuilder: (ctx, index) {
        if (index == _threads.length) return _buildFooter();
        final item = _threads[index];
        return _buildThreadTile(item, wallpaperPath);
      },
    );
  }

  Widget _buildFooter() {
    return _hasMore
        ? const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        : const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text("没有更多了")),
          );
  }

  Widget _buildThreadTile(UserThreadItem item, String? wallpaperPath) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: wallpaperPath != null
          ? Theme.of(context).cardColor.withOpacity(0.7)
          : Theme.of(context).cardColor,
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
