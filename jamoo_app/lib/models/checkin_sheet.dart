enum GuestRoomType {
  standardTwin,
  loft,
  other;

  String get label {
    switch (this) {
      case GuestRoomType.standardTwin:
        return 'スタンダードツイン';
      case GuestRoomType.loft:
        return 'ロフト付き';
      case GuestRoomType.other:
        return 'その他';
    }
  }

  static GuestRoomType fromName(String? value) {
    return GuestRoomType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => GuestRoomType.other,
    );
  }
}

class GuestRoomSpec {
  const GuestRoomSpec({
    required this.number,
    required this.label,
    required this.normalCapacity,
    required this.capacity,
    required this.type,
    this.isAvailable = true,
  });

  factory GuestRoomSpec.fromJson(Map<String, Object?> json) {
    final capacity = _readInt(json['capacity'], fallback: 1);
    final normalCapacity = _readInt(json['normalCapacity'], fallback: capacity);
    return GuestRoomSpec(
      number: _readInt(json['number'], fallback: 1),
      label: json['label']?.toString().trim().isNotEmpty == true
          ? json['label'].toString().trim()
          : GuestRoomType.fromName(json['type']?.toString()).label,
      normalCapacity: normalCapacity.clamp(1, capacity).toInt(),
      capacity: capacity,
      type: GuestRoomType.fromName(json['type']?.toString()),
      isAvailable: json['isAvailable'] != false,
    );
  }

  final int number;
  final String label;
  final int normalCapacity;
  final int capacity;
  final GuestRoomType type;
  final bool isAvailable;

  bool get isLoft => type == GuestRoomType.loft;

  String get displayName => '$number号室';

  String get typeLabel {
    if (!isAvailable) {
      return '使用不可';
    }
    return '$label・$capacity名';
  }

  GuestRoomSpec copyWith({
    int? number,
    String? label,
    int? normalCapacity,
    int? capacity,
    GuestRoomType? type,
    bool? isAvailable,
  }) {
    return GuestRoomSpec(
      number: number ?? this.number,
      label: label ?? this.label,
      normalCapacity: normalCapacity ?? this.normalCapacity,
      capacity: capacity ?? this.capacity,
      type: type ?? this.type,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'number': number,
      'label': label,
      'normalCapacity': normalCapacity,
      'capacity': capacity,
      'type': type.name,
      'isAvailable': isAvailable,
    };
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class CheckinSheetRow {
  const CheckinSheetRow({
    required this.roomNumber,
    required this.reservationKey,
    required this.reservationSource,
    required this.reservationNumber,
    required this.guestName,
    required this.guestCount,
    required this.checkedIn,
    required this.amountYen,
    required this.payment,
    required this.dinnerAndTable,
    required this.bathTime,
    required this.breakfastTime,
    required this.checkedOut,
    required this.notes,
  });

  factory CheckinSheetRow.empty(int roomNumber) {
    return CheckinSheetRow(
      roomNumber: roomNumber,
      reservationKey: null,
      reservationSource: null,
      reservationNumber: null,
      guestName: '',
      guestCount: 0,
      checkedIn: false,
      amountYen: null,
      payment: '',
      dinnerAndTable: '',
      bathTime: '',
      breakfastTime: '',
      checkedOut: false,
      notes: '',
    );
  }

  final int roomNumber;
  final String? reservationKey;
  final String? reservationSource;
  final String? reservationNumber;
  final String guestName;
  final int guestCount;
  final bool checkedIn;
  final int? amountYen;
  final String payment;
  final String dinnerAndTable;
  final String bathTime;
  final String breakfastTime;
  final bool checkedOut;
  final String notes;

  bool get hasReservation => reservationKey != null;

  CheckinSheetRow copyWith({
    int? guestCount,
    bool? checkedIn,
    int? amountYen,
    bool clearAmount = false,
    String? payment,
    String? dinnerAndTable,
    String? bathTime,
    String? breakfastTime,
    bool? checkedOut,
    String? notes,
  }) {
    return CheckinSheetRow(
      roomNumber: roomNumber,
      reservationKey: reservationKey,
      reservationSource: reservationSource,
      reservationNumber: reservationNumber,
      guestName: guestName,
      guestCount: guestCount ?? this.guestCount,
      checkedIn: checkedIn ?? this.checkedIn,
      amountYen: clearAmount ? null : amountYen ?? this.amountYen,
      payment: payment ?? this.payment,
      dinnerAndTable: dinnerAndTable ?? this.dinnerAndTable,
      bathTime: bathTime ?? this.bathTime,
      breakfastTime: breakfastTime ?? this.breakfastTime,
      checkedOut: checkedOut ?? this.checkedOut,
      notes: notes ?? this.notes,
    );
  }
}
