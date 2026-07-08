import 'dart:io';
import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';
import 'forum_model.dart';

/// 下载结果
enum DownloadResult { success, partial, failed, skipped }

class ImageDownloadService {
  static final ImageDownloadService _instance =
      ImageDownloadService._internal();
  factory ImageDownloadService() => _instance;

  late final Dio _dio;

  /// 临时文件统一存放目录,懒加载
  Directory? _tempDir;

  /// 已下载完成的 URL 记录(url → 保存到相册的名字),避免重复下载
  /// 注:用 prefs 而非内存,避免跨会话重复
  static const String _doneKeyPrefix = 'img_dl_done_';

  ImageDownloadService._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 3),
        headers: {'User-Agent': kUserAgent},
      ),
    );
    if (Platform.isAndroid || Platform.isIOS) {
      _dio.httpClientAdapter = NativeAdapter();
    }
  }

  /// 下载单张图片(支持断点续传)。完成后保存到相册并清理临时文件。
  Future<DownloadResult> downloadImage(
    String url, {
    void Function(int received, int total)? onProgress,
    bool skipIfDownloaded = true,
    String? album,
    int maxRetries = 2,
  }) async {
    final tempFile = await _getTempFileFor(url);

    // 1. 去重:已经成功下载过、临时文件又是完整图,直接跳过
    if (skipIfDownloaded && await _isAlreadySaved(url)) {
      return DownloadResult.skipped;
    }

    // 2. 准备 Header(Cookie + Referer 仅对站内图;外链净身)
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString('saved_cookie_string') ?? '';
    final headers = _buildHeaders(url, cookie);

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final received = await tempFile.length();

        final response = await _dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              ...headers,
              if (received > 0) 'Range': 'bytes=$received-',
            },
            validateStatus: (s) =>
                s != null && (s == 200 || s == 206 || s == 416),
          ),
        );

        // 416 Range Not Satisfiable:可能临时文件已经是完整的,直接进相册
        if (response.statusCode == 416) {
          await _saveAndCleanup(tempFile, url, album: album);
          await _markDone(url);
          return DownloadResult.success;
        }

        final supported = response.statusCode == 206;
        final total = int.tryParse(
              response.headers.value('content-length') ?? '',
            ) ??
            -1;
        final realTotal = supported && total >= 0
            ? total + received
            : (total >= 0 ? total : -1);

        final mode = supported ? FileMode.append : FileMode.write;
        if (!supported) {
          // 服务器不支持续传,重头下,清掉旧临时文件
          await tempFile.writeAsBytes([], mode: FileMode.write, flush: true);
        }

        final sink = tempFile.openWrite(mode: mode);
        int current = received;
        try {
          await for (final chunk in response.data!.stream) {
            sink.add(chunk);
            current += chunk.length;
            if (onProgress != null) {
              onProgress(current, realTotal < 0 ? -1 : realTotal);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        // 检查完整性
        if (realTotal >= 0 && await tempFile.length() < realTotal) {
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.unknown,
            message: '下载不完整: ${await tempFile.length()}/$realTotal',
          );
        }

        await _saveAndCleanup(tempFile, url, album: album);
        await _markDone(url);
        return DownloadResult.success;
      } catch (e) {
        if (attempt > maxRetries) {
          // 失败但保留临时文件,下次可续传
          return DownloadResult.partial;
        }
        // 指数退避
        await Future.delayed(
          Duration(milliseconds: 500 * (1 << (attempt - 1))),
        );
      }
    }
  }

  /// 构造下载 Header:站内带 Cookie+Referer,外链只带 UA
  Map<String, String> _buildHeaders(String url, String cookie) {
    final isInternal = url.contains('giantesswaltz.org') ||
        url.contains('gtswaltz.org') ||
        url.contains('gtsproject.org');
    if (isInternal && cookie.isNotEmpty) {
      return {
        'Cookie': cookie,
        'Referer': currentBaseUrl.value,
        'User-Agent': kUserAgent,
        'Connection': 'keep-alive',
      };
    }
    return {'User-Agent': kUserAgent};
  }

  Future<void> _saveAndCleanup(
    File tempFile,
    String url, {
    String? album,
  }) async {
    if (!await tempFile.exists() || await tempFile.length() == 0) {
      throw '下载数据为空';
    }
    // Gal.putImage 用文件名作为相册里的资源名,先 rename 成唯一名再保存
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ext = _extOf(url);
    final named = await _getTempFileFor('gw_$stamp$ext');
    try {
      if (await named.exists()) await named.delete();
      await tempFile.rename(named.path);
    } catch (_) {
      // rename 跨卷可能失败,fallback 到 copy
      await named.writeAsBytes(await tempFile.readAsBytes());
    }
    await Gal.putImage(named.path, album: album ?? 'GiantessWaltz');
    try {
      await named.delete();
    } catch (_) {}
  }

  String _extOf(String url) {
    final noQuery = url.split('?').first.toLowerCase();
    final dot = noQuery.lastIndexOf('.');
    if (dot <= noQuery.lastIndexOf('/')) return '.jpg';
    final ext = noQuery.substring(dot);
    if ({'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}
        .contains(ext)) {
      return ext;
    }
    return '.jpg';
  }

  Future<Directory> _getTempDir() async {
    if (_tempDir != null) return _tempDir!;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/img_dl');
    if (!await dir.exists()) await dir.create(recursive: true);
    _tempDir = dir;
    return dir;
  }

  Future<File> _getTempFileFor(String url) async {
    final dir = await _getTempDir();
    final safeName = url.hashCode.toRadixString(16);
    return File('${dir.path}/dl_$safeName');
  }

  Future<bool> _isAlreadySaved(String url) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_doneKeyPrefix${url.hashCode}') ?? false;
  }

  Future<void> _markDone(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_doneKeyPrefix${url.hashCode}', true);
  }

  /// 清除去重记录(用户在设置里"清缓存"时调用)
  Future<void> clearDownloadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(_doneKeyPrefix))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    // 顺带删掉残留的临时分片
    final dir = await _getTempDir();
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        try {
          await f.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// 批量下载:真正限流并发,默认 3。返回 {success, partial, skipped, failed}。
  Future<Map<DownloadResult, int>> batchDownload(
    List<String> urls, {
    int concurrency = 3,
    void Function(int done, int total)? onOverallProgress,
  }) async {
    final result = <DownloadResult, int>{
      DownloadResult.success: 0,
      DownloadResult.partial: 0,
      DownloadResult.skipped: 0,
      DownloadResult.failed: 0,
    };

    int done = 0;
    int index = -1;

    // 一个简单的 worker pool
    Future<void> worker() async {
      while (true) {
        final i = ++index;
        if (i >= urls.length) return;
        final r = await downloadImage(urls[i]);
        result[r] = (result[r] ?? 0) + 1;
        done++;
        onOverallProgress?.call(done, urls.length);
      }
    }

    final workers = List.generate(
      concurrency.clamp(1, 8),
      (_) => worker(),
    );
    await Future.wait(workers);
    return result;
  }
}
