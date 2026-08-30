import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/models/daily_operations.dart';
import 'package:jamoo_app/models/reservation.dart';

void main() {
  test('到着・連泊・出発と夕食・翌朝食人数を集計する', () {
    final date = DateTime(2026, 8, 30);
    final departure = _reservation(
      id: 'departure',
      checkIn: DateTime(2026, 8, 29),
      checkOut: date,
      guests: 2,
      hasBreakfast: true,
      breakfastGuests: 2,
      hasDinner: false,
    );
    final stayover = _reservation(
      id: 'stayover',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 31),
      guests: 2,
      hasBreakfast: true,
      breakfastGuests: 2,
      hasDinner: true,
    );
    final arrival = _reservation(
      id: 'arrival',
      checkIn: date,
      checkOut: DateTime(2026, 8, 31),
      guests: 3,
      hasBreakfast: true,
      hasDinner: true,
      arrivalTime: null,
    );

    final data = DailyOperationsData(
      date: date,
      generatedAt: date,
      arrivals: [arrival],
      occupiedTonight: [stayover, arrival],
      departures: [departure],
    );

    expect(data.arrivalGuests, 3);
    expect(data.stayoverGuests, 2);
    expect(data.departureGuests, 2);
    expect(data.occupiedGuests, 5);
    expect(data.occupiedRooms, 2);
    expect(data.breakfastGuests, 5);
    expect(data.dinnerGuests, 5);
    expect(data.reviewCount, 1);
    expect(DailyOperationsData.reviewReasons(arrival), ['到着時間未設定']);
    expect(
      DailyOperationsData.reviewReasons(
        arrival.copyWith(arrivalTime: '15:00〜16:00'),
      ),
      isEmpty,
    );
  });

  test('日別人数を宿泊・翌朝食・夕食の集計へ反映する', () {
    final date = DateTime(2026, 8, 30);
    final stayover = _reservation(
      id: 'daily-guests',
      checkIn: DateTime(2026, 8, 29),
      checkOut: DateTime(2026, 8, 31),
      guests: 2,
      hasBreakfast: true,
      hasDinner: true,
      breakfastGuests: null,
      dailyGuestCounts: [
        ReservationDailyGuestCount(
          date: DateTime(2026, 8, 29),
          adults: 2,
          childrenWithBed: 0,
          childrenWithoutBed: 0,
        ),
        ReservationDailyGuestCount(
          date: date,
          adults: 1,
          childrenWithBed: 0,
          childrenWithoutBed: 0,
        ),
      ],
    );
    final data = DailyOperationsData(
      date: date,
      generatedAt: date,
      arrivals: const [],
      occupiedTonight: [stayover],
      departures: const [],
    );

    expect(data.stayoverGuests, 1);
    expect(data.occupiedGuests, 1);
    expect(data.breakfastGuests, 1);
    expect(data.dinnerGuests, 1);
  });

  test('日別人数を予約データへ保存・復元する', () {
    final reservation = _reservation(
      id: 'daily-json',
      checkIn: DateTime(2026, 9, 1),
      checkOut: DateTime(2026, 9, 3),
      guests: 1,
      hasBreakfast: false,
      hasDinner: false,
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
          childrenWithBed: 1,
          childrenWithoutBed: 0,
        ),
      ],
    );

    final restored = Reservation.fromJson(reservation.toJson());

    expect(restored.totalGuestsOn(DateTime(2026, 9, 1)), 1);
    expect(restored.totalGuestsOn(DateTime(2026, 9, 2)), 3);
    expect(restored.guestCountOn(DateTime(2026, 9, 2)).childrenWithBed, 1);
    expect(restored.displayGuestCountOn(DateTime(2026, 9, 1)), '大人1名');
    expect(restored.displayGuestCountOn(DateTime(2026, 9, 2)), '大人2名・子供1名');
  });
}

Reservation _reservation({
  required String id,
  required DateTime checkIn,
  required DateTime checkOut,
  required int guests,
  required bool hasBreakfast,
  required bool hasDinner,
  int? breakfastGuests,
  String? arrivalTime = '15:00',
  List<ReservationDailyGuestCount> dailyGuestCounts = const [],
}) {
  return Reservation(
    id: id,
    source: 'TEST',
    reservationNumber: id,
    guestName: id,
    roomName: 'ツイン',
    checkIn: checkIn,
    checkOut: checkOut,
    nights: checkOut.difference(checkIn).inDays,
    adults: guests,
    children: 0,
    totalGuests: guests,
    priceYen: 10000,
    arrivalTime: arrivalTime,
    bookedOn: null,
    status: 'confirmed',
    hasBreakfast: hasBreakfast,
    breakfastGuestCount: breakfastGuests,
    hasDinner: hasDinner,
    planName: null,
    dailyGuestCounts: dailyGuestCounts,
  );
}
