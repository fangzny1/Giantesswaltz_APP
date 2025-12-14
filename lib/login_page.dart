import 'dart:io';
import 'dart:math'; // 引入这个用于生成随机数
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

// ==========================================
// 全局配置区域
// ==========================================

// 【修改 1】更新 User-Agent，伪装成最新的安卓 Chrome，防止被防火墙嫌弃
const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36";

final CookieJar cookieJar = CookieJar();
final Dio dio = Dio(
  BaseOptions(
    headers: {'User-Agent': kUserAgent},
    connectTimeout: const Duration(seconds: 15), // 稍微延长超时
    receiveTimeout: const Duration(seconds: 15),
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
          // 【新增】拦截重定向错误，防止死循环
          onWebResourceError: (error) {
            print("WebView Error: ${error.description}");
          },
        ),
      );

    // 启动清理并加载
    _clearAndLoad();
  }

  Future<void> _clearAndLoad() async {
    print("🧹 登录页：开始清理环境...");

    // 1. 清除 WebView 缓存
    await controller.clearCache();
    await controller.clearLocalStorage(); // 新增：清理本地存储

    // 2. 彻底清除 Cookie
    // 注意：有时候 clearCookies 返回得太快但系统还没删完
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();

    // 【修改 2】加一个小延时，确保 Cookie 真的被系统删干净了
    // 避免 Discuz 识别到残留 Cookie 导致重定向死循环
    await Future.delayed(const Duration(milliseconds: 500));

    print("🧹 登录页：环境清理完毕，准备加载");

    // 【修改 3】URL 加随机参数 (t=时间戳)
    // 作用：强制服务器认为这是一个全新的请求，绕过 WAF 的缓存或拦截规则
    final String cleanUrl =
        'https://www.giantessnight.com/gnforum2012/member.php?mod=logging&action=login&mobile=2&t=${DateTime.now().millisecondsSinceEpoch}';

    // 这里特意用了 mobile=2，因为 Discuz 的原生手机登录页通常干扰更少，更不容易触发电脑版的复杂跳转
    // 登录成功后获取到的 Cookie 是通用的，不影响 APP 后续伪装成电脑版使用

    controller.loadRequest(Uri.parse(cleanUrl));
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

      // 只要包含 auth 或 saltkey 字段，说明用户手动登录成功了
      if ((rawCookie.contains('auth') || rawCookie.contains('saltkey')) &&
          !isDetecting) {
        isDetecting = true;

        print("✅ 登录成功！捕获 Cookie");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('验证成功，正在同步数据...'),
              duration: Duration(seconds: 1),
            ),
          );

          // 稍微等一下，让 Cookie 写入更稳
          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted) {
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
      appBar: AppBar(
        title: const Text("登录账号"),
        actions: [
          // 【新增】手动刷新按钮，万一卡住可以点一下
          IconButton(icon: const Icon(Icons.refresh), onPressed: _clearAndLoad),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
