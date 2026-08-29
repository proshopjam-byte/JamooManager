import 'reservation.dart';

class DailyOperationsData {
  const DailyOperationsData({
    required this.date,
    required this.generatedAt,
    required this.arrivals,
    required this.occupiedTonight,
    required this.departures,
  });

  final DateTime date;
  final DateTime? generatedAt;
  final List<Reservation> arrivals;
  final List<Reservation> occupiedTonight;
  final List<Reservation> departures;

  List<Reservation> get stayovers => List.unmodifiable(
    occupiedTonight.where(
      (reservation) => !_isSameDate(reservation.checkIn, date),
    ),
  );

  int get arrivalGuests => _guestTotal(arrivals);
  int get stayoverGuests => _guestTotal(stayovers);
  int get departureGuests => _guestTotal(departures);
  int get occupiedGuests => _guestTotal(occupiedTonight);
  int get occupiedRooms => occupiedTonight.fold<int>(
    0,
    (total, reservation) => total + reservation.roomCount,
  );

  int get breakfastGuests {
    final morningGuests = [...departures, ...stayovers];
    return morningGuests.fold<int>(0, (total, reservation) {
      if (reservation.hasBreakfast != true) return total;
      return total +
          (reservation.breakfastGuestCount ?? _guestCount(reservation));
    });
  }

  int get dinnerGuests => occupiedTonight.fold<int>(0, (total, reservation) {
    if (reservation.hasDinner != true) return total;
    return total + _guestCount(reservation);
  });

  int get reviewCount => arrivals
      .where((reservation) => reviewReasons(reservation).isNotEmpty)
      .length;

  bool get isEmpty =>
      arrivals.isEmpty && stayovers.isEmpty && departures.isEmpty;

  bool get isStale {
    final generated = generatedAt?.toLocal();
    if (generated == null) return true;
    final now = DateTime.now();
    return !_isSameDate(generated, now);
  }

  static List<String> reviewReasons(Reservation reservation) {
    final reasons = <String>[];
    if ((reservation.roomName?.trim() ?? '').isEmpty) {
      reasons.add('部屋タイプ未設定');
    }
    if ((reservation.arrivalTime?.trim() ?? '').isEmpty) {
      reasons.add('到着時間未設定');
    }
    if (reservation.priceYen == null) {
      reasons.add('料金未設定');
    }
    if (reservation.hasBreakfast == null || reservation.hasDinner == null) {
      reasons.add('食事未確認');
    }
    return List.unmodifiable(reasons);
  }

  static int _guestTotal(Iterable<Reservation> reservations) {
    return reservations.fold<int>(
      0,
      (total, reservation) => total + _guestCount(reservation),
    );
  }

  static int _guestCount(Reservation reservation) {
    return reservation.totalGuests ??
        (reservation.adults ?? 0) + reservation.children;
  }

  static bool _isSameDate(DateTime? first, DateTime second) {
    return first != null &&
        first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}
