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
          baseUrl: kBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.plain,
          headers: {'User-Agent': kUserAgent, 'Referer': kBaseUrl},
        ),
      );

  // 【核心功能】安全合并并保存 Cookie
  void _saveCookies(List<String>? setCookies) async {
    if (setCookies == null || setCookies.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    String currentCookie = prefs.getString('saved_cookie_string') ?? "";

    final Map<String, String> cookieMap = {};

    // 解析当前已有的
    void parse(String str) {
      str.split(';').forEach((part) {
        var pair = part.split('=');
        if (pair.length >= 2) {
          String key = pair[0].trim();
          String val = pair.sublist(1).join('=').trim();
          if (key.isNotEmpty &&
              !['path', 'domain', 'expires'].contains(key.toLowerCase())) {
            cookieMap[key] = val;
          }
        }
      });
    }

    parse(currentCookie);
    // 合并新返回的 (覆盖旧值)
    for (var header in setCookies) {
      parse(header.split(';')[0]);
    }

    String newCookieStr = cookieMap.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    await prefs.setString('saved_cookie_string', newCookieStr);
    print("💾 [HttpService] Cookie 自动续命成功");
  }

  Future<String> getHtml(
    String urlOrPath, {
    Map<String, String>? headers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final String cookie = prefs.getString('saved_cookie_string') ?? "";

    final Map<String, dynamic> mergedHeaders = {
      if (cookie.isNotEmpty) 'Cookie': cookie,
      ..._dio.options.headers,
      if (headers != null) ...headers,
    };

    try {
      final Response<String> resp = await _dio.get<String>(
        urlOrPath,
        options: Options(headers: mergedHeaders),
      );

      // 【关键修复】每次请求后都尝试捕获新的 Cookie (Session 激活的核心)
      _saveCookies(resp.headers['set-cookie']);

      return resp.data ?? '';
    } catch (e) {
      rethrow;
    }
  }
}
