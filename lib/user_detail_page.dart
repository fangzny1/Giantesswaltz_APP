import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'forum_model.dart';
import 'thread_detail_page.dart';
import 'login_page.dart';
import 'http_service.dart'; // 引入 HttpService
import 'main.dart'; // 引入全局变量

// 用户信息模型
class UserProfile {
  final String username;
  final String uid;
  final String groupTitle;
  final String credits;
  final Map<String, String> extCredits;
  final List<String> medalUrls;
  final String bio;
  final String sightml;
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
  late final WebViewController _hiddenController; // 仅用于维持 Cookie 活性
  final ScrollController _scrollController = ScrollController();

  List<UserThreadItem> _threads = [];
  UserProfile? _userProfile;

  bool _isFirstLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  String _errorMsg = "";
  int _currentPage = 1;

  // 获取当前的 API 基础地址
  String get _baseUrl => currentBaseUrl.value;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _scrollController.addListener(_onScroll);

    // 并发加载
    _loadData();
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
    // 这里不需要 loadRequest，只是占位，请求全部走 HttpService
  }

  Future<void> _loadData() async {
    setState(() {
      _isFirstLoading = true;
      _errorMsg = "";
    });

    // 同时请求用户信息和第一页帖子
    await Future.wait([_loadUserProfile(), _loadThreadPage(1)]);

    if (mounted) {
      setState(() => _isFirstLoading = false);
    }
  }

  Future<void> _loadUserProfile() async {
    String uidParam = widget.uid ?? "";
    if (uidParam.isEmpty) return;

    // 构造请求 URL
    String url =
        '${_baseUrl}api/mobile/index.php?version=4&module=profile&uid=$uidParam';
    print("🚀 [Profile] 正在加载: $url");

    try {
      // 1. 第一次尝试请求
      String responseBody = await HttpService().getHtml(url);

      // 1. 检查是否掉登录
      if (responseBody.contains("to_login")) {
        print("💨 [Profile] 检测到失效，调用全局强力续命...");

        // 【调用全局杀招】
        await HttpService().reviveSession();

        // 稍微等一下服务器数据库同步
        await Future.delayed(const Duration(milliseconds: 800));

        // 重新获取最新 Cookie 并重试
        final prefs = await SharedPreferences.getInstance();
        String freshCookie = prefs.getString('saved_cookie_string') ?? "";

        print("🔄 [Profile] 续命完成，带新 Cookie 重试...");
        responseBody = await HttpService().getHtml(
          url,
          headers: {'Cookie': freshCookie},
        );
      }

      // 3. 数据清洗 (处理可能的引号包裹)
      String cleaned = responseBody.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned
            .substring(1, cleaned.length - 1)
            .replaceAll('\\"', '"')
            .replaceAll('\\\\', '\\');
      }

      final data = jsonDecode(cleaned);

      // 4. 正常解析显示
      if (data['Variables'] != null && data['Variables']['space'] != null) {
        var space = data['Variables']['space'];
        var extCreditsMap = data['Variables']['extcredits'] ?? {};

        Map<String, String> credits = {};
        if (extCreditsMap is Map) {
          extCreditsMap.forEach((k, v) {
            credits[v['title'] ?? "积分$k"] =
                space['extcredits$k']?.toString() ?? "0";
          });
        }

        if (mounted) {
          setState(() {
            _userProfile = UserProfile(
              username: space['username'] ?? widget.username,
              uid: space['uid'].toString(),
              groupTitle: space['group']['grouptitle'] ?? "用户",
              credits: space['credits']?.toString() ?? "0",
              extCredits: credits,
              medalUrls: [],
              bio: space['bio'] ?? "",
              sightml: space['sightml'] ?? "",
              postsCount: space['posts']?.toString() ?? "0",
              threadsCount: space['threads']?.toString() ?? "0",
              friendsCount: space['friends']?.toString() ?? "0",
              regDate: space['regdate'] ?? "",
            );
          });
        }
      } else {
        // 如果两次都失败了，说明真的掉登录了
        print("🚨 [Profile] 自动续命失败，依然返回: $responseBody");
        if (mounted) setState(() => _errorMsg = "该线路登录态同步失败，请重试");
      }
    } catch (e) {
      print("❌ [Profile Error] 加载异常: $e");
      if (mounted) setState(() => _errorMsg = "网络连接异常");
    }
  }

  // 加载帖子列表 (HTML 解析)
  Future<void> _loadThreadPage(int page) async {
    if (!_hasMore && page > 1) return;

    if (page > 1 && mounted) setState(() => _isLoadingMore = true);

    // 必须有 UID 才能查
    if (widget.uid == null) {
      if (mounted) setState(() => _errorMsg = "无法获取用户ID");
      return;
    }

    String url =
        '${_baseUrl}home.php?mod=space&uid=${widget.uid}&do=thread&view=me&order=dateline&mobile=no&page=$page';

    try {
      String html = await HttpService().getHtml(url);
      _parseHtmlData(html, page);
    } catch (e) {
      print("❌ 帖子列表加载失败: $e");
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          if (page == 1) _errorMsg = "网络请求失败，请重试";
        });
      }
    }
  }

  void _parseHtmlData(String htmlString, int page) {
    try {
      var document = html_parser.parse(htmlString);
      List<UserThreadItem> newThreads = [];

      // 【核心修复】双重解析策略

      // 策略 A: 针对特定模板 (.c_threadlist ul li)
      var listItems = document.querySelectorAll('.c_threadlist ul li');
      if (listItems.isNotEmpty) {
        for (var li in listItems) {
          try {
            var titleNode =
                li.querySelector('.tit > a') ?? li.querySelector('.tit a');
            if (titleNode == null) continue;

            String subject = titleNode.text.trim();
            String href = titleNode.attributes['href'] ?? "";
            String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";
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

            // 尝试获取板块名
            String forumName = li.querySelector('.cat a')?.text.trim() ?? "帖子";

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
          } catch (_) {}
        }
      }
      // 策略 B: 针对 Discuz 标准表格布局 (.tl table tr / form table tr)
      else {
        // 查找所有包含 viewthread 链接的行
        var rows = document.querySelectorAll('tr');
        for (var row in rows) {
          var titleLink = row.querySelector('a[href*="viewthread"]');
          if (titleLink == null) continue;
          // 排除掉“最后发表”那一栏的链接，通常标题栏的链接 class 是 xst 或者在 th/td[class=icn] 后面
          // 简单判断：文本长度大于 0 且不是 "新窗口打开" 之类的
          String text = titleLink.text.trim();
          if (text.isEmpty || text == "新窗口打开") continue;

          String href = titleLink.attributes['href'] ?? "";
          String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";
          if (tid.isEmpty) continue;

          // 尝试获取板块
          String forumName =
              row.querySelector('a[href*="forumdisplay"]')?.text.trim() ?? "";

          // 尝试获取数据 (Discuz 表格通常 num 列是 回复/查看)
          String replies = "0";
          String views = "0";
          var numNode = row.querySelector('.num');
          if (numNode != null) {
            var a = numNode.querySelector('a');
            var em = numNode.querySelector('em');
            if (a != null) replies = a.text.trim();
            if (em != null) views = em.text.trim();
          }

          // 尝试获取时间 (by 列的 em 或 span)
          String dateline = "";
          var byNode = row.querySelector('.by');
          if (byNode != null) {
            dateline = byNode.querySelector('em')?.text.trim() ?? "";
            if (dateline.isEmpty)
              dateline = byNode.querySelector('span')?.text.trim() ?? "";
          }

          // 去重添加 (因为有时候一个 tr 里有多个 viewthread 链接)
          if (!newThreads.any((t) => t.tid == tid)) {
            newThreads.add(
              UserThreadItem(
                tid: tid,
                subject: text,
                forumName: forumName,
                dateline: dateline,
                views: views,
                replies: replies,
              ),
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          if (page == 1) {
            _threads = newThreads;
            _currentPage = 1;
            // 如果第一页就没数据，说明真没了
            if (newThreads.isEmpty) {
              _errorMsg = "该用户暂无帖子";
            }
          } else {
            // 追加
            for (var t in newThreads) {
              if (!_threads.any((old) => old.tid == t.tid)) {
                _threads.add(t);
              }
            }
            if (newThreads.isNotEmpty) _currentPage = page;
          }

          // 如果获取到的数量少于每页常见数量(比如10)，说明没更多了
          if (newThreads.length < 5) _hasMore = false;

          _isLoadingMore = false;
          _isFirstLoading = false;
        });
      }
    } catch (e) {
      print("HTML 解析错误: $e");
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    _loadThreadPage(_currentPage + 1);
  }

  // --- 工具方法 ---
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  Color? _extractColor(String html) {
    RegExp reg = RegExp(r'color="?#([0-9a-fA-F]{6})"?');
    var match = reg.firstMatch(html);
    if (match != null) {
      return Color(int.parse("0xFF${match.group(1)}"));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([customWallpaperPath, forumCardOpacity]),
      builder: (context, _) {
        final wallpaperPath = customWallpaperPath.value;
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
                            // 头像加载逻辑
                            backgroundImage: () {
                              if (_userProfile != null &&
                                  _userProfile!.uid.isNotEmpty) {
                                return NetworkImage(
                                  "${_baseUrl}uc_server/avatar.php?uid=${_userProfile!.uid}&size=middle",
                                );
                              }
                              if (widget.avatarUrl != null &&
                                  widget.avatarUrl!.isNotEmpty) {
                                return NetworkImage(widget.avatarUrl!);
                              }
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

                    if (_userProfile != null)
                      SliverToBoxAdapter(
                        child: _buildUserProfileCard(context, wallpaperPath),
                      ),
                  ];
                },
                body: _buildThreadList(wallpaperPath),
              ),

              // 隐藏的 WebView
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

  // 用户信息卡片
  Widget _buildUserProfileCard(BuildContext context, String? wallpaperPath) {
    if (_userProfile == null) return const SizedBox();

    final theme = Theme.of(context);
    final cardColor = wallpaperPath != null
        ? theme.cardColor.withOpacity(forumCardOpacity.value)
        : theme.cardColor;

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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    label: Text(cleanTitle),
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
                  Text(
                    "注册: ${_userProfile!.regDate}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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

    // 【核心修复】显示空状态或错误信息
    if (_threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 10),
            Text(
              _errorMsg.isNotEmpty ? _errorMsg : "这里空空如也",
              style: const TextStyle(color: Colors.grey),
            ),
            if (_errorMsg.isNotEmpty)
              TextButton(onPressed: _loadData, child: const Text("重试")),
          ],
        ),
      );
    }

    return ListView.builder(
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
            child: Center(
              child: Text("没有更多了", style: TextStyle(color: Colors.grey)),
            ),
          );
  }

  Widget _buildThreadTile(UserThreadItem item, String? wallpaperPath) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: wallpaperPath != null
          ? Theme.of(context).cardColor.withOpacity(forumCardOpacity.value)
          : Theme.of(context).cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => adaptivePush(
          context,
          ThreadDetailPage(tid: item.tid, subject: item.subject),
        ),
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
                  if (item.forumName.isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.forumName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  if (item.forumName.isNotEmpty) const SizedBox(width: 8),
                  Text(
                    item.dateline,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Spacer(),
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
                  const SizedBox(width: 10),
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
