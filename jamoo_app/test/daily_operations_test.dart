import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/models/daily_operations.dart';
import 'package:jamoo_app/models/reservation.dart';

void main() {
  test('到着・連泊・出発と食事人数を集計する', () {
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
      hasBreakfast: false,
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
    expect(data.breakfastGuests, 4);
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
  );
}
