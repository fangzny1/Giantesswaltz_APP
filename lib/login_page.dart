import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

// ==========================================
// 全局配置区域
// ==========================================

const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.181 Mobile Safari/537.36";

final CookieJar cookieJar = CookieJar();
final Dio dio = Dio(
  BaseOptions(
    headers: {'User-Agent': kUserAgent},
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);

bool _isInterceptorAdded = false;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController controller;
  bool isDetecting = false;

  @override
  void initState() {
    super.initState();

    if (!_isInterceptorAdded) {
      dio.interceptors.add(CookieManager(cookieJar));
      _isInterceptorAdded = true;
    }

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            if (!isDetecting) {
              checkLoginStatus(url);
            }
          },
        ),
      );

    // 【核心修改】启动时先清空 Cookie，确保每次都是新登录
    _clearAndLoad();
  }

  Future<void> _clearAndLoad() async {
    // 1. 清除 WebView 的缓存 (解决 ERR_CACHE_MISS 的关键)
    await controller.clearCache();

    // 2. 清除 Cookie
    await WebViewCookieManager().clearCookies();

    print("🧹 登录页：已强制清除缓存和 Cookie");

    // 3. 加载登录页
    controller.loadRequest(
      Uri.parse(
        'https://www.giantessnight.com/gnforum2012/member.php?mod=logging&action=login',
      ),
    );
  }

  Future<void> checkLoginStatus(String url) async {
    try {
      final Object result = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      String rawCookie = result.toString();

      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }

      if (rawCookie.isEmpty) return;

      // 只要包含 auth 字段，说明用户手动登录成功了
      if (rawCookie.contains('auth') || rawCookie.contains('saltkey')) {
        if (isDetecting) return;
        isDetecting = true;

        print("✅ 登录成功！捕获 Cookie");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('验证成功，正在同步数据...'),
              duration: Duration(seconds: 1),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted) {
            // 返回 true 表示登录成功
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      print("Cookie 获取错误: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("登录")),
      body: WebViewWidget(controller: controller),
    );
  }
}
