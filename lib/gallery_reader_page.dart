import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:gal/gal.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'forum_model.dart';
import 'login_page.dart';
import 'main.dart';

class GalleryImageItem {
  final String url;
  final String author;
  final String time;
  final String floorIndex;

  GalleryImageItem({
    required this.url,
    required this.author,
    required this.time,
    required this.floorIndex,
  });
}

class GalleryReaderPage extends StatefulWidget {
  final String tid;
  final String title;

  const GalleryReaderPage({super.key, required this.tid, required this.title});

  @override
  State<GalleryReaderPage> createState() => _GalleryReaderPageState();
}

class _GalleryReaderPageState extends State<GalleryReaderPage>
    with SingleTickerProviderStateMixin {
  final List<GalleryImageItem> _images = [];
  bool _isLoading = true;
  String _errorMsg = "";
  int _currentIndex = 0;
  bool _isSaving = false;

  int _scanPage = 1;
  int _totalPages = 1;
  bool _isScanning = false;
  bool _isBarsVisible = true;
  String _userCookies = "";

  late PageController _pageController;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pageController = PageController();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );

    _startImageSpider();
  }

  @override
  void dispose() {
    _isScanning = false;
    _pageController.dispose();
    _fadeController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // 获取 Header 逻辑，完全同步 thread_detail_page.dart
  Map<String, String> _getHeadersForUrl(String url) {
    String currentHost = Uri.parse(currentBaseUrl.value).host;
    if (url.contains('gtswaltz.org')) {
      return {
        'Cookie': _userCookies,
        'User-Agent': kUserAgent,
        'Referer': "https://gtswaltz.org/",
        'Connection': 'keep-alive',
      };
    }
    bool isInternal =
        url.contains(currentHost) || url.contains('giantesswaltz.org');
    if (isInternal) {
      return {
        'Cookie': _userCookies,
        'User-Agent': kUserAgent,
        'Referer': currentBaseUrl.value,
      };
    }
    return {'User-Agent': kUserAgent};
  }

  Future<void> _startImageSpider() async {
    final prefs = await SharedPreferences.getInstance();
    _userCookies = prefs.getString('saved_cookie_string') ?? "";

    var dio = Dio(
      BaseOptions(
        headers: {'User-Agent': kUserAgent, 'Cookie': _userCookies},
        connectTimeout: const Duration(seconds: 15),
        // 关键：如果不写这行，有些系统会自动把响应转成 Map 导致后面 jsonDecode 报错
        responseType: ResponseType.json,
      ),
    );

    _isScanning = true;

    while (_scanPage <= _totalPages && _isScanning && mounted) {
      String url =
          "${currentBaseUrl.value}api/mobile/index.php?version=4&module=viewthread&tid=${widget.tid}&page=$_scanPage";

      try {
        var response = await dio.get(url);

        // --- 【核心修复：解决 Unexpected character 报错】 ---
        dynamic data;
        if (response.data is Map) {
          // 如果已经是 Map 对象，直接使用
          data = response.data;
        } else {
          // 如果是 String 字符串，才需要解析
          String raw = response.data.toString().trim();
          if (raw.startsWith('"')) raw = jsonDecode(raw);
          data = jsonDecode(raw);
        }
        // -----------------------------------------------

        if (data['Variables'] == null) break;
        var vars = data['Variables'];

        if (_scanPage == 1) {
          var tInfo = vars['thread'];
          if (tInfo != null) {
            int allReplies =
                int.tryParse(tInfo['allreplies']?.toString() ?? '0') ?? 0;
            int ppp = int.tryParse(vars['ppp']?.toString() ?? '10') ?? 10;
            _totalPages = ((allReplies + 1) / ppp).ceil();
          }
        }

        _parseImagesFromApi(vars);

        if (mounted) {
          setState(() {
            if (_images.isNotEmpty) _isLoading = false;
          });
        }

        if (_scanPage >= _totalPages) break;
        _scanPage++;
        await Future.delayed(const Duration(milliseconds: 600)); // 匀速抓取
      } catch (e) {
        print("❌ [GallerySpider] 第 $_scanPage 页异常: $e");
        break;
      }
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _isLoading = false;
        if (_images.isEmpty) _errorMsg = "本帖内未找到任何有效图片";
      });
    }
  }

  void _parseImagesFromApi(dynamic vars) {
    var rawList = vars['postlist'];
    Iterable items = (rawList is List)
        ? rawList
        : (rawList is Map ? rawList.values : []);

    for (var p in items) {
      String author = p['author']?.toString() ?? "匿名";
      String time = p['dateline']?.toString().replaceAll('&nbsp;', ' ') ?? "";
      String floor = "${p['number']} 楼";
      String message = p['message']?.toString() ?? "";

      // 完全复刻 thread_detail_page.dart 的图片抓取逻辑
      List<String> foundUrls = [];

      // 1. 附件图片：最权威的来源
      if (p['attachments'] != null && p['attachments'] is Map) {
        Map<String, dynamic> attachs = Map<String, dynamic>.from(
          p['attachments'],
        );
        attachs.forEach((k, v) {
          bool isImg =
              (v['isimage'] != "0" && v['isimage'] != 0) ||
              (v['attachimg'] == "1" || v['attachimg'] == 1);
          if (isImg) {
            // 这里严格按照详情页的拼接公式
            foundUrls.add("${v['url']}${v['attachment']}");
          }
        });
      }

      // 2. 正文图片：抓取外链和插入图
      Iterable<Match> matches = RegExp(
        r'<img[^>]+src="([^">]+)"',
      ).allMatches(message);
      for (var m in matches) {
        String src = m.group(1) ?? "";
        if (src.isEmpty ||
            src.contains('smiley') ||
            src.contains('favicon.ico') ||
            src.contains('static/image'))
          continue;
        foundUrls.add(src);
      }

      // 3. 清洗并加入列表
      for (var url in foundUrls) {
        String finalUrl = url;
        // 彻底清洗 HTML 实体转义（解决 &amp; 问题）
        while (finalUrl.contains('&amp;'))
          finalUrl = finalUrl.replaceAll('&amp;', '&');
        if (!finalUrl.startsWith('http'))
          finalUrl = "${currentBaseUrl.value}$finalUrl";

        // 自动剥离外链缩略图参数（针对部分外链站）
        if (!finalUrl.contains('giantesswaltz') && finalUrl.contains('?')) {
          String noParam = finalUrl.split('?').first;
          if (RegExp(r'\.(jpg|png|jpeg|webp)$').hasMatch(noParam.toLowerCase()))
            finalUrl = noParam;
        }

        if (!_images.any((item) => item.url == finalUrl)) {
          _images.add(
            GalleryImageItem(
              url: finalUrl,
              author: author,
              time: time,
              floorIndex: floor,
            ),
          );
        }
      }
    }
  }

  // 秒传保存，利用 globalImageCache
  Future<void> _saveImage() async {
    if (_images.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    String url = _images[_currentIndex].url;
    try {
      final FileInfo? fileInfo = await globalImageCache.getFileFromCache(url);
      File? imageFile;
      if (fileInfo != null && await fileInfo.file.exists()) {
        imageFile = fileInfo.file;
      } else {
        imageFile = (await globalImageCache.downloadFile(
          url,
          key: url,
          authHeaders: _getHeadersForUrl(url),
        )).file;
      }
      await Gal.putImage(imageFile.path, album: "GiantessWaltz");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ 图片已秒传至相册"),
            duration: Duration(seconds: 1),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ 保存失败: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleBars() {
    setState(() {
      _isBarsVisible = !_isBarsVisible;
      _isBarsVisible ? _fadeController.forward() : _fadeController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_images.isNotEmpty)
            PhotoViewGallery.builder(
              scrollPhysics: const BouncingScrollPhysics(),
              pageController: _pageController,
              itemCount: _images.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              builder: (context, i) {
                final item = _images[i];
                return PhotoViewGalleryPageOptions(
                  // 【关键】：这里必须传入 globalImageCache，否则图片会重新下载且很慢
                  imageProvider: CachedNetworkImageProvider(
                    item.url,
                    headers: _getHeadersForUrl(item.url),
                    cacheManager: globalImageCache,
                  ),
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3.0,
                  heroAttributes: PhotoViewHeroAttributes(tag: item.url),
                );
              },
              loadingBuilder: (c, e) => const Center(
                child: CircularProgressIndicator(color: Colors.white24),
              ),
            )
          else if (!_isLoading)
            Center(
              child: Text(
                _errorMsg,
                style: const TextStyle(color: Colors.white70),
              ),
            ),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          GestureDetector(
            onTap: _toggleBars,
            behavior: HitTestBehavior.translucent,
            child: FadeTransition(
              opacity: _fadeController,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_buildTopBar(), _buildBottomBar()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        bottom: 10,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${_currentIndex + 1} / ${_images.length} ${_isScanning ? '(扫描中...)' : ''}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_images.isEmpty) return const SizedBox();
    final item = _images[_currentIndex];
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.floorIndex,
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  item.author,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  item.time,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: _saveImage,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download, size: 18),
            label: const Text("保存"),
          ),
        ],
      ),
    );
  }
}
