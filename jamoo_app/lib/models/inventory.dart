enum InventoryTransactionType {
  purchase,
  sale,
  internalUse,
  waste,
  adjustment,
  returnToStock,
}

extension InventoryTransactionTypePresentation on InventoryTransactionType {
  String get databaseValue => switch (this) {
    InventoryTransactionType.purchase => 'purchase',
    InventoryTransactionType.sale => 'sale',
    InventoryTransactionType.internalUse => 'internal_use',
    InventoryTransactionType.waste => 'waste',
    InventoryTransactionType.adjustment => 'adjustment',
    InventoryTransactionType.returnToStock => 'return_to_stock',
  };

  String get label => switch (this) {
    InventoryTransactionType.purchase => '入荷',
    InventoryTransactionType.sale => '販売',
    InventoryTransactionType.internalUse => '館内使用',
    InventoryTransactionType.waste => '廃棄',
    InventoryTransactionType.adjustment => '棚卸調整',
    InventoryTransactionType.returnToStock => '返品・在庫戻し',
  };

  bool get decreasesStock =>
      this == InventoryTransactionType.sale ||
      this == InventoryTransactionType.internalUse ||
      this == InventoryTransactionType.waste;

  bool get increasesStock =>
      this == InventoryTransactionType.purchase ||
      this == InventoryTransactionType.returnToStock;

  static InventoryTransactionType fromDatabase(String? value) {
    return InventoryTransactionType.values.firstWhere(
      (type) => type.databaseValue == value,
      orElse: () => InventoryTransactionType.adjustment,
    );
  }
}

class InventoryItem {
  const InventoryItem({
    this.id,
    required this.syncKey,
    this.sku,
    this.barcode,
    required this.name,
    required this.category,
    required this.unit,
    required this.currentStock,
    required this.reorderLevel,
    this.costPriceYen,
    this.salePriceYen,
    this.supplier,
    required this.saleEnabled,
    required this.active,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String syncKey;
  final String? sku;
  final String? barcode;
  final String name;
  final String category;
  final String unit;
  final double currentStock;
  final double reorderLevel;
  final int? costPriceYen;
  final int? salePriceYen;
  final String? supplier;
  final bool saleEnabled;
  final bool active;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLowStock => active && currentStock <= reorderLevel;

  int get stockValueYen => ((costPriceYen ?? 0) * currentStock).round();

  InventoryItem copyWith({
    int? id,
    String? syncKey,
    String? sku,
    bool clearSku = false,
    String? barcode,
    bool clearBarcode = false,
    String? name,
    String? category,
    String? unit,
    double? currentStock,
    double? reorderLevel,
    int? costPriceYen,
    bool clearCostPrice = false,
    int? salePriceYen,
    bool clearSalePrice = false,
    String? supplier,
    bool clearSupplier = false,
    bool? saleEnabled,
    bool? active,
    String? notes,
    bool clearNotes = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      syncKey: syncKey ?? this.syncKey,
      sku: clearSku ? null : sku ?? this.sku,
      barcode: clearBarcode ? null : barcode ?? this.barcode,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      currentStock: currentStock ?? this.currentStock,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      costPriceYen: clearCostPrice ? null : costPriceYen ?? this.costPriceYen,
      salePriceYen: clearSalePrice ? null : salePriceYen ?? this.salePriceYen,
      supplier: clearSupplier ? null : supplier ?? this.supplier,
      saleEnabled: saleEnabled ?? this.saleEnabled,
      active: active ?? this.active,
      notes: clearNotes ? null : notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class InventoryTransaction {
  const InventoryTransaction({
    this.id,
    required this.transactionUuid,
    required this.itemId,
    required this.itemName,
    required this.type,
    required this.quantityChange,
    required this.stockAfter,
    this.unitPriceYen,
    this.totalYen,
    this.note,
    this.reservationSource,
    this.reservationNumber,
    this.deviceId,
    required this.occurredAt,
    this.createdAt,
  });

  final int? id;
  final String transactionUuid;
  final int itemId;
  final String itemName;
  final InventoryTransactionType type;
  final double quantityChange;
  final double stockAfter;
  final int? unitPriceYen;
  final int? totalYen;
  final String? note;
  final String? reservationSource;
  final String? reservationNumber;
  final String? deviceId;
  final DateTime occurredAt;
  final DateTime? createdAt;
}

class InventoryDashboardData {
  const InventoryDashboardData({
    required this.items,
    required this.recentTransactions,
    required this.todaySalesYen,
  });

  final List<InventoryItem> items;
  final List<InventoryTransaction> recentTransactions;
  final int todaySalesYen;

  int get activeItemCount => items.where((item) => item.active).length;

  int get lowStockCount => items.where((item) => item.isLowStock).length;

  int get stockValueYen => items
      .where((item) => item.active)
      .fold(0, (total, item) => total + item.stockValueYen);
}

class InventoryMovementResult {
  const InventoryMovementResult({
    required this.quantityChange,
    required this.stockAfter,
  });

  final double quantityChange;
  final double stockAfter;
}

class InventoryStockCalculator {
  const InventoryStockCalculator._();

  static InventoryMovementResult calculate({
    required double currentStock,
    required InventoryTransactionType type,
    required double quantity,
  }) {
    if (quantity < 0) {
      throw const InventoryValidationException('数量は0以上で入力してください。');
    }

    final double change;
    if (type == InventoryTransactionType.adjustment) {
      change = quantity - currentStock;
    } else if (type.decreasesStock) {
      if (quantity <= 0) {
        throw const InventoryValidationException('数量を入力してください。');
      }
      change = -quantity;
    } else {
      if (quantity <= 0) {
        throw const InventoryValidationException('数量を入力してください。');
      }
      change = quantity;
    }

    final stockAfter = currentStock + change;
    if (stockAfter < 0) {
      throw InventoryValidationException(
        '在庫が不足しています。現在庫は${formatInventoryQuantity(currentStock)}です。',
      );
    }

    return InventoryMovementResult(
      quantityChange: change,
      stockAfter: stockAfter,
    );
  }
}

String formatInventoryQuantity(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

class InventoryValidationException implements Exception {
  const InventoryValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
