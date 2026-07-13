import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'login_page.dart'; // kUserAgent
class NewThreadPage extends StatefulWidget {
  final String fid;
  final String baseUrl;

  const NewThreadPage({super.key, required this.fid, required this.baseUrl});

  @override
  State<NewThreadPage> createState() => _NewThreadPageState();
}

class _NewThreadPageState extends State<NewThreadPage> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isSending = false;
  bool _isUploadingImage = false;
  bool _showSmileyPanel = false;

  WebViewController? _webController;
  String? _sniffedSubmitUrl;
  Map<String, String> _sniffedFormParams = {};
  String? _sniffedUploadUrl;
  Map<String, String> _sniffedUploadParams = {};
  String? _sniffedAttachUrl; // 附件上传 URL（无 type=image）
  Map<String, String> _sniffedAttachParams = {};
  List<Map<String, String>> _unusedAttachments = [];

  // typeid 分类支持
  List<Map<String, String>> _typeidOptions = [];
  String? _selectedTypeid;

  final List<String> _uploadedAids = [];
  String _debugStatus = "正在分析发帖环境...";

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

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      )
      ..addJavaScriptChannel(
        'PostChannel',
        onMessageReceived: (m) => _handleJsMessage(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            final content =
                await _webController!.runJavaScriptReturningResult(
                      "document.body.innerText",
                    )
                    as String;
            if (content.contains("欢迎您回来") || content.contains("现在将转入")) {
              Future.delayed(const Duration(seconds: 2), _sniffForm);
            } else {
              _sniffForm();
            }
          },
        ),
      );
    _prepareSession();
  }

  Future<void> _prepareSession() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString('saved_cookie_string') ?? "";
    if (cookie.isNotEmpty) {
      final mgr = WebViewCookieManager();
      final domain = Uri.parse(widget.baseUrl).host;
      for (var c in cookie.split(';')) {
        if (!c.contains('=')) continue;
        final kv = c.split('=');
        await mgr.setCookie(
          WebViewCookie(
            name: kv[0].trim(),
            value: kv.sublist(1).join('=').trim(),
            domain: domain,
            path: '/',
          ),
        );
      }
    }
    final url =
        "${widget.baseUrl}forum.php?mod=post&action=newthread&fid=${widget.fid}&mobile=no";
    try {
      await _webController?.loadRequest(
        Uri.parse(url),
        headers: {'Cookie': cookie},
      );
    } catch (e) {
      print("❌ [NewThread] 加载失败: $e");
    }
  }

  Future<void> _sniffForm() async {
    if (_webController == null) return;
    if (mounted) setState(() => _debugStatus = "正在分析页面结构...");
    try {
      final result =
          await _webController!.runJavaScriptReturningResult("""
        (function() {
          var info = { submitUrl: '', formParams: {}, uploadUrl: '', uploadParams: {}, attachUrl: '', attachParams: {}, typeidOptions: [], unusedAttachments: [], error: '' };
          try {
            var form = document.getElementById('postform');
            if (form) {
              info.submitUrl = form.action;
              var inputs = form.getElementsByTagName('input');
              for (var i = 0; i < inputs.length; i++) {
                if (inputs[i].type !== 'checkbox' && inputs[i].type !== 'radio' && inputs[i].name)
                  info.formParams[inputs[i].name] = inputs[i].value;
              }
              var textareas = form.getElementsByTagName('textarea');
              for (var i = 0; i < textareas.length; i++) {
                if (textareas[i].name) info.formParams[textareas[i].name] = textareas[i].value;
              }
              // 捕获 select 元素 (如 typeid 分类)
              var selects = form.getElementsByTagName('select');
              for (var i = 0; i < selects.length; i++) {
                if (selects[i].name) {
                  info.formParams[selects[i].name] = selects[i].value;
                  // 部分模板的 typeid 选项在独立的菜单里
                  if (selects[i].name === 'typeid') {
                    var opts = selects[i].getElementsByTagName('option');
                    for (var j = 0; j < opts.length; j++) {
                      if (opts[j].value) {
                        info.typeidOptions.push({value: opts[j].value, label: opts[j].text});
                      }
                    }
                    // 如果 select 里没选项，从自定义菜单抓
                    if (info.typeidOptions.length <= 1) {
                      var menu = document.getElementById('typeid_ctrl_menu');
                      if (menu) {
                        var items = menu.querySelectorAll('li');
                        var currentVal = selects[i].value;
                        var currentIdx = -1;
                        for (var m = 0; m < items.length; m++) {
                          if (items[m].className.indexOf('current') > -1) { currentIdx = m; break; }
                        }
                        // 用 offset 推算每个 option 的值
                        var offset = currentIdx > 0 ? parseInt(currentVal) - currentIdx : 0;
                        for (var m = 0; m < items.length; m++) {
                          var label = items[m].textContent.trim();
                          if (label && label !== '选择主题分类') {
                            info.typeidOptions.push({value: String(offset + m), label: label});
                          }
                        }
                      }
                    }
                  }
                }
              }
            } else {
              info.error = "未找到postform表单";
              // 检测权限错误
              var msgText = document.getElementById('messagetext');
              if (msgText) info.error = msgText.innerText.trim();
            }
          } catch(e) { info.error += "|Err:" + e.toString(); }
          try {
            if (typeof imgUpload !== 'undefined' && imgUpload.settings) {
              info.uploadUrl = imgUpload.settings.upload_url;
              info.uploadParams = imgUpload.settings.post_params;
            } else if (typeof upload !== 'undefined' && upload.settings) {
              info.uploadUrl = upload.settings.upload_url;
              info.uploadParams = upload.settings.post_params;
            } else {
              var hashInput = document.querySelector('input[name="hash"]');
              var uidInput = document.querySelector('input[name="uid"]');
              if (hashInput && uidInput) {
                info.uploadUrl = 'misc.php?mod=swfupload&action=swfupload&operation=upload';
                info.uploadParams = { hash: hashInput.value, uid: uidInput.value, type: 'image' };
              }
            }
            // 附件上传（无 type=image，用于 doc/pdf/zip 等）
            var attachForm = document.getElementById('attachform');
            if (attachForm) {
              info.attachUrl = attachForm.action;
              var attInputs = attachForm.getElementsByTagName('input');
              for (var i = 0; i < attInputs.length; i++) {
                if (attInputs[i].name) info.attachParams[attInputs[i].name] = attInputs[i].value;
              }
            }
            if (!info.attachUrl) {
              // 从 attachform_1 后备获取
              var attachForm1 = document.getElementById('attachform_1');
              if (attachForm1) {
                info.attachUrl = attachForm1.action;
                var attInputs1 = attachForm1.getElementsByTagName('input');
                for (var i = 0; i < attInputs1.length; i++) {
                  if (attInputs1[i].name) info.attachParams[attInputs1[i].name] = attInputs1[i].value;
                }
              }
            }
            // 未使用的附件
            try {
              var unusedList = document.getElementById('unusedlist_attach');
              if (unusedList) {
                var checks = unusedList.querySelectorAll('input[name="unused[]"]');
                for (var i = 0; i < checks.length; i++) {
                  if (checks[i].value) {
                    var label = unusedList.querySelector('label[for="' + checks[i].id + '"]');
                    var title = label ? label.textContent.trim() : checks[i].value;
                    info.unusedAttachments.push({aid: checks[i].value, name: title});
                  }
                }
              }
            } catch(e) {}
          } catch(e) {}
          return JSON.stringify(info);
        })();
      """)
              as String;
      var jsonStr = result;
      if (jsonStr.startsWith('"')) jsonStr = jsonDecode(jsonStr);
      final data = jsonDecode(jsonStr);
      if (mounted) {
        setState(() {
          _sniffedSubmitUrl = data['submitUrl'];
          _sniffedFormParams = Map<String, String>.from(
            data['formParams'] ?? {},
          );
          _sniffedUploadUrl = data['uploadUrl'];
          _sniffedUploadParams = Map<String, String>.from(
            data['uploadParams'] ?? {},
          );
          if (!_sniffedUploadParams.containsKey('fid'))
            _sniffedUploadParams['fid'] = widget.fid;

          _sniffedAttachUrl = data['attachUrl'];
          _sniffedAttachParams = Map<String, String>.from(
            data['attachParams'] ?? {},
          );
          if (!_sniffedAttachParams.containsKey('fid'))
            _sniffedAttachParams['fid'] = widget.fid;

          // 未使用的附件
          final rawUnused = data['unusedAttachments'];
          if (rawUnused is List && rawUnused.isNotEmpty) {
            _unusedAttachments = rawUnused
                .map((o) => Map<String, String>.from(o as Map))
                .toList();
          } else {
            _unusedAttachments = [];
          }

          final err = data['error'] ?? "";

          // 解析 typeid 分类选项
          final rawOptions = data['typeidOptions'];
          if (rawOptions is List && rawOptions.isNotEmpty) {
            _typeidOptions = rawOptions
                .map((o) => Map<String, String>.from(o as Map))
                .toList();
            // 默认选中第一个有值的选项
            if (_selectedTypeid == null && _typeidOptions.isNotEmpty) {
              _selectedTypeid = _typeidOptions.first['value'];
            }
          }

          if (_sniffedFormParams.containsKey('formhash'))
            _debugStatus = "就绪";
          else if (err.contains("没有权限"))
            _debugStatus = "此板块无权发帖";
          else
            _debugStatus = "解析失败，请检查登录状态";
        });
      }
    } catch (e) {
      print("❌ [NewThread] 嗅探失败: $e");
    }
  }

  // ====== 图片上传 ======
  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(source: source);
      if (image != null) _uploadFile(File(image.path));
    } catch (_) {
      _showMsg("选择图片失败");
    }
  }

  Future<File> _compressFile(File file) async {
    final size = await file.length();
    if (size < 500 * 1024) return file;
    final dir = await getTemporaryDirectory();
    final target =
        '${dir.path}/up_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      target,
      quality: 80,
      minWidth: 1920,
      minHeight: 1920,
    );
    return result != null ? File(result.path) : file;
  }

  Future<void> _uploadFile(File originalFile) async {
    if (!_sniffedFormParams.containsKey('formhash')) {
      _showMsg("未获取上传授权");
      return;
    }
    setState(() => _isUploadingImage = true);
    final file = await _compressFile(originalFile);
    var url = _sniffedUploadUrl ?? "";
    if (!url.startsWith('http')) {
      final base = widget.baseUrl.endsWith('/')
          ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
          : widget.baseUrl;
      url = url.startsWith('/') ? base + url : "$base/$url";
    }
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString('saved_cookie_string') ?? "";
    try {
      final dio = Dio();
      dio.options.headers = {
        'Cookie': cookie,
        'User-Agent': kUserAgent,
        'Referer': widget.baseUrl,
      };
      final fd = FormData();
      _sniffedUploadParams.forEach((k, v) => fd.fields.add(MapEntry(k, v)));
      fd.files.add(
        MapEntry(
          'Filedata',
          await MultipartFile.fromFile(file.path, filename: "upload.jpg"),
        ),
      );
      final resp = await dio.post(url, data: fd);
      if (resp.statusCode == 200) {
        final body = resp.data.toString();
        String? aid;
        if (body.contains("DISCUZUPLOAD")) {
          final parts = body.split('|');
          if (parts.length > 2 && parts[1] == '0') aid = parts[2];
        } else if (RegExp(r'^\d+$').hasMatch(body.trim())) {
          aid = body.trim();
        }
        if (aid != null && aid != "0") {
          _uploadedAids.add(aid);
          // 【修复】告诉 Discuz 这个 aid 属于当前帖子
          _sniffedFormParams['attachnew[$aid]'] = '1';
          _insertBBCode("[attachimg]$aid[/attachimg]", "");
          if (mounted) _showMsg("✅ 图片已添加");
        } else {
          _showMsg("上传失败: $body");
        }
      }
    } catch (e) {
      _showMsg("上传出错: $e");
    } finally {
      if (file.path != originalFile.path)
        try {
          await file.delete();
        } catch (_) {}
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // ====== TXT 导入 ======
  Future<void> _importTxtFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      print(
        "📂 [TXT导入] 文件: ${picked.name} 路径: ${picked.path} 大小: ${picked.size}",
      );
      String content = utf8.decode(
        picked.bytes ?? await File(picked.path!).readAsBytes(),
      );

      // 简单 MD→BBCode 转换
      content = content
          .replaceAllMapped(
            RegExp(r'^#{6}\s+(.*)$', multiLine: true),
            (m) => '[size=1]${m[1]}[/size]',
          )
          .replaceAllMapped(
            RegExp(r'^#{5}\s+(.*)$', multiLine: true),
            (m) => '[size=2]${m[1]}[/size]',
          )
          .replaceAllMapped(
            RegExp(r'^#{4}\s+(.*)$', multiLine: true),
            (m) => '[size=2]${m[1]}[/size]',
          )
          .replaceAllMapped(
            RegExp(r'^#{3}\s+(.*)$', multiLine: true),
            (m) => '[size=3]${m[1]}[/size]',
          )
          .replaceAllMapped(
            RegExp(r'^#{2}\s+(.*)$', multiLine: true),
            (m) => '[size=4]${m[1]}[/size]',
          )
          .replaceAllMapped(
            RegExp(r'^#\s+(.*)$', multiLine: true),
            (m) => '[size=5]${m[1]}[/size]',
          )
          .replaceAllMapped(
            RegExp(r'\*\*(.+?)\*\*', dotAll: true),
            (m) => '[b]${m[1]}[/b]',
          )
          .replaceAllMapped(
            RegExp(r'\*(.+?)\*', dotAll: true),
            (m) => '[i]${m[1]}[/i]',
          )
          .replaceAllMapped(
            RegExp(r'```([\s\S]*?)```', dotAll: true),
            (m) => '[code]${m[1]}[/code]',
          );

      // 检查字数
      const maxLen = 50000;
      if (content.length <= maxLen) {
        _messageController.text = content;
        if (mounted) _showMsg("✅ 已导入 ${content.length} 字");
        return;
      }

      // 超长 → 弹窗选分段
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("文件过长"),
          content: Text("共 ${content.length} 字，单帖建议不超过 $maxLen 字。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'insert'),
              child: const Text("直接导入"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'split'),
              child: const Text("分段导入"),
            ),
          ],
        ),
      );
      if (action == null || action == 'cancel') return;

      if (action == 'insert') {
        _messageController.text = content;
        _showMsg("⚠️ 已导入 $maxLen+ 字，发布时可能超限");
      } else if (action == 'split') {
        // 分段：每段 maxLen 字，先导入第一段，其余暂存剪贴板
        _messageController.text = content.substring(0, maxLen);
        await Clipboard.setData(ClipboardData(text: content.substring(maxLen)));
        if (mounted) _showMsg("✅ 已导入第 1 段($maxLen 字)，其余已复制到剪贴板");
      }
    } catch (e) {
      _showMsg("导入失败: $e");
    }
  }

  // ====== 通用附件上传 ======
  Future<void> _uploadAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      // 直接复用图片上传逻辑，只是 BBCode 不同
      await _uploadFileWithBBCode(file, '[attach]', '[/attach]');
    } catch (e) {
      _showMsg("选择文件失败: $e");
    }
  }

  /// 上传文件并用指定 BBCode 标签包裹 aid
  Future<void> _uploadFileWithBBCode(
    File file,
    String openTag,
    String closeTag,
  ) async {
    if (!_sniffedFormParams.containsKey('formhash')) {
      _showMsg("未获取上传授权");
      return;
    }
    setState(() => _isUploadingImage = true);
    final compressed = await _compressFile(file);
    // 附件走附件上传通道，图片走图片上传通道
    final bool isAttach = openTag.contains('attach]');
    final urlBase = isAttach ? _sniffedAttachUrl : _sniffedUploadUrl;
    final paramsBase = isAttach ? _sniffedAttachParams : _sniffedUploadParams;
    var url = urlBase ?? "";
    if (!url.startsWith('http')) {
      final base = widget.baseUrl.endsWith('/')
          ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
          : widget.baseUrl;
      url = url.startsWith('/') ? base + url : "$base/$url";
    }
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString('saved_cookie_string') ?? "";
    try {
      final dio = Dio();
      dio.options.headers = {
        'Cookie': cookie,
        'User-Agent': kUserAgent,
        'Referer': widget.baseUrl,
      };
      final fd = FormData();
      paramsBase.forEach((k, v) => fd.fields.add(MapEntry(k, v)));
      fd.files.add(
        MapEntry(
          'Filedata',
          await MultipartFile.fromFile(
            compressed.path,
            filename: file.path.split('\\').last.split('/').last,
          ),
        ),
      );
      final resp = await dio.post(url, data: fd);
      if (resp.statusCode == 200) {
        final body = resp.data.toString();
        String? aid;
        if (body.contains("DISCUZUPLOAD")) {
          final parts = body.split('|');
          if (parts.length > 2 && parts[1] == '0') aid = parts[2];
        } else if (RegExp(r'^\d+$').hasMatch(body.trim())) {
          aid = body.trim();
        }
        if (aid != null && aid != "0") {
          _uploadedAids.add(aid);
          _sniffedFormParams['attachnew[$aid]'] = '1';
          _insertBBCode("$openTag$aid$closeTag", "");
          _showMsg("✅ 附件已添加");
        } else {
          _showMsg("上传失败: $body");
        }
      }
    } catch (e) {
      _showMsg("上传出错: $e");
    } finally {
      if (compressed.path != file.path)
        try {
          await compressed.delete();
        } catch (_) {}
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _insertBBCode(String start, [String end = '']) {
    final text = _messageController.text;
    final sel = _messageController.selection;
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    if (sel.start < 0) {
      final newText = text + start + end;
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length - end.length),
      );
      return;
    }
    final selected = text.substring(sel.start, sel.end);
    final newText = text.replaceRange(
      sel.start,
      sel.end,
      "$start$selected$end",
    );
    final newSel = selected.isEmpty
        ? TextSelection.collapsed(offset: sel.start + start.length)
        : TextSelection(
            baseOffset: sel.start + start.length,
            extentOffset: sel.start + start.length + selected.length,
          );
    _messageController.value = TextEditingValue(
      text: newText,
      selection: newSel,
    );
    setState(() {});
  }

  // ====== 提交 ======
  Future<void> _sendPost() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) return;
    if (_sniffedSubmitUrl == null ||
        !_sniffedFormParams.containsKey('formhash')) {
      _showMsg("参数未就绪，重新分析...");
      _sniffForm();
      return;
    }
    setState(() => _isSending = true);
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isSending) {
        setState(() => _isSending = false);
        _showMsg("请求超时");
      }
    });
    var url = _sniffedSubmitUrl!;
    if (!url.startsWith("http")) {
      final base = widget.baseUrl.endsWith('/')
          ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
          : widget.baseUrl;
      url = url.startsWith('/') ? base + url : "$base/$url";
    }
    if (!url.contains("inajax=1")) url += "&inajax=1";
    if (!url.contains("topicsubmit=yes")) url += "&topicsubmit=yes";

    final js = StringBuffer();
    js.writeln("var formData = new FormData();");
    _sniffedFormParams.forEach((k, v) {
      if (k != 'subject' && k != 'message') {
        js.writeln("formData.append(${jsonEncode(k)}, ${jsonEncode(v)});");
      }
    });
    js.writeln("formData.append('subject', ${jsonEncode(subject)});");
    js.writeln("formData.append('message', ${jsonEncode(message)});");
    js.writeln("formData.append('topicsubmit', 'yes');");

    _webController?.runJavaScript("""
    (async function() {
      try {
        ${js.toString()}
        var r = await fetch('$url', { method:'POST', body:formData, credentials:'include' });
        var t = await r.text();
        PostChannel.postMessage(JSON.stringify({status:r.status,body:t}));
      } catch(e) { PostChannel.postMessage(JSON.stringify({error:e.toString()})); }
    })();
    """);
  }

  void _handleJsMessage(String message) {
    try {
      final data = jsonDecode(message);
      if (data['error'] != null) {
        _showMsg("错误: ${data['error']}");
        setState(() => _isSending = false);
        return;
      }
      final body = data['body'] ?? "";
      if (body.contains("succeed") ||
          body.contains("发布成功") ||
          body.contains("alert_right")) {
        _showMsg("发布成功！");
        Navigator.pop(context, true);
      } else {
        var err = "发送失败";
        if (body.contains("<![CDATA[")) {
          final m = RegExp(
            r'<!\[CDATA\[(.*?)(?:<script|\]\]>)',
            dotAll: true,
          ).firstMatch(body);
          if (m != null) err = m.group(1)?.trim() ?? err;
        } else if (body.contains("errorhandle_")) {
          final m = RegExp(
            r"errorhandle_\w+\('([^']+)'",
            dotAll: true,
          ).firstMatch(body);
          if (m != null) err = m.group(1) ?? err;
        }
        _showMsg(err);
      }
    } catch (_) {
      _showMsg("解析响应错误");
    }
    setState(() => _isSending = false);
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ====== 颜色选择 ======
  void _showColorPicker() {
    final colors = [
      {'name': '红色', 'code': 'Red', 'color': Colors.red},
      {'name': '橙色', 'code': 'Orange', 'color': Colors.orange},
      {'name': '黄色', 'code': 'Yellow', 'color': Colors.yellow[700]},
      {'name': '绿色', 'code': 'Green', 'color': Colors.green},
      {'name': '青色', 'code': 'Cyan', 'color': Colors.cyan},
      {'name': '蓝色', 'code': 'Blue', 'color': Colors.blue},
      {'name': '紫色', 'code': 'Purple', 'color': Colors.purple},
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
                    Container(
                      width: 20,
                      height: 20,
                      color: c['color'] as Color,
                    ),
                    const SizedBox(width: 10),
                    Text(c['name'] as String),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("从相册选择"),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("拍照"),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== Build ======
  @override
  Widget build(BuildContext context) {
    final ready = _sniffedFormParams.containsKey('formhash');

    return Scaffold(
      appBar: AppBar(
        title: const Text("发表新帖"),
        actions: [
          TextButton(
            onPressed:
                (_isSending ||
                    _subjectController.text.trim().isEmpty ||
                    _messageController.text.trim().isEmpty ||
                    !ready)
                ? null
                : _sendPost,
            child: _isSending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    "发布",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ready ? null : Colors.grey,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 隐藏 WebView
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
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                hintText: "标题",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                isDense: true,
              ),
              maxLength: 80,
              onChanged: (_) => setState(() {}),
            ),
          ),
          // 分类选择 (typeid)
          if (_typeidOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SizedBox(
                height: 40,
                child: DropdownButtonFormField<String>(
                  value: _selectedTypeid,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  items: _typeidOptions
                      .map(
                        (opt) => DropdownMenuItem(
                          value: opt['value'],
                          child: Text(
                            opt['label'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTypeid = v),
                ),
              ),
            ),
          // 未使用的附件提示
          if (_unusedAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.attach_file,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "${_unusedAttachments.length} 个未使用的附件",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        for (final att in _unusedAttachments) {
                          final aid = att['aid'] ?? '';
                          if (aid.isNotEmpty) {
                            _sniffedFormParams['attachnew[$aid]'] = '1';
                            _insertBBCode("[attach]$aid[/attach]", "");
                          }
                        }
                        _showMsg("✅ 已插入 ${_unusedAttachments.length} 个附件");
                        setState(() => _unusedAttachments = []);
                      },
                      child: const Text("插入全部", style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () {
                        for (final att in _unusedAttachments) {
                          final aid = att['aid'] ?? '';
                          if (aid.isNotEmpty && _webController != null) {
                            _webController!.runJavaScript(
                              "attachoption('attach', 0, '$aid');",
                            );
                          }
                        }
                        _showMsg("🗑️ 已删除 ${_unusedAttachments.length} 个附件");
                        setState(() => _unusedAttachments = []);
                      },
                      child: Text(
                        "删除",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 正文
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: ready ? "正文内容..." : "$_debugStatus...",
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
                onTap: () {
                  if (_showSmileyPanel)
                    setState(() => _showSmileyPanel = false);
                },
              ),
            ),
          ),
          // 上传进度
          if (_isUploadingImage) const LinearProgressIndicator(minHeight: 2),
          // 工具栏
          _buildToolbar(),
          // 表情面板
          if (_showSmileyPanel) _buildSmileyPanel(),
          // 状态
          if (!ready)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _debugStatus,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
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
          const VerticalDivider(width: 8),
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
            onPressed: (_sniffedFormParams.isEmpty || _isUploadingImage)
                ? null
                : _showImageSourcePicker,
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: "导入 TXT/MD",
            onPressed: _importTxtFile,
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: "上传附件",
            onPressed: (_sniffedFormParams.isEmpty || _isUploadingImage)
                ? null
                : _uploadAttachment,
          ),
          const VerticalDivider(width: 8),
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
        itemBuilder: (_, i) => InkWell(
          onTap: () => _insertBBCode(_commonSmilies[i], ''),
          child: Center(
            child: Text(
              _commonSmilies[i],
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
}
