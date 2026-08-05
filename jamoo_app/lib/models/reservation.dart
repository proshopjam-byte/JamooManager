class Reservation {
  const Reservation({
    required this.id,
    required this.source,
    required this.reservationNumber,
    required this.guestName,
    required this.roomName,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.adults,
    required this.children,
    required this.totalGuests,
    required this.priceYen,
    required this.arrivalTime,
    required this.bookedOn,
    required this.status,
  });

  final String id;
  final String source;
  final String? reservationNumber;
  final String? guestName;
  final String? roomName;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int? nights;
  final int? adults;
  final int children;
  final int? totalGuests;
  final int? priceYen;
  final String? arrivalTime;
  final DateTime? bookedOn;
  final String? status;

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      id: _readRequiredString(json, 'id'),
      source: _readRequiredString(json, 'source'),
      reservationNumber: _readNullableString(json['reservationNumber']),
      guestName: _readNullableString(json['guestName']),
      roomName: _readNullableString(json['roomName']),
      checkIn: _readNullableDate(json['checkIn']),
      checkOut: _readNullableDate(json['checkOut']),
      nights: _readNullableInt(json['nights']),
      adults: _readNullableInt(json['adults']),
      children: _readNullableInt(json['children']) ?? 0,
      totalGuests: _readNullableInt(json['totalGuests']),
      priceYen: _readNullableInt(json['priceYen']),
      arrivalTime: _readNullableString(json['arrivalTime']),
      bookedOn: _readNullableDate(json['bookedOn']),
      status: _readNullableString(json['status']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source,
      'reservationNumber': reservationNumber,
      'guestName': guestName,
      'roomName': roomName,
      'checkIn': _dateToJson(checkIn),
      'checkOut': _dateToJson(checkOut),
      'nights': nights,
      'adults': adults,
      'children': children,
      'totalGuests': totalGuests,
      'priceYen': priceYen,
      'arrivalTime': arrivalTime,
      'bookedOn': _dateToJson(bookedOn),
      'status': status,
    };
  }

  String get displayGuestName {
    final value = guestName?.trim();
    return value == null || value.isEmpty ? '氏名不明' : value;
  }

  String get displayRoomName {
    final value = roomName?.trim();
    return value == null || value.isEmpty ? '部屋未設定' : value;
  }

  String get displayStayPeriod {
    final checkInText = _formatDate(checkIn);
    final checkOutText = _formatDate(checkOut);

    if (checkInText == null && checkOutText == null) {
      return '宿泊日未設定';
    }

    return '${checkInText ?? '未設定'} ～ ${checkOutText ?? '未設定'}';
  }

  String get displayGuestCount {
    if (adults == null) {
      return '人数不明';
    }

    if (children > 0) {
      return '大人$adults名・子供$children名';
    }

    return '大人$adults名';
  }

  String get displayPrice {
    if (priceYen == null) {
      return '料金未設定';
    }

    return '¥${_formatNumber(priceYen!)}';
  }

  Reservation copyWith({
    String? id,
    String? source,
    String? reservationNumber,
    String? guestName,
    String? roomName,
    DateTime? checkIn,
    DateTime? checkOut,
    int? nights,
    int? adults,
    int? children,
    int? totalGuests,
    int? priceYen,
    String? arrivalTime,
    DateTime? bookedOn,
    String? status,
  }) {
    return Reservation(
      id: id ?? this.id,
      source: source ?? this.source,
      reservationNumber: reservationNumber ?? this.reservationNumber,
      guestName: guestName ?? this.guestName,
      roomName: roomName ?? this.roomName,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      nights: nights ?? this.nights,
      adults: adults ?? this.adults,
      children: children ?? this.children,
      totalGuests: totalGuests ?? this.totalGuests,
      priceYen: priceYen ?? this.priceYen,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      bookedOn: bookedOn ?? this.bookedOn,
      status: status ?? this.status,
    );
  }

  static String _readRequiredString(
    Map<String, dynamic> json,
    String key,
  ) {
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

  static DateTime? _readNullableDate(dynamic value) {
    final text = _readNullableString(value);

    if (text == null) {
      return null;
    }

    return DateTime.tryParse(text);
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

  static String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }

    return '${value.year}/${value.month.toString().padLeft(2, '0')}/'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _formatNumber(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();

    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }

      buffer.write(digits[index]);
    }

    return value < 0 ? '-${buffer.toString()}' : buffer.toString();
  }
}
