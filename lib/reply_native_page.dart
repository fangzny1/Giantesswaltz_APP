import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'login_page.dart'; // 引用 kUserAgent

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
  final FocusNode _focusNode = FocusNode(); // 新增 FocusNode 用于控制光标

  bool _isSending = false;
  bool _isUploadingImage = false;
  bool _showSmileyPanel = false; // 控制表情面板显示

  WebViewController? _webController;

  final List<String> _uploadedAids = [];
  String? _sniffedUploadUrl;
  Map<String, String> _sniffedParams = {};
  String _debugStatus = "正在初始化环境...";

  // Discuz 常用表情映射 (需要根据论坛实际情况调整，这里是通用示例)
  final List<String> _commonSmilies = [
    ':)',
    ':(',
    ':D',
    ":'(",
    ':@',
    ':o',
    ':P',
    ':\$',
    ';P',
    ':L',
    ':Q',
    ':lol',
    ':loveliness:',
    ':funk:',
    ':curse:',
    ':dizzy:',
    ':shutup:',
    ':sleepy:',
    ':hug:',
    ':victory:',
    ':time:',
    ':kiss:',
    ':handshake',
    ':call:',
  ];

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
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
            // 页面加载完，先检查有没有报错（比如主题关闭），再嗅探上传参数
            Future.delayed(const Duration(milliseconds: 800), () async {
              bool hasError = await _checkPageError();
              if (!hasError) {
                _sniffUploadSettings();
              }
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

    print("🕵️ [Reply] 后台加载: $advancedUrl");

    await _webController?.loadRequest(
      Uri.parse(advancedUrl),
      headers: {'Cookie': widget.userCookies},
    );
  }

  // 【新增】检测页面是否包含“主题自动关闭”等错误提示
  Future<bool> _checkPageError() async {
    if (_webController == null) return false;
    try {
      // 检测 id="messagetext" 且 class="alert_error" 的元素
      final String result =
          await _webController!.runJavaScriptReturningResult("""
        (function() {
            var errorNode = document.querySelector('#messagetext.alert_error p');
            if (errorNode) {
                return errorNode.innerText;
            }
            // 有些模板可能是 .alert_info 或其他结构，这里可以补充检测
            var alertInfo = document.querySelector('.alert_info p');
            if (alertInfo && alertInfo.innerText.indexOf('关闭') !== -1) {
                 return alertInfo.innerText;
            }
            return "null";
        })();
      """)
              as String;

      String msg = result;
      if (msg.startsWith('"') && msg.endsWith('"')) {
        msg = msg.substring(1, msg.length - 1); // 去引号
        // 处理转义字符
        msg = msg.replaceAll('\\u003C', '<').replaceAll('\\"', '"');
      }

      if (msg != "null" && msg.isNotEmpty) {
        print("🚨 [Reply] 检测到发帖限制: $msg");
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text("无法回复"),
              content: Text(msg),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx); // 关弹窗
                    Navigator.pop(context); // 关页面
                  },
                  child: const Text("返回"),
                ),
              ],
            ),
          );
        }
        return true; // 发现错误
      }
    } catch (e) {
      print("检查页面错误时异常: $e");
    }
    return false; // 无错误
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
                return "null";
            } catch(e) { return "ERROR:" + e.toString(); }
        })();
      """)
              as String;

      if (result != "null" &&
          result != '"null"' &&
          !result.startsWith('"ERROR')) {
        String jsonStr = result;
        if (jsonStr.startsWith('"')) jsonStr = jsonDecode(jsonStr);
        final data = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _sniffedUploadUrl = data['url'];
            _sniffedParams = Map<String, String>.from(data['params'] ?? {});
            if (!_sniffedParams.containsKey('fid'))
              _sniffedParams['fid'] = widget.fid;
            _debugStatus = "准备就绪";
          });
        }
      } else {
        if (mounted) setState(() => _debugStatus = "未获取到上传权限 (可能需登录)");
      }
    } catch (e) {
      print("嗅探出错: $e");
    }
  }

  // ... (压缩和上传代码保持不变) ...
  Future<File> _compressFile(File file) async {
    final int size = await file.length();
    if (size < 500 * 1024) return file;
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/up_${DateTime.now().millisecondsSinceEpoch}.jpg';
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 80,
      minWidth: 1920,
      minHeight: 1920,
    );
    return result != null ? File(result.path) : file;
  }

  Future<void> _uploadFile(File originalFile) async {
    if (_sniffedParams.isEmpty) {
      _showError("未获取到上传授权，请稍后再试");
      _sniffUploadSettings();
      return;
    }
    setState(() => _isUploadingImage = true);
    File fileToUpload = await _compressFile(originalFile);
    String url = _sniffedUploadUrl ?? "";
    if (!url.startsWith('http')) {
      String base = widget.baseUrl;
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      url = url.startsWith('/') ? base + url : "$base/$url";
    }

    try {
      final dio = Dio();
      dio.options.headers['Cookie'] = widget.userCookies;
      dio.options.headers['User-Agent'] = kUserAgent;
      dio.options.headers['Referer'] =
          "${widget.baseUrl}forum.php?mod=post&action=reply&fid=${widget.fid}&tid=${widget.tid}";

      final formData = FormData();
      _sniffedParams.forEach((k, v) => formData.fields.add(MapEntry(k, v)));
      formData.files.add(
        MapEntry(
          'Filedata',
          await MultipartFile.fromFile(
            fileToUpload.path,
            filename: "upload.jpg",
          ),
        ),
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
          _insertBBCode("[attachimg]$aid[/attachimg]", ""); // 使用新的插入方法
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("✅ 图片已添加")));
        } else {
          _showError("上传失败: $body");
        }
      }
    } catch (e) {
      _showError("上传出错: 网络问题");
    } finally {
      if (fileToUpload.path != originalFile.path) {
        try {
          await fileToUpload.delete();
        } catch (_) {}
      }
      setState(() => _isUploadingImage = false);
    }
  }

  // 【新增】智能插入 BBCode
  void _insertBBCode(String startTag, String endTag) {
    var text = _textController.text;
    var selection = _textController.selection;

    // 如果没有焦点，获取焦点
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    // 如果没有选区，直接插入到最后或者光标处
    if (selection.start < 0) {
      String newText = text + startTag + endTag;
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: newText.length - endTag.length,
        ),
      );
      return;
    }

    String selectedText = text.substring(selection.start, selection.end);
    String newText = text.replaceRange(
      selection.start,
      selection.end,
      "$startTag$selectedText$endTag",
    );

    // 计算新的光标位置
    int newSelectionStart = selection.start + startTag.length;
    int newSelectionEnd = newSelectionStart + selectedText.length;

    _textController.value = TextEditingValue(
      text: newText,
      // 如果之前选中了文字，保持选中状态；没选中则光标在标签中间
      selection: selectedText.isEmpty
          ? TextSelection.collapsed(offset: newSelectionStart)
          : TextSelection(
              baseOffset: newSelectionStart,
              extentOffset: newSelectionEnd,
            ),
    );
  }

  // 【新增】显示颜色选择器
  void _showColorPicker() {
    final List<Map<String, dynamic>> colors = [
      {'name': '红色', 'code': 'Red', 'color': Colors.red},
      {'name': '橙色', 'code': 'Orange', 'color': Colors.orange},
      {
        'name': '黄色',
        'code': 'Yellow',
        'color': Colors.yellow[700],
      }, // 深一点的黄以便看清
      {'name': '绿色', 'code': 'Green', 'color': Colors.green},
      {'name': '青色', 'code': 'Cyan', 'color': Colors.cyan},
      {'name': '蓝色', 'code': 'Blue', 'color': Colors.blue},
      {'name': '紫色', 'code': 'Purple', 'color': Colors.purple},
      {'name': '粉色', 'code': 'Pink', 'color': Colors.pink},
      {'name': '灰色', 'code': 'Gray', 'color': Colors.grey},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("选择文字颜色"),
        children: colors
            .map(
              (c) => SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(ctx);
                  _insertBBCode('[color=${c['code']}]', '[/color]');
                },
                child: Row(
                  children: [
                    Container(width: 20, height: 20, color: c['color']),
                    const SizedBox(width: 10),
                    Text(c['name']),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ... (发送回复相关代码保持不变) ...
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
            
            var response = await fetch('$url', { 
                method: 'POST', 
                body: formData, 
                credentials: 'include' 
            });
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
      if (data['error'] != null) {
        _showError("发送错误: ${data['error']}");
        setState(() => _isSending = false);
        return;
      }
      String body = data['body'] ?? "";
      if (body.contains("succeed") ||
          body.contains("reply_succeed") ||
          body.contains("发布成功")) {
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
          var match = exp.firstMatch(body);
          if (match != null) err = match.group(1)?.trim() ?? err;
        } else if (body.contains("errorhandle_")) {
          RegExp exp = RegExp(r"errorhandle_\w+\('([^']+)'", dotAll: true);
          var match = exp.firstMatch(body);
          if (match != null) err = match.group(1) ?? err;
        }
        _showError(err);
      }
    } catch (e) {
      _showError("解析响应错误");
    }
    setState(() => _isSending = false);
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 【新增】富文本工具栏组件
  Widget _buildToolbar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          IconButton(
            icon: const Icon(Icons.format_bold),
            tooltip: "加粗",
            onPressed: () => _insertBBCode('[b]', '[/b]'),
          ),
          IconButton(
            icon: const Icon(Icons.format_italic),
            tooltip: "斜体",
            onPressed: () => _insertBBCode('[i]', '[/i]'),
          ),
          IconButton(
            icon: const Icon(Icons.format_underlined),
            tooltip: "下划线",
            onPressed: () => _insertBBCode('[u]', '[/u]'),
          ),
          IconButton(
            icon: const Icon(Icons.format_color_text),
            tooltip: "文字颜色",
            onPressed: _showColorPicker,
          ),
          const VerticalDivider(width: 8, indent: 8, endIndent: 8),
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined),
            tooltip: "表情",
            color: _showSmileyPanel ? Colors.blue : null,
            onPressed: () {
              setState(() {
                _showSmileyPanel = !_showSmileyPanel;
                if (_showSmileyPanel) {
                  FocusScope.of(context).unfocus(); // 收起键盘
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: "上传图片",
            onPressed: _sniffedParams.isEmpty || _isUploadingImage
                ? null
                : () => _pickImage(ImageSource.gallery),
          ),
          const VerticalDivider(width: 8, indent: 8, endIndent: 8),
          IconButton(
            icon: const Icon(Icons.format_quote),
            tooltip: "引用",
            onPressed: () => _insertBBCode('\n[quote]', '[/quote]\n'),
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: "代码",
            onPressed: () => _insertBBCode('\n[code]', '[/code]\n'),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: "链接",
            onPressed: () => _insertBBCode('[url]', '[/url]'),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined),
            tooltip: "隐藏内容",
            onPressed: () => _insertBBCode('[hide]', '[/hide]'),
          ),
        ],
      ),
    );
  }

  // 【新增】表情面板
  Widget _buildSmileyPanel() {
    if (!_showSmileyPanel) return const SizedBox.shrink();
    return Container(
      height: 200,
      color: Theme.of(context).colorScheme.surface,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, // 每行显示数量
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _commonSmilies.length,
        itemBuilder: (context, index) {
          final s = _commonSmilies[index];
          return InkWell(
            onTap: () => _insertBBCode(s, ''),
            child: Center(
              child: Text(
                s,
                style: const TextStyle(fontSize: 18),
              ), // 这里展示的是代码，如果服务器有图片API最好
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("回复帖子"),
        actions: [
          // 发送按钮移到这里也行，或者保留在下面
          TextButton(
            onPressed: (_isSending || _textController.text.trim().isEmpty)
                ? null
                : _sendReply,
            child: _isSending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("发送"),
          ),
        ],
      ),
      body: Column(
        children: [
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
              focusNode: _focusNode,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: _sniffedParams.isEmpty
                    ? "$_debugStatus..."
                    : "支持 BBCode 排版...",
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
              ),
              onTap: () {
                if (_showSmileyPanel) {
                  setState(() => _showSmileyPanel = false);
                }
              },
            ),
          ),

          // 图片上传进度条
          if (_isUploadingImage) const LinearProgressIndicator(minHeight: 2),

          // 工具栏
          _buildToolbar(),

          // 表情面板 (放在键盘位置)
          _buildSmileyPanel(),

          // 如果显示表情面板，需要占位符防止被底部 Home 条遮挡
          if (_showSmileyPanel)
            SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image != null) {
        _uploadFile(File(image.path));
      }
    } catch (e) {
      _showError("选择图片失败");
    }
  }
}
