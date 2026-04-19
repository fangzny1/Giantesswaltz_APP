import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'forum_model.dart';
import 'login_page.dart'; // 访问 kUserAgent

class SecuritySolver {
  /// 修改：增加 targetUrl 参数，哪个链接碎了，我们就去修哪个域名
  static Future<bool> show(
    BuildContext context, {
    required String targetUrl,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _SecurityDialog(targetUrl: targetUrl),
        ) ??
        false;
  }
}

class _SecurityDialog extends StatefulWidget {
  final String targetUrl; // 接收传进来的碎图片地址
  const _SecurityDialog({required this.targetUrl});

  @override
  State<_SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<_SecurityDialog> {
  late final WebViewController _controller;
  bool _isSolved = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            final String cookies =
                await _controller.runJavaScriptReturningResult(
                      'document.cookie',
                    )
                    as String;
            String rawCookie = cookies.replaceAll('"', '');

            // 只要发现了 wssplashchk，不管它是给哪个域名的，我们先把它抓下来
            if (rawCookie.contains("wssplashchk")) {
              print("🎯 [Security] 捕获到关键令牌: $rawCookie");
              _onSolved(rawCookie);
            }
          },
        ),
      )
      // 【核心修复】：直接加载那个碎掉的图片链接
      ..loadRequest(Uri.parse(widget.targetUrl));
  }

  Future<void> _onSolved(String newCookies) async {
    if (_isSolved) return;
    _isSolved = true;

    final prefs = await SharedPreferences.getInstance();
    String oldCookie = prefs.getString('saved_cookie_string') ?? "";

    // 【核心黑科技】：合并新老 Cookie
    // 将 wssplashchk 合并到原来的论坛登录 Cookie 里
    String mergedCookie = mergeCookies(oldCookie, [newCookies]);
    await prefs.setString('saved_cookie_string', mergedCookie);

    print("🔑 [Security] 捕获到安全令牌，已全线同步：$newCookies");

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_moon, color: Color(0xFF61CAB8)),
          SizedBox(width: 8),
          Text("线路安全验证", style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        height: 260,
        width: double.maxFinite,
        child: Column(
          children: [
            const Text(
              "检测到图片服务器防护，请等待转圈结束即可完成修复。",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebViewWidget(controller: _controller),
              ),
            ),
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
