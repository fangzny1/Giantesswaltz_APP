import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'miui_theme.dart';
import 'forum_model.dart';

const String kUserAgent =
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";

class LoginPage extends StatefulWidget {
  /// 登录成功后回调
  final VoidCallback? onLoginSuccess;

  /// 是否显示右上角跳过按钮
  final bool showSkip;

  /// 跳过按钮回调
  final VoidCallback? onSkip;

  const LoginPage({
    super.key,
    this.onLoginSuccess,
    this.showSkip = false,
    this.onSkip,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController controller;
  bool isDetecting = false;
  Timer? _timer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WebViewCookieManager().clearCookies();

    final String loginUrl =
        '${currentBaseUrl.value}member.php?mod=logging&action=login&mobile=2';

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _checkLoginStatus(url);
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) _checkLoginStatus(change.url!);
          },
        ),
      );

    controller.loadRequest(Uri.parse(loginUrl));

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _scanPageContent();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _scanPageContent() async {
    if (isDetecting) return;
    try {
      final String text =
          await controller.runJavaScriptReturningResult(
                "document.body.innerText",
              )
              as String;

      if (text.contains("欢迎您回来") ||
          text.contains("现在将转入") ||
          text.contains("登录成功")) {
        _completeLogin();
      }
    } catch (_) {}
  }

  void _checkLoginStatus(String url) {
    if (isDetecting) return;
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
      final String cookies =
          await controller.runJavaScriptReturningResult('document.cookie')
              as String;
      String rawCookie = cookies;
      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_cookie_string', rawCookie);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录成功，正在同步数据...'),
            backgroundColor: MiuiTheme.green,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));

        if (widget.onLoginSuccess != null) {
          widget.onLoginSuccess!();
        } else {
          if (mounted) Navigator.pop(context, true);
        }
      }
    } catch (e) {
      isDetecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("登录账号"),
        centerTitle: true,
        actions: [
          if (widget.showSkip)
            TextButton(
              onPressed: widget.onSkip,
              child: const Text(
                "跳过",
                style: TextStyle(
                  color: MiuiTheme.primaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              controller.reload();
            },
          ),
          TextButton(
            onPressed: () => _completeLogin(),
            child: const Text(
              "已登录点此",
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (_isLoading)
            const Column(
              children: [
                LinearProgressIndicator(
                  color: MiuiTheme.primaryColor,
                  minHeight: 2,
                ),
                Expanded(child: SizedBox()),
              ],
            ),
        ],
      ),
    );
  }
}
