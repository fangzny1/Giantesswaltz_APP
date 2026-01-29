import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'login_page.dart';
import 'offline_manager.dart';

class ReplyNativePage extends StatefulWidget {
  final String tid;
  final String fid;
  final String? pid;
  final String formhash;
  final String? posttime;
  final int minChars;
  final int maxChars;
  final String baseUrl;
  final String userCookies;

  const ReplyNativePage({
    super.key,
    required this.tid,
    required this.fid,
    this.pid,
    required this.formhash,
    this.posttime,
    this.minChars = 0,
    this.maxChars = 0,
    required this.baseUrl,
    required this.userCookies,
  });

  @override
  State<ReplyNativePage> createState() => _ReplyNativePageState();
}

class _ReplyNativePageState extends State<ReplyNativePage> {
  final TextEditingController _textController = TextEditingController();
  bool _isSending = false;

  WebViewController? _webController;

  final List<String> _uploadedAids = [];
  String? _sniffedUploadUrl;
  Map<String, String> _sniffedParams = {};
  String _debugStatus = "正在初始化组件...";

  @override
  void initState() {
    super.initState();

    // 初始化控制器
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..addJavaScriptChannel(
        'ReplyChannel',
        onMessageReceived: (m) => _handleJsMessage(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              _sniffUploadSettings();
            });
          },
        ),
      );

    _prepareSession();
  }

  Future<void> _prepareSession() async {
    if (widget.userCookies.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      String domain = Uri.parse(widget.baseUrl).host;
      List<String> cookieList = widget.userCookies.split(';');
      for (var c in cookieList) {
        if (c.contains('=')) {
          var kv = c.split('=');
          await cookieManager.setCookie(
            WebViewCookie(
              name: kv[0].trim(),
              value: kv.sublist(1).join('=').trim(),
              domain: domain,
              path: '/',
            ),
          );
        }
      }
    }

    String advancedUrl =
        "${widget.baseUrl}forum.php?mod=post&action=reply&fid=${widget.fid}&tid=${widget.tid}&mobile=no";
    await _webController?.loadRequest(
      Uri.parse(advancedUrl),
      headers: {'Cookie': widget.userCookies},
    );
  }

  Future<void> _sniffUploadSettings() async {
    if (_webController == null) return;
    try {
      final String result =
          await _webController!.runJavaScriptReturningResult("""
        (function() {
            try {
                var info = {};
                if (typeof imgUpload !== 'undefined' && imgUpload.settings) {
                    info = { url: imgUpload.settings.upload_url, params: imgUpload.settings.post_params };
                } else if (typeof upload !== 'undefined' && upload.settings) {
                    info = { url: upload.settings.upload_url, params: upload.settings.post_params };
                } else {
                    var hashInput = document.querySelector('input[name="hash"]');
                    var uidInput = document.querySelector('input[name="uid"]');
                    if(hashInput && uidInput) {
                        info = { 
                          url: 'misc.php?mod=swfupload&action=swfupload&operation=upload', 
                          params: { hash: hashInput.value, uid: uidInput.value, type: 'image' } 
                        };
                    }
                }
                if(info.url) return JSON.stringify(info);
            } catch(e) { return "ERROR:" + e.toString(); }
            return null;
        })();
      """)
              as String;

      if (result != "null" && result.isNotEmpty) {
        String jsonStr = result;
        if (jsonStr.startsWith('"')) jsonStr = jsonDecode(jsonStr);
        if (jsonStr.startsWith("ERROR:")) return;

        final data = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _sniffedUploadUrl = data['url'];
            _sniffedParams = Map<String, String>.from(data['params'] ?? {});
            _debugStatus = "可以传图了";
          });
        }
      }
    } catch (e) {
      print("嗅探出错: $e");
    }
  }

  // ... 辅助方法 ...
  Future<File> _compressFile(File file) async {
    final int size = await file.length();
    if (size < 400 * 1024) return file;
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/up_${DateTime.now().millisecondsSinceEpoch}.jpg';
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 75,
      minWidth: 1600,
      minHeight: 1600,
    );
    return result != null ? File(result.path) : file;
  }

  Future<void> _uploadFile(File originalFile) async {
    if (_sniffedParams.isEmpty) return;
    setState(() => _isSending = true);
    File fileToUpload = await _compressFile(originalFile);
    String url = _sniffedUploadUrl ?? "";
    if (!url.startsWith('http')) url = widget.baseUrl + url;
    try {
      final dio = Dio();
      dio.options.headers['Cookie'] = widget.userCookies;
      dio.options.headers['User-Agent'] = kUserAgent;
      final formData = FormData();
      _sniffedParams.forEach((k, v) => formData.fields.add(MapEntry(k, v)));
      if (!_sniffedParams.containsKey('fid'))
        formData.fields.add(MapEntry('fid', widget.fid));
      formData.files.add(
        MapEntry('Filedata', await MultipartFile.fromFile(fileToUpload.path)),
      );
      final response = await dio.post(url, data: formData);
      if (response.statusCode == 200) {
        final body = response.data.toString();
        String? aid;
        if (body.contains("DISCUZUPLOAD")) {
          var parts = body.split('|');
          if (parts.length > 2 && parts[1] == '0') aid = parts[2];
        } else if (RegExp(r'^\d+$').hasMatch(body.trim())) {
          aid = body.trim();
        }
        if (aid != null && aid != "0") {
          _uploadedAids.add(aid);
          _insertTag("[attachimg]$aid[/attachimg]", "");
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("✅ 图片已添加")));
        }
      }
    } catch (e) {
      _showError("上传出错");
    } finally {
      if (fileToUpload.path != originalFile.path) await fileToUpload.delete();
      setState(() => _isSending = false);
    }
  }

  void _insertTag(String s, String e) {
    var text = _textController.text;
    var selection = _textController.selection;
    if (selection.start < 0) {
      _textController.text += "$s$e";
      return;
    }
    var newText = text.replaceRange(
      selection.start,
      selection.end,
      "$s${text.substring(selection.start, selection.end)}$e",
    );
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + s.length),
    );
  }

  Future<void> _sendReply() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    setState(() => _isSending = true);
    String queryParams =
        "mod=post&action=reply&fid=${widget.fid}&tid=${widget.tid}&replysubmit=yes&inajax=1&handlekey=fastpost";
    String url = "${widget.baseUrl}forum.php?$queryParams";
    String escapedMessage = jsonEncode(text);
    escapedMessage = escapedMessage.substring(1, escapedMessage.length - 1);
    String jsCode =
        """
    (async function() {
        try {
            var formData = new FormData();
            formData.append('formhash', '${widget.formhash}');
            formData.append('message', "$escapedMessage");
            formData.append('subject', '');
            formData.append('usesig', '1');
            ${_uploadedAids.map((aid) => "formData.append('attachnew[$aid][description]', '');").join("\n")}
            var response = await fetch('$url', { method: 'POST', body: formData, credentials: 'include' });
            var text = await response.text();
            ReplyChannel.postMessage(JSON.stringify({status: response.status, body: text}));
        } catch (e) { ReplyChannel.postMessage(JSON.stringify({error: e.toString()})); }
    })();
    """;
    _webController?.runJavaScript(jsCode);
  }

  void _handleJsMessage(String message) {
    try {
      final data = jsonDecode(message);
      String body = data['body'] ?? "";
      if (body.contains("succeed") || body.contains("reply_succeed")) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("发布成功！")));
        Navigator.pop(context, true);
      } else {
        String err = "发送失败";
        if (body.contains("<![CDATA[")) {
          RegExp exp = RegExp(
            r'<!\[CDATA\[(.*?)(?:<script|\]\]>)',
            dotAll: true,
          );
          err = exp.firstMatch(body)?.group(1)?.trim() ?? err;
        }
        _showError(err);
      }
    } catch (e) {
      _showError("解析错误");
    }
    setState(() => _isSending = false);
  }

  void _showError(String msg) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("回复帖子")),
      // 解决键盘弹出时挤压底部栏的问题
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // 真正的 WebView 放在 Offstage 中，既不占空间又不影响性能
          Offstage(
            offstage: true,
            child: _webController != null
                ? SizedBox(
                    width: 1,
                    height: 1,
                    child: WebViewWidget(controller: _webController!),
                  )
                : const SizedBox(),
          ),

          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: _sniffedParams.isEmpty ? _debugStatus : "写下你的回复...",
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() {}),
            ),
          ),

          // 底部控制栏
          Container(
            padding: EdgeInsets.only(
              left: 8,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                // 图片按钮 - 使用固定的深蓝色，防止“消失”
                IconButton(
                  icon: Icon(
                    Icons.image_rounded,
                    color: _sniffedParams.isEmpty
                        ? Colors.grey
                        : Colors.blueAccent,
                    size: 28,
                  ),
                  onPressed: _sniffedParams.isEmpty
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                ),

                // 加载提示
                if (_sniffedParams.isEmpty && !_debugStatus.contains("失败"))
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  ),

                const Spacer(),

                // 提交按钮
                FilledButton.icon(
                  onPressed: (_isSending || _textController.text.trim().isEmpty)
                      ? null
                      : _sendReply,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_isSending ? "发送中" : "发表回复"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    if (image != null) _uploadFile(File(image.path));
  }
}
