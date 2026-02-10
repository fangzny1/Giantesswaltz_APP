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

  // 【新增】统一获取当前可用的 Headers
  Future<Map<String, String>> getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String cookie = prefs.getString('saved_cookie_string') ?? "";
    return {
      'Cookie': cookie,
      'User-Agent': kUserAgent,
      'Referer': currentBaseUrl.value, // 动态使用当前域名
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    };
  }

  void _saveCookies(List<String>? setCookies) async {
    if (setCookies == null || setCookies.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    String current = prefs.getString('saved_cookie_string') ?? "";
    // 调用 forum_model.dart 里的 mergeCookies 函数（确保你在 main.dart 里那个函数也叫这个名）
    String merged = mergeCookies(current, setCookies);
    await prefs.setString('saved_cookie_string', merged);
  }

  // ==========================================
  // 【屎山加强版】暴力重试逻辑
  // ==========================================
  Future<String> getHtml(
    String urlOrPath, {
    Map<String, String>? headers,
  }) async {
    int maxRetries = 3; // 最多给它3次机会，不信治不了它
    int currentTry = 0;

    while (currentTry < maxRetries) {
      currentTry++;
      final prefs = await SharedPreferences.getInstance();
      String cookie = prefs.getString('saved_cookie_string') ?? "";

      try {
        // 【暴力点1】每次请求直接创建一个全新的 Dio 实例，杜绝旧连接池污染
        final tempDio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'User-Agent': kUserAgent,
              'Cookie': cookie,
              'Referer': currentBaseUrl.value,
              ...?headers,
            },
          ),
        );

        final response = await tempDio.get<String>(urlOrPath);
        String data = response.data ?? '';

        // 【暴力点2】严格审查返回内容：只要不是 JSON 或者是那个“欢迎回来”的 HTML
        bool isApi = urlOrPath.contains('index.php?version=4');
        bool isJunkHtml =
            data.contains('欢迎您回来') ||
            data.contains('现在将转入') ||
            data.contains('alert_right') ||
            data.contains('<!DOCTYPE html');

        // 如果我们请求 API 却拿到了 HTML 垃圾信息
        if (isApi && isJunkHtml) {
          print("💩 [HttpService] 第 $currentTry 次拿到垃圾HTML，开始暴力修复...");

          // 保存可能存在的新Cookie
          _saveCookies(response.headers['set-cookie']);

          // 执行强力续命
          await reviveSession();

          // 【暴力点3】强制等待。发行版越快，我们要等得越久。
          // 第一次失败等1秒，第二次等2秒
          await Future.delayed(Duration(milliseconds: 1000 * currentTry));

          continue; // 重新进入 while 循环
        }

        // 没问题，正常返回
        _saveCookies(response.headers['set-cookie']);
        return data;
      } catch (e) {
        print("💩 [HttpService] 请求崩了: $e，准备第 ${currentTry + 1} 次重试");
        if (e.toString().contains("CLOUDFLARE")) rethrow;

        await reviveSession();
        await Future.delayed(const Duration(milliseconds: 1000));
        if (currentTry >= maxRetries) rethrow;
      }
    }

    throw "💩 经过 $maxRetries 次暴力尝试，依然无法获取有效数据";
  }
}
