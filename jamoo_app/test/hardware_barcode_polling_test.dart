import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('外付けリーダー入力をイベントに依存せず自動確定する', () {
    final source = File(
      'lib/services/inventory_mobile_page.dart',
    ).readAsStringSync();
    expect(source, contains('function observeBarcodeInput()'));
    expect(source, contains('setInterval(observeBarcodeInput,250)'));
    expect(source, contains('Date.now()-observedBarcodeAt>=900'));
    expect(source, contains('acceptBarcode(code).finally'));
  });
}
