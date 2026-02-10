import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/login_page.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'forum_model.dart'; // 访问 kUserAgent 和 currentBaseUrl

class CloudflareSolver {
  /// 弹出验证窗口
  static Future<bool> show(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _CloudflareDialog(),
        ) ??
        false;
  }
}

class _CloudflareDialog extends StatefulWidget {
  @override
  State<_CloudflareDialog> createState() => _CloudflareDialogState();
}

class _CloudflareDialogState extends State<_CloudflareDialog> {
  late final WebViewController _controller;
  bool _isSolved = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent) // 关键：UA 必须与 Dio 保持一致
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            // 检查页面内容，看盾消失没
            final String html =
                await _controller.runJavaScriptReturningResult(
                      "document.documentElement.outerHTML",
                    )
                    as String;

            // 如果页面不再包含 Cloudflare 的关键词，说明过盾了
            if (!html.contains("challenges.cloudflare.com") &&
                !html.contains("Verify you are human") &&
                html.contains("Bvoy_2132_")) {
              // 确保加载到了论坛内容
              _onSolved();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(currentBaseUrl.value));
  }

  Future<void> _onSolved() async {
    if (_isSolved) return;
    _isSolved = true;

    // 1. 抓取 WebView 里的所有 Cookie (包含 cf_clearance 和论坛登录 Cookie)
    final String cookies =
        await _controller.runJavaScriptReturningResult('document.cookie')
            as String;
    String rawCookie = cookies;
    if (rawCookie.startsWith('"'))
      rawCookie = rawCookie.substring(1, rawCookie.length - 1);

    // 2. 持久化到本地，供 HttpService 使用
    final prefs = await SharedPreferences.getInstance();
    String oldCookie = prefs.getString('saved_cookie_string') ?? "";

    // 合并新老 Cookie (借用之前的合并逻辑)
    // 这里简单处理：直接追加或覆盖。由于 cf 盾通常只在乎 cf_clearance
    await prefs.setString('saved_cookie_string', rawCookie);

    if (mounted) {
      Navigator.pop(context, true); // 验证成功，返回 true
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Text("安全验证", style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          children: [
            const Text(
              "请点击下方的验证框（若无显示请稍等）",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("取消"),
        ),
      ],
    );
  }
}
