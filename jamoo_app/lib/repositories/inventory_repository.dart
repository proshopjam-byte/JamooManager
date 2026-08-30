import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/inventory.dart';
import '../services/database_service.dart';

class InventoryRepository {
  const InventoryRepository({this.database});

  final Database? database;

  Future<Database> _database() async =>
      database ?? DatabaseService.instance.database;

  Future<InventoryDashboardData> loadDashboard({
    String searchText = '',
    bool lowStockOnly = false,
  }) async {
    final db = await _database();
    final normalizedSearch = searchText.trim();
    final where = <String>['active = 1'];
    final whereArgs = <Object?>[];

    if (normalizedSearch.isNotEmpty) {
      where.add(
        '(name LIKE ? OR category LIKE ? OR sku LIKE ? OR barcode LIKE ?)',
      );
      final pattern = '%$normalizedSearch%';
      whereArgs.addAll([pattern, pattern, pattern, pattern]);
    }
    if (lowStockOnly) {
      where.add('current_stock <= reorder_level');
    }

    final itemRows = await db.query(
      'inventory_items',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    final transactionRows = await db.rawQuery('''
      SELECT t.*, i.name AS item_name
      FROM inventory_transactions t
      JOIN inventory_items i ON i.id = t.item_id
      ORDER BY t.occurred_at DESC, t.id DESC
      LIMIT 50
    ''');

    final localNow = DateTime.now();
    final start = DateTime(localNow.year, localNow.month, localNow.day).toUtc();
    final end = start.add(const Duration(days: 1));
    final salesRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_yen), 0) AS total
      FROM inventory_transactions
      WHERE transaction_type = ?
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
      [
        InventoryTransactionType.sale.databaseValue,
        start.toIso8601String(),
        end.toIso8601String(),
      ],
    );

    return InventoryDashboardData(
      items: itemRows.map(_itemFromRow).toList(growable: false),
      recentTransactions: transactionRows
          .map(_transactionFromRow)
          .toList(growable: false),
      todaySalesYen: _readInt(
        salesRows.isEmpty ? null : salesRows.first['total'],
      ),
    );
  }

  Future<List<InventoryItem>> loadItems({bool includeInactive = false}) async {
    final db = await _database();
    final rows = await db.query(
      'inventory_items',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(_itemFromRow).toList(growable: false);
  }

  Future<InventoryItem> saveItem(InventoryItem item) async {
    final db = await _database();
    final now = DateTime.now().toUtc();
    final normalizedSku = _nullableText(item.sku);
    final normalizedBarcode = _nullableText(item.barcode);

    try {
      if (item.id == null) {
        return db.transaction((txn) async {
          final id = await txn.insert('inventory_items', {
            'sync_key': item.syncKey,
            'sku': normalizedSku,
            'barcode': normalizedBarcode,
            'name': item.name.trim(),
            'category': item.category.trim(),
            'unit': item.unit.trim(),
            'current_stock': item.currentStock,
            'reorder_level': item.reorderLevel,
            'cost_price_yen': item.costPriceYen,
            'sale_price_yen': item.salePriceYen,
            'supplier': _nullableText(item.supplier),
            'sale_enabled': item.saleEnabled ? 1 : 0,
            'active': item.active ? 1 : 0,
            'notes': _nullableText(item.notes),
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
          if (item.currentStock != 0) {
            await _insertTransaction(
              txn,
              itemId: id,
              type: InventoryTransactionType.adjustment,
              quantityChange: item.currentStock,
              stockAfter: item.currentStock,
              note: '初期在庫',
              occurredAt: now,
            );
          }
          return item.copyWith(id: id, createdAt: now, updatedAt: now);
        });
      }

      await db.update(
        'inventory_items',
        {
          'sku': normalizedSku,
          'barcode': normalizedBarcode,
          'name': item.name.trim(),
          'category': item.category.trim(),
          'unit': item.unit.trim(),
          'current_stock': item.currentStock,
          'reorder_level': item.reorderLevel,
          'cost_price_yen': item.costPriceYen,
          'sale_price_yen': item.salePriceYen,
          'supplier': _nullableText(item.supplier),
          'sale_enabled': item.saleEnabled ? 1 : 0,
          'active': item.active ? 1 : 0,
          'notes': _nullableText(item.notes),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
      return item.copyWith(updatedAt: now);
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const InventoryRepositoryException('同じ商品コードまたはバーコードが既に登録されています。');
      }
      throw InventoryRepositoryException('商品を保存できませんでした。\n$error');
    }
  }

  Future<void> deactivateItem(int itemId) async {
    final db = await _database();
    await db.update(
      'inventory_items',
      {'active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<InventoryTransaction> recordMovement({
    required InventoryItem item,
    required InventoryTransactionType type,
    required double quantity,
    int? unitPriceYen,
    String? note,
    String? reservationSource,
    String? reservationNumber,
    String deviceId = 'windows',
    DateTime? occurredAt,
  }) async {
    final itemId = item.id;
    if (itemId == null) {
      throw const InventoryRepositoryException('商品がまだ保存されていません。');
    }
    final db = await _database();
    final movementAt = (occurredAt ?? DateTime.now()).toUtc();

    return db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_items',
        columns: ['current_stock', 'name'],
        where: 'id = ? AND active = 1',
        whereArgs: [itemId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const InventoryRepositoryException('対象の商品が見つかりません。');
      }

      final currentStock = _readDouble(rows.single['current_stock']);
      final result = InventoryStockCalculator.calculate(
        currentStock: currentStock,
        type: type,
        quantity: quantity,
      );
      final effectiveUnitPrice =
          unitPriceYen ??
          (type == InventoryTransactionType.sale
              ? item.salePriceYen
              : type == InventoryTransactionType.purchase
              ? item.costPriceYen
              : null);
      final totalYen = effectiveUnitPrice == null
          ? null
          : (effectiveUnitPrice * result.quantityChange.abs()).round();

      await txn.update(
        'inventory_items',
        {
          'current_stock': result.stockAfter,
          'updated_at': movementAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
      final transactionUuid = _transactionUuid(movementAt);
      final transactionId = await _insertTransaction(
        txn,
        transactionUuid: transactionUuid,
        itemId: itemId,
        type: type,
        quantityChange: result.quantityChange,
        stockAfter: result.stockAfter,
        unitPriceYen: effectiveUnitPrice,
        totalYen: totalYen,
        note: note,
        reservationSource: reservationSource,
        reservationNumber: reservationNumber,
        deviceId: deviceId,
        occurredAt: movementAt,
      );

      return InventoryTransaction(
        id: transactionId,
        transactionUuid: transactionUuid,
        itemId: itemId,
        itemName: rows.single['name']?.toString() ?? item.name,
        type: type,
        quantityChange: result.quantityChange,
        stockAfter: result.stockAfter,
        unitPriceYen: effectiveUnitPrice,
        totalYen: totalYen,
        note: _nullableText(note),
        reservationSource: _nullableText(reservationSource),
        reservationNumber: _nullableText(reservationNumber),
        deviceId: deviceId,
        occurredAt: movementAt,
        createdAt: movementAt,
      );
    });
  }

  static Future<int> _insertTransaction(
    DatabaseExecutor db, {
    String? transactionUuid,
    required int itemId,
    required InventoryTransactionType type,
    required double quantityChange,
    required double stockAfter,
    int? unitPriceYen,
    int? totalYen,
    String? note,
    String? reservationSource,
    String? reservationNumber,
    String? deviceId,
    required DateTime occurredAt,
  }) {
    return db.insert('inventory_transactions', {
      'transaction_uuid': transactionUuid ?? _transactionUuid(occurredAt),
      'item_id': itemId,
      'transaction_type': type.databaseValue,
      'quantity_change': quantityChange,
      'stock_after': stockAfter,
      'unit_price_yen': unitPriceYen,
      'total_yen': totalYen,
      'note': _nullableText(note),
      'reservation_source': _nullableText(reservationSource),
      'reservation_number': _nullableText(reservationNumber),
      'device_id': _nullableText(deviceId),
      'sync_status': 'local',
      'occurred_at': occurredAt.toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static String createSyncKey() {
    final now = DateTime.now().toUtc();
    return 'item-${now.microsecondsSinceEpoch}';
  }

  static String _transactionUuid(DateTime occurredAt) {
    return 'movement-${occurredAt.microsecondsSinceEpoch}-'
        '${DateTime.now().microsecondsSinceEpoch}';
  }

  static InventoryItem _itemFromRow(Map<String, Object?> row) {
    return InventoryItem(
      id: _readInt(row['id']),
      syncKey: row['sync_key']?.toString() ?? '',
      sku: _nullableText(row['sku']),
      barcode: _nullableText(row['barcode']),
      name: row['name']?.toString() ?? '',
      category: row['category']?.toString() ?? '',
      unit: row['unit']?.toString() ?? '個',
      currentStock: _readDouble(row['current_stock']),
      reorderLevel: _readDouble(row['reorder_level']),
      costPriceYen: _nullableInt(row['cost_price_yen']),
      salePriceYen: _nullableInt(row['sale_price_yen']),
      supplier: _nullableText(row['supplier']),
      saleEnabled: _readInt(row['sale_enabled']) != 0,
      active: _readInt(row['active']) != 0,
      notes: _nullableText(row['notes']),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  static InventoryTransaction _transactionFromRow(Map<String, Object?> row) {
    return InventoryTransaction(
      id: _readInt(row['id']),
      transactionUuid: row['transaction_uuid']?.toString() ?? '',
      itemId: _readInt(row['item_id']),
      itemName: row['item_name']?.toString() ?? '',
      type: InventoryTransactionTypePresentation.fromDatabase(
        row['transaction_type']?.toString(),
      ),
      quantityChange: _readDouble(row['quantity_change']),
      stockAfter: _readDouble(row['stock_after']),
      unitPriceYen: _nullableInt(row['unit_price_yen']),
      totalYen: _nullableInt(row['total_yen']),
      note: _nullableText(row['note']),
      reservationSource: _nullableText(row['reservation_source']),
      reservationNumber: _nullableText(row['reservation_number']),
      deviceId: _nullableText(row['device_id']),
      occurredAt:
          DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
    );
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _readInt(Object? value) => _nullableInt(value) ?? 0;

  static int? _nullableInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class InventoryRepositoryException implements Exception {
  const InventoryRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
