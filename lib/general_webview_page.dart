import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'login_page.dart';

class GeneralWebViewPage extends StatefulWidget {
  final String url;
  final String title;
  final bool isPrintMode; // 【新增】开关：是否为打印/纯净模式

  const GeneralWebViewPage({
    super.key,
    required this.url,
    required this.title,
    this.isPrintMode = false, // 默认为 false (普通浏览)
  });

  @override
  State<GeneralWebViewPage> createState() => _GeneralWebViewPageState();
}

class _GeneralWebViewPageState extends State<GeneralWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            // 【核心修复】只有在打印模式下，才注入美化去广告脚本
            if (widget.isPrintMode) {
              _injectBeautifyScript();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  // 注入打印版专用 CSS (隐藏无关元素，美化排版)
  void _injectBeautifyScript() {
    const String css = """
      body {
        font-family: 'PingFang SC', 'Microsoft YaHei', sans-serif !important;
        line-height: 1.8 !important;
        color: #333 !important;
        background-color: #fff !important;
        padding: 20px !important;
        max-width: 100% !important;
        margin: 0 !important;
      }
      h1 {
        color: #61CAB8 !important;
        font-size: 24px !important;
        border-bottom: 2px solid #eee;
        padding-bottom: 10px;
        text-align: center;
      }
      /* 隐藏原本的打印按钮、横线、页眉页脚 */
      a[onclick*="window.print"], hr, .noprint {
        display: none !important;
      }
      .t_f, font {
        font-size: 16px !important;
        text-align: justify;
      }
      img {
        max-width: 100% !important;
        height: auto !important;
        border-radius: 8px;
        margin: 10px 0;
      }
    """;

    _controller.runJavaScript("""
      var style = document.createElement('style');
      style.innerHTML = `$css`;
      document.head.appendChild(style);
    """);
  }

  Future<void> _exportToPdf() async {
    try {
      String htmlContent =
          await _controller.runJavaScriptReturningResult(
                "document.documentElement.outerHTML",
              )
              as String;

      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = jsonDecode(htmlContent);
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          return await Printing.convertHtml(
            format: format,
            html: htmlContent,
            baseUrl: widget.url,
          );
        },
        name: 'GW_Document_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("PDF生成失败: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          // 只有打印模式显示 PDF 按钮
          if (widget.isPrintMode)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: "保存PDF",
              onPressed: _exportToPdf,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () async {
              await launchUrl(
                Uri.parse(widget.url),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
