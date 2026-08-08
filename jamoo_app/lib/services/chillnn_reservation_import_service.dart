import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'chillnn_email_parser.dart';
import 'database_service.dart';

class ChillnnReservationImportService {
  const ChillnnReservationImportService();

  Future<ChillnnReservationImportResult> importEmail(
    ChillnnReservationEmail email,
  ) async {
    final db = await DatabaseService.instance.database;

    return db.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final status = _statusFor(email.type);
      final guestCounts = _guestCounts(email);
      final roomName = _roomNames(email);
      final rawPayload = jsonEncode({
        'type': email.type.name,
        'guestName': email.guestName,
        'guestKana': email.guestKana,
        'phone': email.phone,
        'email': email.email,
        'address': email.address,
        'reservationNumber': email.reservationNumber,
        'checkIn': _formatDate(email.checkIn),
        'checkOut': _formatDate(email.checkOut),
        'planName': email.planName,
        'planPriceYen': email.planPriceYen,
        'reservationUrl': email.reservationUrl,
        'paymentMethod': email.paymentMethod,
        'totalPriceYen': email.totalPriceYen,
        'rawBody': email.rawBody,
      });

      final existing = await txn.query(
        'reservations',
        columns: const ['id'],
        where: 'source = ? AND external_reservation_id = ?',
        whereArgs: ['CHILLNN', email.reservationNumber],
        limit: 1,
      );

      final values = <String, Object?>{
        'source': 'CHILLNN',
        'external_reservation_id': email.reservationNumber,
        'guest_name': email.guestName,
        'email': email.email,
        'phone': email.phone,
        'check_in': _formatDate(email.checkIn),
        'check_out': _formatDate(email.checkOut),
        'adults': guestCounts.adults,
        'children': guestCounts.children,
        'total_guests': guestCounts.adults + guestCounts.children,
        'room_name': roomName,
        'plan_name': email.planName,
        'price_yen': email.totalPriceYen,
        'status': status,
        'arrival_time': null,
        'special_requests': null,
        'raw_payload': rawPayload,
        'updated_at': now,
      };

      late final int reservationId;
      late final ChillnnImportAction action;

      if (existing.isEmpty) {
        reservationId = await txn.insert('reservations', {
          ...values,
          'created_at': now,
        });

        action = status == 'cancelled'
            ? ChillnnImportAction.cancelled
            : ChillnnImportAction.inserted;
      } else {
        reservationId = existing.first['id'] as int;

        await txn.update(
          'reservations',
          values,
          where: 'id = ?',
          whereArgs: [reservationId],
        );

        action = status == 'cancelled'
            ? ChillnnImportAction.cancelled
            : ChillnnImportAction.updated;
      }

      if (email.type != ChillnnEmailType.cancelled) {
        await _upsertCustomer(txn, email, now);
      }

      await txn.insert('import_history', {
        'source': 'CHILLNN',
        'external_message_id': null,
        'import_type': 'chillnn_email',
        'result': action.name,
        'reservation_id': reservationId,
        'message': _historyMessage(action),
        'imported_at': now,
      });

      await txn.insert('app_metadata', {
        'key': 'last_reservation_import_at',
        'value': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return ChillnnReservationImportResult(
        action: action,
        reservationId: reservationId,
        reservationNumber: email.reservationNumber,
      );
    });
  }

  Future<void> _upsertCustomer(
    Transaction txn,
    ChillnnReservationEmail email,
    String now,
  ) async {
    final match = _customerMatch(email);

    final existing = await txn.query(
      'customers',
      columns: const ['id', 'first_stay_date', 'last_stay_date'],
      where: match.where,
      whereArgs: match.whereArgs,
      limit: 1,
    );

    final checkInText = _formatDate(email.checkIn);

    if (existing.isEmpty) {
      await txn.insert('customers', {
        'full_name': email.guestName,
        'email': email.email,
        'phone': email.phone,
        'address': email.address,
        'first_stay_date': checkInText,
        'last_stay_date': checkInText,
        'stay_count': 0,
        'total_spend_yen': 0,
        'notes': null,
        'created_at': now,
        'updated_at': now,
      });

      return;
    }

    final row = existing.first;
    final customerId = row['id'] as int;
    final oldFirst = row['first_stay_date']?.toString();
    final oldLast = row['last_stay_date']?.toString();

    await txn.update(
      'customers',
      {
        'full_name': email.guestName,
        if (email.email != null) 'email': email.email,
        if (email.phone != null) 'phone': email.phone,
        if (email.address != null) 'address': email.address,
        'first_stay_date': _earlier(oldFirst, checkInText),
        'last_stay_date': _later(oldLast, checkInText),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  _CustomerMatch _customerMatch(ChillnnReservationEmail email) {
    final emailAddress = email.email?.trim();

    if (emailAddress != null && emailAddress.isNotEmpty) {
      return _CustomerMatch(
        where: 'LOWER(email) = LOWER(?)',
        whereArgs: [emailAddress],
      );
    }

    final phone = email.phone?.trim();

    if (phone != null && phone.isNotEmpty) {
      return _CustomerMatch(where: 'phone = ?', whereArgs: [phone]);
    }

    return _CustomerMatch(where: 'full_name = ?', whereArgs: [email.guestName]);
  }

  _GuestCounts _guestCounts(ChillnnReservationEmail email) {
    final checkInRooms = email.rooms
        .where((room) {
          final date = room.stayDate;

          if (date == null) {
            return true;
          }

          return date.year == email.checkIn.year &&
              date.month == email.checkIn.month &&
              date.day == email.checkIn.day;
        })
        .toList(growable: false);

    final targetRooms = checkInRooms.isEmpty ? email.rooms : checkInRooms;

    var adults = 0;
    var children = 0;

    for (final room in targetRooms) {
      adults += room.adults;
      children += room.children;
    }

    return _GuestCounts(adults: adults, children: children);
  }

  String? _roomNames(ChillnnReservationEmail email) {
    final names = <String>{};

    for (final room in email.rooms) {
      final name = room.roomName.trim();

      if (name.isNotEmpty) {
        names.add(name);
      }
    }

    if (names.isEmpty) {
      return null;
    }

    return names.join(' / ');
  }

  String _statusFor(ChillnnEmailType type) {
    switch (type) {
      case ChillnnEmailType.cancelled:
        return 'cancelled';
      case ChillnnEmailType.newReservation:
      case ChillnnEmailType.changed:
      case ChillnnEmailType.unknown:
        return 'confirmed';
    }
  }

  String _historyMessage(ChillnnImportAction action) {
    switch (action) {
      case ChillnnImportAction.inserted:
        return 'CHILLNNメールから新規予約を取り込みました。';
      case ChillnnImportAction.updated:
        return 'CHILLNNメールから予約情報を更新しました。';
      case ChillnnImportAction.cancelled:
        return 'CHILLNNメールから予約をキャンセルに更新しました。';
    }
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String _earlier(String? first, String second) {
    if (first == null || first.isEmpty) {
      return second;
    }

    return first.compareTo(second) <= 0 ? first : second;
  }

  static String _later(String? first, String second) {
    if (first == null || first.isEmpty) {
      return second;
    }

    return first.compareTo(second) >= 0 ? first : second;
  }
}

class ChillnnReservationImportResult {
  const ChillnnReservationImportResult({
    required this.action,
    required this.reservationId,
    required this.reservationNumber,
  });

  final ChillnnImportAction action;
  final int reservationId;
  final String reservationNumber;

  String get summary {
    switch (action) {
      case ChillnnImportAction.inserted:
        return 'CHILLNN予約を新規登録しました。';
      case ChillnnImportAction.updated:
        return 'CHILLNN予約を更新しました。';
      case ChillnnImportAction.cancelled:
        return 'CHILLNN予約をキャンセルに更新しました。';
    }
  }
}

enum ChillnnImportAction { inserted, updated, cancelled }

class _CustomerMatch {
  const _CustomerMatch({required this.where, required this.whereArgs});

  final String where;
  final List<Object?> whereArgs;
}

class _GuestCounts {
  const _GuestCounts({required this.adults, required this.children});

  final int adults;
  final int children;
}
