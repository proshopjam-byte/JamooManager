enum GuestRoomType {
  standardTwin,
  loft,
  other;

  String get label {
    switch (this) {
      case GuestRoomType.standardTwin:
        return '少人数向け';
      case GuestRoomType.loft:
        return '大人数向け';
      case GuestRoomType.other:
        return '標準・その他';
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
    this.roomName = '',
    this.isAvailable = true,
    this.adjacentRoomNumbers = const [],
  });

  factory GuestRoomSpec.fromJson(Map<String, Object?> json) {
    final capacity = _readInt(json['capacity'], fallback: 1);
    final normalCapacity = _readInt(json['normalCapacity'], fallback: capacity);
    return GuestRoomSpec(
      number: _readInt(json['number'], fallback: 1),
      roomName: json['roomName']?.toString().trim() ?? '',
      label: json['label']?.toString().trim().isNotEmpty == true
          ? json['label'].toString().trim()
          : GuestRoomType.fromName(json['type']?.toString()).label,
      normalCapacity: normalCapacity.clamp(1, capacity).toInt(),
      capacity: capacity,
      type: GuestRoomType.fromName(json['type']?.toString()),
      isAvailable: json['isAvailable'] != false,
      adjacentRoomNumbers: _readIntList(json['adjacentRoomNumbers']),
    );
  }

  final int number;
  final String roomName;
  final String label;
  final int normalCapacity;
  final int capacity;
  final GuestRoomType type;
  final bool isAvailable;
  final List<int> adjacentRoomNumbers;

  bool get isLoft => type == GuestRoomType.loft;

  String get displayName => roomName.trim().isEmpty
      ? '$number号室'
      : roomName.trim();

  String get typeLabel {
    if (!isAvailable) {
      return '使用不可';
    }
    return '$label・$capacity名';
  }

  GuestRoomSpec copyWith({
    int? number,
    String? roomName,
    String? label,
    int? normalCapacity,
    int? capacity,
    GuestRoomType? type,
    bool? isAvailable,
    List<int>? adjacentRoomNumbers,
  }) {
    return GuestRoomSpec(
      number: number ?? this.number,
      roomName: roomName ?? this.roomName,
      label: label ?? this.label,
      normalCapacity: normalCapacity ?? this.normalCapacity,
      capacity: capacity ?? this.capacity,
      type: type ?? this.type,
      isAvailable: isAvailable ?? this.isAvailable,
      adjacentRoomNumbers: adjacentRoomNumbers ?? this.adjacentRoomNumbers,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'number': number,
      'roomName': roomName,
      'label': label,
      'normalCapacity': normalCapacity,
      'capacity': capacity,
      'type': type.name,
      'isAvailable': isAvailable,
      'adjacentRoomNumbers': adjacentRoomNumbers,
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

  static List<int> _readIntList(Object? value) {
    if (value is! List) return const [];
    final result = <int>{};
    for (final item in value) {
      final parsed = _readInt(item, fallback: 0);
      if (parsed > 0) result.add(parsed);
    }
    return List.unmodifiable(result);
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
    this.guestCountManuallyChanged = false,
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
      guestCountManuallyChanged: false,
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
  final bool guestCountManuallyChanged;
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
    bool? guestCountManuallyChanged,
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
      guestCountManuallyChanged:
          guestCountManuallyChanged ?? this.guestCountManuallyChanged,
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
