import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  static const String databaseFileName = 'jamoo_manager.db';
  static const int databaseVersion = 5;

  Database? _database;

  Future<Database> get database async {
    final current = _database;

    if (current != null && current.isOpen) {
      return current;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    if (!Platform.isWindows) {
      throw const DatabaseServiceException(
        '現在のJamooManagerデータベースはWindows版を対象にしています。',
      );
    }

    sqfliteFfiInit();

    final supportDirectory = await getApplicationSupportDirectory();

    final dataDirectory = Directory(
      p.join(supportDirectory.path, 'JamooManager', 'data'),
    );

    await dataDirectory.create(recursive: true);

    final databasePath = p.join(dataDirectory.path, databaseFileName);

    final factory = databaseFactoryFfi;

    return factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE reservations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source TEXT NOT NULL,
          external_reservation_id TEXT NOT NULL,
          guest_name TEXT,
          email TEXT,
          phone TEXT,
          check_in TEXT,
          check_out TEXT,
          adults INTEGER NOT NULL DEFAULT 0,
          children INTEGER NOT NULL DEFAULT 0,
          total_guests INTEGER NOT NULL DEFAULT 0,
          room_name TEXT,
          plan_name TEXT,
          price_yen INTEGER,
          status TEXT NOT NULL DEFAULT 'confirmed',
          arrival_time TEXT,
          special_requests TEXT,
          raw_payload TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          UNIQUE(source, external_reservation_id)
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_reservations_check_in
        ON reservations(check_in)
      ''');

      await txn.execute('''
        CREATE INDEX idx_reservations_status
        ON reservations(status)
      ''');

      await txn.execute('''
        CREATE INDEX idx_reservations_guest_name
        ON reservations(guest_name)
      ''');

      await txn.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          full_name TEXT NOT NULL,
          email TEXT,
          phone TEXT,
          postal_code TEXT,
          address TEXT,
          country TEXT,
          first_stay_date TEXT,
          last_stay_date TEXT,
          stay_count INTEGER NOT NULL DEFAULT 0,
          total_spend_yen INTEGER NOT NULL DEFAULT 0,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_customers_email
        ON customers(email)
      ''');

      await txn.execute('''
        CREATE INDEX idx_customers_phone
        ON customers(phone)
      ''');

      await txn.execute('''
        CREATE INDEX idx_customers_name
        ON customers(full_name)
      ''');

      await txn.execute('''
        CREATE TABLE stays (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          reservation_id INTEGER NOT NULL,
          customer_id INTEGER,
          representative_name TEXT,
          address TEXT,
          phone TEXT,
          email TEXT,
          guest_names TEXT,
          signature_name TEXT,
          checked_in_at TEXT,
          checked_out_at TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(reservation_id)
            REFERENCES reservations(id)
            ON DELETE CASCADE,
          FOREIGN KEY(customer_id)
            REFERENCES customers(id)
            ON DELETE SET NULL
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_stays_reservation_id
        ON stays(reservation_id)
      ''');

      await txn.execute('''
        CREATE INDEX idx_stays_customer_id
        ON stays(customer_id)
      ''');

      await txn.execute('''
        CREATE TABLE import_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source TEXT NOT NULL,
          external_message_id TEXT,
          import_type TEXT NOT NULL,
          result TEXT NOT NULL,
          reservation_id INTEGER,
          message TEXT,
          imported_at TEXT NOT NULL,
          FOREIGN KEY(reservation_id)
            REFERENCES reservations(id)
            ON DELETE SET NULL
        )
      ''');

      await txn.execute('''
        CREATE UNIQUE INDEX idx_import_history_message
        ON import_history(source, external_message_id)
        WHERE external_message_id IS NOT NULL
      ''');

      await txn.execute('''
        CREATE TABLE app_metadata (
          key TEXT PRIMARY KEY,
          value TEXT,
          updated_at TEXT NOT NULL
        )
      ''');

      await _createMealOverridesTable(txn);
      await _createCustomerDocumentsTable(txn);
      await _createCheckinSheetRowsTable(txn);
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createMealOverridesTable(db);
    }
    if (oldVersion < 3) {
      await _createCustomerDocumentsTable(db);
    }
    if (oldVersion < 4) {
      await _addCustomerCountryColumn(db);
    }
    if (oldVersion < 5) {
      await _createCheckinSheetRowsTable(db);
    }
  }

  static Future<void> _addCustomerCountryColumn(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customers)');
    final hasCountry = columns.any((row) => row['name'] == 'country');
    if (!hasCountry) {
      await db.execute('ALTER TABLE customers ADD COLUMN country TEXT');
    }
  }

  static Future<void> _createMealOverridesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reservation_meal_overrides (
        reservation_id INTEGER PRIMARY KEY,
        has_breakfast INTEGER NOT NULL,
        has_dinner INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(reservation_id)
          REFERENCES reservations(id)
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createCustomerDocumentsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        original_file_name TEXT NOT NULL,
        stored_file_path TEXT NOT NULL,
        mime_type TEXT,
        ocr_text TEXT,
        ocr_status TEXT NOT NULL DEFAULT 'not_processed',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(customer_id)
          REFERENCES customers(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_documents_customer_id
      ON customer_documents(customer_id)
    ''');
  }

  static Future<void> _createCheckinSheetRowsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checkin_sheet_rows (
        sheet_date TEXT NOT NULL,
        room_number INTEGER NOT NULL,
        reservation_key TEXT,
        reservation_source TEXT,
        reservation_number TEXT,
        guest_name TEXT NOT NULL DEFAULT '',
        guest_count INTEGER NOT NULL DEFAULT 0,
        checked_in INTEGER NOT NULL DEFAULT 0,
        amount_yen INTEGER,
        payment TEXT NOT NULL DEFAULT '',
        dinner_and_table TEXT NOT NULL DEFAULT '',
        bath_time TEXT NOT NULL DEFAULT '',
        breakfast_time TEXT NOT NULL DEFAULT '',
        checked_out INTEGER NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL,
        PRIMARY KEY(sheet_date, room_number)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_checkin_sheet_rows_date
      ON checkin_sheet_rows(sheet_date)
    ''');
  }

  Future<String> databasePath() async {
    final db = await database;
    return db.path;
  }

  Future<bool> isReady() async {
    try {
      final db = await database;

      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' "
        "AND name = 'reservations'",
      );

      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    final db = _database;

    if (db != null && db.isOpen) {
      await db.close();
    }

    _database = null;
  }
}

class DatabaseServiceException implements Exception {
  const DatabaseServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
