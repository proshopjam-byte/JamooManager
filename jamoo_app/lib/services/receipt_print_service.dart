import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/facility_settings.dart';
import '../models/usage_statement.dart';
import 'windows_pdf_font_service.dart';

class ReceiptPrintService {
  const ReceiptPrintService();

  Future<void> preview(
    BuildContext context, {
    required UsageStatement statement,
    required FacilitySettings facility,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ReceiptPreviewScreen(
          service: this,
          statement: statement,
          facility: facility,
        ),
      ),
    );
  }

  Future<Uint8List> buildPdf(
    UsageStatement statement,
    FacilitySettings facility,
  ) async {
    final fonts = await WindowsPdfFontService.load();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final logoData = await rootBundle.load('assets/images/jamoo_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
          fontFallback: fonts.fallback,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                pw.Image(logo, width: 82, height: 77, fit: pw.BoxFit.contain),
                pw.SizedBox(width: 12),
                pw.Text(
                  'Vegetarian House JAMOO',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '領 収 書',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'RECEIPT',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 32),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 1)),
                    ),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: statement.recipientName,
                            style: pw.TextStyle(
                              fontSize: 16,
                              font: fonts.fontFor(statement.recipientName),
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.TextSpan(
                            text: ' 様',
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 36),
                pw.Text(
                  '発行日 ${_date(statement.issueDate)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 15),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(width: 1.4),
                  bottom: pw.BorderSide(width: 1.4),
                ),
              ),
              child: pw.Text(
                '金額　${_yen(statement.totalYen)}${facility.receiptTaxStatus == ReceiptTaxStatus.qualifiedInvoiceIssuer ? '（税込）' : ''}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 21,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            _labeledText('但し ', statement.proviso, fonts, 10),
            _labeledText('お支払方法：', statement.paymentMethod, fonts, 9),
            pw.Text(
              '領収書番号：${statement.receiptNumber}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Text(
              '予約番号：${statement.reservationNumber}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'ご利用明細',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .6),
              columnWidths: const {
                0: pw.FixedColumnWidth(55),
                1: pw.FlexColumnWidth(3),
                2: pw.FixedColumnWidth(42),
                3: pw.FixedColumnWidth(72),
                4: pw.FixedColumnWidth(72),
                5: pw.FixedColumnWidth(38),
              },
              children: [
                _row(
                  [
                    '区分',
                    '内容',
                    '数量',
                    '単価',
                    '金額',
                    facility.receiptTaxStatus ==
                            ReceiptTaxStatus.qualifiedInvoiceIssuer
                        ? '税率'
                        : '',
                  ],
                  fonts: fonts,
                  header: true,
                ),
                for (final line in statement.lines)
                  _row([
                    line.type.label,
                    line.description,
                    _quantity(line.quantity),
                    _yen(line.unitPriceYen),
                    _yen(line.amountYen),
                    facility.receiptTaxStatus !=
                            ReceiptTaxStatus.qualifiedInvoiceIssuer
                        ? ''
                        : line.taxRate == 0
                        ? '非課税'
                        : line.taxRate == 8
                        ? '8%軽減'
                        : '${line.taxRate}%',
                  ], fonts: fonts),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 210,
                child: pw.Column(
                  children: [
                    _totalRow(
                      facility.receiptTaxStatus ==
                              ReceiptTaxStatus.qualifiedInvoiceIssuer
                          ? '合計（税込）'
                          : '合計',
                      _yen(statement.totalYen),
                      bold: true,
                    ),
                    if (facility.receiptTaxStatus ==
                        ReceiptTaxStatus.qualifiedInvoiceIssuer)
                      for (final entry in statement.amountByRate.entries.where(
                        (entry) => entry.key > 0,
                      )) ...[
                        _totalRow('${entry.key}%対象額', _yen(entry.value)),
                        _totalRow(
                          '${entry.key}%対象 内消費税',
                          _yen(statement.taxByRate[entry.key] ?? 0),
                        ),
                      ],
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 36),
            pw.Divider(color: PdfColors.grey500),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      facility.facilityName,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (facility.address.trim().isNotEmpty)
                      pw.Text(
                        facility.address,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    if (facility.phone.trim().isNotEmpty)
                      pw.Text(
                        'TEL ${facility.phone}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    if (facility.receiptTaxStatus ==
                        ReceiptTaxStatus.qualifiedInvoiceIssuer)
                      pw.Text(
                        '登録番号 ${facility.invoiceRegistrationNumber}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  '上記正に領収いたしました。',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  static pw.TableRow _row(
    List<String> values, {
    required WindowsPdfFonts fonts,
    bool header = false,
  }) => pw.TableRow(
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey200)
        : null,
    children: [
      for (var index = 0; index < values.length; index++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          child: pw.Text(
            values[index],
            textAlign: index >= 2 ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 8,
              font: fonts.fontFor(values[index]),
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
    ],
  );

  static pw.Widget _labeledText(
    String label,
    String value,
    WindowsPdfFonts fonts,
    double fontSize,
  ) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: label,
            style: pw.TextStyle(fontSize: fontSize),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(fontSize: fontSize, font: fonts.fontFor(value)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  static String _date(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';
  static String _yen(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final formatted = digits.replaceAllMapped(
      RegExp(r'(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${negative ? '-' : ''}¥$formatted';
  }

  static String _quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

class _ReceiptPreviewScreen extends StatefulWidget {
  const _ReceiptPreviewScreen({
    required this.service,
    required this.statement,
    required this.facility,
  });

  final ReceiptPrintService service;
  final UsageStatement statement;
  final FacilitySettings facility;

  @override
  State<_ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<_ReceiptPreviewScreen> {
  late final Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.service
        .buildPdf(widget.statement, widget.facility)
        .timeout(const Duration(seconds: 30));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('利用明細・領収書プレビュー')),
      body: FutureBuilder<Uint8List>(
        future: _bytesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '領収書PDFを作成できませんでした。\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('領収書を作成中…'),
                ],
              ),
            );
          }
          return PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            build: (_) async => bytes,
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: false,
            allowSharing: false,
            actions: [
              IconButton(
                tooltip: '印刷',
                onPressed: () => Printing.layoutPdf(
                  name: 'receipt_${widget.statement.reservationNumber}.pdf',
                  format: PdfPageFormat.a4,
                  dynamicLayout: false,
                  onLayout: (_) async => bytes,
                ),
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          );
        },
      ),
    );
  }
}
