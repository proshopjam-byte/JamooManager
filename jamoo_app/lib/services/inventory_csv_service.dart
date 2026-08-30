import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/inventory.dart';
import '../repositories/inventory_repository.dart';

class InventoryCsvService {
  const InventoryCsvService({this.repository = const InventoryRepository()});

  final InventoryRepository repository;

  static const headers = [
    '商品コード',
    'バーコード',
    '商品名',
    '分類',
    '単位',
    '現在庫',
    '最低在庫',
    '仕入単価',
    '販売価格',
    '仕入先',
    '販売対象',
    '備考',
  ];

  Future<String?> exportCsv(List<InventoryItem> items) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final outputPath = await FilePicker.saveFile(
      dialogTitle: '在庫表CSVの保存先',
      fileName: 'JamooManager_inventory_$date.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return null;
    }

    final buffer = StringBuffer('\uFEFF')..writeln(_csvRow(headers));
    for (final item in items) {
      buffer.writeln(
        _csvRow([
          item.sku ?? '',
          item.barcode ?? '',
          item.name,
          item.category,
          item.unit,
          formatInventoryQuantity(item.currentStock),
          formatInventoryQuantity(item.reorderLevel),
          item.costPriceYen?.toString() ?? '',
          item.salePriceYen?.toString() ?? '',
          item.supplier ?? '',
          item.saleEnabled ? 'はい' : 'いいえ',
          item.notes ?? '',
        ]),
      );
    }

    final file = File(outputPath);
    await file.writeAsString(buffer.toString(), encoding: utf8, flush: true);
    return file.path;
  }

  Future<InventoryCsvImportResult?> pickAndImport() async {
    final selection = await FilePicker.pickFiles(
      dialogTitle: '取り込む在庫表CSVを選択',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      allowMultiple: false,
    );
    if (selection == null || selection.files.isEmpty) {
      return null;
    }
    final path = selection.files.single.path;
    if (path == null || path.trim().isEmpty) {
      throw const InventoryCsvException('選択したCSVファイルの場所を取得できませんでした。');
    }
    return importFile(File(path));
  }

  Future<InventoryCsvImportResult> importFile(File file) async {
    if (!await file.exists()) {
      throw InventoryCsvException('CSVファイルが見つかりません。\n${file.path}');
    }
    final bytes = await file.readAsBytes();
    var content = utf8.decode(bytes);
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      throw const InventoryCsvException('CSVにデータがありません。');
    }

    final headerIndexes = <String, int>{};
    for (var i = 0; i < rows.first.length; i++) {
      headerIndexes[rows.first[i].trim()] = i;
    }
    for (final requiredHeader in const ['商品名']) {
      if (!headerIndexes.containsKey(requiredHeader)) {
        throw InventoryCsvException('必須列「$requiredHeader」がありません。');
      }
    }

    final existingItems = await repository.loadItems(includeInactive: true);
    final bySku = <String, InventoryItem>{
      for (final item in existingItems)
        if ((item.sku ?? '').isNotEmpty) item.sku!: item,
    };
    final byBarcode = <String, InventoryItem>{
      for (final item in existingItems)
        if ((item.barcode ?? '').isNotEmpty) item.barcode!: item,
    };
    final byDescription = <String, InventoryItem>{
      for (final item in existingItems)
        _descriptionKey(item.name, item.category, item.unit): item,
    };

    var added = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.trim().isEmpty)) continue;
      try {
        String value(String header) {
          final index = headerIndexes[header];
          if (index == null || index >= row.length) return '';
          return row[index].trim();
        }

        final name = value('商品名');
        if (name.isEmpty) {
          skipped++;
          errors.add('${rowIndex + 1}行目：商品名が空です。');
          continue;
        }
        final sku = value('商品コード');
        final barcode = value('バーコード');
        final existing =
            (barcode.isEmpty ? null : byBarcode[barcode]) ??
            (sku.isEmpty ? null : bySku[sku]) ??
            byDescription[_descriptionKey(
              name,
              value('分類'),
              value('単位').isEmpty ? '個' : value('単位'),
            )];
        final importedStock = _doubleValue(value('現在庫'), fallback: 0);
        final item = InventoryItem(
          id: existing?.id,
          syncKey: existing?.syncKey ?? InventoryRepository.createSyncKey(),
          sku: _nullable(sku),
          barcode: _nullable(barcode),
          name: name,
          category: value('分類'),
          unit: value('単位').isEmpty ? '個' : value('単位'),
          currentStock: existing?.currentStock ?? importedStock,
          reorderLevel: _doubleValue(value('最低在庫'), fallback: 0),
          costPriceYen: _intValue(value('仕入単価')),
          salePriceYen: _intValue(value('販売価格')),
          supplier: _nullable(value('仕入先')),
          saleEnabled: _boolValue(value('販売対象'), fallback: true),
          active: true,
          notes: _nullable(value('備考')),
          createdAt: existing?.createdAt,
          updatedAt: existing?.updatedAt,
        );
        final saved = await repository.saveItem(item);
        if (existing == null) {
          added++;
          if (sku.isNotEmpty) bySku[sku] = saved;
          if (barcode.isNotEmpty) byBarcode[barcode] = saved;
          byDescription[_descriptionKey(
                saved.name,
                saved.category,
                saved.unit,
              )] =
              saved;
        } else {
          updated++;
          if (importedStock != existing.currentStock) {
            await repository.recordMovement(
              item: saved,
              type: InventoryTransactionType.adjustment,
              quantity: importedStock,
              note: 'CSV取込による棚卸調整',
            );
          }
        }
      } catch (error) {
        skipped++;
        errors.add('${rowIndex + 1}行目：$error');
      }
    }

    return InventoryCsvImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  static String _csvRow(List<String> values) => values.map(_escape).join(',');

  static String _escape(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  static List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;

    for (var i = 0; i < content.length; i++) {
      final character = content[i];
      if (character == '"') {
        if (quoted && i + 1 < content.length && content[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((character == '\n' || character == '\r') && !quoted) {
        if (character == '\r' &&
            i + 1 < content.length &&
            content[i + 1] == '\n') {
          i++;
        }
        row.add(field.toString());
        rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(character);
      }
    }
    if (field.length > 0 || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  static double _doubleValue(String value, {required double fallback}) =>
      double.tryParse(value.replaceAll(',', '').trim()) ?? fallback;

  static int? _intValue(String value) =>
      int.tryParse(value.replaceAll(',', '').replaceAll('¥', '').trim());

  static bool _boolValue(String value, {required bool fallback}) {
    final normalized = value.trim().toLowerCase();
    if (const ['はい', 'true', '1', 'yes', 'on'].contains(normalized)) {
      return true;
    }
    if (const ['いいえ', 'false', '0', 'no', 'off'].contains(normalized)) {
      return false;
    }
    return fallback;
  }

  static String _descriptionKey(String name, String category, String unit) {
    return '${name.trim().toLowerCase()}|'
        '${category.trim().toLowerCase()}|'
        '${unit.trim().toLowerCase()}';
  }
}

class InventoryCsvImportResult {
  const InventoryCsvImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.errors,
  });

  final int added;
  final int updated;
  final int skipped;
  final List<String> errors;

  String get summary => '追加 $added件・更新 $updated件・スキップ $skipped件';
}

class InventoryCsvException implements Exception {
  const InventoryCsvException(this.message);

  final String message;

  @override
  String toString() => message;
}
