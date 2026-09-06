import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('外付けリーダーのEnter・Tab・末尾なし入力を商品登録へ渡す', () {
    final source = File(
      'lib/services/inventory_mobile_page.dart',
    ).readAsStringSync();

    expect(source, contains('function handleHardwareReaderKey(event)'));
    expect(source, contains("event.key==='Enter'||event.key==='Tab'"));
    expect(source, contains('setTimeout(submitHardwareReader,220)'));
    expect(source, contains('acceptBarcode(code)'));
  });
}
