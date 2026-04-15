import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'dart:convert';
import 'forum_model.dart';
import 'main.dart';

// 阅读器主题配置
class ReaderTheme {
  final String name;
  final Color background;
  final Color text;
  final Color surface;
  final Color primary;

  ReaderTheme({
    required this.name,
    required this.background,
    required this.text,
    required this.surface,
    required this.primary,
  });
}

class ReaderChapter {
  final String author;
  final String time;
  final String content;

  ReaderChapter({
    required this.author,
    required this.time,
    required this.content,
  });
}

class UltraReaderPage extends StatefulWidget {
  final String tid;
  final String title;
  final int initialIndex; // 【新增】支持从书签跳入指定楼层

  const UltraReaderPage({
    super.key,
    required this.tid,
    required this.title,
    this.initialIndex = 0,
  });

  @override
  State<UltraReaderPage> createState() => _UltraReaderPageState();
}

class _UltraReaderPageState extends State<UltraReaderPage>
    with SingleTickerProviderStateMixin {
  List<ReaderChapter> _chapters = [];
  bool _isLoading = true;
  String _errorMsg = "";

  double _fontSize = 18.0;
  int _currentThemeIndex = 1;
  bool _isBarsVisible = true;

  late int _currentIndex;
  int _dragChapter = 1;

  late AnimationController _hideController;
  final ScrollController _scrollController = ScrollController();

  final List<ReaderTheme> _themes = [
    ReaderTheme(
      name: "白昼",
      background: const Color(0xFFFFFFFF),
      text: const Color(0xFF2C2C2C),
      surface: const Color(0xFFF5F5F5),
      primary: Colors.blueAccent,
    ),
    ReaderTheme(
      name: "护眼",
      background: const Color(0xFFF4ECD8),
      text: const Color(0xFF3C2F2F),
      surface: const Color(0xFFEBE3CF),
      primary: Colors.brown,
    ),
    ReaderTheme(
      name: "深邃",
      background: const Color(0xFF141218),
      text: const Color(0xFFE6E1E5),
      surface: const Color(0xFF2C2C2C),
      primary: Colors.tealAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex; // 接入书签初始楼层
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _hideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    _loadUserPreferences();
    _fetchContent();
  }

  @override
  void dispose() {
    _hideController.dispose();
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fontSize = prefs.getDouble('reader_font_size') ?? 18.0;
        _currentThemeIndex = prefs.getInt('reader_theme_index') ?? 1;
      });
    }
  }

  Future<void> _saveUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader_font_size', _fontSize);
    await prefs.setInt('reader_theme_index', _currentThemeIndex);
  }

  Future<void> _fetchContent() async {
    final prefs = await SharedPreferences.getInstance();
    String cookie = prefs.getString('saved_cookie_string') ?? "";
    final String url =
        "${currentBaseUrl.value}forum.php?mod=viewthread&action=printable&tid=${widget.tid}";

    try {
      var response = await Dio().get(
        url,
        options: Options(
          headers: {
            'User-Agent':
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            'Cookie': cookie,
          },
        ),
      );
      _parseHtml(response.data.toString());
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _errorMsg = "加载失败: $e";
        });
    }
  }

  void _parseHtml(String html) {
    String cleanHtml = html.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?<\/script>'),
      '',
    );
    var body = html_parser.parse(cleanHtml).body;
    if (body == null) return;

    List<ReaderChapter> temp = [];
    List<String> blocks = body.innerHtml.split(RegExp(r'<hr[^>]*>'));

    for (int i = 0; i < blocks.length; i++) {
      String trimmedBlock = blocks[i].trim();
      if (trimmedBlock.isEmpty || trimmedBlock.contains("Powered by Discuz"))
        continue;

      if (i == 0 && !trimmedBlock.contains("作者:")) continue;

      String author =
          RegExp(
            r'作者:\s*<\/b>\s*([^&<]+)',
          ).firstMatch(trimmedBlock)?.group(1)?.trim() ??
          "匿名";
      String time =
          RegExp(
            r'时间:\s*<\/b>\s*([^<]+)',
          ).firstMatch(trimmedBlock)?.group(1)?.trim() ??
          "";

      String content = trimmedBlock;
      Match? timeMatch = RegExp(
        r'时间:\s*<\/b>.*?(<br\s*\/?>)',
      ).firstMatch(content);
      if (timeMatch != null) {
        content = content.substring(timeMatch.end).trim();
      }

      content = content
          .replaceFirst(RegExp(r'^<b>标题:\s*<\/b>.*?(<br\s*\/?>)'), '')
          .trim();
      content = content.replaceFirst(RegExp(r'^(<br\s*\/?>)+'), '').trim();

      temp.add(ReaderChapter(author: author, time: time, content: content));
    }

    if (mounted) {
      setState(() {
        _chapters = temp;
        // 如果传入的索引超出范围，重置为0
        if (_currentIndex >= temp.length) _currentIndex = 0;
        _isLoading = false;
      });
    }
  }

  // 【核心性能修复】：去掉 setState，纯通过 AnimationController 控制，杜绝 HtmlWidget 重绘！
  void _toggleBars() {
    _isBarsVisible = !_isBarsVisible;
    if (_isBarsVisible) {
      _hideController.forward();
    } else {
      _hideController.reverse();
    }
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;

    // 【核心修复】先重置滚动位置，再切换内容
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    setState(() {
      _currentIndex = index;
    });

    // 切换章节后强制刷新一下，确保 AnimatedBuilder 重新计算新楼层的高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  // 【新增】：保存超级模式专属书签
  Future<void> _saveUltraBookmark() async {
    if (_chapters.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('local_bookmarks');
    List<dynamic> jsonList = [];
    if (jsonStr != null) jsonList = jsonDecode(jsonStr);

    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: "${widget.title} [全量模式]",
      author: _chapters[_currentIndex].author,
      authorId: "", // Printable API 不方便抓 authorId，留空不影响
      page: 1,
      savedTime:
          "${DateTime.now().toString().substring(5, 16)} · 读至 第${_currentIndex + 1}楼",
      isNovelMode: false,
      // 使用特定前缀标识这是全量模式书签，并带上索引
      targetFloor: "ultra_$_currentIndex",
    );

    // 删除同一帖子的旧全量书签
    jsonList.removeWhere(
      (e) =>
          e['tid'] == widget.tid &&
          e['targetFloor']?.toString().startsWith('ultra_') == true,
    );
    jsonList.insert(0, newMark.toJson());
    await prefs.setString('local_bookmarks', jsonEncode(jsonList));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("✅ 已保存全量专属书签")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes[_currentThemeIndex];

    return Scaffold(
      backgroundColor: theme.background,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.reverse &&
              _isBarsVisible) {
            _toggleBars();
          } else if (notification.direction == ScrollDirection.forward &&
              !_isBarsVisible) {
            _toggleBars();
          }
          return false;
        },
        child: GestureDetector(
          onTap: _toggleBars,
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! < -300) {
              _goToChapter(_currentIndex + 1);
            } else if (details.primaryVelocity! > 300) {
              _goToChapter(_currentIndex - 1);
            }
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox.expand(
            child: Stack(
              children: [
                _buildContentArea(theme),
                _buildTopAppBar(theme),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomBar(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopAppBar(ReaderTheme theme) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(_hideController),
      child: Container(
        color: theme.surface.withOpacity(0.98),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: theme.text),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  Widget _buildContentArea(ReaderTheme theme) {
    if (_isLoading)
      return Center(child: CircularProgressIndicator(color: theme.primary));
    if (_errorMsg.isNotEmpty)
      return Center(
        child: Text(_errorMsg, style: TextStyle(color: theme.text)),
      );
    if (_chapters.isEmpty)
      return Center(
        child: Text("没有内容", style: TextStyle(color: theme.text)),
      );

    final ch = _chapters[_currentIndex];

    String finalHtml = ch.content;
    if (_currentThemeIndex == 2) {
      finalHtml = finalHtml
          .replaceAll('color:rgb(0, 0, 0)', 'color:#BBBBBB')
          .replaceAll('color: rgb(0, 0, 0)', 'color:#BBBBBB')
          .replaceAll('color:#000000', 'color:#BBBBBB')
          .replaceAll('color="#000000"', 'color="#BBBBBB"')
          .replaceAll('color="#000"', 'color="#BBBBBB"');
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 1. 标题区域
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            left: 16,
            right: 16,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "第 ${_currentIndex + 1} 楼 · ${ch.author}",
                      style: TextStyle(
                        color: theme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      ch.time,
                      style: TextStyle(
                        color: theme.text.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Divider(
                  color: theme.text.withOpacity(0.3),
                  thickness: 1,
                  height: 16,
                ),
              ],
            ),
          ),
        ),

        // 2. 【核心优化】：HtmlWidget 直接作为 Sliver 运行（开启懒加载）
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: HtmlWidget(
            finalHtml,
            renderMode: RenderMode.sliverList, // 开启懒加载，保证滑动不卡顿
            textStyle: TextStyle(
              fontSize: _fontSize,
              height: 1.8,
              color: theme.text,
              fontFamily: "Serif",
            ),
            customStylesBuilder: (element) {
              if (_currentThemeIndex == 2) {
                String style = element.attributes['style'] ?? '';
                if (style.contains('background')) {
                  return {
                    'background-color': 'transparent !important',
                    'color': '#BBBBBB !important',
                  };
                }
              }
              return null;
            },
          ),
        ),

        // 3. 底部填充区域
        SliverFillRemaining(
          hasScrollBody: false,
          child: Container(
            padding: const EdgeInsets.only(top: 40, bottom: 120),
            alignment: Alignment.bottomCenter,
            child: _currentIndex < _chapters.length - 1
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.arrow_downward),
                    label: const Text("进入下一楼"),
                    onPressed: () => _goToChapter(_currentIndex + 1),
                  )
                : Text(
                    "--- 完 ---",
                    style: TextStyle(color: theme.text.withOpacity(0.5)),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ReaderTheme theme) {
    int maxChapter = _chapters.isEmpty ? 1 : _chapters.length;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_hideController),
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: theme.surface.withOpacity(0.98),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 【修正后的进度条：在 _buildBottomBar 内部】
            AnimatedBuilder(
              animation: _scrollController,
              builder: (context, child) {
                double currentOffset = 0.0;
                double maxScroll = 0.01;

                if (_scrollController.hasClients &&
                    _scrollController.position.hasContentDimensions) {
                  currentOffset = _scrollController.offset;
                  maxScroll = _scrollController.position.maxScrollExtent;
                }

                // 计算当前的百分比
                int progressPercent = (currentOffset / maxScroll * 100)
                    .clamp(0, 100)
                    .toInt();

                bool _isScrubbingScroll;
                return Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.chevron_left,
                        color: _currentIndex > 0
                            ? theme.primary
                            : theme.text.withOpacity(0.2),
                      ),
                      onPressed: _currentIndex > 0
                          ? () => _goToChapter(_currentIndex - 1)
                          : null,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: theme.primary,
                          inactiveTrackColor: theme.text.withOpacity(0.2),
                          thumbColor: theme.primary,
                        ),
                        child: Slider(
                          // 【核心修复1】：如果正在拖动，我们使用拖动的值，不接受 scrollController 的反馈
                          value: currentOffset.clamp(0.0, maxScroll),
                          min: 0.0,
                          max: maxScroll,
                          // 【核心修复2】：onChangeStart 时标记正在拖拽
                          onChangeStart: (v) => _isScrubbingScroll = true,
                          onChanged: (v) {
                            // 【核心修复3】：绝对不要在这里写 setState() ！！！
                            // 直接操作 position 改变位置，AnimatedBuilder 会局部刷新滑块，
                            // 这样正文内容完全不会重绘，效率提升 100 倍。
                            _scrollController.position.jumpTo(v);
                          },
                          // 【核心修复4】：松手时释放保护
                          onChangeEnd: (v) => _isScrubbingScroll = false,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: _currentIndex < maxChapter - 1
                            ? theme.primary
                            : theme.text.withOpacity(0.2),
                      ),
                      onPressed: _currentIndex < maxChapter - 1
                          ? () => _goToChapter(_currentIndex + 1)
                          : null,
                    ),
                    Text(
                      "$progressPercent%",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.text,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                );
              },
            ),

            // 下方功能按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 在目录按钮上显示总进度，方便用户随时知道自己在第几楼
                _buildBottomBtn(
                  Icons.menu_book,
                  "目录 (${_currentIndex + 1}/$maxChapter)",
                  theme,
                  () => _showTOCSheet(theme),
                ),
                _buildBottomBtn(
                  Icons.bookmark_add,
                  "书签",
                  theme,
                  _saveUltraBookmark,
                ),
                _buildBottomBtn(
                  Icons.settings,
                  "设置",
                  theme,
                  () => _showSettingsSheet(theme),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBtn(
    IconData icon,
    String label,
    ReaderTheme theme,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: theme.text.withOpacity(0.8), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: theme.text.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTOCSheet(ReaderTheme theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "文章目录 (${_chapters.length} 楼)",
                style: TextStyle(
                  color: theme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(height: 1, color: theme.text.withOpacity(0.1)),
            Expanded(
              child: ListView.builder(
                itemCount: _chapters.length,
                itemBuilder: (context, i) => ListTile(
                  leading: Text(
                    "${i + 1}",
                    style: TextStyle(
                      color: _currentIndex == i
                          ? theme.primary
                          : theme.text.withOpacity(0.5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  title: Text(
                    _chapters[i].author,
                    style: TextStyle(
                      color: _currentIndex == i ? theme.primary : theme.text,
                    ),
                  ),
                  subtitle: Text(
                    _chapters[i].time,
                    style: TextStyle(
                      color: theme.text.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _goToChapter(i);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet(ReaderTheme theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "排版与外观",
                style: TextStyle(
                  color: theme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.text_fields, color: theme.text.withOpacity(0.7)),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 14,
                      max: 30,
                      divisions: 8,
                      activeColor: theme.primary,
                      inactiveColor: theme.text.withOpacity(0.2),
                      onChanged: (v) {
                        setModalState(() => _fontSize = v);
                        setState(() => _fontSize = v);
                      },
                      onChangeEnd: (_) => _saveUserPreferences(),
                    ),
                  ),
                  Text(
                    "${_fontSize.toInt()}",
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_themes.length, (index) {
                  bool isSelected = _currentThemeIndex == index;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _currentThemeIndex = index);
                      _saveUserPreferences();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _themes[index].background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? _themes[index].primary
                              : _themes[index].text.withOpacity(0.2),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        _themes[index].name,
                        style: TextStyle(
                          color: _themes[index].text,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
