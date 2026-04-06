import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart'; // 引入原生适配器
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart'; // 获取 kUserAgent
import 'forum_model.dart'; // 获取 currentBaseUrl

class ImageDownloadService {
  static final ImageDownloadService _instance =
      ImageDownloadService._internal();
  factory ImageDownloadService() => _instance;

  late Dio _dio;

  ImageDownloadService._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'User-Agent': kUserAgent},
      ),
    );

    // 【核心黑科技】：使用安卓原生网络库 (Cronet)
    // 这比 Dart 默认的网络请求快得多，尤其是在处理备用站这种跨境/延迟高的服务器时
    if (Platform.isAndroid || Platform.isIOS) {
      _dio.httpClientAdapter = NativeAdapter();
    }
  }

  // 极速下载并保存
  Future<void> downloadImage(String url, {Function(double)? onProgress}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String cookie = prefs.getString('saved_cookie_string') ?? "";

      // 准备 Header，Discuz 校验 Referer 很严
      Map<String, String> headers = {
        'Cookie': cookie,
        'Referer': currentBaseUrl.value,
        'User-Agent': kUserAgent,
      };

      // 针对外链（非论坛域名）清洗 Header，防止触发防盗链
      if (!url.contains('giantesswaltz.org') && !url.contains('gtswaltz.org')) {
        headers = {'User-Agent': kUserAgent};
      }

      // 1. 发起请求获取字节流
      final response = await _dio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes, headers: headers),
        onReceiveProgress: (count, total) {
          if (total != -1 && onProgress != null) {
            onProgress(count / total);
          }
        },
      );

      if (response.data == null) throw "下载数据为空";

      // 2. 调用 Gal 保存到相册
      await Gal.putImageBytes(
        response.data!,
        name: "GW_${DateTime.now().millisecondsSinceEpoch}",
      );
    } catch (e) {
      rethrow;
    }
  }

  // 【扩展】：如果是批量下载帖子里的图，用这个可以多线程并发
  Future<void> batchDownload(List<String> urls) async {
    // 限制同时并发 3 个，既快又不会被服务器拉黑
    List<Future> tasks = urls.map((u) => downloadImage(u)).toList();
    await Future.wait(tasks);
  }
}
