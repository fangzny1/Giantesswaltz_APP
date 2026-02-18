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
  // 只需要传入这几个关键参数，其他的全靠嗅探
  final String targetUrl; // 【新增】完整的回复页面链接
  final String fid;
  final String tid;
  final String userCookies;
  final String baseUrl;

  const ReplyNativePage({
    super.key,
    required this.targetUrl, // 必传
    required this.fid,
    required this.tid,
    required this.userCookies,
    required this.baseUrl,
  });

  @override
  State<ReplyNativePage> createState() => _ReplyNativePageState();
}

class _ReplyNativePageState extends State<ReplyNativePage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isSending = false;
  bool _isUploadingImage = false;
  bool _showSmileyPanel = false;

  WebViewController? _webController;

  final List<String> _uploadedAids = [];

  // 嗅探到的数据
  String? _sniffedUploadUrl;
  Map<String, String> _sniffedUploadParams = {}; // 上传图片用的
  Map<String, String> _sniffedFormParams = {}; // 发帖提交用的 (hidden inputs)
  String? _sniffedSubmitUrl; // 发帖提交的真实 Action URL

  String _debugStatus = "正在分析回复环境...";

  // 常用表情列表
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
          onPageFinished: (url) async {
            // 【核心修复】检测是否是中间跳转页
            final String content =
                await _webController!.runJavaScriptReturningResult(
                      "document.body.innerText",
                    )
                    as String;

            if (content.contains("欢迎您回来") || content.contains("现在将转入")) {
              print("🔄 [Reply] 检测到跳转页，等待自动跳转...");
              // 这种页面通常自带 setTimeout 跳转，我们只需要多等一会儿再次嗅探
              Future.delayed(const Duration(seconds: 2), () {
                _sniffAllSettings();
              });
            } else {
              // 正常页面，开始嗅探
              _sniffAllSettings();
            }
          },
        ),
      );

    _prepareSession();
  }

  Future<void> _prepareSession() async {
    // 1. 设置 Cookie (保持不变)
    if (widget.userCookies.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      // 防止 baseUrl 为空导致解析崩溃
      String safeBase = widget.baseUrl.isNotEmpty
          ? widget.baseUrl
          : "https://giantesswaltz.org/";
      String domain = Uri.parse(safeBase).host;

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

    // 2. 处理 URL (核心修复)
    String urlToLoad = widget.targetUrl;

    // 如果 URL 是空的，尝试用 baseUrl 补救一下（死马当活马医）
    if (urlToLoad.isEmpty) {
      print("⚠️ [Reply] 警告：传入的 targetUrl 为空，尝试自动构造...");
      urlToLoad =
          "${widget.baseUrl}forum.php?mod=post&action=reply&fid=${widget.fid}&tid=${widget.tid}&mobile=no";
    }

    // 如果没有 http 头，自动补全
    if (!urlToLoad.startsWith('http')) {
      // 这里的逻辑是为了防止 "forum.php?..." 这种相对路径导致崩溃
      if (widget.baseUrl.startsWith('http')) {
        // 确保 baseUrl 结尾有 / 且 urlToLoad 开头无 /，或者反之，避免双斜杠或无斜杠
        if (widget.baseUrl.endsWith('/') && urlToLoad.startsWith('/')) {
          urlToLoad = widget.baseUrl + urlToLoad.substring(1);
        } else if (!widget.baseUrl.endsWith('/') &&
            !urlToLoad.startsWith('/')) {
          urlToLoad = "${widget.baseUrl}/$urlToLoad";
        } else {
          urlToLoad = "${widget.baseUrl}$urlToLoad";
        }
      } else {
        urlToLoad = "https://$urlToLoad";
      }
    }

    print("🕵️ [Reply] 后台加载目标页: $urlToLoad");

    try {
      await _webController?.loadRequest(
        Uri.parse(urlToLoad),
        headers: {'Cookie': widget.userCookies},
      );
    } catch (e) {
      print("❌ [Reply] 加载 URL 失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("加载失败: 链接格式错误")));
      }
    }
  }

  // 【核心升级】全能嗅探函数
  Future<void> _sniffAllSettings() async {
    if (_webController == null) return;

    // 如果还没加载完，或者正在重试，给一个视觉反馈
    if (mounted) setState(() => _debugStatus = "正在分析页面结构...");

    try {
      final String result =
          await _webController!.runJavaScriptReturningResult("""
        (function() {
            var info = {
                uploadUrl: '',
                uploadParams: {},
                submitUrl: '',
                formParams: {},
                error: ''
            };

            // --- 任务1: 嗅探表单 (这是最重要的，发帖全靠它) ---
            try {
                var form = document.getElementById('postform');
                if (form) {
                    info.submitUrl = form.action;
                    var inputs = form.getElementsByTagName('input');
                    for (var i = 0; i < inputs.length; i++) {
                        if (inputs[i].type !== 'checkbox' && inputs[i].type !== 'radio' && inputs[i].name) {
                            info.formParams[inputs[i].name] = inputs[i].value;
                        }
                    }
                    var textareas = form.getElementsByTagName('textarea'); // 有些特殊参数在textarea里
                     for (var i = 0; i < textareas.length; i++) {
                        if (textareas[i].name) info.formParams[textareas[i].name] = textareas[i].value;
                    }
                } else {
                    info.error = "未找到postform表单";
                    // 检查是不是需要登录
                    if (document.body.innerText.indexOf('需要登录') > -1) info.error = "需要登录";
                }
            } catch(e) {
                info.error += "|FormErr:" + e.toString();
            }

            // --- 任务2: 嗅探图片上传 (失败了也不影响发帖) ---
            try {
                if (typeof imgUpload !== 'undefined' && imgUpload.settings) {
                    info.uploadUrl = imgUpload.settings.upload_url;
                    info.uploadParams = imgUpload.settings.post_params;
                } else if (typeof upload !== 'undefined' && upload.settings) {
                    info.uploadUrl = upload.settings.upload_url;
                    info.uploadParams = upload.settings.post_params;
                } else {
                    // 暴力查找 hash
                    var hashInput = document.querySelector('input[name="hash"]');
                    var uidInput = document.querySelector('input[name="uid"]');
                    if(hashInput && uidInput) {
                        info.uploadUrl = 'misc.php?mod=swfupload&action=swfupload&operation=upload';
                        info.uploadParams = { hash: hashInput.value, uid: uidInput.value, type: 'image' };
                    }
                }
            } catch(e) {
                // 图片模块报错忽略，不影响主流程
                console.log("Image sniff error: " + e);
            }

            return JSON.stringify(info);
        })();
      """)
              as String;

      String jsonStr = result;
      if (jsonStr.startsWith('"'))
        jsonStr = jsonDecode(jsonStr); // 解包 Flutter 的双引号

      final data = jsonDecode(jsonStr);

      if (mounted) {
        setState(() {
          // 1. 填入数据
          _sniffedUploadUrl = data['uploadUrl'];
          _sniffedUploadParams = Map<String, String>.from(
            data['uploadParams'] ?? {},
          );
          if (!_sniffedUploadParams.containsKey('fid'))
            _sniffedUploadParams['fid'] = widget.fid;

          _sniffedSubmitUrl = data['submitUrl'];
          _sniffedFormParams = Map<String, String>.from(
            data['formParams'] ?? {},
          );

          // 2. 更新状态文字
          String err = data['error'] ?? "";
          if (_sniffedFormParams.isNotEmpty &&
              _sniffedFormParams.containsKey('formhash')) {
            _debugStatus = "回复通道就绪"; // 成功！
          } else if (err.contains("需要登录")) {
            _debugStatus = "Cookie 失效，请重新登录";
          } else {
            _debugStatus = "解析失败，请检查网络或权限";
            // 如果失败，尝试自动重试一次（可能是页面还没渲染完）
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _sniffedFormParams.isEmpty) _sniffAllSettings();
            });
          }
        });
        print(
          "✅ [Reply] 嗅探结果: 表单=${_sniffedFormParams.isNotEmpty}, 上传=${_sniffedUploadParams.isNotEmpty}",
        );
      }
    } catch (e) {
      print("❌ [Reply] 嗅探发生严重错误: $e");
      if (mounted) setState(() => _debugStatus = "初始化异常");
    }
  }

  // ... 图片压缩逻辑 (保持不变) ...
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

  // ... 图片上传逻辑 (微调参数名) ...
  Future<void> _uploadFile(File originalFile) async {
    if (_sniffedUploadParams.isEmpty) {
      _showError("未获取到上传授权，请稍后再试");
      _sniffAllSettings(); // 重试嗅探
      return;
    }
    setState(() => _isUploadingImage = true);
    File fileToUpload = await _compressFile(originalFile);

    // URL 补全
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
      dio.options.headers['Referer'] = widget.targetUrl; // 引用当前页为 Referer

      final formData = FormData();
      _sniffedUploadParams.forEach(
        (k, v) => formData.fields.add(MapEntry(k, v)),
      );
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
          _insertBBCode("[attachimg]$aid[/attachimg]", "");
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

  // ... 插入 BBCode 和 颜色选择器 (保持不变) ...
  void _insertBBCode(String startTag, String endTag) {
    var text = _textController.text;
    var selection = _textController.selection;
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
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
    int newSelectionStart = selection.start + startTag.length;
    int newSelectionEnd = newSelectionStart + selectedText.length;
    _textController.value = TextEditingValue(
      text: newText,
      selection: selectedText.isEmpty
          ? TextSelection.collapsed(offset: newSelectionStart)
          : TextSelection(
              baseOffset: newSelectionStart,
              extentOffset: newSelectionEnd,
            ),
    );
  }

  void _showColorPicker() {
    final List<Map<String, dynamic>> colors = [
      {'name': '红色', 'code': 'Red', 'color': Colors.red},
      {'name': '橙色', 'code': 'Orange', 'color': Colors.orange},
      {'name': '黄色', 'code': 'Yellow', 'color': Colors.yellow[700]},
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

  // 【最终修复版】发送逻辑：使用 jsonEncode 彻底解决特殊字符和换行报错
  Future<void> _sendReply() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;

    // 再次检查参数
    if (_sniffedSubmitUrl == null || _sniffedFormParams.isEmpty) {
      _showError("参数未就绪，正在重新分析...");
      _sniffAllSettings();
      return;
    }

    setState(() => _isSending = true);

    // 1. 超时保护
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isSending) {
        setState(() => _isSending = false);
        _showError("请求超时，请检查网络或重试");
      }
    });

    // 2. 构造 URL
    String url = _sniffedSubmitUrl!;
    if (!url.startsWith("http")) {
      String base = widget.baseUrl;
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      url = url.startsWith('/') ? base + url : "$base/$url";
    }
    // 补全 Discuz 提交标志
    if (!url.contains("inajax=1")) url += "&inajax=1";
    if (!url.contains("replysubmit=yes")) url += "&replysubmit=yes";

    // 3. 【核心修改】构建安全的 JS 代码
    StringBuffer jsBuilder = StringBuffer();
    jsBuilder.writeln("var formData = new FormData();");

    // 遍历所有隐藏字段 (formhash, reppid, noticeauthor, noticetrimstr 等)
    _sniffedFormParams.forEach((k, v) {
      // 排除我们要手动填写的字段
      if (k != 'message' && k != 'subject') {
        // 【关键改动】使用 jsonEncode 自动处理所有转义 (换行、引号、斜杠等)
        // jsonEncode("abc") -> "\"abc\"" (带双引号的字符串)
        // 所以 JS 变成: formData.append('key', "安全的内容");
        String safeKey = jsonEncode(k); // 只有 Key 极特殊时才需要，一般不需要，但保险起见
        String safeValue = jsonEncode(v);
        // 这里的 safeKey 和 safeValue 已经包含了引号，所以外面不用再加引号
        jsBuilder.writeln("formData.append($safeKey, $safeValue);");
      }
    });

    // 手动补充 replysubmit (防止被遗漏)
    jsBuilder.writeln("formData.append('replysubmit', 'yes');");

    // 添加用户输入的内容 (同样使用 jsonEncode 处理换行和特殊符号)
    String safeMessage = jsonEncode(text);
    jsBuilder.writeln("formData.append('message', $safeMessage);");

    jsBuilder.writeln("formData.append('usesig', '1');");

    // 4. 打印生成的脚本 (调试用，发布时可注释)
    // print("🚀 [Reply] 生成的 JS 脚本片段:\n${jsBuilder.toString()}");

    // 5. 执行脚本
    String jsCode =
        """
    (async function() {
        try {
            // 注入表单数据
            ${jsBuilder.toString()}
            
            // 发起请求
            var response = await fetch('$url', { 
                method: 'POST', 
                body: formData, 
                credentials: 'include' 
            });
            
            var text = await response.text();
            
            ReplyChannel.postMessage(JSON.stringify({
                status: response.status, 
                body: text
            }));
            
        } catch (e) { 
            ReplyChannel.postMessage(JSON.stringify({
                error: e.toString()
            })); 
        }
    })();
    """;

    _webController?.runJavaScript(jsCode);
  }

  // ... 结果处理 (保持不变) ...
  void _handleJsMessage(String message) {
    try {
      final data = jsonDecode(message);
      if (data['error'] != null) {
        _showError("发送错误: ${data['error']}");
        setState(() => _isSending = false);
        return;
      }
      String body = data['body'] ?? "";
      // 成功关键词：succeed, 发布成功, 回复主题
      if (body.contains("succeed") ||
          body.contains("发布成功") ||
          body.contains("class=\"alert_right\"")) {
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

  // ... 界面构建 (基本保持不变，只是调用 _pickImage) ...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("回复帖子"),
        actions: [
          TextButton(
            // 只有当：没有在发送中 && 有文字 && 嗅探已完成(表单参数不为空) 时，按钮才可用
            onPressed:
                (_isSending ||
                    _textController.text.trim().isEmpty ||
                    _sniffedFormParams.isEmpty)
                ? null
                : _sendReply,
            child: _isSending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    "发送",
                    // 如果嗅探没完成，文字显示灰色，提示用户在加载
                    style: TextStyle(
                      color: _sniffedFormParams.isEmpty ? Colors.grey : null,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 隐藏的 WebView (干活的主力)
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
                hintText: _sniffedFormParams.isEmpty
                    ? "$_debugStatus..."
                    : (_sniffedFormParams.containsKey('reppid')
                          ? "回复某楼层..."
                          : "回复楼主..."),
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
              ),
              // 【核心修复】加上这句！
              // 每次输入文字时，强制刷新界面，这样 AppBar 上的发送按钮才能变色
              onChanged: (v) => setState(() {}),
              onTap: () {
                if (_showSmileyPanel) setState(() => _showSmileyPanel = false);
              },
            ),
          ),

          if (_isUploadingImage) const LinearProgressIndicator(minHeight: 2),

          _buildToolbar(),

          _buildSmileyPanel(),

          if (_showSmileyPanel)
            SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

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
                if (_showSmileyPanel) FocusScope.of(context).unfocus();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: "上传图片",
            onPressed: _sniffedUploadParams.isEmpty || _isUploadingImage
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

  Widget _buildSmileyPanel() {
    if (!_showSmileyPanel) return const SizedBox.shrink();
    return Container(
      height: 200,
      color: Theme.of(context).colorScheme.surface,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _commonSmilies.length,
        itemBuilder: (context, index) {
          final s = _commonSmilies[index];
          return InkWell(
            onTap: () => _insertBBCode(s, ''),
            child: Center(child: Text(s, style: const TextStyle(fontSize: 18))),
          );
        },
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image != null) _uploadFile(File(image.path));
    } catch (e) {
      _showError("选择图片失败");
    }
  }
}
