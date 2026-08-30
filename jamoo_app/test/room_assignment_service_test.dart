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
      result.rows.singleWhere((row) => row.reservationKey == continuingKey).roomNumber,
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

  test('連泊途中で手動変更した人数を保存後も維持する', () {
    final continuing = _reservation(
      id: 'manual-guest-count',
      guestName: '人数変更 客',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 9, 1),
      guests: 2,
      priceYen: 30000,
    );
    final service = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 30),
    );
    final savedRows = service.create([continuing]).rows.map((row) {
      if (!row.hasReservation) return row;
      return row.copyWith(
        guestCount: 1,
        guestCountManuallyChanged: true,
      );
    }).toList(growable: false);

    final result = service.reconcileWithCarryForward(
      savedRows,
      const [],
      [continuing],
    );
    final assigned = result.rows.where((row) => row.hasReservation).toList();

    expect(assigned, hasLength(1));
    expect(assigned.single.guestCount, 1);
    expect(assigned.single.guestCountManuallyChanged, isTrue);
    expect(result.warnings, isEmpty);
  });

  test('連泊途中で手動変更した人数を翌日に引き継ぐ', () {
    final continuing = _reservation(
      id: 'carry-manual-guest-count',
      guestName: '人数引継 客',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 9, 1),
      guests: 2,
      priceYen: 30000,
    );
    final previousService = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 30),
    );
    final previousRows = previousService.create([continuing]).rows.map((row) {
      if (!row.hasReservation) return row;
      return row.copyWith(
        guestCount: 1,
        guestCountManuallyChanged: true,
      );
    }).toList(growable: false);

    final result = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 8, 31),
    ).carryForward(previousRows, [continuing]);
    final assigned = result.rows.where((row) => row.hasReservation).toList();

    expect(assigned, hasLength(1));
    expect(assigned.single.guestCount, 1);
    expect(assigned.single.guestCountManuallyChanged, isTrue);
    expect(assigned.single.notes, contains('連泊中（3泊目／全3泊）'));
    expect(result.warnings, isEmpty);
  });

  test('直接予約の日別人数を同じ部屋へ反映する', () {
    final continuing = _reservation(
      id: 'daily-guest-counts',
      guestName: '日別人数 客',
      checkIn: DateTime(2026, 9, 1),
      checkOut: DateTime(2026, 9, 4),
      guests: 1,
      priceYen: 46500,
      dailyGuestCounts: [
        ReservationDailyGuestCount(
          date: DateTime(2026, 9, 1),
          adults: 1,
          childrenWithBed: 0,
          childrenWithoutBed: 0,
        ),
        ReservationDailyGuestCount(
          date: DateTime(2026, 9, 2),
          adults: 2,
          childrenWithBed: 0,
          childrenWithoutBed: 0,
        ),
        ReservationDailyGuestCount(
          date: DateTime(2026, 9, 3),
          adults: 1,
          childrenWithBed: 0,
          childrenWithoutBed: 0,
        ),
      ],
    );
    final firstNight = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 9, 1),
    ).create([continuing]);
    final secondNight = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 9, 2),
    ).carryForward(firstNight.rows, [continuing]);
    final thirdNight = RoomAssignmentService(
      rooms: rooms,
      stayDate: DateTime(2026, 9, 3),
    ).carryForward(secondNight.rows, [continuing]);

    final first = firstNight.rows.singleWhere((row) => row.hasReservation);
    final second = secondNight.rows.singleWhere((row) => row.hasReservation);
    final third = thirdNight.rows.singleWhere((row) => row.hasReservation);
    expect(first.guestCount, 1);
    expect(second.guestCount, 2);
    expect(third.guestCount, 1);
    expect({first.roomNumber, second.roomNumber, third.roomNumber}, {1});
    expect(secondNight.warnings, isEmpty);
    expect(thirdNight.warnings, isEmpty);
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
    final savedRows = service.create([continuing]).rows.map((row) {
      if (!row.hasReservation) return row;
      return row.copyWith(notes: '低い枕を希望');
    }).toList(growable: false);

    final result = service.reconcileWithCarryForward(
      savedRows,
      const [],
      [continuing],
    );
    final row = result.rows.firstWhere((value) => value.hasReservation);

    expect(row.notes, '連泊開始（1泊目／全2泊）・低い枕を希望');
    expect(row.checkedIn, isFalse);
    expect(row.amountYen, 24000);
    expect(row.payment, '現地');
  });

  test('自由入力した部屋タイプ名を予約内容から照合する', () {
    const customRooms = [
      GuestRoomSpec(
        number: 101,
        label: '和室6畳',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.other,
      ),
      GuestRoomSpec(
        number: 201,
        label: '離れ',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.other,
      ),
    ];
    final reservation = _reservation(
      id: 'custom-room-type',
      guestName: '離れ指定 客',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 30),
      guests: 2,
      priceYen: 18000,
      roomName: '離れ',
    );

    final result = RoomAssignmentService(
      rooms: customRooms,
      stayDate: DateTime(2026, 8, 29),
    ).create([reservation]);

    expect(
      result.rows.singleWhere((row) => row.hasReservation).roomNumber,
      201,
    );
    expect(result.warnings, isEmpty);
  });

  test('複数部屋の予約では設定した隣室を優先する', () {
    const customRooms = [
      GuestRoomSpec(
        number: 101,
        label: 'ファミリー',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.other,
        adjacentRoomNumbers: [305],
      ),
      GuestRoomSpec(
        number: 202,
        label: 'ファミリー',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.other,
        adjacentRoomNumbers: [203],
      ),
      GuestRoomSpec(
        number: 203,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 2,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 305,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 2,
        type: GuestRoomType.standardTwin,
      ),
    ];
    final reservation = _reservation(
      id: 'adjacent-rooms',
      guestName: '家族 グループ',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 30),
      guests: 5,
      priceYen: 40000,
      roomName: '',
    );

    final result = RoomAssignmentService(
      rooms: customRooms,
      stayDate: DateTime(2026, 8, 29),
    ).create([reservation]);
    final assignedRooms = result.rows
        .where((row) => row.hasReservation)
        .map((row) => row.roomNumber)
        .toSet();

    expect(assignedRooms, {101, 305});
    expect(result.warnings, isEmpty);
  });

  test('旧設定でも大人数を大部屋と近い小部屋へ割り当てる', () {
    const legacyRooms = [
      GuestRoomSpec(
        number: 1,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 2,
        label: 'ロフト付き',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.loft,
      ),
      GuestRoomSpec(
        number: 3,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 7,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 8,
        label: 'ロフト付き',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.loft,
      ),
    ];
    final reservation = _reservation(
      id: 'legacy-large-group',
      guestName: '五名 グループ',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 30),
      guests: 5,
      priceYen: 45000,
      roomName: 'ロフト付き4人部屋',
    );

    final result = RoomAssignmentService(
      rooms: legacyRooms,
      stayDate: DateTime(2026, 8, 29),
    ).create([reservation]);
    final assignedRooms = result.rows
        .where((row) => row.hasReservation)
        .map((row) => row.roomNumber)
        .toSet();

    expect(assignedRooms, {2, 3});
    expect(result.warnings, isEmpty);
  });

  test('自由入力した同一タイプを複数室予約できる', () {
    const customRooms = [
      GuestRoomSpec(
        number: 11,
        label: '和室',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.other,
      ),
      GuestRoomSpec(
        number: 12,
        label: '和室',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.other,
      ),
    ];
    final reservation = _reservation(
      id: 'multiple-custom-rooms',
      guestName: '二部屋 予約',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 30),
      guests: 2,
      priceYen: 20000,
      roomName: '2 x 和室',
    );

    final result = RoomAssignmentService(
      rooms: customRooms,
      stayDate: DateTime(2026, 8, 29),
    ).create([reservation]);

    expect(
      result.rows.where((row) => row.hasReservation).length,
      2,
    );
    expect(result.warnings, isEmpty);
  });

  test('隣室設定を保存・復元し、旧設定は空のまま読み込む', () {
    const room = GuestRoomSpec(
      number: 101,
      roomName: '白樺',
      label: '和室',
      normalCapacity: 2,
      capacity: 4,
      type: GuestRoomType.other,
      adjacentRoomNumbers: [102, 103],
    );

    final restored = GuestRoomSpec.fromJson(room.toJson());
    final legacy = GuestRoomSpec.fromJson({
      'number': 1,
      'label': 'ツイン',
      'normalCapacity': 2,
      'capacity': 3,
      'type': 'standardTwin',
      'isAvailable': true,
    });

    expect(restored.adjacentRoomNumbers, [102, 103]);
    expect(restored.roomName, '白樺');
    expect(restored.displayName, '白樺');
    expect(legacy.adjacentRoomNumbers, isEmpty);
    expect(legacy.roomName, isEmpty);
    expect(legacy.displayName, '1号室');
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
  String roomName = 'ツイン',
  List<ReservationDailyGuestCount> dailyGuestCounts = const [],
}) {
  return Reservation(
    id: id,
    source: 'MANUAL',
    reservationNumber: id,
    guestName: guestName,
    roomName: roomName,
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
    dailyGuestCounts: dailyGuestCounts,
  );
}
