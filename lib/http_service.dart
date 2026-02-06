// lib/http_service.dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'forum_model.dart';
import 'login_page.dart' show kUserAgent;

class HttpService {
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;
  final Dio _dio;
  HttpService._internal()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
          headers: {'User-Agent': kUserAgent},
        ),
      );

  void updateBaseUrl(String newUrl) {
    _dio.options.headers['Referer'] = newUrl;
  }

  // 【核心功能】主页同款“终极续命”杀招，现在全局可用
  Future<String> reviveSession() async {
    print("🚀 [Global Http] 启动 Session 强力激活程序...");
    final prefs = await SharedPreferences.getInstance();
    String currentCookie = prefs.getString('saved_cookie_string') ?? "";
    String baseUrl = currentBaseUrl.value;

    final dio = Dio(
      BaseOptions(
        headers: {
          'User-Agent': kUserAgent,
          'Cookie': currentCookie,
          'Referer': baseUrl,
        },
        followRedirects: false, // 关键：手动处理重定向以捕获每一个 Set-Cookie
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    try {
      // 1. 请求 forum.php
      Response resp = await dio.get('${baseUrl}forum.php?mobile=2');
      _saveCookies(resp.headers['set-cookie']);

      // 2. 如果有重定向（通常是 302），跟进去拿第二波 Cookie
      if ((resp.statusCode == 301 || resp.statusCode == 302)) {
        String? loc = resp.headers.value('location');
        if (loc != null) {
          String fullLoc = loc.startsWith('http')
              ? loc
              : (baseUrl + loc.replaceFirst('/', ''));
          print("🔄 [Global Http] 发现重定向: $fullLoc");
          Response resp2 = await dio.get(fullLoc);
          _saveCookies(resp2.headers['set-cookie']);
        }
      }

      final updated = prefs.getString('saved_cookie_string') ?? "";
      print("✅ [Global Http] Session 激活完成");
      return updated;
    } catch (e) {
      print("❌ [Global Http] 激活失败: $e");
      return currentCookie;
    }
  }

  void _saveCookies(List<String>? setCookies) async {
    if (setCookies == null || setCookies.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    String current = prefs.getString('saved_cookie_string') ?? "";
    // 调用 forum_model.dart 里的 mergeCookies 函数（确保你在 main.dart 里那个函数也叫这个名）
    String merged = mergeCookies(current, setCookies);
    await prefs.setString('saved_cookie_string', merged);
  }

  Future<String> getHtml(
    String urlOrPath, {
    Map<String, String>? headers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String cookie = prefs.getString('saved_cookie_string') ?? "";
    final response = await _dio.get<String>(
      urlOrPath,
      options: Options(headers: {'Cookie': cookie, ...?headers}),
    );
    _saveCookies(response.headers['set-cookie']);
    return response.data ?? '';
  }
}
