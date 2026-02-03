import 'dart:io';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 必须有这个，速度才快

import 'forum_model.dart';
import 'thread_detail_page.dart';
import 'user_detail_page.dart';
import 'http_service.dart';
import 'main.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Thread> _threadResults = [];
  List<Map<String, String>> _userResults = [];
  List<String> _history = [];

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _isSearchUser = false; // false=搜贴, true=搜人
  String? _nextPageUrl;

  @override
  void initState() {
    super.initState();
    _loadHistory();

    _textController.addListener(() {
      if (_textController.text.isEmpty && _hasSearched) {
        setState(() {
          _hasSearched = false;
          _threadResults.clear();
          _userResults.clear();
        });
      }
    });

    _scrollController.addListener(() {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = prefs.getStringList('search_history') ?? []);
  }

  Future<void> _saveHistory(String keyword) async {
    if (keyword.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _history.remove(keyword);
    _history.insert(0, keyword);
    if (_history.length > 15) _history = _history.sublist(0, 15);
    await prefs.setStringList('search_history', _history);
    setState(() {});
  }

  Future<void> _doSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    _saveHistory(keyword.trim());

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _threadResults.clear();
      _userResults.clear();
      _nextPageUrl = null;
    });

    String url;
    if (_isSearchUser) {
      // 用户搜索接口
      url =
          '${kBaseUrl}home.php?mod=spacecp&ac=search&searchsubmit=yes&username=${Uri.encodeComponent(keyword)}';
    } else {
      // 帖子搜索接口
      url =
          '${kBaseUrl}search.php?mod=forum&searchsubmit=yes&srchtxt=${Uri.encodeComponent(keyword)}&mobile=no';
    }

    try {
      String html = await HttpService().getHtml(url);
      _parseHtmlContent(html);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _nextPageUrl == null) return;
    setState(() => _isLoading = true);
    try {
      String html = await HttpService().getHtml(_nextPageUrl!);
      _parseHtmlContent(html);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _parseHtmlContent(String html) {
    var document = html_parser.parse(html);

    if (_isSearchUser) {
      _parseUsers(document);
    } else {
      _parseThreads(document);
    }

    var nextBtn = document.querySelector('.pg .nxt');
    String? nextUrl;
    if (nextBtn != null) {
      String href = nextBtn.attributes['href'] ?? "";
      nextUrl = href.startsWith("http") ? href : "$kBaseUrl$href";
      if (!nextUrl.contains("mobile=no")) nextUrl += "&mobile=no";
    }

    if (mounted) {
      setState(() {
        _nextPageUrl = nextUrl;
        _isLoading = false;
      });
    }
  }

  void _parseThreads(var document) {
    var listItems = document.querySelectorAll('li.pbw');
    for (var li in listItems) {
      var titleNode = li.querySelector('h3.xs3 a');
      if (titleNode == null) continue;
      String title = titleNode.text.trim();
      String href = titleNode.attributes['href'] ?? "";
      String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";

      String author = "未知";
      var authorLink = li.querySelector('p a[href*="uid="]');
      if (authorLink != null) author = authorLink.text.trim();

      if (tid.isNotEmpty) {
        if (!_threadResults.any((r) => r.tid == tid)) {
          _threadResults.add(
            Thread(
              tid: tid,
              subject: title,
              author: author,
              replies: "0",
              views: "0",
              readperm: "0",
            ),
          );
        }
      }
    }
  }

  // === 核心修复：解析查找好友界面的用户列表 ===
  void _parseUsers(var document) {
    // 查找好友页面的结构通常在 ul.buddy li 里面
    var buddyItems = document.querySelectorAll('ul.buddy li');

    for (var li in buddyItems) {
      // 1. 抓取用户名和 UID
      var userLink = li.querySelector('h4 a');
      if (userLink == null) continue;

      String username = userLink.text.trim();
      String href = userLink.attributes['href'] ?? "";
      String uid = RegExp(r'uid=(\d+)').firstMatch(href)?.group(1) ?? "";

      // 2. 抓取积分/等级作为描述 (可选)
      String info = li.querySelector('p.maxh')?.text.trim() ?? "";

      if (uid.isNotEmpty) {
        if (!_userResults.any((u) => u['uid'] == uid)) {
          _userResults.add({'uid': uid, 'username': username, 'info': info});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Scaffold(
          backgroundColor: wallpaperPath != null ? Colors.transparent : null,
          appBar: AppBar(
            backgroundColor: wallpaperPath != null ? Colors.transparent : null,
            title: _buildSearchInput(),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildMD3Toggle(),
              ),
            ),
          ),
          body: Stack(
            children: [
              if (wallpaperPath != null) ...[
                Positioned.fill(
                  child: Image.file(File(wallpaperPath), fit: BoxFit.cover),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.5)),
                ),
              ],
              Column(
                children: [
                  if (!_hasSearched) _buildHistoryView(),
                  if (_hasSearched)
                    Expanded(
                      child: _isSearchUser
                          ? _buildUserList(wallpaperPath)
                          : _buildThreadList(wallpaperPath),
                    ),
                ],
              ),
              if (_isLoading &&
                  (_threadResults.isEmpty && _userResults.isEmpty))
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMD3Toggle() {
    return SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(
          value: false,
          label: Text('搜帖子'),
          icon: Icon(Icons.article_outlined),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('找用户'),
          icon: Icon(Icons.person_search_outlined),
        ),
      ],
      selected: <bool>{_isSearchUser},
      onSelectionChanged: (Set<bool> newSelection) {
        setState(() {
          _isSearchUser = newSelection.first;
          _hasSearched = false;
        });
      },
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _buildSearchInput() {
    return SearchBar(
      controller: _textController,
      hintText: _isSearchUser ? "输入用户名或UID..." : "输入关键词...",
      onSubmitted: (v) => _doSearch(v),
      leading: const Icon(Icons.search),
      trailing: [
        if (_textController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _textController.clear(),
          ),
      ],
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      ),
    );
  }

  Widget _buildHistoryView() {
    return Expanded(
      child: _history.isEmpty
          ? const Center(
              child: Text("尝试搜索感兴趣的内容", style: TextStyle(color: Colors.grey)),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "最近搜索",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('search_history');
                        setState(() => _history = []);
                      },
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: _history
                      .map(
                        (h) => ActionChip(
                          label: Text(h, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            _textController.text = h;
                            _doSearch(h);
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
    );
  }

  Widget _buildThreadList(String? wallpaperPath) {
    if (_threadResults.isEmpty && !_isLoading)
      return const Center(child: Text("未找到相关帖子"));
    return ListView.builder(
      controller: _scrollController,
      itemCount: _threadResults.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _threadResults.length) return _buildLoadIndicator();
        final item = _threadResults[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: wallpaperPath != null ? Colors.white.withOpacity(0.1) : null,
          elevation: 0,
          child: ListTile(
            title: Text(
              item.subject,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              "作者: ${item.author}",
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) =>
                    ThreadDetailPage(tid: item.tid, subject: item.subject),
              ),
            ),
          ),
        );
      },
    );
  }

  // === 优化：用户结果列表 (使用 CachedNetworkImage) ===
  Widget _buildUserList(String? wallpaperPath) {
    if (_userResults.isEmpty && !_isLoading)
      return const Center(child: Text("未找到匹配用户"));
    return ListView.builder(
      controller: _scrollController,
      itemCount: _userResults.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _userResults.length) return _buildLoadIndicator();
        final user = _userResults[i];
        final String uid = user['uid']!;
        final String username = user['username']!;
        final String info = user['info'] ?? "";

        // 构造高清头像地址
        final String avatarUrl =
            "${kBaseUrl}uc_server/avatar.php?uid=$uid&size=middle";

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: CachedNetworkImageProvider(avatarUrl), // 极速加载缓存头像
          ),
          title: Text(
            username,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            "UID: $uid ${info.isNotEmpty ? '· $info' : ''}",
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            // 点击直接跳转，详情页会秒开，因为我们已经给了关键信息
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => UserDetailPage(
                  uid: uid,
                  username: username,
                  avatarUrl: avatarUrl,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadIndicator() {
    return _nextPageUrl != null
        ? const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        : const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: Text(
                "到底啦",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          );
  }
}
