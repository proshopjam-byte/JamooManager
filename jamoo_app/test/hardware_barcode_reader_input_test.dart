import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('リーダー入力完了後に未登録商品の判定へ自動的に進む', () {
    final source = File(
      'lib/services/inventory_mobile_page.dart',
    ).readAsStringSync();

    expect(source, contains("el('scanCode').addEventListener('input'"));
    expect(source, contains('setTimeout(observeBarcodeInput,950)'));
    expect(source, contains('acceptBarcode(code).finally'));
  });
}
