import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/reservation.dart';
import '../models/reservation_data.dart';
import 'database_service.dart';

class ReservationImportService {
  const ReservationImportService();

  Future<ReservationImportResult> importReservationData(
    ReservationData data,
  ) async {
    final db = await DatabaseService.instance.database;

    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    await db.transaction((txn) async {
      for (final reservation in data.reservations) {
        final result = await _upsertReservation(
          txn,
          reservation,
        );

        switch (result.action) {
          case ReservationImportAction.inserted:
            inserted++;
            break;
          case ReservationImportAction.updated:
            updated++;
            break;
          case ReservationImportAction.skipped:
            skipped++;
            break;
        }

        if (result.reservationId != null) {
          await txn.insert(
            'import_history',
            {
              'source': reservation.source,
              'external_message_id': null,
              'import_type': 'reservation_json',
              'result': result.action.name,
              'reservation_id': result.reservationId,
              'message':
                  'Booking.com JSONから予約データを取り込みました。',
              'imported_at': DateTime.now()
                  .toUtc()
                  .toIso8601String(),
            },
          );
        }
      }

      final now = DateTime.now()
          .toUtc()
          .toIso8601String();

      await txn.insert(
        'app_metadata',
        {
          'key': 'last_reservation_json_import_at',
          'value': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return ReservationImportResult(
      total: data.reservations.length,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
    );
  }

  Future<_UpsertResult> _upsertReservation(
    Transaction txn,
    Reservation reservation,
  ) async {
    final source = reservation.source.trim();
    final externalReservationId =
        _externalReservationId(reservation);

    if (source.isEmpty ||
        externalReservationId == null) {
      return const _UpsertResult(
        action: ReservationImportAction.skipped,
      );
    }

    final now = DateTime.now()
        .toUtc()
        .toIso8601String();

    final values = <String, Object?>{
      'source': source,
      'external_reservation_id':
          externalReservationId,
      'guest_name': _cleanText(
        reservation.guestName,
      ),
      'email': null,
      'phone': null,
      'check_in': _formatDate(
        reservation.checkIn,
      ),
      'check_out': _formatDate(
        reservation.checkOut,
      ),
      'adults': reservation.adults ?? 0,
      'children': reservation.children,
      'total_guests':
          reservation.totalGuests ??
          ((reservation.adults ?? 0) +
              reservation.children),
      'room_name': _cleanText(
        reservation.roomName,
      ),
      'plan_name': null,
      'price_yen': reservation.priceYen,
      'status': _cleanText(
            reservation.status,
          ) ??
          'confirmed',
      'arrival_time': _cleanText(
        reservation.arrivalTime,
      ),
      'special_requests': null,
      'raw_payload': jsonEncode(
        reservation.toJson(),
      ),
      'updated_at': now,
    };

    final existing = await txn.query(
      'reservations',
      columns: const ['id'],
      where:
          'source = ? AND external_reservation_id = ?',
      whereArgs: [
        source,
        externalReservationId,
      ],
      limit: 1,
    );

    if (existing.isEmpty) {
      final id = await txn.insert(
        'reservations',
        {
          ...values,
          'created_at': now,
        },
      );

      return _UpsertResult(
        action: ReservationImportAction.inserted,
        reservationId: id,
      );
    }

    final id = existing.first['id'] as int;

    await txn.update(
      'reservations',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );

    return _UpsertResult(
      action: ReservationImportAction.updated,
      reservationId: id,
    );
  }

  String? _externalReservationId(
    Reservation reservation,
  ) {
    final reservationNumber = _cleanText(
      reservation.reservationNumber,
    );

    if (reservationNumber != null) {
      return reservationNumber;
    }

    final id = reservation.id.trim();

    if (id.isNotEmpty) {
      return id;
    }

    return null;
  }

  static String? _cleanText(
    String? value,
  ) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  static String? _formatDate(
    DateTime? value,
  ) {
    if (value == null) {
      return null;
    }

    final year = value.year
        .toString()
        .padLeft(4, '0');
    final month = value.month
        .toString()
        .padLeft(2, '0');
    final day = value.day
        .toString()
        .padLeft(2, '0');

    return '$year-$month-$day';
  }
}

class ReservationImportResult {
  const ReservationImportResult({
    required this.total,
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final int total;
  final int inserted;
  final int updated;
  final int skipped;

  bool get hasChanges =>
      inserted > 0 || updated > 0;

  String get summary {
    return '対象$total件 / '
        '新規$inserted件 / '
        '更新$updated件 / '
        'スキップ$skipped件';
  }
}

enum ReservationImportAction {
  inserted,
  updated,
  skipped,
}

class _UpsertResult {
  const _UpsertResult({
    required this.action,
    this.reservationId,
  });

  final ReservationImportAction action;
  final int? reservationId;
}
