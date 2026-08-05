import 'reservation.dart';

class ReservationData {
  const ReservationData({
    required this.schemaVersion,
    required this.generatedAt,
    required this.source,
    required this.count,
    required this.reservations,
  });

  final int schemaVersion;
  final DateTime? generatedAt;
  final String source;
  final int count;
  final List<Reservation> reservations;

  factory ReservationData.fromJson(Map<String, dynamic> json) {
    final rawReservations = json['reservations'];

    if (rawReservations is! List) {
      throw const FormatException(
        'reservations が配列ではありません。',
      );
    }

    final reservations = rawReservations.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          'reservations 内のデータ形式が不正です。',
        );
      }

      return Reservation.fromJson(item);
    }).toList(growable: false);

    final declaredCount = _readNullableInt(json['count']);

    return ReservationData(
      schemaVersion: _readNullableInt(json['schemaVersion']) ?? 1,
      generatedAt: _readNullableDateTime(json['generatedAt']),
      source: _readRequiredString(json, 'source'),
      count: declaredCount ?? reservations.length,
      reservations: reservations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt?.toIso8601String(),
      'source': source,
      'count': reservations.length,
      'reservations': reservations
          .map((reservation) => reservation.toJson())
          .toList(growable: false),
    };
  }

  bool get isEmpty => reservations.isEmpty;

  bool get isNotEmpty => reservations.isNotEmpty;

  int get totalGuests {
    return reservations.fold<int>(
      0,
      (sum, reservation) =>
          sum + (reservation.totalGuests ?? 0),
    );
  }

  int get totalPriceYen {
    return reservations.fold<int>(
      0,
      (sum, reservation) =>
          sum + (reservation.priceYen ?? 0),
    );
  }

  List<Reservation> get sortedByCheckIn {
    final sorted = List<Reservation>.from(reservations);

    sorted.sort((first, second) {
      final firstDate = first.checkIn;
      final secondDate = second.checkIn;

      if (firstDate == null && secondDate == null) {
        return first.displayGuestName.compareTo(
          second.displayGuestName,
        );
      }

      if (firstDate == null) {
        return 1;
      }

      if (secondDate == null) {
        return -1;
      }

      final dateComparison = firstDate.compareTo(secondDate);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return first.displayGuestName.compareTo(
        second.displayGuestName,
      );
    });

    return List.unmodifiable(sorted);
  }

  List<Reservation> reservationsForDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);

    return reservations.where((reservation) {
      final checkIn = reservation.checkIn;
      final checkOut = reservation.checkOut;

      if (checkIn == null || checkOut == null) {
        return false;
      }

      final start = DateTime(
        checkIn.year,
        checkIn.month,
        checkIn.day,
      );

      final end = DateTime(
        checkOut.year,
        checkOut.month,
        checkOut.day,
      );

      return !target.isBefore(start) && target.isBefore(end);
    }).toList(growable: false);
  }

  Reservation? findByReservationNumber(
    String reservationNumber,
  ) {
    final target = reservationNumber.trim();

    if (target.isEmpty) {
      return null;
    }

    for (final reservation in reservations) {
      if (reservation.reservationNumber == target) {
        return reservation;
      }
    }

    return null;
  }

  static String _readRequiredString(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];

    if (value == null) {
      throw FormatException('$key がありません。');
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      throw FormatException('$key が空です。');
    }

    return text;
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static DateTime? _readNullableDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }
}
