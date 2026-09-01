import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/models/app_settings.dart';
import 'package:jamoo_app/models/inventory.dart';
import 'package:jamoo_app/repositories/inventory_repository.dart';
import 'package:jamoo_app/services/inventory_csv_service.dart';
import 'package:jamoo_app/services/inventory_mobile_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late InventoryRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE inventory_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_key TEXT NOT NULL UNIQUE,
        sku TEXT UNIQUE,
        barcode TEXT UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT '個',
        current_stock REAL NOT NULL DEFAULT 0,
        reorder_level REAL NOT NULL DEFAULT 0,
        cost_price_yen INTEGER,
        sale_price_yen INTEGER,
        supplier TEXT,
        sale_enabled INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_uuid TEXT NOT NULL UNIQUE,
        item_id INTEGER NOT NULL,
        transaction_type TEXT NOT NULL,
        quantity_change REAL NOT NULL,
        stock_after REAL NOT NULL,
        unit_price_yen INTEGER,
        total_yen INTEGER,
        note TEXT,
        reservation_source TEXT,
        reservation_number TEXT,
        device_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'local',
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(item_id) REFERENCES inventory_items(id)
      )
    ''');
    repository = InventoryRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('入荷と販売で在庫・販売額・履歴を更新する', () async {
    final item = await repository.saveItem(
      InventoryItem(
        syncKey: InventoryRepository.createSyncKey(),
        sku: 'DRINK-001',
        barcode: '490000000001',
        name: 'オーガニックジュース',
        category: '飲料',
        unit: '本',
        currentStock: 2,
        reorderLevel: 2,
        costPriceYen: 180,
        salePriceYen: 350,
        saleEnabled: true,
        active: true,
      ),
    );

    await repository.recordMovement(
      item: item,
      type: InventoryTransactionType.purchase,
      quantity: 5,
    );
    final afterPurchase = (await repository.loadItems()).single;
    expect(afterPurchase.currentStock, 7);

    await repository.recordMovement(
      item: afterPurchase,
      type: InventoryTransactionType.sale,
      quantity: 3,
    );
    final dashboard = await repository.loadDashboard();

    expect(dashboard.items.single.currentStock, 4);
    expect(dashboard.todaySalesYen, 1050);
    expect(
      dashboard.recentTransactions.first.type,
      InventoryTransactionType.sale,
    );
    expect(dashboard.recentTransactions.first.stockAfter, 4);
  });

  test('販売数が現在庫を超えた場合は保存しない', () async {
    final item = await repository.saveItem(
      InventoryItem(
        syncKey: InventoryRepository.createSyncKey(),
        name: 'アメニティ',
        category: '消耗品',
        unit: '個',
        currentStock: 1,
        reorderLevel: 1,
        saleEnabled: true,
        active: true,
      ),
    );

    expect(
      repository.recordMovement(
        item: item,
        type: InventoryTransactionType.sale,
        quantity: 2,
      ),
      throwsA(isA<InventoryValidationException>()),
    );
    expect((await repository.loadItems()).single.currentStock, 1);
  });

  test('棚卸調整は入力値を調整後在庫として扱う', () {
    final result = InventoryStockCalculator.calculate(
      currentStock: 8,
      type: InventoryTransactionType.adjustment,
      quantity: 5,
    );

    expect(result.quantityChange, -3);
    expect(result.stockAfter, 5);
  });

  test('端末から同じ処理IDが再送されても在庫を二重に減らさない', () async {
    final item = await repository.saveItem(
      InventoryItem(
        syncKey: InventoryRepository.createSyncKey(),
        barcode: '490000000099',
        name: '端末販売テスト',
        category: '食品',
        unit: '個',
        currentStock: 3,
        reorderLevel: 1,
        salePriceYen: 500,
        saleEnabled: true,
        active: true,
      ),
    );

    await repository.recordMovement(
      item: item,
      type: InventoryTransactionType.sale,
      quantity: 1,
      deviceId: 'chromebook',
      transactionUuid: 'mobile-transaction-001',
    );
    await repository.recordMovement(
      item: item,
      type: InventoryTransactionType.sale,
      quantity: 1,
      deviceId: 'chromebook',
      transactionUuid: 'mobile-transaction-001',
    );

    final dashboard = await repository.loadDashboard();
    expect(dashboard.items.single.currentStock, 2);
    expect(
      (await repository.findItemByIdentifier('490000000099'))?.name,
      '端末販売テスト',
    );
    expect(
      dashboard.recentTransactions
          .where(
            (transaction) =>
                transaction.transactionUuid == 'mobile-transaction-001',
          )
          .length,
      1,
    );
  });

  test('スマホ・Chromebook用画面に必要な操作が含まれる', () {
    expect(inventoryMobilePageHtml, contains('在庫・販売'));
    expect(inventoryMobilePageHtml, contains('接続コード'));
    expect(inventoryMobilePageHtml, contains('館内使用'));
    expect(inventoryMobilePageHtml, contains('棚卸調整'));
    expect(inventoryMobilePageHtml, contains('setInterval'));
    expect(inventoryMobilePageHtml, contains('コード再入力'));
    expect(inventoryMobilePageHtml, contains('バーコード読み取り'));
    expect(inventoryMobilePageHtml, contains('capture="environment"'));
    expect(inventoryMobilePageHtml, contains('BarcodeDetector'));
    expect(inventoryMobilePageHtml, contains('decodeEan13'));
    expect(inventoryMobilePageHtml, contains('USBバーコードリーダー'));
  });

  test('既存商品にバーコードを登録して番号で検索できる', () async {
    final item = await repository.saveItem(
      InventoryItem(
        syncKey: InventoryRepository.createSyncKey(),
        name: 'バーコード登録テスト',
        category: '食品',
        unit: '個',
        currentStock: 2,
        reorderLevel: 1,
        saleEnabled: true,
        active: true,
      ),
    );

    await repository.saveItem(item.copyWith(barcode: '4901234567894'));

    final found = await repository.findItemByIdentifier('4901234567894');
    expect(found?.name, 'バーコード登録テスト');
  });

  test('旧設定ファイルでも在庫管理は初期値で有効になる', () {
    final settings = AppSettings.fromJson(const {
      'appName': 'JamooManager',
      'facilityName': 'テスト施設',
    });

    expect(settings.inventoryEnabled, isTrue);
  });

  test('商品コードがなくても商品名・分類・単位が同じCSVは既存商品を更新する', () async {
    await repository.saveItem(
      InventoryItem(
        syncKey: InventoryRepository.createSyncKey(),
        name: '生アーモンドバター',
        category: '食品',
        unit: '個',
        currentStock: 1,
        reorderLevel: 2,
        costPriceYen: 836,
        salePriceYen: 1200,
        saleEnabled: true,
        active: true,
      ),
    );
    final directory = await Directory.systemTemp.createTemp(
      'jamoo_inventory_test_',
    );
    try {
      final file = File('${directory.path}/inventory.csv');
      await file.writeAsString(
        '"商品コード","バーコード","商品名","分類","単位","現在庫",'
        '"最低在庫","仕入単価","販売価格","仕入先","販売対象","備考"\n'
        '"","","生アーモンドバター","食品","個","3","2",'
        '"836","1200","","はい",""\n',
      );
      final result = await InventoryCsvService(
        repository: repository,
      ).importFile(file);
      final items = await repository.loadItems();

      expect(result.added, 0);
      expect(result.updated, 1);
      expect(items, hasLength(1));
      expect(items.single.currentStock, 3);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
