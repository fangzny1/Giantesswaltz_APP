// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:giantesswaltz_app/forum_model.dart';

void main() {
  test('mergeCookies merges latest values', () {
    final merged = mergeCookies('a=1; auth=old', [
      'auth=new; Path=/; HttpOnly',
    ]);
    expect(merged.contains('a=1'), true);
    expect(merged.contains('auth=new'), true);
  });
}
