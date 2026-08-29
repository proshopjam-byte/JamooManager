import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/models/checkin_sheet.dart';
import 'package:jamoo_app/models/reservation.dart';
import 'package:jamoo_app/services/room_assignment_service.dart';

void main() {
  const rooms = [
    GuestRoomSpec(
      number: 1,
      label: 'ツイン',
      normalCapacity: 2,
      capacity: 3,
      type: GuestRoomType.standardTwin,
    ),
    GuestRoomSpec(
      number: 2,
      label: 'ツイン',
      normalCapacity: 2,
      capacity: 3,
      type: GuestRoomType.standardTwin,
    ),
  ];

  test('連泊客を同じ部屋の翌日シートへ引き継ぐ', () {
    final continuing = _reservation(
      id: 'continuing',
      guestName: '連泊 太郎',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 9, 1),
      guests: 2,
      priceYen: 30000,
    );
    final arrivalService = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 29),
    );
    final previousRows = arrivalService.create([continuing]).rows;
    final arrivalRow = previousRows.firstWhere((row) => row.hasReservation);

    expect(arrivalRow.checkedIn, isFalse);
    expect(arrivalRow.amountYen, 30000);
    expect(arrivalRow.payment, '現地');
    expect(arrivalRow.notes, contains('連泊開始（1泊目／全3泊）'));

    final stayoverService = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 30),
    );
    final result = stayoverService.carryForward(previousRows, [continuing]);
    final continuedRow = result.rows.firstWhere((row) => row.hasReservation);

    expect(continuedRow.roomNumber, 1);
    expect(continuedRow.checkedIn, isTrue);
    expect(continuedRow.amountYen, isNull);
    expect(continuedRow.payment, isEmpty);
    expect(continuedRow.notes, contains('連泊中（2泊目／全3泊）'));
    expect(result.warnings, isEmpty);
  });

  test('連泊客の部屋を維持し、当日到着客を空室へ割り当てる', () {
    final continuing = _reservation(
      id: 'continuing',
      guestName: '連泊 太郎',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 9, 1),
      guests: 2,
      priceYen: 30000,
    );
    final newArrival = _reservation(
      id: 'new-arrival',
      guestName: '到着 花子',
      checkIn: DateTime(2026, 8, 30),
      checkOut: DateTime(2026, 8, 31),
      guests: 2,
      priceYen: 12000,
    );
    final previousRows = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 29),
    ).create([continuing]).rows;

    final result = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 30),
    ).carryForward(previousRows, [continuing, newArrival]);
    final continuingKey = RoomAssignmentService.reservationKey(continuing);
    final arrivalKey = RoomAssignmentService.reservationKey(newArrival);

    expect(
      result.rows
          .singleWhere((row) => row.reservationKey == continuingKey)
          .roomNumber,
      1,
    );
    final arrivalRow = result.rows.singleWhere(
      (row) => row.reservationKey == arrivalKey,
    );
    expect(arrivalRow.roomNumber, 2);
    expect(arrivalRow.checkedIn, isFalse);
    expect(arrivalRow.amountYen, 12000);
    expect(result.warnings, isEmpty);
  });

  test('保存済みの1泊目にも連泊表示を追加し、手入力内容を残す', () {
    final continuing = _reservation(
      id: 'saved-first-night',
      guestName: '保存済み 連泊客',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 31),
      guests: 2,
      priceYen: 24000,
    );
    final service = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 29),
    );
    final savedRows = service
        .create([continuing])
        .rows
        .map((row) {
          if (!row.hasReservation) return row;
          return row.copyWith(notes: '低い枕を希望');
        })
        .toList(growable: false);

    final result = service.reconcileWithCarryForward(savedRows, const [], [
      continuing,
    ]);
    final row = result.rows.firstWhere((value) => value.hasReservation);

    expect(row.notes, '連泊開始（1泊目／全2泊）・低い枕を希望');
    expect(row.checkedIn, isFalse);
    expect(row.amountYen, 24000);
    expect(row.payment, '現地');
  });

  test('宿泊日の判定はチェックイン日を含みチェックアウト日を除く', () {
    final reservation = _reservation(
      id: 'date-boundary',
      guestName: '日付確認',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 31),
      guests: 1,
      priceYen: 10000,
    );

    expect(reservation.staysOn(DateTime(2026, 8, 28)), isFalse);
    expect(reservation.staysOn(DateTime(2026, 8, 29)), isTrue);
    expect(reservation.staysOn(DateTime(2026, 8, 30)), isTrue);
    expect(reservation.staysOn(DateTime(2026, 8, 31)), isFalse);
  });
}

Reservation _reservation({
  required String id,
  required String guestName,
  required DateTime checkIn,
  required DateTime checkOut,
  required int guests,
  required int priceYen,
}) {
  return Reservation(
    id: id,
    source: 'MANUAL',
    reservationNumber: id,
    guestName: guestName,
    roomName: 'ツイン',
    checkIn: checkIn,
    checkOut: checkOut,
    nights: checkOut.difference(checkIn).inDays,
    adults: guests,
    children: 0,
    totalGuests: guests,
    priceYen: priceYen,
    arrivalTime: null,
    bookedOn: null,
    status: 'confirmed',
    hasBreakfast: false,
    hasDinner: false,
  );
}
