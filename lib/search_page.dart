import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
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

  // 标签相关数据
  List<Map<String, String>> _tagCloud = []; // [{id: 123, name: 巨大娘}]
  bool _isTagsLoaded = false;

  List<String> _history = [];

  bool _isLoading = false;
  bool _hasSearched = false;

  // 0=搜贴, 1=搜人, 2=标签
  int _searchType = 0;
  String? _nextPageUrl;

  @override
  void initState() {
    super.initState();
    _loadHistory();

    _textController.addListener(() {
      // 搜贴或搜人模式下，清空输入框回退到历史
      if (_textController.text.isEmpty && _hasSearched && _searchType != 2) {
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

  // ==========================================
  // 核心逻辑：加载标签云
  // ==========================================
  Future<void> _fetchTagCloud() async {
    if (_isTagsLoaded) return;
    setState(() => _isLoading = true);

    // 标签页 URL
    final url = '${currentBaseUrl.value}misc.php?mod=tag&mobile=2';

    try {
      String html = await HttpService().getHtml(url);

      // 使用正则从 JS 代码中提取 tagIds 和 tagStrings
      // 源码格式: tagIds[tagCount]=342; ... tagStrings[tagCount]='巨研社2';
      List<Map<String, String>> tags = [];

      RegExp idReg = RegExp(r"tagIds\[\w+\]=(\d+);");
      RegExp nameReg = RegExp(r"tagStrings\[\w+\]='(.*?)';");

      Iterable<Match> idMatches = idReg.allMatches(html);
      Iterable<Match> nameMatches = nameReg.allMatches(html);

      List<String> ids = idMatches.map((m) => m.group(1)!).toList();
      List<String> names = nameMatches.map((m) => m.group(1)!).toList();

      int count = ids.length < names.length ? ids.length : names.length;

      for (int i = 0; i < count; i++) {
        tags.add({'id': ids[i], 'name': names[i]});
      }

      if (mounted) {
        setState(() {
          _tagCloud = tags;
          _isTagsLoaded = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("标签加载失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // 核心逻辑：执行搜索 (含标签搜索)
  // ==========================================
  Future<void> _doSearch(String keyword, {String? tagId}) async {
    if (keyword.trim().isEmpty && tagId == null) return;

    FocusScope.of(context).unfocus();
    if (_searchType != 2) _saveHistory(keyword.trim());

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _threadResults.clear();
      _userResults.clear();
      _nextPageUrl = null;
    });

    String url;
    if (_searchType == 1) {
      // 搜人
      url =
          '${currentBaseUrl.value}home.php?mod=spacecp&ac=search&searchsubmit=yes&username=${Uri.encodeComponent(keyword)}';
    } else if (_searchType == 2 && tagId != null) {
      // 搜标签 (点击标签)
      url = '${currentBaseUrl.value}misc.php?mod=tag&id=$tagId&mobile=2';
    } else {
      // 搜帖子
      url =
          '${currentBaseUrl.value}search.php?mod=forum&searchsubmit=yes&srchtxt=${Uri.encodeComponent(keyword)}&mobile=no';
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

    // 检查是否有 Discuz 常见的错误提示
    if (html.contains("抱歉") && html.contains("秒") && !_isLoading) {
      // 简单的防抖提示
    }

    if (_searchType == 1) {
      _parseUsers(document);
    } else {
      // 帖子搜索 和 标签搜索 共用解析逻辑
      _parseThreads(document);
    }

    // 解析下一页
    var nextBtn = document.querySelector('.pg .nxt');
    String? nextUrl;
    if (nextBtn != null) {
      String href = nextBtn.attributes['href'] ?? "";
      nextUrl = href.startsWith("http") ? href : "${currentBaseUrl.value}$href";
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
    // 兼容两种模式：
    // 1. 电脑版搜索结果 (li.pbw)
    // 2. 标签/板块列表 (tbody > tr)

    var listItems = document.querySelectorAll('li.pbw');
    if (listItems.isNotEmpty) {
      for (var li in listItems) {
        var titleNode = li.querySelector('h3.xs3 a');
        if (titleNode == null) continue;
        String title = titleNode.text.trim();
        String href = titleNode.attributes['href'] ?? "";
        String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";

        String author = "未知";
        var authorLink = li.querySelector('p a[href*="uid="]');
        if (authorLink != null) author = authorLink.text.trim();

        if (tid.isNotEmpty && !_threadResults.any((r) => r.tid == tid)) {
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
    } else {
      // 尝试解析表格模式 (标签结果页通常是这种)
      var rows = document.querySelectorAll('tr');
      for (var row in rows) {
        var titleLink =
            row.querySelector('th a.xst') ?? row.querySelector('th a');
        if (titleLink == null) continue;
        // 排除非帖子链接
        if (!titleLink.attributes.containsKey('href') ||
            !titleLink.attributes['href']!.contains('tid='))
          continue;

        String title = titleLink.text.trim();
        String href = titleLink.attributes['href']!;
        String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";

        String author = row.querySelector('.by cite a')?.text.trim() ?? "未知";
        String replies = row.querySelector('.num a')?.text.trim() ?? "0";
        String views = row.querySelector('.num em')?.text.trim() ?? "0";

        if (tid.isNotEmpty && !_threadResults.any((r) => r.tid == tid)) {
          _threadResults.add(
            Thread(
              tid: tid,
              subject: title,
              author: author,
              replies: replies,
              views: views,
              readperm: "0",
            ),
          );
        }
      }
    }
    // 2. 【新增】尝试解析标签页结果 (.hotlist li)
    // 针对 misc.php?mod=tag 返回的结构
    var hotListItems = document.querySelectorAll('.hotlist li');
    if (hotListItems.isNotEmpty) {
      for (var li in hotListItems) {
        try {
          var titleNode = li.querySelector('.list_top a');
          if (titleNode == null) continue;

          String title = titleNode.text.trim();
          String href = titleNode.attributes['href'] ?? "";
          String tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1) ?? "";

          // 提取作者 (在 list_bottom 的 .z 类里)
          String author = "未知";
          var authorNode = li.querySelector('.list_bottom .z');
          if (authorNode != null) author = authorNode.text.trim();

          // 提取回复/查看 (在 list_bottom 的 .y 类里)
          String replies = "0";
          String views = "0";
          var statsNodes = li.querySelectorAll('.list_bottom .y');
          for (var stat in statsNodes) {
            String text = stat.text.trim();
            if (stat.innerHtml.contains('forum_posts.png')) {
              replies = text;
            } else if (stat.innerHtml.contains('chakan.png')) {
              views = text;
            }
          }

          if (tid.isNotEmpty && !_threadResults.any((r) => r.tid == tid)) {
            _threadResults.add(
              Thread(
                tid: tid,
                subject: title,
                author: author,
                replies: replies,
                views: views,
                readperm: "0",
              ),
            );
          }
        } catch (_) {}
      }
      return; // 匹配成功后返回
    }
  }

  void _parseUsers(var document) {
    var buddyItems = document.querySelectorAll('ul.buddy li');
    for (var li in buddyItems) {
      var userLink = li.querySelector('h4 a');
      if (userLink == null) continue;
      String username = userLink.text.trim();
      String href = userLink.attributes['href'] ?? "";
      String uid = RegExp(r'uid=(\d+)').firstMatch(href)?.group(1) ?? "";
      String info = li.querySelector('p.maxh')?.text.trim() ?? "";

      if (uid.isNotEmpty && !_userResults.any((u) => u['uid'] == uid)) {
        _userResults.add({'uid': uid, 'username': username, 'info': info});
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
            // 标签模式下隐藏输入框，显示标题
            title: _searchType == 2
                ? const Text("标签广场", style: TextStyle(fontSize: 18))
                : _buildSearchInput(),
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

              // 主要内容区域
              _buildMainContent(wallpaperPath),

              if (_isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainContent(String? wallpaperPath) {
    // 1. 标签模式
    if (_searchType == 2) {
      if (_hasSearched) {
        // 显示标签下的帖子
        return Column(
          children: [
            // 加一个返回按钮
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _hasSearched = false),
                  ),
                  const Text("返回标签列表"),
                ],
              ),
            ),
            Expanded(child: _buildThreadList(wallpaperPath)),
          ],
        );
      } else {
        // 显示标签云
        return _buildTagCloud();
      }
    }

    // 2. 搜帖/搜人模式
    return Column(
      children: [
        if (!_hasSearched) _buildHistoryView(),
        if (_hasSearched)
          Expanded(
            child: _searchType == 1
                ? _buildUserList(wallpaperPath)
                : _buildThreadList(wallpaperPath),
          ),
      ],
    );
  }

  Widget _buildMD3Toggle() {
    return SegmentedButton<int>(
      segments: const <ButtonSegment<int>>[
        ButtonSegment<int>(
          value: 0,
          label: Text('搜贴'),
          icon: Icon(Icons.article_outlined),
        ),
        ButtonSegment<int>(
          value: 1,
          label: Text('找人'),
          icon: Icon(Icons.person_search_outlined),
        ),
        ButtonSegment<int>(
          value: 2,
          label: Text('标签'),
          icon: Icon(Icons.label_outline),
        ),
      ],
      selected: <int>{_searchType},
      onSelectionChanged: (Set<int> newSelection) {
        int newValue = newSelection.first;
        setState(() {
          _searchType = newValue;
          _hasSearched = false; // 切换 Tab 重置结果
          _threadResults.clear();
          _userResults.clear();
        });

        // 如果切到标签页且没加载过，自动加载
        if (newValue == 2 && !_isTagsLoaded) {
          _fetchTagCloud();
        }
      },
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _buildSearchInput() {
    return SearchBar(
      controller: _textController,
      hintText: _searchType == 1 ? "输入用户名/UID..." : "输入关键词...",
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
        Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
    );
  }

  // 标签云视图
  Widget _buildTagCloud() {
    if (!_isTagsLoaded && !_isLoading) {
      return Center(
        child: ElevatedButton(
          onPressed: _fetchTagCloud,
          child: const Text("加载标签失败，点击重试"),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _tagCloud.map((tag) {
          return ActionChip(
            avatar: const Icon(Icons.tag, size: 16),
            label: Text(tag['name']!),
            onPressed: () => _doSearch("", tagId: tag['id']),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.7),
            side: BorderSide.none,
          );
        }).toList(),
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
      return const Center(child: Text("未找到内容"));
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
              "作者: ${item.author} ${item.replies != '0' ? '· ${item.replies}回' : ''}",
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

  Widget _buildUserList(String? wallpaperPath) {
    if (_userResults.isEmpty && !_isLoading)
      return const Center(child: Text("未找到用户"));
    return ListView.builder(
      controller: _scrollController,
      itemCount: _userResults.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _userResults.length) return _buildLoadIndicator();
        final user = _userResults[i];
        final String uid = user['uid']!;
        final String avatarUrl =
            "${currentBaseUrl.value}uc_server/avatar.php?uid=$uid&size=middle";

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: NetworkImage(avatarUrl),
          ),
          title: Text(
            user['username']!,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            "UID: $uid ${user['info'] != null ? '· ${user['info']}' : ''}",
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => UserDetailPage(
                  uid: uid,
                  username: user['username']!,
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
