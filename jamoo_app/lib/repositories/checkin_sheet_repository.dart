import '../models/checkin_sheet.dart';
import '../services/database_service.dart';

class CheckinSheetRepository {
  const CheckinSheetRepository();

  Future<List<CheckinSheetRow>> load(
    DateTime date, {
    required List<GuestRoomSpec> rooms,
  }) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'checkin_sheet_rows',
      where: 'sheet_date = ?',
      whereArgs: [_formatDate(date)],
      orderBy: 'room_number ASC',
    );

    final stored = <int, CheckinSheetRow>{
      for (final row in rows) _readInt(row['room_number']): _fromRow(row),
    };

    return rooms
        .map(
          (room) => stored[room.number] ?? CheckinSheetRow.empty(room.number),
        )
        .toList(growable: false);
  }

  Future<void> save(DateTime date, List<CheckinSheetRow> rows) async {
    final db = await DatabaseService.instance.database;
    final sheetDate = _formatDate(date);
    final updatedAt = DateTime.now().toUtc().toIso8601String();

    await db.transaction((transaction) async {
      await transaction.delete(
        'checkin_sheet_rows',
        where: 'sheet_date = ?',
        whereArgs: [sheetDate],
      );

      final batch = transaction.batch();
      for (final row in rows) {
        batch.insert('checkin_sheet_rows', {
          'sheet_date': sheetDate,
          'room_number': row.roomNumber,
          'reservation_key': row.reservationKey,
          'reservation_source': row.reservationSource,
          'reservation_number': row.reservationNumber,
          'guest_name': row.guestName.trim(),
          'guest_count': row.guestCount,
          'checked_in': row.checkedIn ? 1 : 0,
          'amount_yen': row.amountYen,
          'payment': row.payment.trim(),
          'dinner_and_table': row.dinnerAndTable.trim(),
          'bath_time': row.bathTime.trim(),
          'breakfast_time': row.breakfastTime.trim(),
          'checked_out': row.checkedOut ? 1 : 0,
          'notes': row.notes.trim(),
          'updated_at': updatedAt,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  static CheckinSheetRow _fromRow(Map<String, Object?> row) {
    return CheckinSheetRow(
      roomNumber: _readInt(row['room_number']),
      reservationKey: _readNullableText(row['reservation_key']),
      reservationSource: _readNullableText(row['reservation_source']),
      reservationNumber: _readNullableText(row['reservation_number']),
      guestName: _readText(row['guest_name']),
      guestCount: _readInt(row['guest_count']),
      checkedIn: _readInt(row['checked_in']) != 0,
      amountYen: _readNullableInt(row['amount_yen']),
      payment: _readText(row['payment']),
      dinnerAndTable: _readText(row['dinner_and_table']),
      bathTime: _readText(row['bath_time']),
      breakfastTime: _readText(row['breakfast_time']),
      checkedOut: _readInt(row['checked_out']) != 0,
      notes: _readText(row['notes']),
    );
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _readText(Object? value) => value?.toString() ?? '';

  static String? _readNullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _readInt(Object? value) => _readNullableInt(value) ?? 0;

  static int? _readNullableInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
