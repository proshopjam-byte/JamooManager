import 'checkin_sheet.dart';

class FacilitySettings {
  const FacilitySettings({
    required this.facilityName,
    required this.address,
    required this.phone,
    required this.rooms,
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

    return FacilitySettings(
      facilityName: _readText(
        json['facilityName'],
        fallback: defaults.facilityName,
      ),
      address: _readText(json['address']),
      phone: _readText(json['phone']),
      rooms: rooms.isEmpty ? defaults.rooms : List.unmodifiable(rooms),
    );
  }

  final String facilityName;
  final String address;
  final String phone;
  final List<GuestRoomSpec> rooms;

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
    for (final type in GuestRoomType.values) {
      final matches = available.where((room) => room.type == type).toList();
      if (matches.isEmpty) {
        continue;
      }
      final normal = matches.map((room) => room.normalCapacity).toSet();
      final maximum = matches.map((room) => room.capacity).toSet();
      final label = matches.first.label;
      if (normal.length == 1 && maximum.length == 1) {
        groups.add('$label：通常${normal.first}名・最大${maximum.first}名');
      } else {
        groups.add('$label：各室設定');
      }
    }
    return groups.join(' / ');
  }

  FacilitySettings copyWith({
    String? facilityName,
    String? address,
    String? phone,
    List<GuestRoomSpec>? rooms,
  }) {
    return FacilitySettings(
      facilityName: facilityName ?? this.facilityName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      rooms: List.unmodifiable(rooms ?? this.rooms),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'version': 1,
      'facilityName': facilityName,
      'address': address,
      'phone': phone,
      'rooms': rooms.map((room) => room.toJson()).toList(),
    };
  }

  static String _readText(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
