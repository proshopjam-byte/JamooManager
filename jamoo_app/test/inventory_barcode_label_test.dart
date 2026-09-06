import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/services/inventory_barcode_label_service.dart';

void main() {
  test('専用EAN-13バーコードを検査数字付きで生成する', () {
    final first = InventoryBarcodeLabelService.buildInternalBarcode(1);
    final second = InventoryBarcodeLabelService.buildInternalBarcode(2);

    expect(first, hasLength(13));
    expect(first, startsWith('20'));
    expect(InventoryBarcodeLabelService.isValidEan13(first), isTrue);
    expect(InventoryBarcodeLabelService.isValidEan13(second), isTrue);
    expect(first, isNot(second));
  });

  test('誤った検査数字のEAN-13を拒否する', () {
    expect(InventoryBarcodeLabelService.isValidEan13('2000000000010'), isFalse);
  });
}
