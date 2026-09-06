import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('読み取り画面から明示的に新商品登録へ進める', () {
    final source = File(
      'lib/services/inventory_mobile_page.dart',
    ).readAsStringSync();

    expect(source, contains('id="registerScanCode"'));
    expect(source, contains('function registerScannedCodeAsNewItem()'));
    expect(source, contains("pendingBarcode=code"));
    expect(source, contains('openNewItem()'));
  });
}
