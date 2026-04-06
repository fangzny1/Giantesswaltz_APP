import 'dart:typed_data';
import 'dart:io'; // 用于 File
import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/forum_model.dart';
import 'package:giantesswaltz_app/image_download_service.dart';
import 'package:photo_view/photo_view.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'main.dart'; // 【引入】访问 currentBaseUrl
import 'login_page.dart'; // 【引入】访问 kUserAgent

class ImagePreviewPage extends StatefulWidget {
  final String imageUrl;
  final Map<String, String> headers;
  final BaseCacheManager? cacheManager;

  const ImagePreviewPage({
    super.key,
    required this.imageUrl,
    required this.headers,
    this.cacheManager,
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  bool _isSaving = false;

  // 【核心修复】智能获取 Header
  // 即使上层传错了，这里也能最后一道防线修正
  Map<String, String> get _safeHeaders {
    String url = widget.imageUrl;
    String currentHost = Uri.parse(currentBaseUrl.value).host;

    // 判断是否是自家域名
    bool isInternal =
        url.contains(currentHost) ||
        !url.startsWith('http') ||
        url.contains('giantesswaltz.org') ||
        url.contains('gtswaltz.org');

    if (isInternal) {
      // 站内图：使用传入的完整 Headers (含 Cookie, Referer)
      return widget.headers;
    } else {
      // 站外图：清洗 Headers，只留 UA，防止防盗链拦截
      return {'User-Agent': kUserAgent};
    }
  }

  Future<void> _saveImage() async {
    setState(() => _isSaving = true);

    try {
      // 1. 尝试从全局缓存中直接获取已下载的文件
      // globalImageCache 是你在 forum_model 里定义的那个带加速的缓存器
      final FileInfo? fileInfo = await globalImageCache.getFileFromCache(
        widget.imageUrl,
      );

      File? imageFile;

      if (fileInfo != null && await fileInfo.file.exists()) {
        // 情况 A: 命中缓存，直接用缓存文件
        print("🚀 [SaveImage] 命中缓存，直接保存本地文件");
        imageFile = fileInfo.file;
      } else {
        // 情况 B: 缓存意外丢失或尚未下载完，则执行下载并存入缓存
        print("🌐 [SaveImage] 缓存未命中，开始流式下载...");
        // 使用 cacheManager 的 downloadFile 也会自动走你写的 MyDioFileService 加速
        final FileInfo downloaded = await globalImageCache.downloadFile(
          widget.imageUrl,
          key: widget.imageUrl,
          authHeaders: _safeHeaders,
        );
        imageFile = downloaded.file;
      }

      // 2. 将文件保存到相册
      // 使用 Gal.putImage 直接传入路径，这是最快的方式
      await Gal.putImage(imageFile.path, album: "GiantessWaltz");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ 图片已秒传至相册"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print("❌ 保存失败详情: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ 保存失败: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取清洗后的 Headers
    final Map<String, String> realHeaders = _safeHeaders;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: "保存图片",
                  onPressed: _saveImage,
                ),
        ],
      ),
      body: Hero(
        tag: widget.imageUrl, // 必须和上一页的 tag 完全一致
        child: PhotoView(
          // 【关键】ImageProvider 也要用清洗后的 Headers
          imageProvider: CachedNetworkImageProvider(
            widget.imageUrl,
            headers: realHeaders,
            cacheManager: widget.cacheManager,
          ),
          loadingBuilder: (context, event) => Center(
            child: CircularProgressIndicator(
              value: event == null
                  ? null
                  : event.cumulativeBytesLoaded /
                        (event.expectedTotalBytes ?? 1),
            ),
          ),
          errorBuilder: (context, error, stackTrace) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                const SizedBox(height: 10),
                const Text("加载失败", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 5),
                // 增加一个调试提示，方便看是不是 Header 导致的
                Text(
                  widget.imageUrl.contains("giantesswaltz") ? "(站内图)" : "(外链图)",
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3.0,
        ),
      ),
    );
  }
}
