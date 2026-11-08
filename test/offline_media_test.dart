import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giantesswaltz_app/offline_media.dart';

void main() {
  test('从离线 JSON 提取正文 <img> 与图片附件直链', () {
    final json = jsonEncode({
      "Variables": {
        "postlist": [
          {
            "pid": "101",
            "number": 1,
            "message": "看这张 <img src=\"https://a.com/1.jpg\" /> 和 <img src='https://a.com/2.png'>",
            "attachments": {
              "1": {"isimage": "1", "url": "https://a.com/", "attachment": "3.jpg"},
              "2": {"isimage": "0", "url": "https://a.com/", "attachment": "4.zip"},
            },
          },
          {"pid": "102", "number": 2, "message": "纯文字楼层"},
        ],
      },
    });
    final urls = extractImageUrls(json);

    expect(urls, contains('https://a.com/1.jpg'));
    expect(urls, contains('https://a.com/2.png'));
    expect(urls, contains('https://a.com/3.jpg'));
    expect(urls, isNot(contains('https://a.com/4.zip')));
    expect(urls.length, 3);
  });

  test('坏 JSON 不抛异常返回空列表', () {
    expect(extractImageUrls('not a json'), isEmpty);
  });
}
