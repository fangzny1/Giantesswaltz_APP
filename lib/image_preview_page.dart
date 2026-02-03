import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart'; // 【改动1】引入新库
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

  Future<void> _saveImage() async {
    // Gal 库会自动处理权限，所以我们不需要手动请求 Permission.storage 了
    setState(() => _isSaving = true);

    try {
      // 1. 下载图片数据
      var response = await Dio().get(
        widget.imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: widget.headers,
        ),
      );

      // 2. 【改动2】使用 Gal 保存图片到相册
      // format: name 这一行是可选的，用来给图片命名
      await Gal.putImageBytes(
        Uint8List.fromList(response.data),
        name: "GN_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ 图片已保存到相册")));
      }
    } on GalException catch (e) {
      // Gal 专门的异常处理（比如用户拒绝权限）
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ 保存失败: ${e.type.message}")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ 下载出错: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: PhotoView(
        imageProvider: CachedNetworkImageProvider(
          widget.imageUrl,
          headers: widget.headers,
          cacheManager: widget.cacheManager,
        ),
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null
                ? null
                : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
          ),
        ),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, color: Colors.grey, size: 50),
              Text("加载失败", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3.0,
      ),
    );
  }
}
