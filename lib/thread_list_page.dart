import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/http_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import 'dart:io'; // 用于 File
import 'package:dio/dio.dart'; // 必须引用
import 'package:shared_preferences/shared_preferences.dart'; // 必须引用

import 'forum_model.dart';
import 'login_page.dart'; // 引用 kUserAgent
import 'thread_detail_page.dart';
import 'main.dart'; // 引用全局配置 useDioProxyLoader, customWallpaperPath 等

class ThreadListPage extends StatefulWidget {
  final String fid;
  final String forumName;

  const ThreadListPage({super.key, required this.fid, required this.forumName});

  @override
  State<ThreadListPage> createState() => _ThreadListPageState();
}

class _ThreadListPageState extends State<ThreadListPage> {
  late final WebViewController _hiddenController;
  final ScrollController _scrollController = ScrollController();
  int _currentTypeId = 0; // 0 表示全部
  Map<String, String> _threadTypes = {}; // 存储分类：{ "62": "短篇小说", "63": "长篇小说" }

  List<Thread> _threads = [];
  bool _isFirstLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _errorMsg = "";
  int _currentPage = 1;
  int _totalPages = 1; // 总页数

  @override
  void initState() {
    super.initState();
    _initWebView();
    _scrollController.addListener(_onScroll);

    // 初始加载第一页
    _loadPage(1);
  }

  // WebView 初始化：仅用于在后台同步 Cookie，不直接参与解析列表
  void _initWebView() {
    _hiddenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  // 修改 _loadPage 方法
  Future<void> _loadPage(int page) async {
    if (page > 1 && !_hasMore) return;

    // 构造 API 链接
    // 核心：增加 typeid 参数
    String apiUrl =
        '${kBaseUrl}api/mobile/index.php?version=4&module=forumdisplay&fid=${widget.fid}&page=$page';
    if (_currentTypeId != 0) {
      apiUrl += '&filter=typeid&typeid=$_currentTypeId';
    }

    print("📡 请求列表 API: $apiUrl");

    try {
      String responseBody = await HttpService().getHtml(apiUrl);
      if (responseBody.startsWith('"') && responseBody.endsWith('"')) {
        responseBody = jsonDecode(responseBody);
      }
      final data = jsonDecode(responseBody);

      // 【新增】解析分类元数据 (仅在第一页时解析一次)
      final vars = data['Variables'];
      if (vars != null && vars['threadtypes'] != null) {
        var types = vars['threadtypes']['types'];
        if (types is Map) {
          setState(() {
            _threadTypes = Map<String, String>.from(types);
          });
        }
      }

      _parseApiData(data, page);
    } catch (e) {
      // 错误处理...
    }
  }

  // 解析 API 返回的 JSON
  void _parseApiData(dynamic data, int page) {
    final vars = data['Variables'];
    if (vars == null) return;

    // 1. 解析帖子列表
    List<dynamic> rawList = vars['forum_threadlist'] ?? [];
    List<Thread> newThreads = rawList.map((e) => Thread.fromJson(e)).toList();

    // 2. 分页计算
    if (vars['forum'] != null) {
      int totalThreads = int.tryParse(vars['forum']['threads'].toString()) ?? 0;
      int tpp = int.tryParse(vars['tpp'].toString()) ?? 20;
      _totalPages = (totalThreads / tpp).ceil();
      _hasMore = page < _totalPages;
    }

    if (mounted) {
      setState(() {
        if (page == 1) {
          _threads = newThreads;
        } else {
          // 去重追加
          for (var t in newThreads) {
            if (!_threads.any((old) => old.tid == t.tid)) {
              _threads.add(t);
            }
          }
        }
        _currentPage = page;
        _isFirstLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    _loadPage(_currentPage + 1);
  }

  Future<void> _refresh() async {
    _hasMore = true;
    await _loadPage(1);
  }

  // ==========================================
  // 【新增】构建横向分类筛选栏
  // ==========================================
  Widget _buildFilterBar() {
    if (_threadTypes.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Container(
        height: 50,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _buildTypeChip("全部", 0),
            ..._threadTypes.entries.map((entry) {
              return _buildTypeChip(entry.value, int.parse(entry.key));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, int typeId) {
    bool isSelected = _currentTypeId == typeId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          if (isSelected) return;
          setState(() {
            _currentTypeId = typeId;
            _isFirstLoading = true; // 显示加载动画
            _threads.clear();
          });
          _loadPage(1); // 切换分类后重新加载第一页
        },
        // 样式美化
        labelStyle: TextStyle(
          fontSize: 13,
          color: isSelected ? Colors.white : null,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        selectedColor: Theme.of(context).primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Scaffold(
          backgroundColor: wallpaperPath != null ? Colors.transparent : null,
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
                      if (mode == ThemeMode.system)
                        isDark =
                            MediaQuery.of(context).platformBrightness ==
                            Brightness.dark;
                      return Container(
                        color: isDark
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.3),
                      );
                    },
                  ),
                ),

              NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverAppBar.large(
                      title: Text(widget.forumName),
                      backgroundColor:
                          (wallpaperPath != null &&
                              transparentBarsEnabled.value)
                          ? Colors.transparent
                          : null,
                      actions: [
                        Center(
                          child: Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: Text("${_threads.length} 帖"),
                          ),
                        ),
                      ],
                    ),
                    _buildFilterBar(),
                  ];
                },
                body: _buildList(),
              ),
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

  Widget _buildList() {
    if (_isFirstLoading)
      return const Center(child: CircularProgressIndicator());
    if (_errorMsg.isNotEmpty && _threads.isEmpty)
      return Center(
        child: Column(
          children: [
            Text(_errorMsg),
            ElevatedButton(onPressed: _refresh, child: const Text("重试")),
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        ),
      );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 30),
        itemCount: _threads.length + 1,
        itemBuilder: (context, index) {
          if (index == _threads.length) return _buildFooter();
          return _buildCard(_threads[index]);
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: _isLoadingMore
              ? const CircularProgressIndicator()
              : TextButton(
                  onPressed: _loadMore,
                  child: const Text("点击加载下一页", style: TextStyle(fontSize: 16)),
                ),
        ),
      );
    } else {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text("--- 到底啦 ---", style: TextStyle(color: Colors.grey)),
        ),
      );
    }
  }

  Widget _buildCard(Thread thread) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 0,
          color: wallpaperPath != null
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerLow.withOpacity(0.7)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          child: ListTile(
            title: Text(
              thread.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "${thread.author} • ${thread.replies} 回复",
              style: TextStyle(
                fontSize: 12,
                color: wallpaperPath != null
                    ? Theme.of(context).colorScheme.onSurface.withOpacity(0.6)
                    : Colors.grey,
              ),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ThreadDetailPage(tid: thread.tid, subject: thread.subject),
              ),
            ),
          ),
        );
      },
    );
  }
}
