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
    this.phone,
    this.email,
    this.address,
    this.postalCode,
    this.specialRequests,
    this.hasBreakfast,
    this.breakfastGuestCount,
    this.hasDinner,
    this.planName,
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
  final String? phone;
  final String? email;
  final String? address;
  final String? postalCode;
  final String? specialRequests;
  final bool? hasBreakfast;
  final int? breakfastGuestCount;
  final bool? hasDinner;
  final String? planName;

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
      phone: _readNullableString(json['phone']),
      email: _readNullableString(json['email']),
      address: _readNullableString(json['address']),
      postalCode: _readNullableString(json['postalCode']),
      specialRequests: _readNullableString(json['specialRequests']),
      hasBreakfast: _readNullableBool(json['hasBreakfast']),
      breakfastGuestCount: _readNullableInt(json['breakfastGuestCount']),
      hasDinner: _readNullableBool(json['hasDinner']),
      planName: _readNullableString(json['planName']),
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
      'phone': phone,
      'email': email,
      'address': address,
      'postalCode': postalCode,
      'specialRequests': specialRequests,
      'hasBreakfast': hasBreakfast,
      'breakfastGuestCount': breakfastGuestCount,
      'hasDinner': hasDinner,
      'planName': planName,
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

  /// Number of rooms represented by this reservation.
  ///
  /// Booking.com may store multiple booked room types in one reservation,
  /// for example: `1 x Standard Twin Room, 1 x ロフト付き4人部屋`.
  /// When no explicit quantity is present, one reservation is treated as one
  /// room so existing CHILLNN and manually entered reservations keep working.
  int get roomCount {
    final value = roomName?.trim();
    if (value == null || value.isEmpty) return 1;

    final prefixedQuantityPattern = RegExp(
      r'(?:^|[,\u3001\uff0c/+\uff0b])\s*(\d+)\s*[xX\u00d7]\s*',
    );
    final prefixedTotal = _sumRoomQuantities(
      prefixedQuantityPattern.allMatches(value),
    );
    if (prefixedTotal > 0) return prefixedTotal;

    final suffixedQuantityPattern = RegExp(
      r'(?:Standard\s*Twin\s*Room|Twin\s*Room|Quadruple\s*Room\s*with\s*Loft|'
      r'スタンダード\s*ツイン(?:ルーム)?|ツイン(?:ルーム)?|'
      r'ロフト付き(?:4人部屋)?|ロフト(?:付き)?(?:ルーム)?)'
      r'\s*[xX\u00d7]\s*(\d+)',
      caseSensitive: false,
    );
    final suffixedTotal = _sumRoomQuantities(
      suffixedQuantityPattern.allMatches(value),
    );
    if (suffixedTotal > 0) return suffixedTotal;

    final roomTypePattern = RegExp(
      r'Standard\s*Twin\s*Room|Twin\s*Room|Quadruple\s*Room\s*with\s*Loft|'
      r'スタンダード\s*ツイン(?:ルーム)?|ツイン(?:ルーム)?|'
      r'ロフト付き|ロフト',
      caseSensitive: false,
    );
    final separatedRoomCount = value
        .split(RegExp(r'\s*[,\u3001\uff0c/+\uff0b]\s*'))
        .where((part) => roomTypePattern.hasMatch(part))
        .length;
    if (separatedRoomCount > 1) return separatedRoomCount;

    final compactJapanesePattern = RegExp(
      r'(?:スタンダードツイン(?:ルーム)?|ツイン(?:ルーム)?|'
      r'ロフト付き|ロフト)(\d+)(?!\d*(?:人|名))',
    );
    final compactTotal = _sumRoomQuantities(
      compactJapanesePattern.allMatches(value.replaceAll(RegExp(r'\s+'), '')),
    );
    return compactTotal > 0 ? compactTotal : 1;
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
    String? phone,
    String? email,
    String? address,
    String? postalCode,
    String? specialRequests,
    bool? hasBreakfast,
    int? breakfastGuestCount,
    bool? hasDinner,
    String? planName,
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
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      postalCode: postalCode ?? this.postalCode,
      specialRequests: specialRequests ?? this.specialRequests,
      hasBreakfast: hasBreakfast ?? this.hasBreakfast,
      breakfastGuestCount: breakfastGuestCount ?? this.breakfastGuestCount,
      hasDinner: hasDinner ?? this.hasDinner,
      planName: planName ?? this.planName,
    );
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

  static bool? _readNullableBool(dynamic value) {
    if (value is bool) return value;
    if (value == 1 || value == '1' || value == 'true') return true;
    if (value == 0 || value == '0' || value == 'false') return false;
    return null;
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

  static int _sumRoomQuantities(Iterable<RegExpMatch> matches) {
    return matches.fold<int>(
      0,
      (sum, match) => sum + (int.tryParse(match.group(1) ?? '') ?? 0),
    );
  }
}
