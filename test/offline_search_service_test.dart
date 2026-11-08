import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giantesswaltz_app/offline_search_service.dart';

void main() {
  test('stripHtml 去标签去实体', () {
    expect(
      stripHtml('<div>你好&nbsp;<b>世界</b>&amp;朋友<br/>下一行</div>'),
      '你好 世界 &朋友 下一行',
    );
  });

  test('extractSearchablePosts 解析楼层纯文本', () {
    const json = '''
{"Variables":{"postlist":[
  {"pid":"201","number":3,"author":"abalaba","authorid":"9",
   "message":"<div>不行，就算大半夜的我也得回来补一嘴。</div>"},
  {"pid":"202","number":4,"author":"x","authorid":"1","message":""}
]}}
''';
    final posts = extractSearchablePosts('19564', '测试帖', 2, json);

    expect(posts.length, 1);
    expect(posts.first.pid, '201');
    expect(posts.first.floor, 3);
    expect(posts.first.page, 2);
    expect(posts.first.text, contains('大半夜'));
  });

  test('标题/作者命中（matchThreadMeta）', () {
    final byAuthor =
        OfflineSearchService.matchThreadMeta('1', '某帖', '明哥233', '9', '明哥');
    expect(byAuthor, isNotNull);
    expect(byAuthor!.isTitleHit, true);

    final byTitle =
        OfflineSearchService.matchThreadMeta('1', '薇塔之旅', 'x', '1', '薇塔');
    expect(byTitle, isNotNull);

    final miss =
        OfflineSearchService.matchThreadMeta('1', '薇塔之旅', 'x', '1', '不存在');
    expect(miss, isNull);
  });

  test('真实离线数据金样：5 楼可解析且台词可命中', () {
    final json = File('test/fixtures/real_offline_page.json').readAsStringSync();
    final posts = extractSearchablePosts('35440', '薇塔女神的星铁之旅', 1, json);

    expect(posts.length, 5);
    expect(posts.any((p) => p.text.contains('薇塔')), true);
    expect(posts.any((p) => p.text.contains('找不到这个群呢')), true);
    // 真实数据的楼层号从 1 开始递增
    expect(posts.map((p) => p.floor).toList(), [1, 2, 3, 4, 5]);
  });

  test('buildSnippet 围绕命中位置截取上下文', () {
    final text = 'A' * 100 + '目标台词' + 'B' * 100;
    final start = text.indexOf('目标台词');
    final s = OfflineSearchService.buildSnippet(text, start, 4);

    expect(s, contains('目标台词'));
    expect(s.startsWith('…'), true);
    expect(s.endsWith('…'), true);
    expect(s.length, lessThan(4 + OfflineSearchService.snippetRadius * 2 + 4));
  });
}
