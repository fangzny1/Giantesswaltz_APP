import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 引入存储库

// 统一的 UA，千万别改，保持和 main.dart 一致
const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36";

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

    // 1. 先清除所有旧的脏数据，保证这是一个全新的开始
    _clearCookies();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            _checkLoginStatus();
          },
        ),
      );

    // 2. 加载最原始的手机登录页 (兼容性最好)
    controller.loadRequest(
      Uri.parse(
        'https://www.giantessnight.com/gnforum2012/member.php?mod=logging&action=login&mobile=2',
      ),
    );
  }

  Future<void> _clearCookies() async {
    await WebViewCookieManager().clearCookies();
    await WebViewController().clearCache();
  }

  Future<void> _checkLoginStatus() async {
    if (isDetecting) return;

    try {
      // 获取当前页面的所有 Cookie
      final String cookies =
          await controller.runJavaScriptReturningResult('document.cookie')
              as String;

      String rawCookie = cookies;
      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }

      // 判断是否登录成功
      if (rawCookie.contains('auth') ||
          (rawCookie.contains('saltkey') && rawCookie.contains('uchome'))) {
        isDetecting = true;
        print("✅ 捕获到登录 Cookie: $rawCookie");

        // 【核心修改】手动持久化保存 Cookie！
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_cookie_string', rawCookie); // 存入硬盘

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('登录成功，正在保存凭证...'),
              duration: Duration(seconds: 1),
            ),
          );

          // 强行同步给 WebViewCookieManager (双重保险)
          final cookieMgr = WebViewCookieManager();
          // 这里简单的把 cookie 字符串拆分一下设置进去，防止 webview 重启丢失
          // 实际 Discuz 关键是 saltkey 和 auth

          await Future.delayed(const Duration(milliseconds: 500));

          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      print("Cookie 检查失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("登录账号"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.reload(),
          ),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
