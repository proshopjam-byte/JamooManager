import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_service.dart';
import 'portal_reservation_email.dart';

class PortalReservationImportService {
  const PortalReservationImportService();

  Future<PortalImportResult> importEmail(
    PortalReservationEmail email, {
    required String externalMessageId,
  }) async {
    final db = await DatabaseService.instance.database;

    return db.transaction((txn) async {
      final messageId = externalMessageId.trim();
      final imported = await txn.query(
        'import_history',
        columns: const ['reservation_id'],
        where: 'source = ? AND external_message_id = ?',
        whereArgs: ['PORTAL_MAIL', messageId],
        limit: 1,
      );
      if (imported.isNotEmpty) {
        return PortalImportResult(
          action: PortalImportAction.skipped,
          source: email.source,
          reservationNumber: email.reservationNumber,
        );
      }

      final existing = await txn.query(
        'reservations',
        where: 'source = ? AND external_reservation_id = ?',
        whereArgs: [email.source, email.reservationNumber],
        limit: 1,
      );
      final previous = existing.isEmpty ? null : existing.first;
      final previousRaw = _json(previous?['raw_payload']);
      final now = DateTime.now().toUtc().toIso8601String();
      final roomName = _roomName(email.roomName, email.roomCount);

      final adults = email.adults ?? _int(previous?['adults']) ?? 0;
      final children = email.children ?? _int(previous?['children']) ?? 0;
      final totalGuests = email.adults != null || email.children != null
          ? adults + children
          : _int(previous?['total_guests']) ?? adults + children;
      final guestName = email.guestName ?? _text(previous?['guest_name']);
      final checkIn =
          _formatDate(email.checkIn) ?? _text(previous?['check_in']);
      final checkOut =
          _formatDate(email.checkOut) ?? _text(previous?['check_out']);

      final rawPayload = jsonEncode({
        ...?previousRaw,
        'portalMail': true,
        'source': email.source,
        'eventType': email.eventType,
        'reservationNumber': email.reservationNumber,
        if (email.address != null) 'address': email.address,
        if (email.paymentMethod != null) 'paymentMethod': email.paymentMethod,
        if (email.roomCount != null) 'roomCount': email.roomCount,
        if (email.hasBreakfast != null) 'hasBreakfast': email.hasBreakfast,
        if (email.hasDinner != null) 'hasDinner': email.hasDinner,
        if (email.rawBody != null) 'rawBody': email.rawBody,
      });

      final values = <String, Object?>{
        'source': email.source,
        'external_reservation_id': email.reservationNumber,
        'guest_name': guestName,
        'email': email.email ?? _text(previous?['email']),
        'phone': email.phone ?? _text(previous?['phone']),
        'check_in': checkIn,
        'check_out': checkOut,
        'adults': adults,
        'children': children,
        'total_guests': totalGuests,
        'room_name': roomName ?? _text(previous?['room_name']),
        'plan_name': email.planName ?? _text(previous?['plan_name']),
        'price_yen': email.priceYen ?? _int(previous?['price_yen']),
        'status': email.isCancelled ? 'cancelled' : 'confirmed',
        'arrival_time': email.arrivalTime ?? _text(previous?['arrival_time']),
        'special_requests': _text(previous?['special_requests']),
        'raw_payload': rawPayload,
        'updated_at': now,
      };

      late final int reservationId;
      late final PortalImportAction action;
      if (previous == null) {
        reservationId = await txn.insert('reservations', {
          ...values,
          'created_at': now,
        });
        action = email.isCancelled
            ? PortalImportAction.cancelled
            : PortalImportAction.inserted;
      } else {
        reservationId = previous['id'] as int;
        await txn.update(
          'reservations',
          values,
          where: 'id = ?',
          whereArgs: [reservationId],
        );
        action = email.isCancelled
            ? PortalImportAction.cancelled
            : PortalImportAction.updated;
      }

      if (!email.isCancelled && guestName != null && checkIn != null) {
        await _upsertCustomer(
          txn,
          guestName: guestName,
          email: email.email ?? _text(previous?['email']),
          phone: email.phone ?? _text(previous?['phone']),
          address: email.address ?? _text(previousRaw?['address']),
          checkIn: checkIn,
          now: now,
        );
      }

      await txn.insert('import_history', {
        'source': 'PORTAL_MAIL',
        'external_message_id': messageId,
        'import_type': 'portal_email',
        'result': action.name,
        'reservation_id': reservationId,
        'message': '${email.source}の通知メールを反映しました。',
        'imported_at': now,
      });

      return PortalImportResult(
        action: action,
        source: email.source,
        reservationNumber: email.reservationNumber,
      );
    });
  }

  Future<void> _upsertCustomer(
    Transaction txn, {
    required String guestName,
    required String? email,
    required String? phone,
    required String? address,
    required String checkIn,
    required String now,
  }) async {
    late final String where;
    late final List<Object?> whereArgs;
    if (email != null && email.isNotEmpty) {
      where = 'LOWER(email) = LOWER(?)';
      whereArgs = [email];
    } else if (phone != null && phone.isNotEmpty) {
      where = 'phone = ?';
      whereArgs = [phone];
    } else {
      where = 'full_name = ?';
      whereArgs = [guestName];
    }

    final existing = await txn.query(
      'customers',
      columns: const ['id', 'first_stay_date', 'last_stay_date'],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert('customers', {
        'full_name': guestName,
        'email': email,
        'phone': phone,
        'address': address,
        'first_stay_date': checkIn,
        'last_stay_date': checkIn,
        'stay_count': 0,
        'total_spend_yen': 0,
        'created_at': now,
        'updated_at': now,
      });
      return;
    }

    final row = existing.first;
    await txn.update(
      'customers',
      {
        'full_name': guestName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        'first_stay_date': _earlier(_text(row['first_stay_date']), checkIn),
        'last_stay_date': _later(_text(row['last_stay_date']), checkIn),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }

  static String? _roomName(String? name, int? count) {
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    final roomCount = count ?? 1;
    return roomCount > 1 ? '$roomCount x ${name.trim()}' : name.trim();
  }

  static Map<String, Object?>? _json(Object? value) {
    if (value == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(value.toString());
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  static String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _earlier(String? first, String second) {
    return first == null || first.compareTo(second) > 0 ? second : first;
  }

  static String _later(String? first, String second) {
    return first == null || first.compareTo(second) < 0 ? second : first;
  }
}

class PortalImportResult {
  const PortalImportResult({
    required this.action,
    required this.source,
    required this.reservationNumber,
  });

  final PortalImportAction action;
  final String source;
  final String reservationNumber;
}

enum PortalImportAction { inserted, updated, cancelled, skipped }
