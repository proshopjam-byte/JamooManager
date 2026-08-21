class PortalReservationEmail {
  const PortalReservationEmail({
    required this.source,
    required this.eventType,
    required this.reservationNumber,
    required this.guestName,
    required this.phone,
    required this.email,
    required this.address,
    required this.checkIn,
    required this.checkOut,
    required this.arrivalTime,
    required this.nights,
    required this.adults,
    required this.children,
    required this.roomCount,
    required this.roomName,
    required this.planName,
    required this.priceYen,
    required this.paymentMethod,
    required this.hasBreakfast,
    required this.hasDinner,
    required this.rawBody,
  });

  factory PortalReservationEmail.fromJson(Map<String, dynamic> json) {
    final source = _requiredText(json['source'], '予約元');
    if (source != 'Rakuten Travel' && source != 'Jalan') {
      throw FormatException('未対応の予約元です: $source');
    }

    return PortalReservationEmail(
      source: source,
      eventType: _requiredText(json['eventType'], '通知種別'),
      reservationNumber: _requiredText(json['reservationNumber'], '予約番号'),
      guestName: _text(json['guestName']),
      phone: _text(json['phone']),
      email: _text(json['email']),
      address: _text(json['address']),
      checkIn: _date(json['checkIn']),
      checkOut: _date(json['checkOut']),
      arrivalTime: _text(json['arrivalTime']),
      nights: _integer(json['nights']),
      adults: _integer(json['adults']),
      children: _integer(json['children']),
      roomCount: _integer(json['roomCount']),
      roomName: _text(json['roomName']),
      planName: _text(json['planName']),
      priceYen: _integer(json['priceYen']),
      paymentMethod: _text(json['paymentMethod']),
      hasBreakfast: _boolean(json['hasBreakfast']),
      hasDinner: _boolean(json['hasDinner']),
      rawBody: _text(json['rawBody']),
    );
  }

  final String source;
  final String eventType;
  final String reservationNumber;
  final String? guestName;
  final String? phone;
  final String? email;
  final String? address;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String? arrivalTime;
  final int? nights;
  final int? adults;
  final int? children;
  final int? roomCount;
  final String? roomName;
  final String? planName;
  final int? priceYen;
  final String? paymentMethod;
  final bool? hasBreakfast;
  final bool? hasDinner;
  final String? rawBody;

  bool get isCancelled => eventType == 'cancelled';
}

String _requiredText(Object? value, String label) {
  final text = _text(value);
  if (text == null) {
    throw FormatException('$labelがありません。');
  }
  return text;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _integer(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}

bool? _boolean(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value == 1 || value?.toString().toLowerCase() == 'true') {
    return true;
  }
  if (value == 0 || value?.toString().toLowerCase() == 'false') {
    return false;
  }
  return null;
}

DateTime? _date(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}
