import 'dart:typed_data'; // 需要引入以支持下面的类型
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'forum_model.dart';
import 'login_page.dart' show kUserAgent;

const String kDirectIp = '104.128.90.178';

class HttpService {
  // 【新增】开关：是否开启直连模式 (在 ProfilePage 里控制这个变量)
  static bool useHostsMode = false;

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

  // 1. 强力续命 (只负责拿 Session，不乱动 WebViewCookieManager)
  Future<String> reviveSession() async {
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
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    try {
      Response resp = await dio.get('${baseUrl}forum.php?mobile=2');
      _saveCookies(resp.headers['set-cookie']);

      String? loc = resp.headers.value('location');
      if (loc != null) {
        String fullLoc = loc.startsWith('http')
            ? loc
            : (baseUrl + loc.replaceFirst('/', ''));
        Response resp2 = await dio.get(fullLoc);
        _saveCookies(resp2.headers['set-cookie']);
      }
      await Future.delayed(const Duration(milliseconds: 800));
      return prefs.getString('saved_cookie_string') ?? "";
    } catch (e) {
      return currentCookie;
    }
  }

  // 2. 核心请求器：内置【Hosts直连】+【暴力重试】+【自愈逻辑】
  Future<String> getHtml(
    String urlOrPath, {
    Map<String, String>? headers,
  }) async {
    int maxRetries = 3;
    int currentTry = 0;

    // --- 【 Hosts 模式逻辑 】 ---
    String targetUrl = urlOrPath;
    Map<String, String> finalHeaders = {...?headers};

    if (useHostsMode &&
        (targetUrl.contains('giantesswaltz.org') ||
            targetUrl.contains('gtswaltz.org'))) {
      String domain = Uri.parse(currentBaseUrl.value).host;
      targetUrl = targetUrl.replaceFirst(domain, kDirectIp);
      finalHeaders['Host'] = domain; // 必须带上正确的 Host 头，服务器才认
    }
    // --------------------------

    while (currentTry < maxRetries) {
      currentTry++;
      final prefs = await SharedPreferences.getInstance();
      String cookie = prefs.getString('saved_cookie_string') ?? "";

      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            responseType: ResponseType.plain,
            headers: {
              'User-Agent': kUserAgent,
              'Cookie': cookie,
              ...finalHeaders,
            },
          ),
        );

        final response = await dio.get<String>(targetUrl);
        String data = response.data ?? '';

        // 检查是否又是那该死的“欢迎回来”页面
        bool isApi = urlOrPath.contains('api/mobile/index.php');
        bool isJunkHtml =
            data.contains('欢迎您回来') ||
            data.contains('alert_right') ||
            data.contains('现在将转入');

        if (isApi && isJunkHtml) {
          print("💩 [HttpService] 拿到垃圾中间页，尝试自愈...");
          _saveCookies(response.headers['set-cookie']);
          await reviveSession();
          await Future.delayed(Duration(milliseconds: 1000 * currentTry));
          continue;
        }

        if (data.contains('challenges.cloudflare.com')) throw "CLOUDFLARE";

        _saveCookies(response.headers['set-cookie']);
        return data;
      } catch (e) {
        if (e.toString().contains("CLOUDFLARE")) rethrow;
        print("❌ 请求失败: $e，尝试续命重试...");
        await reviveSession();
        await Future.delayed(const Duration(milliseconds: 1000));
        if (currentTry >= maxRetries) rethrow;
      }
    }
    throw "💩 经过 $maxRetries 次重试依然无法获取有效数据";
  }

  void _saveCookies(List<String>? setCookies) async {
    if (setCookies == null || setCookies.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    String current = prefs.getString('saved_cookie_string') ?? "";
    String merged = mergeCookies(current, setCookies);
    await prefs.setString('saved_cookie_string', merged);
  }
}
