import 'reservation.dart';

class ReservationData {
  const ReservationData({
    required this.schemaVersion,
    required this.generatedAt,
    required this.source,
    required this.scope,
    required this.targetDate,
    required this.count,
    required this.reservations,
  });

  final int schemaVersion;
  final DateTime? generatedAt;
  final String source;

  /// 取得範囲。
  ///
  /// 現在のBooking.com取得処理では
  /// `today_checkins` が入ります。
  final String? scope;

  /// 取得対象日。
  ///
  /// JSONでは `2026-08-05` のような形式です。
  final DateTime? targetDate;

  final int count;
  final List<Reservation> reservations;

  factory ReservationData.fromJson(Map<String, dynamic> json) {
    final rawReservations = json['reservations'];

    if (rawReservations is! List) {
      throw const FormatException('reservations が配列ではありません。');
    }

    final reservations = rawReservations
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('reservations 内のデータ形式が不正です。');
          }

          return Reservation.fromJson(item);
        })
        .toList(growable: false);

    final declaredCount = _readNullableInt(json['count']);

    return ReservationData(
      schemaVersion: _readNullableInt(json['schemaVersion']) ?? 1,
      generatedAt: _readNullableDateTime(json['generatedAt']),
      source: _readRequiredString(json, 'source'),
      scope: _readNullableString(json['scope']),
      targetDate: _readNullableDate(json['targetDate']),
      count: declaredCount ?? reservations.length,
      reservations: reservations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt?.toIso8601String(),
      'source': source,
      'scope': scope,
      'targetDate': _dateToJson(targetDate),
      'count': reservations.length,
      'reservations': reservations
          .map((reservation) => reservation.toJson())
          .toList(growable: false),
    };
  }

  bool get isEmpty => reservations.isEmpty;

  bool get isNotEmpty => reservations.isNotEmpty;

  bool get isTodayCheckIns => scope == 'today_checkins';

  bool get hasTargetDate => targetDate != null;

  bool get isForToday {
    final date = targetDate;

    if (date == null) {
      return false;
    }

    final now = DateTime.now();

    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool get isStale {
    final generated = generatedAt;

    if (generated == null) {
      return true;
    }

    final now = DateTime.now();
    final localGenerated = generated.toLocal();

    return localGenerated.year != now.year ||
        localGenerated.month != now.month ||
        localGenerated.day != now.day;
  }

  int get totalGuests {
    return reservations.fold<int>(
      0,
      (sum, reservation) => sum + (reservation.totalGuests ?? 0),
    );
  }

  int get totalPriceYen {
    return reservations.fold<int>(
      0,
      (sum, reservation) => sum + (reservation.priceYen ?? 0),
    );
  }

  List<Reservation> get sortedByCheckIn {
    final sorted = List<Reservation>.from(reservations);

    sorted.sort((first, second) {
      final firstDate = first.checkIn;
      final secondDate = second.checkIn;

      if (firstDate == null && secondDate == null) {
        return first.displayGuestName.compareTo(second.displayGuestName);
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

      return first.displayGuestName.compareTo(second.displayGuestName);
    });

    return List.unmodifiable(sorted);
  }

  List<Reservation> reservationsForDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);

    return reservations
        .where((reservation) {
          final checkIn = reservation.checkIn;
          final checkOut = reservation.checkOut;

          if (checkIn == null || checkOut == null) {
            return false;
          }

          final start = DateTime(checkIn.year, checkIn.month, checkIn.day);

          final end = DateTime(checkOut.year, checkOut.month, checkOut.day);

          return !target.isBefore(start) && target.isBefore(end);
        })
        .toList(growable: false);
  }

  Reservation? findByReservationNumber(String reservationNumber) {
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

  static String _readRequiredString(Map<String, dynamic> json, String key) {
    final value = _readNullableString(json[key]);

    if (value == null) {
      throw FormatException('$key がありません。');
    }

    return value;
  }

  static String? _readNullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
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
    final text = _readNullableString(value);

    if (text == null) {
      return null;
    }

    return DateTime.tryParse(text);
  }

  static DateTime? _readNullableDate(dynamic value) {
    final parsed = _readNullableDateTime(value);

    if (parsed == null) {
      return null;
    }

    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String? _dateToJson(DateTime? value) {
    if (value == null) {
      return null;
    }

    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
