import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../repositories/inventory_repository.dart';

class InventoryBarcodeLabelService {
  const InventoryBarcodeLabelService({
    this.repository = const InventoryRepository(),
  });

  final InventoryRepository repository;

  static String buildInternalBarcode(int serial) {
    if (serial < 1 || serial > 9999999999) {
      throw const FormatException('バーコード番号の範囲を超えています。');
    }
    final body = '20${serial.toString().padLeft(10, '0')}';
    return '$body${_checkDigit(body)}';
  }

  static bool isValidEan13(String value) {
    if (!RegExp(r'^\d{13}$').hasMatch(value)) return false;
    return int.parse(value[12]) == _checkDigit(value.substring(0, 12));
  }

  static int _checkDigit(String firstTwelveDigits) {
    if (!RegExp(r'^\d{12}$').hasMatch(firstTwelveDigits)) {
      throw const FormatException('EAN-13は12桁の数字から作成します。');
    }
    var sum = 0;
    for (var index = 0; index < firstTwelveDigits.length; index++) {
      final digit = int.parse(firstTwelveDigits[index]);
      sum += index.isEven ? digit : digit * 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  Future<String> generateUniqueBarcode() async {
    final items = await repository.loadItems(includeInactive: true);
    final used = items
        .map((item) => item.barcode?.trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet();
    var serial = 1;
    for (final code in used) {
      if (RegExp(r'^20\d{11}$').hasMatch(code) && isValidEan13(code)) {
        final value = int.tryParse(code.substring(2, 12));
        if (value != null && value >= serial) serial = value + 1;
      }
    }
    while (used.contains(buildInternalBarcode(serial))) {
      serial++;
    }
    return buildInternalBarcode(serial);
  }

  Future<void> showPrintDialog(
    BuildContext context, {
    required String itemName,
    required String barcode,
    int? salePriceYen,
  }) async {
    final normalized = barcode.trim();
    if (!isValidEan13(normalized)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('印刷できません'),
          content: const Text('印刷するバーコードは正しいEAN-13の13桁で入力してください。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }

    var copies = 1;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('バーコードラベルを印刷'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(itemName.trim().isEmpty ? '商品名未入力' : itemName.trim()),
              Text(normalized),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('印刷枚数'),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: copies > 1
                        ? () => setState(() => copies--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$copies枚'),
                  IconButton(
                    onPressed: copies < 24
                        ? () => setState(() => copies++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const Text('A4用紙に3列×8段で配置します（最大24枚）。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(copies),
              icon: const Icon(Icons.print_outlined),
              label: const Text('印刷'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    await Printing.layoutPdf(
      name: 'barcode_$normalized.pdf',
      format: PdfPageFormat.a4,
      dynamicLayout: false,
      usePrinterSettings: false,
      forceCustomPrintPaper: true,
      windowsModernDialog: false,
      onLayout: (_) => _buildLabels(
        itemName: itemName.trim().isEmpty ? '商品' : itemName.trim(),
        barcode: normalized,
        salePriceYen: salePriceYen,
        copies: selected,
      ),
    );
  }

  Future<Uint8List> _buildLabels({
    required String itemName,
    required String barcode,
    required int? salePriceYen,
    required int copies,
  }) async {
    final document = pw.Document();
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    const millimeter = PdfPageFormat.mm;

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(8 * millimeter),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (_) => pw.Wrap(
          spacing: 3 * millimeter,
          runSpacing: 2 * millimeter,
          children: List.generate(
            copies,
            (_) => _label(
              itemName: itemName,
              barcode: barcode,
              salePriceYen: salePriceYen,
            ),
          ),
        ),
      ),
    );
    return document.save();
  }

  pw.Widget _label({
    required String itemName,
    required String barcode,
    required int? salePriceYen,
  }) {
    const millimeter = PdfPageFormat.mm;
    return pw.Container(
      width: 62 * millimeter,
      height: 32 * millimeter,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 2 * millimeter,
        vertical: 1.5 * millimeter,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  itemName,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (salePriceYen != null)
                pw.Text(
                  '¥$salePriceYen',
                  style: const pw.TextStyle(fontSize: 8),
                ),
            ],
          ),
          pw.SizedBox(height: 1 * millimeter),
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.ean13(),
              data: barcode,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 7),
            ),
          ),
        ],
      ),
    );
  }
}
