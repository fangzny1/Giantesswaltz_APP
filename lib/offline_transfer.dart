import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// 把离线数据目录里的 *.json 打包成 ZIP 字节（备份用）。
List<int> buildOfflineZipBytes(Directory source) {
  final archive = Archive();
  final files = source
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    archive.addFile(
      ArchiveFile(f.uri.pathSegments.last, f.lengthSync(), f.readAsBytesSync()),
    );
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('ZIP 编码失败');
  return encoded;
}

/// 合并两份离线索引 JSON（导入覆盖同 tid 的旧条目）。纯函数，可单测。
Map<String, dynamic> mergeOfflineIndex(String? existingJson, String? importedJson) {
  Map<String, dynamic> parse(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return {};
    }
  }

  final out = <String, dynamic>{};
  out.addAll(parse(existingJson));
  out.addAll(parse(importedJson));
  return out;
}

/// 把备份 ZIP 恢复进离线数据目录（同名覆盖 + 索引合并），
/// 返回导入的数据文件数。只接受根级 *.json，防路径穿越。
int restoreOfflineZipBytes(List<int> bytes, Directory dest) {
  final archive = ZipDecoder().decodeBytes(bytes);
  dest.createSync(recursive: true);
  var count = 0;
  String? existingIndex;
  String? importedIndex;
  final synthesized = <String, Map<String, dynamic>>{};

  final idxFile = File('${dest.path}/index.json');
  if (idxFile.existsSync()) existingIndex = idxFile.readAsStringSync();

  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    if (name.contains('/') || name.contains('..')) continue; // 只取根级文件
    if (!name.endsWith('.json')) continue;
    final data = f.content as List<int>;
    if (name == 'index.json') {
      importedIndex = utf8.decode(data, allowMalformed: true);
      continue;
    }
    File('${dest.path}/$name').writeAsBytesSync(data, flush: true);
    count++;

    // 无索引时从文件名 thread_<tid>_<page>.json 合成最小条目
    final m = RegExp(r'^thread_(.+)_(\d+)\.json$').firstMatch(name);
    if (m != null) {
      synthesized.putIfAbsent(m.group(1)!, () => {
        'tid': m.group(1),
        'subject': '离线导入 ${m.group(1)}',
        'author': '',
        'author_id': '',
        'max_page': 0,
        'update_time': 0,
      });
      final page = int.tryParse(m.group(2)!) ?? 0;
      final entry = synthesized[m.group(1)]!;
      if (page > (entry['max_page'] as int)) entry['max_page'] = page;
    }
  }

  // 合并/补写索引
  if (importedIndex != null) {
    final merged = mergeOfflineIndex(existingIndex, importedIndex);
    if (merged.isNotEmpty) idxFile.writeAsStringSync(jsonEncode(merged));
  } else if (synthesized.isNotEmpty) {
    final merged = mergeOfflineIndex(existingIndex, jsonEncode(synthesized));
    idxFile.writeAsStringSync(jsonEncode(merged));
  }
  return count;
}