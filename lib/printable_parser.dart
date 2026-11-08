import 'package:html/parser.dart' as html_parser;

/// Discuz! 打印版（action=printable）单页最多返回的楼层数。
/// 帖子超过这个楼数时必须继续翻页加载，否则超出部分会被静默截断。
const int kPrintableFloorLimit = 100;

/// 安全上限：一次超级阅读最多尝试的打印页数，防止异常站点导致无限翻页。
const int kMaxPrintablePages = 30;

/// 超级阅读模式的一个"楼"（章节）。
class ReaderChapter {
  final String author;
  final String time;
  final String content;

  /// 跨页去重签名：服务器忽略 `page` 参数重复返回同一页时，
  /// 依靠它把重复楼层挡在门外。
  final String signature;

  ReaderChapter({
    required this.author,
    required this.time,
    required this.content,
  }) : signature = '$author\u0000$time\u0000${content.hashCode}';
}

/// 剥离 Discuz 的渲染 hack（dzcode 表格包装、font size 属性）。
/// 在解析阶段（后台 isolate）一次性完成，渲染时不再重复跑正则。
String _stripRenderingHacks(String content) {
  var out = content.replaceAll(RegExp(r'<table[^>]*>'), '');
  out = out.replaceAll(RegExp(r'<tr[^>]*>'), '');
  out = out.replaceAll(RegExp(r'<td[^>]*>'), '');
  out = out.replaceAll('</table>', '');
  out = out.replaceAll('</tr>', '');
  out = out.replaceAll('</td>', '');
  // 剥离 <font size="..."> 属性，保留标签本身使 textStyle 全局生效
  out = out.replaceAll(RegExp(r'<font[^>]*size\s*=\s*"\d+"[^>]*>'), '<font>');
  out = out.replaceAll(RegExp(r"<font[^>]*size\s*=\s*'\d+'[^>]*>"), '<font>');
  out = out.replaceAll(RegExp(r'<font[^>]*size\s*=\s*\d+[^>]*>'), '<font>');
  return out;
}

/// 一页打印版 HTML 的解析结果。
class PrintableParseResult {
  final List<ReaderChapter> chapters;

  /// 本页楼数是否达到单页上限（达到则说明后面可能还有内容，需要翻页）。
  final bool hitPageLimit;

  const PrintableParseResult({
    required this.chapters,
    required this.hitPageLimit,
  });
}

/// 解析 Discuz! 打印版页面（forum.php?mod=viewthread&action=printable）。
///
/// 这是纯 Dart 函数，通过 [compute] 在后台 isolate 运行，
/// 长帖解析不会卡住 UI 主线程。
PrintableParseResult parsePrintableHtml(String html) {
  String cleanHtml = html.replaceAll(
    RegExp(r'<script[^>]*>[\s\S]*?<\/script>'),
    '',
  );
  var body = html_parser.parse(cleanHtml).body;
  if (body == null) {
    return const PrintableParseResult(chapters: [], hitPageLimit: false);
  }

  List<ReaderChapter> temp = [];
  List<String> blocks = body.innerHtml.split(RegExp(r'<hr[^>]*>'));

  for (int i = 0; i < blocks.length; i++) {
    String trimmedBlock = blocks[i].trim();
    if (trimmedBlock.isEmpty || trimmedBlock.contains("Powered by Discuz")) {
      continue;
    }

    // 页面头部（标题、链接等）没有作者信息，跳过
    if (i == 0 && !trimmedBlock.contains("作者:")) continue;

    String author =
        RegExp(r'作者:\s*<\/b>\s*([^&<]+)').firstMatch(trimmedBlock)?.group(1)?.trim() ??
            "匿名";
    String time =
        RegExp(r'时间:\s*<\/b>\s*([^<]+)').firstMatch(trimmedBlock)?.group(1)?.trim() ??
            "";

    String content = trimmedBlock;
    Match? timeMatch = RegExp(r'时间:\s*<\/b>.*?(<br\s*\/?>)').firstMatch(content);
    if (timeMatch != null) {
      content = content.substring(timeMatch.end).trim();
    }

    content = content
        .replaceFirst(RegExp(r'^<b>标题:\s*<\/b>.*?(<br\s*\/?>)'), '')
        .trim();
    content = content.replaceFirst(RegExp(r'^(<br\s*\/?>)+'), '').trim();

    content = _stripRenderingHacks(content);
    temp.add(ReaderChapter(author: author, time: time, content: content));
  }

  return PrintableParseResult(
    chapters: temp,
    hitPageLimit: temp.length >= kPrintableFloorLimit,
  );
}
