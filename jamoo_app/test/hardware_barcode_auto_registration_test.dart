import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未登録バーコードから新商品登録画面を自動表示する', () {
    final source = File(
      'lib/services/inventory_mobile_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('async function acceptBarcode(raw)');
    final end = source.indexOf('async function saveBarcodeAssignment()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final acceptBarcode = source.substring(start, end);
    expect(acceptBarcode, contains('pendingBarcode=code;openNewItem()'));
    expect(
      acceptBarcode,
      isNot(contains("el('assignBarcode').classList.remove")),
    );
  });
}
