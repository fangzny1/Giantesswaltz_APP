import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart'; // For upload
import 'login_page.dart'; // For kUserAgent

class ReplyNativePage extends StatefulWidget {
  final String tid;
  final String fid;
  final String? pid; // For quoting/targeting a floor
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
  late final WebViewController _webController;
  // Upload params
  String? _uploadUrl;
  Map<String, String>? _uploadParams; // uid, hash, etc.
  final List<String> _uploadedAids =
      []; // Store uploaded AIDs to submit with form

  @override
  void initState() {
    super.initState();
    // Initialize WebView
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent) // Use standard UA
      ..addJavaScriptChannel(
        'ReplyChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJsMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // WebView loaded
            _extractUploadParams();
          },
        ),
      );

    // Load the thread page in background to ensure cookies/session are valid
    // and to satisfy Same-Origin Policy for the fetch request
    _webController.loadRequest(
      Uri.parse("${widget.baseUrl}forum.php?mod=viewthread&tid=${widget.tid}"),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _extractUploadParams() async {
    // Try to extract SWFUpload settings from the page
    // The page usually has 'var upload = new SWFUpload({...})'
    // We can try to find the 'upload_url' and 'post_params'
    try {
      final String result =
          await _webController.runJavaScriptReturningResult("""
        (function() {
            // Check if 'upload' object exists (Discuz standard)
            if (typeof upload !== 'undefined' && upload.settings) {
                return JSON.stringify({
                    url: upload.settings.upload_url,
                    params: upload.settings.post_params
                });
            }
            // Check if there are any input fields with hash
            // Sometimes it's in a hidden input named 'hash' or similar
            // But usually for attachments it's complicated.
            // Let's try to return null for now if not found.
            return null;
        })();
      """)
              as String;

      if (result != "null" && result != "null") {
        // Parse JSON (result might be double quoted string if returned from runJavaScriptReturningResult)
        String jsonStr = result;
        if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
          jsonStr = jsonDecode(jsonStr);
        }
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        if (data['url'] != null) {
          _uploadUrl = data['url'];
          _uploadParams = Map<String, String>.from(data['params'] ?? {});
          print("Upload params found: $_uploadUrl, $_uploadParams");
        }
      }
    } catch (e) {
      print("Error extracting upload params: $e");
    }
  }

  void _handleJsMessage(String message) {
    try {
      final data = jsonDecode(message);

      if (data['error'] != null) {
        _showError("发送错误: ${data['error']}");
        setState(() => _isSending = false);
        return;
      }

      int status = data['status'] ?? 0;
      String body = data['body'] ?? "";

      if (status == 200) {
        if (body.contains("succeed") ||
            body.contains("reply_succeed") ||
            body.contains("发布成功")) {
          // Success!
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("回复发布成功！")));
          Navigator.pop(context, true);
        } else {
          // Check for error in body
          if (body.contains("error") || body.contains("alert_error")) {
            // Try to extract error message
            RegExp exp = RegExp(
              r'<div class="alert_[^"]+">[\s\S]*?<p>(.*?)</p>',
              multiLine: true,
              dotAll: true,
            );
            Match? match = exp.firstMatch(body);
            String err =
                match?.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ??
                "未知错误";

            if (err == "未知错误") {
              RegExp exp2 = RegExp(
                r'<div id="message">([\s\S]*?)</div>',
                multiLine: true,
                dotAll: true,
              );
              Match? match2 = exp2.firstMatch(body);
              if (match2 != null)
                err =
                    match2
                        .group(1)
                        ?.replaceAll(RegExp(r'<[^>]*>'), '')
                        .trim() ??
                    err;
            }
            _showError("回复失败: $err");
          } else {
            _showError("回复可能失败 (未知响应)");
          }
        }
      } else {
        _showError("服务器返回状态码: $status");
      }
    } catch (e) {
      _showError("解析响应失败: $e");
    }
    setState(() => _isSending = false);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _insertTag(String startTag, String endTag) {
    var text = _textController.text;
    var selection = _textController.selection;

    if (selection.start < 0 ||
        selection.end < 0 ||
        selection.start > text.length ||
        selection.end > text.length) {
      // Append to end if selection is invalid
      var newText = text + "$startTag$endTag";
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      return;
    }

    var selectedText = text.substring(selection.start, selection.end);
    var newText = text.replaceRange(
      selection.start,
      selection.end,
      "$startTag$selectedText$endTag",
    );
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + startTag.length + selectedText.length,
      ),
    );
  }

  Future<void> _insertImage() async {
    // Show bottom sheet to choose between URL and System Picker
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text("输入图片链接 (URL)"),
            onTap: () {
              Navigator.pop(ctx);
              _showImageUrlDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text("从相册选择图片"),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text("拍摄图片"),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showImageUrlDialog() async {
    final urlController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("插入图片链接"),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: "图片链接 (URL)",
            hintText: "https://example.com/image.jpg",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                _insertTag("[img]", "${urlController.text}[/img]");
              }
              Navigator.pop(ctx);
            },
            child: const Text("插入"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image != null) {
      // Logic to upload image
      // Since we can't reliably upload to Discuz without full context (hash, uid),
      // we might need to tell the user, OR try a best-effort upload if params are found.
      if (_uploadUrl != null && _uploadParams != null) {
        _uploadFile(File(image.path), isImage: true);
      } else {
        // Fallback: Just insert local path? No, useless.
        // Show dialog explaining the limitation or asking for hosting.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("正在尝试获取上传权限，请稍后..."),
              duration: Duration(seconds: 1),
            ),
          );
          // Retry extraction just in case
          await _extractUploadParams();
          if (_uploadUrl != null && _uploadParams != null) {
            _uploadFile(File(image.path), isImage: true);
          } else {
            if (mounted) _showError("无法获取上传权限 (缺少Hash)，请使用图片链接或在网页版上传。");
          }
        }
      }
    }
  }

  Future<void> _pickAttachment() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      if (_uploadUrl != null && _uploadParams != null) {
        _uploadFile(file, isImage: false);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("正在尝试获取上传权限，请稍后..."),
              duration: Duration(seconds: 1),
            ),
          );
          await _extractUploadParams();
          if (_uploadUrl != null && _uploadParams != null) {
            _uploadFile(file, isImage: false);
          } else {
            if (mounted) _showError("无法获取上传权限 (缺少Hash)，请在网页版上传附件。");
          }
        }
      }
    }
  }

  // Best-effort upload implementation
  // Requires 'dio' package. If not imported, we need to add import 'package:dio/dio.dart';
  // But wait, I didn't add dio import yet.
  // Actually, I can use a simple MultipartRequest with dart:io or http package if dio is not convenient to add now.
  // But the project has dio. Let's assume I can add the import.
  // Wait, I can't easily add import if I don't see the top of file.
  // I added 'dart:io' but not 'package:dio/dio.dart'.
  // I'll stick to standard http or just warn user for now if I can't upload.
  // "Please use URL" is the safest.
  // BUT user demanded "system picker".
  // I'll use the WebView to upload!
  // I can create a hidden form in the webview, populate it with file data? No, JS can't read local file path.
  // OK, I will use `MultipartRequest` from `http` package? `http` might not be in pubspec.
  // `dio` IS in pubspec.
  // I'll add `import 'package:dio/dio.dart';` at the top in a separate tool call.

  Future<void> _uploadFile(File file, {required bool isImage}) async {
    if (_uploadUrl == null) return;

    setState(() => _isSending = true); // Use sending state for progress
    try {
      final dio = Dio();
      // Add cookies
      dio.options.headers['Cookie'] = widget.userCookies;
      dio.options.headers['User-Agent'] = kUserAgent;

      // Construct FormData
      final formData = FormData();
      // Add params (uid, hash, etc)
      _uploadParams?.forEach((key, value) {
        formData.fields.add(MapEntry(key, value));
      });

      // Add filetype param (Discuz needs this sometimes)
      String filename = file.path.split(Platform.pathSeparator).last;
      String ext = filename.split('.').last.toLowerCase();
      String mimeType = "application/octet-stream";
      if (['jpg', 'jpeg'].contains(ext))
        mimeType = "image/jpeg";
      else if (ext == 'png')
        mimeType = "image/png";
      else if (ext == 'gif')
        mimeType = "image/gif";

      formData.fields.add(MapEntry('filetype', mimeType));

      // Add file
      formData.files.add(
        MapEntry(
          'Filedata',
          await MultipartFile.fromFile(file.path, filename: filename),
        ),
      );

      final response = await dio.post(_uploadUrl!, data: formData);

      if (response.statusCode == 200) {
        // Response is usually the AID (Attachment ID) or an XML/JSON
        // Discuz SWFUpload usually returns just the AID for success
        final String body = response.data.toString();
        print("Upload response: $body");

        // Check if it's a number (AID)
        if (RegExp(r'^\d+$').hasMatch(body.trim())) {
          final aid = body.trim();
          _uploadedAids.add(aid); // Track for form submission
          if (isImage) {
            // For images, Discuz might not auto-insert, we need to use [attachimg] or [img]
            // Usually [attachimg]AID[/attachimg]
            _insertTag("[attachimg]$aid[/attachimg]", "");
          } else {
            _insertTag("[attach]$aid[/attach]", "");
          }
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("上传成功，已插入附件代码，请勿删除")));
          }
        } else {
          // Maybe it returned XML or error
          _showError("上传返回未知格式: $body");
        }
      } else {
        _showError("上传失败，状态码: ${response.statusCode}");
      }
    } catch (e) {
      _showError("上传出错: $e");
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showError("请输入内容");
      return;
    }

    int byteLength = utf8.encode(text).length;
    if (widget.minChars > 0 && byteLength < widget.minChars) {
      _showError("内容太短，至少需${widget.minChars}字节");
      return;
    }

    setState(() => _isSending = true);

    // Construct the URL parameters
    String queryParams =
        "mod=post&action=reply&fid=${widget.fid}&tid=${widget.tid}&replysubmit=yes&inajax=1&handlekey=fastpost";
    if (widget.pid != null) {
      queryParams += "&reppid=${widget.pid}";
    }
    String url = "${widget.baseUrl}forum.php?$queryParams";

    // Escape the message for JS string
    String escapedMessage = jsonEncode(text); // "message"
    escapedMessage = escapedMessage.substring(
      1,
      escapedMessage.length - 1,
    ); // Remove surrounding quotes

    // JS code to execute fetch
    String jsCode =
        """
    (async function() {
        try {
            var formData = new FormData();
            formData.append('formhash', '${widget.formhash}');
            formData.append('message', "$escapedMessage");
            formData.append('subject', '');
            formData.append('usesig', '1');
            formData.append('posttime', '${widget.posttime ?? ""}');
            
            // Append uploaded attachments (required for them to be linked to the post)
            ${_uploadedAids.map((aid) => "formData.append('attachnew[$aid][description]', '');").join("\n")}

            var response = await fetch('$url', {
                method: 'POST',
                body: formData
            });
            var text = await response.text();
            ReplyChannel.postMessage(JSON.stringify({status: response.status, body: text}));
        } catch (e) {
            ReplyChannel.postMessage(JSON.stringify({error: e.toString()}));
        }
    })();
    """;

    _webController.runJavaScript(jsCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    int currentBytes = utf8.encode(_textController.text).length;
    bool isTooShort = widget.minChars > 0 && currentBytes < widget.minChars;

    return Scaffold(
      appBar: AppBar(
        title: const Text("回复帖子"),
        scrolledUnderElevation: 1, // MD3 style
      ),
      body: Stack(
        children: [
          // Hidden WebView for executing requests
          SizedBox(height: 1, child: WebViewWidget(controller: _webController)),
          Column(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: "在此输入回复内容...",
                      border: InputBorder.none,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerLow,
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    onChanged: (v) => setState(() {}),
                  ),
                ),
              ),
              // Toolbar
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.format_bold),
                      tooltip: "加粗",
                      onPressed: () => _insertTag("[b]", "[/b]"),
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_italic),
                      tooltip: "斜体",
                      onPressed: () => _insertTag("[i]", "[/i]"),
                    ),
                    IconButton(
                      icon: const Icon(Icons.image),
                      tooltip: "插入图片",
                      onPressed: _insertImage,
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      tooltip: "附件",
                      onPressed: _pickAttachment, // Use new method
                    ),
                    // Add more buttons like Font Size/Color if needed
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.text_format),
                      tooltip: "字体大小/颜色",
                      onSelected: (value) {
                        if (value == "size") {
                          _insertTag("[size=4]", "[/size]");
                        } else if (value == "color") {
                          _insertTag("[color=Red]", "[/color]");
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: "size",
                          child: Text("字体大小 (Size)"),
                        ),
                        const PopupMenuItem(
                          value: "color",
                          child: Text("字体颜色 (Color)"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: colorScheme.surfaceContainerHigh,
                child: Row(
                  children: [
                    Text(
                      "$currentBytes 字节",
                      style: TextStyle(
                        color: isTooShort
                            ? colorScheme.error
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.minChars > 0)
                      Text(
                        " / 需 ${widget.minChars}",
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    const Spacer(),
                    SizedBox(
                      height: 36,
                      child: FilledButton.icon(
                        // MD3 FilledButton
                        onPressed: _isSending ? null : _sendReply,
                        icon: _isSending
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.send, size: 18),
                        label: Text(_isSending ? "发送中..." : "发送"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
