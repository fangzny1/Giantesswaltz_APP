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
    // 【核心修复】动态获取当前选中的域名
    // 之前可能写死成 '${kBaseUrl}member.php...' 了，现在要改成 currentBaseUrl.value
    final String loginUrl =
        '${currentBaseUrl.value}member.php?mod=logging&action=login&mobile=2';
    print("🔐 正在打开登录页: $loginUrl");

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

    // 2. 加载动态构建的 URL
    controller.loadRequest(Uri.parse(loginUrl));

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

  void _checkLoginStatus(String url) {
    if (isDetecting) return;

    // 【优化】使用动态域名判断跳转
    // 只要 URL 包含了当前基础域名，且是首页或论坛页，就认为登录跳转完成了
    String domain = Uri.parse(currentBaseUrl.value).host;

    if (url == currentBaseUrl.value ||
        (url.contains(domain) &&
            (url.contains("index.php") || url.contains("forum.php")))) {
      _completeLogin();
    }
  }

  Future<void> _completeLogin() async {
    if (isDetecting) return;
    isDetecting = true;
    _timer?.cancel();

    try {
      // 抓取 Cookie
      final String cookies =
          await controller.runJavaScriptReturningResult('document.cookie')
              as String;
      String rawCookie = cookies;
      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }

      print("✅ [Login] 捕获凭证: $rawCookie");

      // 保存到本地
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_cookie_string', rawCookie);

      // 【新增】同时保存UID（如果能从Cookie里简单解析的话），或者留给主页去解析
      // 这里主要确保 Cookie 被写入

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录成功，正在同步数据...'),
            backgroundColor: Colors.green,
          ),
        );
        // 稍微等待一下写入
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, true);
      }
    } catch (e) {
      isDetecting = false;
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
