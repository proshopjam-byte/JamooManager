import 'checkin_sheet.dart';

class FacilitySettings {
  const FacilitySettings({
    required this.facilityName,
    required this.address,
    required this.phone,
    required this.rooms,
    this.roomRates = const [],
    this.personRates = PersonRateSettings.jamooDefaults,
  });

  factory FacilitySettings.fromJson(Map<String, Object?> json) {
    final roomValues = json['rooms'];
    final rooms = roomValues is List
        ? roomValues
              .whereType<Map>()
              .map(
                (room) => GuestRoomSpec.fromJson(
                  room.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : <GuestRoomSpec>[];
    rooms.sort((first, second) => first.number.compareTo(second.number));
    final rateValues = json['roomRates'];
    final roomRates = rateValues is List
        ? rateValues
              .whereType<Map>()
              .map(
                (rate) => RoomTypeRate.fromJson(
                  rate.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((rate) => rate.roomTypeName.isNotEmpty)
              .toList(growable: false)
        : <RoomTypeRate>[];

    return FacilitySettings(
      facilityName: _readText(
        json['facilityName'],
        fallback: defaults.facilityName,
      ),
      address: _readText(json['address']),
      phone: _readText(json['phone']),
      rooms: rooms.isEmpty ? defaults.rooms : List.unmodifiable(rooms),
      roomRates: List.unmodifiable(roomRates),
      personRates: json['personRates'] is Map
          ? PersonRateSettings.fromJson(
              (json['personRates'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : defaults.personRates,
    );
  }

  final String facilityName;
  final String address;
  final String phone;
  final List<GuestRoomSpec> rooms;
  final List<RoomTypeRate> roomRates;
  final PersonRateSettings personRates;

  static const defaults = FacilitySettings(
    facilityName: 'Vegetarian House Jamoo',
    address: '',
    phone: '0555-62-1339',
    rooms: [
      GuestRoomSpec(
        number: 1,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 2,
        label: 'ロフト付き',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.loft,
      ),
      GuestRoomSpec(
        number: 3,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 4,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 5,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 6,
        label: '使用不可',
        normalCapacity: 1,
        capacity: 1,
        type: GuestRoomType.other,
        isAvailable: false,
      ),
      GuestRoomSpec(
        number: 7,
        label: 'ツイン',
        normalCapacity: 2,
        capacity: 3,
        type: GuestRoomType.standardTwin,
      ),
      GuestRoomSpec(
        number: 8,
        label: 'ロフト付き',
        normalCapacity: 4,
        capacity: 5,
        type: GuestRoomType.loft,
      ),
    ],
  );

  GuestRoomSpec roomByNumber(int roomNumber) {
    return rooms.firstWhere(
      (room) => room.number == roomNumber,
      orElse: () => GuestRoomSpec(
        number: roomNumber,
        label: 'その他',
        normalCapacity: 1,
        capacity: 1,
        type: GuestRoomType.other,
      ),
    );
  }

  String get capacitySummary {
    final available = rooms.where((room) => room.isAvailable).toList();
    final groups = <String>[];
    final roomsByType = <String, List<GuestRoomSpec>>{};
    final displayNames = <String, String>{};
    for (final room in available) {
      final key = _normalizeRoomTypeName(room.label);
      displayNames.putIfAbsent(key, () => room.label);
      roomsByType.putIfAbsent(key, () => []).add(room);
    }
    for (final entry in roomsByType.entries) {
      final matches = entry.value;
      final normal = matches.map((room) => room.normalCapacity).toSet();
      final maximum = matches.map((room) => room.capacity).toSet();
      final label = displayNames[entry.key] ?? matches.first.label;
      if (normal.length == 1 && maximum.length == 1) {
        groups.add('$label：通常${normal.first}名・最大${maximum.first}名');
      } else {
        groups.add('$label：各室設定');
      }
    }
    return groups.join(' / ');
  }

  List<String> get availableRoomTypeNames {
    final result = <String>[];
    final keys = <String>{};
    for (final room in rooms.where((room) => room.isAvailable)) {
      final name = room.label.trim();
      final key = _normalizeRoomTypeName(name);
      if (name.isNotEmpty && keys.add(key)) {
        result.add(name);
      }
    }
    return List.unmodifiable(result);
  }

  int? nightlyRate({
    required String roomTypeName,
    required int guestCount,
    required StayPlan plan,
  }) {
    final key = _normalizeRoomTypeName(roomTypeName);
    for (final table in roomRates) {
      if (_normalizeRoomTypeName(table.roomTypeName) == key) {
        return table.rateFor(guestCount, plan);
      }
    }
    return null;
  }

  int minimumGuestsFor(String roomTypeName) {
    final table = _roomRateFor(roomTypeName);
    if (table?.minimumGuests != null) return table!.minimumGuests!;
    final room = _roomForTypeName(roomTypeName);
    return room?.type == GuestRoomType.loft ? 3 : 1;
  }

  int maximumGuestsFor(String roomTypeName) {
    final key = _normalizeRoomTypeName(roomTypeName);
    var maximum = 0;
    for (final room in rooms.where((room) => room.isAvailable)) {
      if (_normalizeRoomTypeName(room.label) == key &&
          room.capacity > maximum) {
        maximum = room.capacity;
      }
    }
    return maximum;
  }

  int singleUseSurchargeFor(String roomTypeName) {
    final table = _roomRateFor(roomTypeName);
    if (table?.singleUseSurchargeYen != null) {
      return table!.singleUseSurchargeYen!;
    }
    final room = _roomForTypeName(roomTypeName);
    return room?.type == GuestRoomType.standardTwin ? 3000 : 0;
  }

  int? calculateNightlyRate({
    required String roomTypeName,
    required int adults,
    required int childrenWithBed,
    required int childrenWithoutBed,
    required StayPlan plan,
  }) {
    final guestCount = adults + childrenWithBed + childrenWithoutBed;
    if (guestCount <= 0) return null;

    // An explicitly entered all-adult room total remains the first choice.
    if (childrenWithBed == 0 && childrenWithoutBed == 0) {
      final roomTotal = nightlyRate(
        roomTypeName: roomTypeName,
        guestCount: adults,
        plan: plan,
      );
      if (roomTotal != null) return roomTotal;
    }

    final adultRate = personRates.adult.rateFor(plan);
    final childWithBedRate = personRates.childWithBed.rateFor(plan);
    final childWithoutBedRate = personRates.childWithoutBed.rateFor(plan);
    if ((adults > 0 && adultRate == null) ||
        (childrenWithBed > 0 && childWithBedRate == null) ||
        (childrenWithoutBed > 0 && childWithoutBedRate == null)) {
      return null;
    }

    var total = (adultRate ?? 0) * adults;
    total += (childWithBedRate ?? 0) * childrenWithBed;
    total += (childWithoutBedRate ?? 0) * childrenWithoutBed;
    if (guestCount == 1) total += singleUseSurchargeFor(roomTypeName);
    return total;
  }

  RoomTypeRate? _roomRateFor(String roomTypeName) {
    final key = _normalizeRoomTypeName(roomTypeName);
    for (final table in roomRates) {
      if (_normalizeRoomTypeName(table.roomTypeName) == key) return table;
    }
    return null;
  }

  GuestRoomSpec? _roomForTypeName(String roomTypeName) {
    final key = _normalizeRoomTypeName(roomTypeName);
    for (final room in rooms.where((room) => room.isAvailable)) {
      if (_normalizeRoomTypeName(room.label) == key) return room;
    }
    return null;
  }

  FacilitySettings copyWith({
    String? facilityName,
    String? address,
    String? phone,
    List<GuestRoomSpec>? rooms,
    List<RoomTypeRate>? roomRates,
    PersonRateSettings? personRates,
  }) {
    return FacilitySettings(
      facilityName: facilityName ?? this.facilityName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      rooms: List.unmodifiable(rooms ?? this.rooms),
      roomRates: List.unmodifiable(roomRates ?? this.roomRates),
      personRates: personRates ?? this.personRates,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'version': 3,
      'facilityName': facilityName,
      'address': address,
      'phone': phone,
      'rooms': rooms.map((room) => room.toJson()).toList(),
      'roomRates': roomRates.map((rate) => rate.toJson()).toList(),
      'personRates': personRates.toJson(),
    };
  }

  static String _readText(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

enum StayPlan {
  roomOnly,
  breakfast,
  twoMeals;

  String get label {
    switch (this) {
      case StayPlan.roomOnly:
        return '素泊まり';
      case StayPlan.breakfast:
        return '朝食付き';
      case StayPlan.twoMeals:
        return '2食付き';
    }
  }
}

class GuestCountRate {
  const GuestCountRate({
    required this.guestCount,
    this.roomOnlyYen,
    this.breakfastYen,
    this.twoMealsYen,
  });

  factory GuestCountRate.fromJson(Map<String, Object?> json) {
    return GuestCountRate(
      guestCount: _readPositiveInt(json['guestCount'], fallback: 1),
      roomOnlyYen: _readNullableNonNegativeInt(json['roomOnlyYen']),
      breakfastYen: _readNullableNonNegativeInt(json['breakfastYen']),
      twoMealsYen: _readNullableNonNegativeInt(json['twoMealsYen']),
    );
  }

  final int guestCount;
  final int? roomOnlyYen;
  final int? breakfastYen;
  final int? twoMealsYen;

  int? rateFor(StayPlan plan) {
    switch (plan) {
      case StayPlan.roomOnly:
        return roomOnlyYen;
      case StayPlan.breakfast:
        return breakfastYen;
      case StayPlan.twoMeals:
        return twoMealsYen;
    }
  }

  Map<String, Object?> toJson() {
    return {
      'guestCount': guestCount,
      'roomOnlyYen': roomOnlyYen,
      'breakfastYen': breakfastYen,
      'twoMealsYen': twoMealsYen,
    };
  }
}

class PersonPlanRate {
  const PersonPlanRate({this.roomOnlyYen, this.breakfastYen, this.twoMealsYen});

  factory PersonPlanRate.fromJson(Map<String, Object?> json) {
    return PersonPlanRate(
      roomOnlyYen: _readNullableNonNegativeInt(json['roomOnlyYen']),
      breakfastYen: _readNullableNonNegativeInt(json['breakfastYen']),
      twoMealsYen: _readNullableNonNegativeInt(json['twoMealsYen']),
    );
  }

  final int? roomOnlyYen;
  final int? breakfastYen;
  final int? twoMealsYen;

  int? rateFor(StayPlan plan) {
    switch (plan) {
      case StayPlan.roomOnly:
        return roomOnlyYen;
      case StayPlan.breakfast:
        return breakfastYen;
      case StayPlan.twoMeals:
        return twoMealsYen;
    }
  }

  Map<String, Object?> toJson() => {
    'roomOnlyYen': roomOnlyYen,
    'breakfastYen': breakfastYen,
    'twoMealsYen': twoMealsYen,
  };
}

class PersonRateSettings {
  const PersonRateSettings({
    required this.adult,
    required this.childWithBed,
    required this.childWithoutBed,
  });

  factory PersonRateSettings.fromJson(Map<String, Object?> json) {
    PersonPlanRate readRate(String key, PersonPlanRate fallback) {
      final value = json[key];
      if (value is! Map) return fallback;
      return PersonPlanRate.fromJson(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    return PersonRateSettings(
      adult: readRate('adult', jamooDefaults.adult),
      childWithBed: readRate('childWithBed', jamooDefaults.childWithBed),
      childWithoutBed: readRate(
        'childWithoutBed',
        jamooDefaults.childWithoutBed,
      ),
    );
  }

  static const jamooDefaults = PersonRateSettings(
    adult: PersonPlanRate(
      roomOnlyYen: 7500,
      breakfastYen: 9700,
      twoMealsYen: 13500,
    ),
    childWithBed: PersonPlanRate(
      roomOnlyYen: 4500,
      breakfastYen: 6000,
      twoMealsYen: 8500,
    ),
    childWithoutBed: PersonPlanRate(
      roomOnlyYen: 2500,
      breakfastYen: 4000,
      twoMealsYen: 6500,
    ),
  );

  final PersonPlanRate adult;
  final PersonPlanRate childWithBed;
  final PersonPlanRate childWithoutBed;

  Map<String, Object?> toJson() => {
    'adult': adult.toJson(),
    'childWithBed': childWithBed.toJson(),
    'childWithoutBed': childWithoutBed.toJson(),
  };
}

class RoomTypeRate {
  const RoomTypeRate({
    required this.roomTypeName,
    required this.rates,
    this.minimumGuests,
    this.singleUseSurchargeYen,
  });

  factory RoomTypeRate.fromJson(Map<String, Object?> json) {
    final values = json['rates'];
    final rates = values is List
        ? values
              .whereType<Map>()
              .map(
                (rate) => GuestCountRate.fromJson(
                  rate.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : <GuestCountRate>[];
    rates.sort(
      (first, second) => first.guestCount.compareTo(second.guestCount),
    );
    return RoomTypeRate(
      roomTypeName: json['roomTypeName']?.toString().trim() ?? '',
      rates: List.unmodifiable(rates),
      minimumGuests: _readNullablePositiveInt(json['minimumGuests']),
      singleUseSurchargeYen: _readNullableNonNegativeInt(
        json['singleUseSurchargeYen'],
      ),
    );
  }

  final String roomTypeName;
  final List<GuestCountRate> rates;
  final int? minimumGuests;
  final int? singleUseSurchargeYen;

  int? rateFor(int guestCount, StayPlan plan) {
    for (final rate in rates) {
      if (rate.guestCount == guestCount) {
        return rate.rateFor(plan);
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'roomTypeName': roomTypeName,
      'rates': rates.map((rate) => rate.toJson()).toList(),
      'minimumGuests': minimumGuests,
      'singleUseSurchargeYen': singleUseSurchargeYen,
    };
  }
}

String _normalizeRoomTypeName(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

int _readPositiveInt(Object? value, {required int fallback}) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  return parsed == null || parsed <= 0 ? fallback : parsed;
}

int? _readNullableNonNegativeInt(Object? value) {
  if (value == null) return null;
  final parsed = value is num ? value.toInt() : int.tryParse(value.toString());
  return parsed == null || parsed < 0 ? null : parsed;
}

int? _readNullablePositiveInt(Object? value) {
  final parsed = _readNullableNonNegativeInt(value);
  return parsed == null || parsed <= 0 ? null : parsed;
}
