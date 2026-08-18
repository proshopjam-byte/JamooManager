class GuestRoomSpec {
  const GuestRoomSpec({
    required this.number,
    required this.label,
    required this.capacity,
    required this.isLoft,
    this.isAvailable = true,
  });

  final int number;
  final String label;
  final int capacity;
  final bool isLoft;
  final bool isAvailable;

  String get displayName => '$number号室';

  String get typeLabel {
    if (!isAvailable) {
      return '使用不可';
    }
    return isLoft ? 'ロフト付き・$capacity名' : 'ツイン・$capacity名';
  }

  static const rooms = <GuestRoomSpec>[
    GuestRoomSpec(number: 1, label: 'スタンダードツイン', capacity: 3, isLoft: false),
    GuestRoomSpec(number: 2, label: 'ロフト付き5名室', capacity: 5, isLoft: true),
    GuestRoomSpec(number: 3, label: 'スタンダードツイン', capacity: 3, isLoft: false),
    GuestRoomSpec(number: 4, label: 'スタンダードツイン', capacity: 3, isLoft: false),
    GuestRoomSpec(number: 5, label: 'スタンダードツイン', capacity: 3, isLoft: false),
    GuestRoomSpec(
      number: 6,
      label: '使用不可',
      capacity: 0,
      isLoft: false,
      isAvailable: false,
    ),
    GuestRoomSpec(number: 7, label: 'スタンダードツイン', capacity: 3, isLoft: false),
    GuestRoomSpec(number: 8, label: 'ロフト付き5名室', capacity: 5, isLoft: true),
  ];

  static GuestRoomSpec byNumber(int roomNumber) {
    return rooms.firstWhere((room) => room.number == roomNumber);
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

  GuestRoomSpec get room => GuestRoomSpec.byNumber(roomNumber);

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
