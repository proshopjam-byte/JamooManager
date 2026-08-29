import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/checkin_sheet.dart';
import '../models/facility_settings.dart';

class CheckinSheetPrintService {
  const CheckinSheetPrintService();

  Future<void> preview(
    BuildContext context, {
    required DateTime date,
    required List<CheckinSheetRow> rows,
    required FacilitySettings facilitySettings,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${_formatDate(date)} チェックインシート')),
          body: PdfPreview(
            initialPageFormat: PdfPageFormat.a4.landscape,
            build: (_) => _buildPdf(date, rows, facilitySettings),
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            actions: [
              IconButton(
                tooltip: 'A4横で印刷',
                onPressed: () => _print(date, rows, facilitySettings),
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _print(
    DateTime date,
    List<CheckinSheetRow> rows,
    FacilitySettings facilitySettings,
  ) async {
    await Printing.layoutPdf(
      name: 'checkin_sheet_${_fileDate(date)}.pdf',
      format: PdfPageFormat.a4.landscape,
      dynamicLayout: false,
      usePrinterSettings: true,
      forceCustomPrintPaper: false,
      windowsModernDialog: true,
      onLayout: (_) => _buildPdf(date, rows, facilitySettings),
    );
  }

  Future<Uint8List> _buildPdf(
    DateTime date,
    List<CheckinSheetRow> rows,
    FacilitySettings facilitySettings,
  ) async {
    final document = pw.Document();
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final sortedRows = List<CheckinSheetRow>.from(rows)
      ..sort((first, second) => first.roomNumber.compareTo(second.roomNumber));
    final totalGuests = sortedRows
        .where(
          (row) => facilitySettings.roomByNumber(row.roomNumber).isAvailable,
        )
        .fold<int>(0, (sum, row) => sum + row.guestCount);
    final totalAmount = sortedRows.fold<int>(
      0,
      (sum, row) => sum + (row.amountYen ?? 0),
    );
    final pages = _splitRows(sortedRows);

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final pageRows = pages[pageIndex];
      final displayedKeys = <String>{};
      final rowHeight = pageRows.isEmpty
          ? 45.0
          : (360 / pageRows.length).clamp(25, 45).toDouble();

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 14),
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    _formatDate(date),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'チェックインシート',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 90,
                    child: pw.Text(
                      '${pageIndex + 1} / ${pages.length}',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: 0.8),
                columnWidths: const {
                  0: pw.FixedColumnWidth(45),
                  1: pw.FlexColumnWidth(2.3),
                  2: pw.FixedColumnWidth(32),
                  3: pw.FixedColumnWidth(28),
                  4: pw.FixedColumnWidth(62),
                  5: pw.FixedColumnWidth(48),
                  6: pw.FlexColumnWidth(1.45),
                  7: pw.FixedColumnWidth(58),
                  8: pw.FixedColumnWidth(58),
                  9: pw.FixedColumnWidth(28),
                  10: pw.FlexColumnWidth(1.45),
                },
                children: [
                  _headerRow(),
                  for (final row in pageRows)
                    _dataRow(row, displayedKeys, facilitySettings, rowHeight),
                ],
              ),
              pw.SizedBox(height: 7),
              pw.Row(
                children: [
                  pw.SizedBox(width: 30),
                  pw.Text(
                    '全ページ合計人数　$totalGuests名',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(width: 35),
                  pw.Text(
                    '全ページ合計金額　${_formatYen(totalAmount)}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    facilitySettings.facilityName,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return document.save();
  }

  static List<List<CheckinSheetRow>> _splitRows(List<CheckinSheetRow> rows) {
    const rowsPerPage = 12;
    if (rows.isEmpty) return const [<CheckinSheetRow>[]];
    return [
      for (var start = 0; start < rows.length; start += rowsPerPage)
        rows.sublist(
          start,
          start + rowsPerPage > rows.length ? rows.length : start + rowsPerPage,
        ),
    ];
  }

  static pw.TableRow _headerRow() {
    const labels = [
      '部屋',
      'お名前',
      '人数',
      'CI',
      '精算金額',
      '決済',
      '夕食時間・テーブル',
      '入浴時間',
      '朝食時間',
      'CO',
      '備考',
    ];
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        for (final label in labels)
          _cell(
            label,
            height: 34,
            fontSize: 7.4,
            bold: true,
            alignment: pw.Alignment.center,
          ),
      ],
    );
  }

  static pw.TableRow _dataRow(
    CheckinSheetRow row,
    Set<String> displayedKeys,
    FacilitySettings facilitySettings,
    double rowHeight,
  ) {
    final unavailable = !facilitySettings
        .roomByNumber(row.roomNumber)
        .isAvailable;
    var guestName = row.guestName;
    final key = row.reservationKey;
    if (key != null && displayedKeys.contains(key)) {
      guestName = '〃';
    } else if (key != null) {
      displayedKeys.add(key);
    }
    if (unavailable) {
      guestName = '使用不可';
    }

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: unavailable ? PdfColors.grey200 : PdfColors.white,
      ),
      children: [
        _cell(
          facilitySettings.roomByNumber(row.roomNumber).displayName,
          height: rowHeight,
          fontSize: 7.2,
          bold: true,
          alignment: pw.Alignment.center,
        ),
        _cell(guestName, height: rowHeight, fontSize: 8.2),
        _cell(
          unavailable || !row.hasReservation ? '' : '${row.guestCount}',
          height: rowHeight,
          fontSize: 9,
          alignment: pw.Alignment.center,
        ),
        _cell(
          unavailable || !row.hasReservation
              ? ''
              : row.checkedIn
              ? '■'
              : '□',
          height: rowHeight,
          alignment: pw.Alignment.center,
        ),
        _cell(
          unavailable || row.amountYen == null
              ? ''
              : _formatNumber(row.amountYen!),
          height: rowHeight,
          alignment: pw.Alignment.centerRight,
        ),
        _cell(row.payment, height: rowHeight, alignment: pw.Alignment.center),
        _cell(row.dinnerAndTable, height: rowHeight, fontSize: 7.5),
        _cell(row.bathTime, height: rowHeight, alignment: pw.Alignment.center),
        _cell(
          row.breakfastTime,
          height: rowHeight,
          alignment: pw.Alignment.center,
        ),
        _cell(
          unavailable || !row.hasReservation
              ? ''
              : row.checkedOut
              ? '■'
              : '□',
          height: rowHeight,
          alignment: pw.Alignment.center,
        ),
        _cell(row.notes, height: rowHeight, fontSize: 7.2),
      ],
    );
  }

  static pw.Widget _cell(
    String value, {
    double height = 45,
    double fontSize = 8,
    bool bold = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      alignment: alignment,
      child: pw.Text(
        value,
        maxLines: 3,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${value.year}年${value.month}月${value.day}日'
        '（${weekdays[value.weekday - 1]}）';
  }

  static String _fileDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}$month$day';
  }

  static String _formatYen(int value) => '¥${_formatNumber(value)}';

  static String _formatNumber(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return negative ? '-$buffer' : buffer.toString();
  }
}
