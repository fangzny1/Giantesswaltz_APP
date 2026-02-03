import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'forum_model.dart';

// 统一 UA，务必保持一致
const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController controller;
  bool isDetecting = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 1. 清理环境
    WebViewCookieManager().clearCookies();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            print("🌐 页面加载完: $url");
            _checkLoginStatus(url);
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) _checkLoginStatus(change.url!);
          },
        ),
      );

    // 2. 加载登录页
    controller.loadRequest(
      Uri.parse('${kBaseUrl}member.php?mod=logging&action=login&mobile=2'),
    );

    // 3. 【核心修复】定时器主动嗅探内容
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _scanPageContent();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // 【黑科技 1】扫描网页文本内容
  Future<void> _scanPageContent() async {
    if (isDetecting) return;
    try {
      // 检查页面是否包含“欢迎您回来”或“现在将转入”
      final String text =
          await controller.runJavaScriptReturningResult(
                "document.body.innerText",
              )
              as String;

      if (text.contains("欢迎您回来") ||
          text.contains("现在将转入") ||
          text.contains("登录成功")) {
        print("🎯 探测到网页版登录成功提示！");
        _completeLogin();
      }
    } catch (e) {
      // 忽略
    }
  }

  // 【黑科技 2】检查 URL 状态
  void _checkLoginStatus(String url) {
    if (isDetecting) return;

    // 如果跳回了首页或导读页，说明登录动作已完成
    if (url == kBaseUrl ||
        url.contains("index.php") ||
        url.contains("forum.php")) {
      _completeLogin();
    }
  }

  // 【核心方法】抓取 Cookie 并退出
  Future<void> _completeLogin() async {
    if (isDetecting) return;
    isDetecting = true;
    _timer?.cancel();

    try {
      // 抓取当前所有能读到的 Cookie
      final String cookies =
          await controller.runJavaScriptReturningResult('document.cookie')
              as String;
      String rawCookie = cookies;
      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }

      print("✅ [Login] 捕获凭证: $rawCookie");

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_cookie_string', rawCookie);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录成功，正在同步数据...'),
            backgroundColor: Colors.green,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        Navigator.pop(context, true);
      }
    } catch (e) {
      isDetecting = false; // 出错重试
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
          // 手动干预按钮
          TextButton(
            onPressed: () => _completeLogin(),
            child: const Text("已登录点此"),
          ),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
