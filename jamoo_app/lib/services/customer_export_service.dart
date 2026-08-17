import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../models/customer.dart';

class CustomerExportService {
  const CustomerExportService();

  Future<String?> exportCsv(List<Customer> customers) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final outputPath = await FilePicker.saveFile(
      dialogTitle: '顧客一覧CSVの保存先',
      fileName: 'JamooManager_customers_$date.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return null;
    }

    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      _csvRow(const [
        '氏名',
        '電話番号',
        'メールアドレス',
        '郵便番号',
        '住所',
        '国名',
        '予約経路',
        '予約状態',
        '宿泊回数',
        '累計金額（円）',
        '初回宿泊日',
        '最終宿泊日',
        'メモ',
      ]),
    );
    for (final customer in customers) {
      buffer.writeln(
        _csvRow([
          customer.fullName,
          _excelPhone(customer.phone),
          customer.email ?? '',
          customer.postalCode ?? '',
          customer.address ?? '',
          customer.country ?? '',
          customer.reservationSourceLabel,
          customer.reservationStatusLabel,
          customer.stayCount.toString(),
          customer.totalSpendYen.toString(),
          _formatDate(customer.firstStayDate),
          _formatDate(customer.lastStayDate),
          customer.notes ?? '',
        ]),
      );
    }

    final file = File(outputPath);
    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  Future<String?> exportXlsx(List<Customer> customers) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final outputPath = await FilePicker.saveFile(
      dialogTitle: '顧客一覧Excelファイルの保存先',
      fileName: 'JamooManager_customers_$date.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return null;
    }

    const sheetName = '顧客一覧';
    const headers = [
      '氏名',
      '電話番号',
      'メールアドレス',
      '郵便番号',
      '住所',
      '国名',
      '予約経路',
      '予約状態',
      '宿泊回数',
      '累計金額（円）',
      '初回宿泊日',
      '最終宿泊日',
      'メモ',
    ];
    final workbook = Excel.createExcel();
    final sheet = workbook[sheetName];
    workbook.delete('Sheet1');
    workbook.setDefaultSheet(sheetName);

    final headerStyle = CellStyle(bold: true);
    for (var column = 0; column < headers.length; column++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
        TextCellValue(headers[column]),
        cellStyle: headerStyle,
      );
    }
    sheet.setRowHeight(0, 24);

    for (final customer in customers) {
      sheet.appendRow([
        TextCellValue(customer.fullName),
        TextCellValue(customer.phone ?? ''),
        TextCellValue(customer.email ?? ''),
        TextCellValue(customer.postalCode ?? ''),
        TextCellValue(customer.address ?? ''),
        TextCellValue(customer.country ?? ''),
        TextCellValue(customer.reservationSourceLabel),
        TextCellValue(customer.reservationStatusLabel),
        IntCellValue(customer.stayCount),
        IntCellValue(customer.totalSpendYen),
        TextCellValue(_formatDate(customer.firstStayDate)),
        TextCellValue(_formatDate(customer.lastStayDate)),
        TextCellValue(customer.notes ?? ''),
      ]);
    }

    const columnWidths = <double>[
      20,
      17,
      32,
      13,
      48,
      18,
      22,
      28,
      11,
      16,
      14,
      14,
      32,
    ];
    for (var column = 0; column < columnWidths.length; column++) {
      sheet.setColumnWidth(column, columnWidths[column]);
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw FileSystemException('Excelファイルを作成できませんでした。');
    }
    final file = File(outputPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String _csvRow(List<String> values) {
    return values.map(_escape).join(',');
  }

  static String _escape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _excelPhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) {
      return '';
    }
    if (!RegExp(r'^[0-9+(). -]+$').hasMatch(phone)) {
      return phone;
    }
    return '="$phone"';
  }
}
