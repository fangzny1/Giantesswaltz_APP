import 'package:flutter_test/flutter_test.dart';
import 'package:giantesswaltz_app/printable_parser.dart';

String _buildBlock(int i) =>
    '<b>标题:</b> 第$i章<br/>'
    '<b>作者:</b> Author$i<br/>'
    '<b>时间:</b> 2024-01-01 12:00<br/>'
    '<div>正文内容 $i</div>';

String _buildPrintablePage(int count) {
  final blocks = List.generate(count, _buildBlock);
  return '<h1>打印预览</h1><hr />'
      '${blocks.join('<hr />')}<hr />Powered by Discuz!';
}

void main() {
  test('解析打印页：提取作者/时间/正文，跳过页眉页脚', () {
    final result = parsePrintableHtml(_buildPrintablePage(3));

    expect(result.chapters.length, 3);
    expect(result.hitPageLimit, isFalse);
    expect(result.chapters[0].author, 'Author0');
    expect(result.chapters[1].author, 'Author1');
    expect(result.chapters[0].time, '2024-01-01 12:00');
    expect(result.chapters[2].content, contains('正文内容 2'));
    expect(result.chapters[0].content, isNot(contains('标题:')));
    expect(result.chapters[0].content, isNot(contains('时间:')));
  });

  test('楼数达到单页上限时命中截断标记', () {
    final result = parsePrintableHtml(_buildPrintablePage(kPrintableFloorLimit));

    expect(result.chapters.length, kPrintableFloorLimit);
    expect(result.hitPageLimit, isTrue);
  });

  test('未达到单页上限时不命中截断标记', () {
    final result =
        parsePrintableHtml(_buildPrintablePage(kPrintableFloorLimit - 1));

    expect(result.hitPageLimit, isFalse);
  });

  test('相同楼层产生相同去重签名，不同正文则不同', () {
    final a = ReaderChapter(author: 'A', time: 'T', content: 'C');
    final b = ReaderChapter(author: 'A', time: 'T', content: 'C');
    final c = ReaderChapter(author: 'A', time: 'T', content: 'D');

    expect(a.signature, b.signature);
    expect(a.signature, isNot(c.signature));
  });

  test('解析时剥离 dzcode 表格包装与 font size 属性', () {
    final html = '<h1>x</h1><hr />'
        '<b>作者:</b> A<br/><b>时间:</b> T<br/>'
        '<table><tr><td>表格内容</td></tr></table>'
        '<font size="7">大字</font>正文';
    final c = parsePrintableHtml(html).chapters.single.content;

    expect(c, contains('表格内容'));
    expect(c, contains('大字'));
    expect(c, isNot(contains('<table')));
    expect(c, isNot(contains('</td>')));
    expect(c, isNot(contains('size="7"')));
    expect(c, contains('<font>'));
  });

  test('空页面/登录页返回空结果而不是崩溃', () {
    final result = parsePrintableHtml('<html><body>请先登录</body></html>');

    expect(result.chapters, isEmpty);
    expect(result.hitPageLimit, isFalse);
  });
}
