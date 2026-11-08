import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giantesswaltz_app/offline_transfer.dart';

void main() {
  test('离线数据 ZIP 导出/导入往返一致', () {
    final src = Directory.systemTemp.createTempSync('gw_src');
    File('${src.path}/index.json').writeAsStringSync(
        jsonEncode({'1': {'tid': '1', 'subject': '甲', 'max_page': 2}}));
    File('${src.path}/thread_1_1.json').writeAsStringSync('{"a":1}');
    File('${src.path}/thread_1_2.json').writeAsStringSync('{"a":2}');
    File('${src.path}/not_json.txt').writeAsStringSync('忽略我');

    final zip = buildOfflineZipBytes(src);
    final dest = Directory.systemTemp.createTempSync('gw_dest');
    final count = restoreOfflineZipBytes(zip, dest);

    expect(count, 2); // 2 个 thread 数据页（index 单独合并，不计数）
    expect(File('${dest.path}/thread_1_2.json').readAsStringSync(), '{"a":2}');
    expect(File('${dest.path}/not_json.txt').existsSync(), isFalse);
    final index = jsonDecode(File('${dest.path}/index.json').readAsStringSync());
    expect(index['1']['subject'], '甲');
  });

  test('索引合并：导入覆盖同 tid，保留其他条目', () {
    final merged = mergeOfflineIndex(
      jsonEncode({
        '1': {'tid': '1', 'subject': '旧'},
        '2': {'tid': '2', 'subject': '保留'},
      }),
      jsonEncode({
        '1': {'tid': '1', 'subject': '新'},
      }),
    );
    expect(merged['1']['subject'], '新');
    expect(merged['2']['subject'], '保留');
    expect(mergeOfflineIndex(null, null), isEmpty);
  });

  test('无索引备份：从文件名合成索引', () {
    final src = Directory.systemTemp.createTempSync('gw_noidx');
    File('${src.path}/thread_9_3.json').writeAsStringSync('{}');
    final zip = buildOfflineZipBytes(src);
    final dest = Directory.systemTemp.createTempSync('gw_noidx_out');
    restoreOfflineZipBytes(zip, dest);

    final index = jsonDecode(File('${dest.path}/index.json').readAsStringSync());
    expect(index['9']['max_page'], 3);
    expect(index['9']['subject'], contains('离线导入'));
  });
}