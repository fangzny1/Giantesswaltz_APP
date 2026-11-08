import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'dart:convert';
import 'forum_model.dart';
import 'global_cache_widget_factory.dart';
import 'printable_parser.dart';

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

class UltraReaderPage extends StatefulWidget {
  final String tid;
  final String title;
  final int initialIndex;
  final double initialScrollOffset; // 支持从书签恢复阅读进度

  const UltraReaderPage({
    super.key,
    required this.tid,
    required this.title,
    this.initialIndex = 0,
    this.initialScrollOffset = 0.0,
  });

  @override
  State<UltraReaderPage> createState() => _UltraReaderPageState();
}

class _UltraReaderPageState extends State<UltraReaderPage>
    with SingleTickerProviderStateMixin {
  List<ReaderChapter> _chapters = [];
  bool _isLoading = true;
  String _errorMsg = "";
  bool _truncated = false; // 打印页被截断：超出单页上限且无法继续加载
  bool _isFetchingMore = false; // 正在加载后续打印页

  double _fontSize = 18.0;
  int _currentThemeIndex = 1;
  bool _isBarsVisible = true;

  // 【新增】：阅读设置开关
  bool _enableSwipePaging = true; // 默认开启左右滑动翻页
  bool _syncTocWithCurrentFloor = true; // 默认开启目录自动跟随

  late int _currentIndex;
  int _dragChapter = 1;
  double? _draggingValue; // 记录拖动中的临时值
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

  double _initialScrollOffset = 0.0;

  // 【性能】章节渲染结果缓存（只保留最近 3 个变体，避免长帖内存膨胀）
  final Map<String, String> _renderedHtmlCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initialScrollOffset = widget.initialScrollOffset;
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
        // 【新增】：读取设置
        _enableSwipePaging = prefs.getBool('reader_enable_swipe') ?? true;
        _syncTocWithCurrentFloor = prefs.getBool('reader_sync_toc') ?? true;
      });
    }
  }

  Future<void> _saveUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader_font_size', _fontSize);
    await prefs.setInt('reader_theme_index', _currentThemeIndex);
    // 【新增】：保存设置
    await prefs.setBool('reader_enable_swipe', _enableSwipePaging);
    await prefs.setBool('reader_sync_toc', _syncTocWithCurrentFloor);
  }

  Future<void> _fetchContent() async {
    final prefs = await SharedPreferences.getInstance();
    String cookie = prefs.getString('saved_cookie_string') ?? "";

    final List<ReaderChapter> loaded = [];
    final Set<String> seenSignatures = {};
    bool truncated = false;
    bool maybeMore = false;
    int page = 1;

    try {
      // 【核心】打印页单页最多 kPrintableFloorLimit 楼，按 page 参数续载，
      // 服务器忽略 page 参数时依靠签名去重安全停下，并给出截断提示。
      while (page <= kMaxPrintablePages) {
        final String url =
            "${currentBaseUrl.value}forum.php?mod=viewthread&action=printable&tid=${widget.tid}&page=$page";

        if (mounted && page > 1) setState(() => _isFetchingMore = true);

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

        // 【性能优化】HTML 解析放到后台 isolate，超长帖不再卡住 UI 主线程
        final result =
            await compute(parsePrintableHtml, response.data.toString());
        final fresh = result.chapters
            .where((c) => seenSignatures.add(c.signature))
            .toList();

        if (fresh.isEmpty) {
          // 没有新楼层：到底了，或服务器重复返回同一页。
          // 只有上一页刚好打满单页上限时，才认为后面还有内容被截断。
          truncated = maybeMore;
          break;
        }

        loaded.addAll(fresh);
        maybeMore = result.chapters.length == kPrintableFloorLimit;

        // 边加载边显示：第一页解析完即可开始阅读
        if (mounted) {
          setState(() {
            _chapters = List.of(loaded);
            _isLoading = false;
            _isFetchingMore = result.hitPageLimit;
            if (_currentIndex >= _chapters.length) {
              _currentIndex = _chapters.isEmpty ? 0 : _chapters.length - 1;
            }
          });
        }

        // 未打满单页 → 已到底；一次给了超过单页的量 → 服务器未截断，也到底
        if (!result.hitPageLimit ||
            result.chapters.length > kPrintableFloorLimit) {
          break;
        }
        page++;
      }

      if (page > kMaxPrintablePages) truncated = maybeMore;
    } catch (e) {
      if (loaded.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMsg = "加载失败: $e";
          });
        }
        return;
      }
      // 已有内容时出错：保留已加载楼层，并明确提示可能被截断
      truncated = true;
    }

    if (!mounted) return;

    setState(() {
      _chapters = List.of(loaded);
      _isLoading = false;
      _isFetchingMore = false;
      _truncated = truncated;
      // 恢复书签指定的楼层（此时列表才完整）
      if (widget.initialIndex >= 0 && widget.initialIndex < _chapters.length) {
        _currentIndex = widget.initialIndex;
      } else if (_currentIndex >= _chapters.length) {
        _currentIndex = _chapters.isEmpty ? 0 : _chapters.length - 1;
      }
    });

    if (_chapters.isEmpty) {
      setState(() {
        _errorMsg = "没有解析到内容：可能需要登录，或该帖没有可打印的内容";
      });
      return;
    }

    if (truncated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "⚠️ 论坛打印页最多提供前 ${_chapters.length} 楼（论坛接口限制），后续楼层可点底部按钮回普通阅读继续",
          ),
        ),
      );
    }

    // 恢复书签保存的阅读进度
    if (_initialScrollOffset > 0) {
      _retryRestoreScroll(retries: 0);
    }
  }

  /// 递归等待 HtmlWidget 懒加载完成后恢复滚动位置
  void _retryRestoreScroll({int retries = 0, double lastExtent = 0}) {
    const int maxRetries = 100;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final currentExtent = _scrollController.position.maxScrollExtent;
        // 等待 maxScrollExtent 稳定（连续两帧相同）且 > 0 才跳转
        if (currentExtent > 0 && currentExtent == lastExtent) {
          double target = _initialScrollOffset.clamp(0.0, currentExtent);
          _scrollController.jumpTo(target);
          if (mounted) setState(() {});
          return;
        }
      }
      if (retries < maxRetries) {
        _retryRestoreScroll(retries: retries + 1, lastExtent: _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent
            : 0);
      }
    });
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

  // 【新增】：保存超级模式专属书签（含阅读进度）
  Future<void> _saveUltraBookmark() async {
    if (_chapters.isEmpty) return;

    // 获取当前滚动位置
    double currentOffset = 0.0;
    int progressPercent = 0;
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      currentOffset = _scrollController.offset;
      double maxScroll = _scrollController.position.maxScrollExtent;
      progressPercent = (maxScroll > 0)
          ? (currentOffset / maxScroll * 100).clamp(0, 100).toInt()
          : 100;
    }

    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('local_bookmarks');
    List<dynamic> jsonList = [];
    if (jsonStr != null) jsonList = jsonDecode(jsonStr);

    final newMark = BookmarkItem(
      tid: widget.tid,
      subject: "${widget.title} [全量模式]",
      author: _chapters[_currentIndex].author,
      authorId: "",
      page: 1,
      savedTime:
          "${DateTime.now().toString().substring(5, 16)} · 第${_currentIndex + 1}楼 · $progressPercent%",
      isNovelMode: false,
      targetFloor: "ultra_${_currentIndex}_${currentOffset.toStringAsFixed(1)}",
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ 已保存书签 · 第${_currentIndex + 1}楼 · $progressPercent%"),
        ),
      );
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
          // 【核心修改】：通过 _enableSwipePaging 开关控制是否启用横向手势
          onHorizontalDragEnd: _enableSwipePaging
              ? (details) {
                  if (details.primaryVelocity! < -300) {
                    _goToChapter(_currentIndex + 1);
                  } else if (details.primaryVelocity! > 300) {
                    _goToChapter(_currentIndex - 1);
                  }
                }
              : null, // 设为 null 即彻底禁用滑动事件
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

  /// 超出打印页上限时的常驻提示条：明确告诉用户内容被截断、去哪看完整版
  /// 生成最终渲染 HTML：主题色修正 + 全局字号样式（正则清洗已在解析阶段完成）
  String _renderChapterHtml(ReaderChapter ch) {
    String html = ch.content;
    if (_currentThemeIndex == 2) {
      html = html
          .replaceAll('color:rgb(0, 0, 0)', 'color:#BBBBBB')
          .replaceAll('color: rgb(0, 0, 0)', 'color:#BBBBBB')
          .replaceAll('color:#000000', 'color:#BBBBBB')
          .replaceAll('color="#000000"', 'color="#BBBBBB"')
          .replaceAll('color="#000"', 'color="#BBBBBB"');
    }
    return '<style>*{font-size:${_fontSize}px!important;line-height:1.8!important}</style>$html';
  }

  Widget _buildTruncationBanner(ReaderTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primary.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "论坛打印页最多提供前 $kPrintableFloorLimit 楼内容（论坛接口的限制），本帖后续楼层没有包含。点「继续」可回普通阅读从第 ${_chapters.length + 1} 楼无缝接上。",
              style: TextStyle(color: theme.text, fontSize: 13, height: 1.5),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _chapters.length + 1),
            child: Text("继续", style: TextStyle(color: theme.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("返回", style: TextStyle(color: theme.primary)),
          ),
        ],
      ),
    );
  }

  /// 续载后续打印页时的轻量进度提示
  Widget _buildFetchingMore(ReaderTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "正在加载后续楼层…（已加载 ${_chapters.length} 楼）",
            style: TextStyle(color: theme.text.withOpacity(0.6), fontSize: 12),
          ),
        ],
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

    // 【性能】渲染结果按 (章节,主题,字号) 缓存；表格/字体清洗已在解析阶段完成
    final cacheKey = '$_currentIndex|$_currentThemeIndex|$_fontSize';
    final String finalHtml = _renderedHtmlCache.putIfAbsent(cacheKey, () {
      if (_renderedHtmlCache.length >= 3) _renderedHtmlCache.clear();
      return _renderChapterHtml(ch);
    });

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
                if (_truncated) _buildTruncationBanner(theme),
                if (_isFetchingMore) _buildFetchingMore(theme),
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
            factoryBuilder: GlobalCacheWidgetFactory.new,
            finalHtml,
            renderMode: RenderMode.sliverList, // 开启懒加载，保证滑动不卡顿
            textStyle: TextStyle(
              fontSize: _fontSize,
              height: 1.8,
              color: theme.text,
              fontFamily: "Serif",
            ),
            customStylesBuilder: (element) {
              // 始终覆盖字体大小，无视 HTML 内 CSS
              final styles = <String, String>{
                'font-size': '${_fontSize}px',
              };
              if (_currentThemeIndex == 2) {
                final style = element.attributes['style'] ?? '';
                if (style.contains('background')) {
                  styles['background-color'] = 'transparent !important';
                  styles['color'] = '#BBBBBB !important';
                }
              }
              return styles;
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
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _truncated
                            ? "⚠️ 论坛打印页只提供到第 ${_chapters.length} 楼（论坛接口限制）"
                            : "--- 完 ---",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.text.withOpacity(0.5)),
                      ),
                      if (_truncated) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.menu_book),
                          label: Text(
                            "去普通阅读继续（第 ${_chapters.length + 1} 楼）",
                          ),
                          onPressed: () =>
                              Navigator.pop(context, _chapters.length + 1),
                        ),
                      ],
                    ],
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
                double maxScroll = 1.0;

                if (_scrollController.hasClients &&
                    _scrollController.position.hasContentDimensions) {
                  currentOffset = _scrollController.offset;
                  maxScroll = _scrollController.position.maxScrollExtent;
                }

                // 计算显示百分比：如果正在拖动，用拖动值算；否则用实际偏移算
                double displayValue = _draggingValue ?? currentOffset;
                int progressPercent = (maxScroll > 0)
                    ? (displayValue / maxScroll * 100).clamp(0, 100).toInt()
                    : 100;

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
                          trackHeight: 3.0,
                        ),
                        child: Slider(
                          // 如果正在拖动，滑块位置跟着手指走（_draggingValue）
                          // 否则滑块位置跟着页面走（currentOffset）
                          value: displayValue.clamp(0.0, maxScroll),
                          min: 0.0,
                          max: maxScroll,
                          onChanged: (v) {
                            // 【关键】只更新滑块和文字，不让页面滚动！
                            setState(() {
                              _draggingValue = v;
                            });
                          },
                          onChangeEnd: (v) {
                            // 【关键】松开手后，执行一次性跳转
                            _scrollController.jumpTo(v);
                            setState(() {
                              _draggingValue =
                                  null; // 清空临时值，交还给 ScrollController 控制
                            });
                          },
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
                    // 这里显示的百分比会随着手指滑动实时变化
                    Text(
                      "$progressPercent%",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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
    // 【核心修改】：如果开启了目录跟随，预估偏移量让当前楼层出现在屏幕中间
    // ListTile 带副标题的高度大约是 72 像素
    double initialOffset = 0.0;
    if (_syncTocWithCurrentFloor && _chapters.isNotEmpty) {
      initialOffset =
          (_currentIndex * 72.0) - (MediaQuery.of(context).size.height * 0.2);
      if (initialOffset < 0) initialOffset = 0.0;
    }
    final ScrollController tocController = ScrollController(
      initialScrollOffset: initialOffset,
    );

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
                controller: tocController, // 【新增】：绑定刚才带偏移量的控制器
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
                    _goToChapter(i); // 注意：全量模式是调 _goToChapter
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
              Divider(color: theme.text.withOpacity(0.1)),

              // 【新增】：滑动翻页开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: theme.primary,
                title: Text(
                  "左右滑动翻页",
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: _enableSwipePaging,
                onChanged: (val) {
                  setModalState(() => _enableSwipePaging = val); // 更新弹窗状态
                  setState(() => _enableSwipePaging = val); // 更新底层页面状态
                  _saveUserPreferences(); // 保存到本地
                },
              ),

              // 【新增】：目录跟随开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: theme.primary,
                title: Text(
                  "目录自动定位到当前楼层",
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: _syncTocWithCurrentFloor,
                onChanged: (val) {
                  setModalState(() => _syncTocWithCurrentFloor = val);
                  setState(() => _syncTocWithCurrentFloor = val);
                  _saveUserPreferences();
                },
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}
