import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giantesswaltz_app/forum_extras_api.dart';
import 'package:giantesswaltz_app/thread_watch_store.dart';

void main() {
  test('parseNotice 解析四类未读计数', () {
    final n = parseNotice({
      'notice': {'newpush': '2', 'newpm': 1, 'newprompt': 0, 'newmypost': 3},
    });
    expect(n.newpush, 2);
    expect(n.newpm, 1);
    expect(n.newmypost, 3);
    expect(n.total, 6);
    expect(n.hasUnread, true);

    expect(parseNotice(null).hasUnread, false);
    expect(parseNotice({}).hasUnread, false);
  });

  test('parseHotThreads 真实金样：50 条热帖可解析', () {
    final json = File('test/fixtures/real_hotthread.json').readAsStringSync();
    final hot = parseHotThreads(json);

    expect(hot.length, 50);
    expect(hot.first.tid, isNotEmpty);
    expect(hot.first.subject, isNotEmpty);
    // 真实数据的数字字段可能是字符串，解析必须容错
    expect(hot.first.views, greaterThanOrEqualTo(0));
    expect(hot.first.maxPosition, greaterThanOrEqualTo(0));
  });

  test('parseGuideNew 解析导读行', () {
    const html = '''
<table><tbody id="normalthread_37994"> <tr>
<td class="avr"><a href="home.php?mod=space&amp;uid=25543"><img src="uc_server/avatar.php?uid=25543&size=small" /></a></td>
<th class="main common"> <div class="titbox">
<a href="forum.php?mod=viewthread&amp;tid=37994&amp;extra=" target="_blank" class="tit xst" >网上瞎逛发现的网站</a></div>
<div class="sub"> <em class="aor"> <a href="home.php?mod=space&amp;uid=25543" c="1">awa_hh1</a></em>
<em class="dte xi1"><span title="2026-11-8">9&nbsp;小时前</span></em>
<em class="vie">100</em> <em class="rey"> 1</em> </div></th></tr></tbody></table>
''';
    final g = parseGuideNew(html);

    expect(g.length, 1);
    expect(g.first.tid, '37994');
    expect(g.first.subject, '网上瞎逛发现的网站');
    expect(g.first.author, 'awa_hh1');
    expect(g.first.views, 100);
    expect(g.first.replies, 1);
  });

  test('parseFriends 容错解析（Map/List/空）', () {
    final friends = parseFriends(
        '{"Variables":{"list":[{"uid":"9","username":"小明"}]}}');
    expect(friends.length, 1);
    expect(friends.first.username, '小明');

    expect(parseFriends('{"Variables":{"list":{}}}'), isEmpty);
    expect(parseFriends('not json'), isEmpty);
  });

  test('computeNewFloors 新楼层数（永不为负）', () {
    expect(
        computeNewFloors(const WatchEntry(
            tid: '1', subject: 's', seenMaxPosition: 10, latestMaxPosition: 15)),
        5);
    expect(
        computeNewFloors(const WatchEntry(
            tid: '1', subject: 's', seenMaxPosition: 20, latestMaxPosition: 15)),
        0);
    expect(computeNewFloors(const WatchEntry(tid: '1', subject: 's')), 0);
  });
}
