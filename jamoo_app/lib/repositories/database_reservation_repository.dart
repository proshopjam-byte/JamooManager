import '../models/reservation.dart';
import '../models/reservation_data.dart';
import '../services/database_service.dart';

class DatabaseReservationRepository {
  const DatabaseReservationRepository();

  Future<ReservationData> loadTodayCheckIns() {
    return loadCheckInsForDate(DateTime.now());
  }

  Future<ReservationData> loadCheckInsForDate(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final targetText = _formatDate(targetDate);
    final db = await DatabaseService.instance.database;

    final rows = await db.query(
      'reservations',
      where: 'check_in = ?',
      whereArgs: [targetText],
      orderBy: 'guest_name COLLATE NOCASE ASC',
    );

    final reservations = rows.map(_reservationFromRow).toList(growable: false);

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

    DateTime? generatedAt;
    if (metadata.isNotEmpty) {
      generatedAt = DateTime.tryParse(
        metadata.first['value']?.toString() ?? '',
      );
    }

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

  Reservation _reservationFromRow(Map<String, Object?> row) {
    final checkIn = _readDate(row['check_in']);
    final checkOut = _readDate(row['check_out']);

    int? nights;
    if (checkIn != null && checkOut != null) {
      nights = checkOut.difference(checkIn).inDays;
    }

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
      totalGuests: _readInt(row['total_guests']),
      priceYen: _readInt(row['price_yen']),
      arrivalTime: _readText(row['arrival_time']),
      bookedOn: null,
      status: _readText(row['status']),
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
}
