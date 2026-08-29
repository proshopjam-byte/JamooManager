import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../models/reservation.dart';
import '../models/reservation_data.dart';
import '../models/daily_operations.dart';
import '../services/database_service.dart';

class DatabaseReservationRepository {
  const DatabaseReservationRepository();

  Future<void> saveArrivalTime({
    required String source,
    required String reservationNumber,
    required String? arrivalTime,
  }) async {
    final db = await DatabaseService.instance.database;
    final normalized = arrivalTime?.trim();
    final updated = await db.update(
      'reservations',
      {
        'arrival_time': normalized == null || normalized.isEmpty
            ? null
            : normalized,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'source = ? AND external_reservation_id = ?',
      whereArgs: [source, reservationNumber],
    );
    if (updated == 0) {
      throw StateError('到着時間を保存する予約が見つかりません。');
    }
  }

  Future<void> saveMealOverride({
    required String source,
    required String reservationNumber,
    required bool hasBreakfast,
    required bool hasDinner,
  }) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'reservations',
      columns: const ['id'],
      where: 'source = ? AND external_reservation_id = ?',
      whereArgs: [source, reservationNumber],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('食事設定の対象予約が見つかりません。');
    }
    final reservationId = rows.first['id'] as int;
    await db.rawInsert(
      'INSERT INTO reservation_meal_overrides '
      '(reservation_id, has_breakfast, has_dinner, updated_at) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(reservation_id) DO UPDATE SET '
      'has_breakfast = excluded.has_breakfast, '
      'has_dinner = excluded.has_dinner, '
      'updated_at = excluded.updated_at',
      [
        reservationId,
        hasBreakfast ? 1 : 0,
        hasDinner ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> saveManualReservation({
    String? reservationNumber,
    required String guestName,
    required DateTime checkIn,
    required DateTime checkOut,
    required String roomName,
    required int adults,
    required int childrenWithBed,
    required int childrenWithoutBed,
    required int? priceYen,
    required String? phone,
    required String? address,
    required String? postalCode,
    required String? notes,
    required bool hasBreakfast,
    required bool hasDinner,
  }) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id =
        reservationNumber ?? 'manual-${DateTime.now().microsecondsSinceEpoch}';
    final values = <String, Object?>{
      'source': 'MANUAL',
      'external_reservation_id': id,
      'guest_name': guestName.trim(),
      'phone': _emptyToNull(phone),
      'check_in': _formatDate(checkIn),
      'check_out': _formatDate(checkOut),
      'adults': adults,
      'children': childrenWithBed + childrenWithoutBed,
      'total_guests': adults + childrenWithBed + childrenWithoutBed,
      'room_name': roomName.trim(),
      'price_yen': priceYen,
      'plan_name': hasDinner
          ? '2食付き'
          : hasBreakfast
          ? '朝食付き'
          : '素泊まり',
      'status': 'confirmed',
      'special_requests': _emptyToNull(notes),
      'raw_payload': jsonEncode({
        'manual': true,
        'address': _emptyToNull(address),
        'postalCode': _emptyToNull(postalCode),
        'hasBreakfast': hasBreakfast,
        'hasDinner': hasDinner,
        'childrenWithBed': childrenWithBed,
        'childrenWithoutBed': childrenWithoutBed,
      }),
      'created_at': now,
      'updated_at': now,
    };

    if (reservationNumber == null) {
      await db.insert('reservations', values);
    } else {
      values.remove('created_at');
      await db.update(
        'reservations',
        values,
        where: 'source = ? AND external_reservation_id = ?',
        whereArgs: ['MANUAL', reservationNumber],
      );
    }
  }

  Future<void> cancelManualReservation(String reservationNumber) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'reservations',
      {
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'source = ? AND external_reservation_id = ?',
      whereArgs: ['MANUAL', reservationNumber],
    );
  }

  Future<List<Reservation>> loadReservationsOverlapping(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery(
      'SELECT r.*, '
      'm.has_breakfast AS override_has_breakfast, '
      'm.has_dinner AS override_has_dinner '
      'FROM reservations r '
      'LEFT JOIN reservation_meal_overrides m ON m.reservation_id = r.id '
      'WHERE r.check_in IS NOT NULL AND r.check_out IS NOT NULL AND '
      'r.check_in <= ? AND r.check_out > ? AND '
      "LOWER(r.status) NOT IN ('cancelled', 'canceled') "
      'ORDER BY r.check_in ASC, r.guest_name COLLATE NOCASE ASC',
      [_formatDate(end), _formatDate(start)],
    );

    return rows.map(_reservationFromRow).toList(growable: false);
  }

  Future<ReservationData> loadTodayCheckIns() {
    return loadCheckInsForDate(DateTime.now());
  }

  /// Loads every active reservation that occupies a room on [date].
  ///
  /// Unlike [loadCheckInsForDate], this includes guests who checked in on an
  /// earlier day and are still staying. The checkout date is deliberately
  /// excluded because the room is no longer occupied for that night's sheet.
  Future<ReservationData> loadStaysForDate(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final targetText = _formatDate(targetDate);
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery(
      'SELECT r.*, '
      'm.has_breakfast AS override_has_breakfast, '
      'm.has_dinner AS override_has_dinner '
      'FROM reservations r '
      'LEFT JOIN reservation_meal_overrides m ON m.reservation_id = r.id '
      'WHERE r.check_in IS NOT NULL AND r.check_out IS NOT NULL AND '
      'r.check_in <= ? AND r.check_out > ? AND '
      "LOWER(r.status) NOT IN ('cancelled', 'canceled') "
      'ORDER BY r.check_in ASC, r.guest_name COLLATE NOCASE ASC',
      [targetText, targetText],
    );

    final reservations = rows.map(_reservationFromRow).toList(growable: false);
    final generatedAt = await _lastImportAt(db);

    return ReservationData(
      schemaVersion: 1,
      generatedAt: generatedAt,
      source: 'All',
      scope: 'staying_guests',
      targetDate: targetDate,
      count: reservations.length,
      reservations: reservations,
    );
  }

  Future<ReservationData> loadCheckInsForDate(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final targetText = _formatDate(targetDate);
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'reservations',
      where:
          "check_in = ? AND "
          "LOWER(status) NOT IN ('cancelled', 'canceled')",
      whereArgs: [targetText],
      orderBy: 'guest_name COLLATE NOCASE ASC',
    );

    final reservations = rows.map(_reservationFromRow).toList(growable: false);

    final generatedAt = await _lastImportAt(db);

    return ReservationData(
      schemaVersion: 1,
      generatedAt: generatedAt,
      source: 'Booking.com',
      scope: 'today_checkins',
      targetDate: targetDate,
      count: reservations.length,
      reservations: reservations,
    );
  }

  Future<ReservationData> loadCheckOutsForDate(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final targetText = _formatDate(targetDate);
    final db = await DatabaseService.instance.database;

    final rows = await db.rawQuery(
      'SELECT r.*, '
      'm.has_breakfast AS override_has_breakfast, '
      'm.has_dinner AS override_has_dinner '
      'FROM reservations r '
      'LEFT JOIN reservation_meal_overrides m ON m.reservation_id = r.id '
      'WHERE r.check_out = ? AND '
      "LOWER(r.status) NOT IN ('cancelled', 'canceled') "
      'ORDER BY r.guest_name COLLATE NOCASE ASC',
      [targetText],
    );

    final reservations = rows.map(_reservationFromRow).toList(growable: false);
    final generatedAt = await _lastImportAt(db);

    return ReservationData(
      schemaVersion: 1,
      generatedAt: generatedAt,
      source: 'All',
      scope: 'today_checkouts',
      targetDate: targetDate,
      count: reservations.length,
      reservations: reservations,
    );
  }

  Future<DailyOperationsData> loadDailyOperationsForDate(DateTime date) async {
    final results = await Future.wait<ReservationData>([
      loadCheckInsForDate(date),
      loadStaysForDate(date),
      loadCheckOutsForDate(date),
    ]);
    return DailyOperationsData(
      date: DateTime(date.year, date.month, date.day),
      generatedAt:
          results[0].generatedAt ??
          results[1].generatedAt ??
          results[2].generatedAt,
      arrivals: results[0].sortedByCheckIn,
      occupiedTonight: results[1].sortedByCheckIn,
      departures: results[2].sortedByCheckIn,
    );
  }

  Future<DateTime?> _lastImportAt(Database db) async {
    final metadata = await db.query(
      'app_metadata',
      columns: const ['value'],
      where: 'key IN (?, ?)',
      whereArgs: const [
        'last_reservation_import_at',
        'last_reservation_json_import_at',
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (metadata.isNotEmpty) {
      return DateTime.tryParse(metadata.first['value']?.toString() ?? '');
    }
    return null;
  }

  Reservation _reservationFromRow(Map<String, Object?> row) {
    final checkIn = _readDate(row['check_in']);
    final checkOut = _readDate(row['check_out']);

    int? nights;
    if (checkIn != null && checkOut != null) {
      nights = checkOut.difference(checkIn).inDays;
    }

    final rawData = _readJsonData(row['raw_payload']);
    final manualData = rawData?['manual'] == true ? rawData : null;
    final portalData = rawData?['portalMail'] == true ? rawData : null;
    final planName = _readText(row['plan_name']);
    final inferredMeals = _inferMeals(planName);
    final overrideBreakfast = _readBool(row['override_has_breakfast']);
    final overrideDinner = _readBool(row['override_has_dinner']);
    final guestCount =
        _readInt(row['total_guests']) ??
        ((_readInt(row['adults']) ?? 0) + (_readInt(row['children']) ?? 0));
    final chillnnBreakfastCount = _chillnnBreakfastCount(
      source: row['source']?.toString(),
      rawData: rawData,
      nights: nights,
      maximumGuests: guestCount,
      hasBreakfast: inferredMeals.breakfast,
    );
    final hasBreakfast =
        overrideBreakfast ??
        manualData?['hasBreakfast'] as bool? ??
        portalData?['hasBreakfast'] as bool? ??
        inferredMeals.breakfast;

    return Reservation(
      id: row['external_reservation_id']?.toString() ?? row['id'].toString(),
      source: row['source']?.toString() ?? 'Booking.com',
      reservationNumber: row['external_reservation_id']?.toString(),
      guestName: _readText(row['guest_name']),
      roomName: _readText(row['room_name']),
      checkIn: checkIn,
      checkOut: checkOut,
      nights: nights,
      adults: _readInt(row['adults']),
      children: _readInt(row['children']) ?? 0,
      childrenWithBed: _readInt(manualData?['childrenWithBed']),
      childrenWithoutBed: _readInt(manualData?['childrenWithoutBed']),
      totalGuests: _readInt(row['total_guests']),
      priceYen: _readInt(row['price_yen']),
      arrivalTime: _readText(row['arrival_time']),
      bookedOn: null,
      status: _readText(row['status']),
      phone: _readText(row['phone']),
      email: _readText(row['email']),
      address: _readText(rawData?['address']),
      postalCode: _readText(rawData?['postalCode']),
      specialRequests: _readText(row['special_requests']),
      hasBreakfast: hasBreakfast,
      breakfastGuestCount: hasBreakfast == true
          ? (overrideBreakfast != null || manualData != null
                ? guestCount
                : chillnnBreakfastCount ?? guestCount)
          : 0,
      hasDinner:
          overrideDinner ??
          manualData?['hasDinner'] as bool? ??
          portalData?['hasDinner'] as bool? ??
          inferredMeals.dinner,
      planName: planName,
    );
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _readDate(Object? value) {
    final text = _readText(value);

    if (text == null) {
      return null;
    }

    return DateTime.tryParse(text);
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static bool? _readBool(Object? value) {
    final number = _readInt(value);
    return number == null ? null : number != 0;
  }

  static String? _emptyToNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Map<String, Object?>? _readJsonData(Object? value) {
    final text = _readText(value);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Imported reservation payloads use different formats.
    }
    return null;
  }

  static int? _chillnnBreakfastCount({
    required String? source,
    required Map<String, Object?>? rawData,
    required int? nights,
    required int maximumGuests,
    required bool? hasBreakfast,
  }) {
    if (source?.toUpperCase() != 'CHILLNN' || hasBreakfast != true) {
      return null;
    }

    final planPrice = _readInt(rawData?['planPriceYen']);
    final stayNights = nights ?? 0;
    if (planPrice == null || planPrice <= 0 || stayNights <= 0) {
      return null;
    }

    const breakfastPricePerPerson = 2200;
    final count = (planPrice / breakfastPricePerPerson / stayNights).round();
    if (count <= 0) return null;
    return count > maximumGuests ? maximumGuests : count;
  }

  static ({bool? breakfast, bool? dinner}) _inferMeals(String? planName) {
    final text = planName?.trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return (breakfast: null, dinner: null);
    }
    if (text.contains('素泊') || text.contains('standard rate')) {
      return (breakfast: false, dinner: false);
    }
    final twoMeals =
        text.contains('2食') ||
        text.contains('二食') ||
        text.contains('朝夕') ||
        text.contains('朝・夕');
    final hasBreakfastKeyword =
        text.contains('朝食') || text.contains('onbreakfast');
    final hasDinnerKeyword = text.contains('夕食') || text.contains('ディナー');
    if (!twoMeals && !hasBreakfastKeyword && !hasDinnerKeyword) {
      return (breakfast: null, dinner: null);
    }
    return (
      breakfast: twoMeals || hasBreakfastKeyword,
      dinner: twoMeals || hasDinnerKeyword,
    );
  }
}
