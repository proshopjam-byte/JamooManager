import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/inventory.dart';
import '../repositories/inventory_repository.dart';
import 'database_service.dart';
import 'inventory_mobile_page.dart';

class InventoryLanServerService {
  InventoryLanServerService._();

  static final InventoryLanServerService instance =
      InventoryLanServerService._();

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  String? _accessToken;
  String _facilityName = 'JamooManager';

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  String? get accessToken => _accessToken;

  Stream<void> get changes => _changes.stream;

  Future<InventoryLanServerStatus> start({
    required String facilityName,
    int preferredPort = 8787,
  }) async {
    if (_server != null) {
      _facilityName = facilityName.trim().isEmpty
          ? 'JamooManager'
          : facilityName.trim();
      return status();
    }

    final db = await DatabaseService.instance.database;
    final token = await _loadOrCreateToken(db);
    final storedPort = await _loadStoredPort(db);
    final targetPort = storedPort ?? preferredPort;

    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        targetPort,
        shared: false,
      );
      _server = server;
      _accessToken = token;
      _facilityName = facilityName.trim().isEmpty
          ? 'JamooManager'
          : facilityName.trim();
      _subscription = server.listen(
        (request) => unawaited(_handleRequest(request)),
        onError: (_) {},
      );
      await _saveMetadata(db, 'inventory_lan_port', server.port.toString());
      return status();
    } on SocketException catch (error) {
      throw InventoryLanServerException(
        '端末接続を開始できませんでした。ポート$targetPortが'
        'ほかのアプリで使用されていないか確認してください。\n$error',
      );
    }
  }

  Future<void> stop() async {
    final subscription = _subscription;
    final server = _server;
    _subscription = null;
    _server = null;
    if (subscription != null) await subscription.cancel();
    if (server != null) await server.close(force: true);
  }

  Future<InventoryLanServerStatus> status() async {
    final addresses = await _privateIpv4Addresses();
    return InventoryLanServerStatus(
      running: isRunning,
      port: port,
      accessToken: _accessToken,
      addresses: addresses,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _setCommonHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && (path == '/' || path == '/inventory')) {
        await _htmlResponse(request.response, inventoryMobilePageHtml);
        return;
      }

      if (!_isAuthorized(request)) {
        await _jsonResponse(
          request.response,
          HttpStatus.unauthorized,
          {'error': '接続コードが正しくありません。'},
        );
        return;
      }

      if (request.method == 'GET' && path == '/api/v1/health') {
        await _jsonResponse(request.response, HttpStatus.ok, {
          'ok': true,
          'service': 'JamooManager Inventory',
          'apiVersion': 1,
          'facilityName': _facilityName,
        });
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/inventory/items') {
        final items = await const InventoryRepository().loadItems();
        await _jsonResponse(request.response, HttpStatus.ok, {
          'items': items.map(_itemJson).toList(growable: false),
        });
        return;
      }
      if (request.method == 'POST' &&
          path == '/api/v1/inventory/movements') {
        await _handleMovement(request);
        return;
      }
      if (request.method == 'POST' &&
          path == '/api/v1/inventory/items/barcode') {
        await _handleBarcodeAssignment(request);
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/inventory/items') {
        await _handleItemCreation(request);
        return;
      }

      await _jsonResponse(request.response, HttpStatus.notFound, {
        'error': '指定された機能が見つかりません。',
      });
    } on InventoryValidationException catch (error) {
      await _jsonResponse(request.response, HttpStatus.conflict, {
        'error': error.message,
      });
    } on InventoryRepositoryException catch (error) {
      await _jsonResponse(request.response, HttpStatus.badRequest, {
        'error': error.message,
      });
    } on FormatException catch (error) {
      await _jsonResponse(request.response, HttpStatus.badRequest, {
        'error': error.message,
      });
    } catch (error) {
      await _jsonResponse(request.response, HttpStatus.internalServerError, {
        'error': '処理中にエラーが発生しました。',
        'detail': error.toString(),
      });
    }
  }

  Future<void> _handleMovement(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.length > 100000) {
      throw const FormatException('送信データが大きすぎます。');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('送信データの形式が正しくありません。');
    }

    final identifier = decoded['itemIdentifier']?.toString().trim() ?? '';
    final transactionUuid = decoded['transactionUuid']?.toString().trim() ?? '';
    final typeValue = decoded['type']?.toString().trim() ?? '';
    final quantity = _readDouble(decoded['quantity']);
    if (identifier.isEmpty || transactionUuid.isEmpty || typeValue.isEmpty) {
      throw const FormatException('商品、処理ID、処理区分を指定してください。');
    }
    final validTypeValues = InventoryTransactionType.values
        .map((type) => type.databaseValue)
        .toSet();
    if (!validTypeValues.contains(typeValue)) {
      throw const FormatException('処理区分が正しくありません。');
    }

    const repository = InventoryRepository();
    final item = await repository.findItemByIdentifier(identifier);
    if (item == null) {
      await _jsonResponse(request.response, HttpStatus.notFound, {
        'error': '商品が見つかりません。Windows版で商品コードを確認してください。',
      });
      return;
    }
    final type = InventoryTransactionTypePresentation.fromDatabase(typeValue);
    if (type == InventoryTransactionType.sale && !item.saleEnabled) {
      throw const InventoryValidationException('この商品は販売対象外です。');
    }

    final transaction = await repository.recordMovement(
      item: item,
      type: type,
      quantity: quantity,
      unitPriceYen: _readNullableInt(decoded['unitPriceYen']),
      note: _nullableText(decoded['note']),
      deviceId: _nullableText(decoded['deviceId']) ?? 'mobile',
      transactionUuid: transactionUuid,
      occurredAt: DateTime.tryParse(decoded['occurredAt']?.toString() ?? ''),
    );
    _changes.add(null);
    await _jsonResponse(request.response, HttpStatus.ok, {
      'ok': true,
      'transactionUuid': transaction.transactionUuid,
      'itemName': transaction.itemName,
      'quantityChange': transaction.quantityChange,
      'stockAfter': transaction.stockAfter,
      'totalYen': transaction.totalYen,
    });
  }

  Future<void> _handleBarcodeAssignment(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.length > 100000) {
      throw const FormatException('送信データが大きすぎます。');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('送信データの形式が正しくありません。');
    }
    final identifier = decoded['itemIdentifier']?.toString().trim() ?? '';
    final barcode = decoded['barcode']?.toString().trim() ?? '';
    if (identifier.isEmpty || barcode.isEmpty) {
      throw const FormatException('商品とバーコードを指定してください。');
    }
    if (barcode.length > 100 || barcode.contains(RegExp(r'[\r\n\t]'))) {
      throw const FormatException('バーコードの形式が正しくありません。');
    }

    const repository = InventoryRepository();
    final item = await repository.findItemByIdentifier(identifier);
    if (item == null) {
      await _jsonResponse(request.response, HttpStatus.notFound, {
        'error': '商品が見つかりません。',
      });
      return;
    }
    final alreadyAssigned = await repository.findItemByIdentifier(barcode);
    if (alreadyAssigned != null && alreadyAssigned.id != item.id) {
      throw InventoryRepositoryException(
        'このバーコードは「${alreadyAssigned.name}」に登録済みです。',
      );
    }
    final saved = await repository.saveItem(
      item.copyWith(barcode: barcode),
    );
    _changes.add(null);
    await _jsonResponse(request.response, HttpStatus.ok, {
      'ok': true,
      'item': _itemJson(saved),
    });
  }

  Future<void> _handleItemCreation(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.length > 100000) {
      throw const FormatException('送信データが大きすぎます。');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('送信データの形式が正しくありません。');
    }

    final barcode = decoded['barcode']?.toString().trim() ?? '';
    final name = decoded['name']?.toString().trim() ?? '';
    final category = decoded['category']?.toString().trim() ?? '';
    final unit = decoded['unit']?.toString().trim() ?? '';
    final currentStock = _readDouble(decoded['currentStock']);
    final reorderLevel = _readDouble(decoded['reorderLevel']);
    if (barcode.isEmpty || name.isEmpty || category.isEmpty || unit.isEmpty) {
      throw const FormatException('バーコード、商品名、分類、単位は必須です。');
    }
    if (barcode.length > 100 || barcode.contains(RegExp(r'[\r\n\t]'))) {
      throw const FormatException('バーコードの形式が正しくありません。');
    }
    if (name.length > 200 || category.length > 100 || unit.length > 30) {
      throw const FormatException('入力文字数が上限を超えています。');
    }
    if (currentStock < 0 || reorderLevel < 0) {
      throw const FormatException('在庫数と最低在庫は0以上で入力してください。');
    }

    const repository = InventoryRepository();
    final existing = await repository.findItemByIdentifier(barcode);
    if (existing != null) {
      throw InventoryRepositoryException(
        'このバーコードは「${existing.name}」に登録済みです。',
      );
    }
    final saved = await repository.saveItem(
      InventoryItem(
        syncKey: InventoryRepository.createSyncKey(),
        sku: _nullableText(decoded['sku']),
        barcode: barcode,
        name: name,
        category: category,
        unit: unit,
        currentStock: currentStock,
        reorderLevel: reorderLevel,
        costPriceYen: _readNullableInt(decoded['costPriceYen']),
        salePriceYen: _readNullableInt(decoded['salePriceYen']),
        supplier: _nullableText(decoded['supplier']),
        saleEnabled: decoded['saleEnabled'] != false,
        active: true,
        notes: _nullableText(decoded['notes']),
      ),
    );
    _changes.add(null);
    await _jsonResponse(request.response, HttpStatus.created, {
      'ok': true,
      'item': _itemJson(saved),
    });
  }

  bool _isAuthorized(HttpRequest request) {
    final expected = _accessToken;
    if (expected == null || expected.isEmpty) return false;
    final supplied = request.headers.value('x-jamoo-token')?.trim();
    return supplied == expected;
  }

  static Map<String, Object?> _itemJson(InventoryItem item) {
    return {
      'syncKey': item.syncKey,
      'sku': item.sku,
      'barcode': item.barcode,
      'name': item.name,
      'category': item.category,
      'unit': item.unit,
      'currentStock': item.currentStock,
      'reorderLevel': item.reorderLevel,
      'costPriceYen': item.costPriceYen,
      'salePriceYen': item.salePriceYen,
      'saleEnabled': item.saleEnabled,
    };
  }

  static void _setCommonHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, X-Jamoo-Token',
    );
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Cache-Control', 'no-store');
  }

  static Future<void> _jsonResponse(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  static Future<void> _htmlResponse(
    HttpResponse response,
    String body,
  ) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'self'; style-src 'unsafe-inline'; "
          "script-src 'unsafe-inline'; img-src 'self' data:; "
          "connect-src 'self'",
    );
    response.write(body);
    await response.close();
  }

  static Future<String> _loadOrCreateToken(Database db) async {
    final rows = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['inventory_lan_token'],
      limit: 1,
    );
    final existing = rows.isEmpty ? null : rows.single['value']?.toString();
    if (existing != null && existing.trim().length >= 8) {
      return existing.trim();
    }
    final random = Random.secure();
    final token = List.generate(8, (_) => random.nextInt(10)).join();
    await _saveMetadata(db, 'inventory_lan_token', token);
    return token;
  }

  static Future<int?> _loadStoredPort(Database db) async {
    final rows = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['inventory_lan_port'],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.single['value']?.toString();
    final port = int.tryParse(value ?? '');
    return port != null && port >= 1024 && port <= 65535 ? port : null;
  }

  static Future<void> _saveMetadata(
    Database db,
    String key,
    String value,
  ) {
    return db.insert('app_metadata', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<String>> _privateIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final all = interfaces
        .expand((interface) => interface.addresses)
        .map((address) => address.address)
        .toSet()
        .toList(growable: false);
    final privateAddresses = all.where(_isPrivateIpv4).toList(growable: false);
    return privateAddresses.isEmpty ? all : privateAddresses;
  }

  static bool _isPrivateIpv4(String address) {
    if (address.startsWith('10.') || address.startsWith('192.168.')) {
      return true;
    }
    final parts = address.split('.');
    if (parts.length != 4 || parts.first != '172') return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  static double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) throw const FormatException('数量を確認してください。');
    return parsed;
  }

  static int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class InventoryLanServerStatus {
  const InventoryLanServerStatus({
    required this.running,
    required this.port,
    required this.accessToken,
    required this.addresses,
  });

  final bool running;
  final int? port;
  final String? accessToken;
  final List<String> addresses;

  List<String> get serverUrls {
    final currentPort = port;
    if (!running || currentPort == null) return const [];
    return addresses
        .map((address) => 'http://$address:$currentPort')
        .toList(growable: false);
  }
}

class InventoryLanServerException implements Exception {
  const InventoryLanServerException(this.message);

  final String message;

  @override
  String toString() => message;
}
