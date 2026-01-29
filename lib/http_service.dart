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

  Future<String> getHtml(
    String urlOrPath, {
    Map<String, String>? headers,
    bool saveSetCookie = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final String cookie = prefs.getString('saved_cookie_string') ?? "";

    final Map<String, dynamic> mergedHeaders = {
      if (cookie.isNotEmpty) 'Cookie': cookie,
      ..._dio.options.headers,
      if (headers != null) ...headers,
    };

    final Response<String> resp = await _dio.get<String>(
      urlOrPath,
      options: Options(headers: mergedHeaders),
    );

    if (saveSetCookie) {
      final List<String>? setCookies = resp.headers['set-cookie'];
      if (setCookies != null && setCookies.isNotEmpty) {
        final String current = prefs.getString('saved_cookie_string') ?? '';
        final String merged = mergeCookies(current, setCookies);
        if (merged.isNotEmpty && merged != current) {
          await prefs.setString('saved_cookie_string', merged);
        }
      }
    }

    return resp.data ?? '';
  }

  Future<String> postForm(
    String urlOrPath, {
    required Map<String, dynamic> data,
    Map<String, String>? headers,
    bool saveSetCookie = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final String cookie = prefs.getString('saved_cookie_string') ?? "";

    final Map<String, dynamic> mergedHeaders = {
      if (cookie.isNotEmpty) 'Cookie': cookie,
      ..._dio.options.headers,
      if (headers != null) ...headers,
    };

    final Response<String> resp = await _dio.post<String>(
      urlOrPath,
      data: FormData.fromMap(data),
      options: Options(headers: mergedHeaders),
    );

    if (saveSetCookie) {
      final List<String>? setCookies = resp.headers['set-cookie'];
      if (setCookies != null && setCookies.isNotEmpty) {
        final String current = prefs.getString('saved_cookie_string') ?? '';
        final String merged = mergeCookies(current, setCookies);
        if (merged.isNotEmpty && merged != current) {
          await prefs.setString('saved_cookie_string', merged);
        }
      }
    }

    return resp.data ?? '';
  }
}
