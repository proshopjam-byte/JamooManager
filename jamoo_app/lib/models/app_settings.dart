class AppSettings {
  const AppSettings({
    required this.appName,
    required this.facilityName,
    required this.bookingSourceName,
    required this.timeZone,
    required this.showPrice,
    required this.showReservationNumber,
    required this.showArrivalTime,
    this.managerRootPath,
  });

  final String appName;
  final String facilityName;
  final String bookingSourceName;
  final String timeZone;
  final bool showPrice;
  final bool showReservationNumber;
  final bool showArrivalTime;

  /// JamooManagerのルートフォルダ。
  ///
  /// nullの場合は、実行場所から自動検索します。
  /// 例: C:\work\JamooManager
  final String? managerRootPath;

  static const AppSettings defaults = AppSettings(
    appName: 'JamooManager',
    facilityName: 'Vegetarian House Jamoo',
    bookingSourceName: 'Booking.com',
    timeZone: 'Asia/Tokyo',
    showPrice: true,
    showReservationNumber: true,
    showArrivalTime: true,
    managerRootPath: null,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      appName: _readString(json['appName'], defaults.appName),
      facilityName: _readString(json['facilityName'], defaults.facilityName),
      bookingSourceName: _readString(
        json['bookingSourceName'],
        defaults.bookingSourceName,
      ),
      timeZone: _readString(json['timeZone'], defaults.timeZone),
      showPrice: _readBool(json['showPrice'], defaults.showPrice),
      showReservationNumber: _readBool(
        json['showReservationNumber'],
        defaults.showReservationNumber,
      ),
      showArrivalTime: _readBool(
        json['showArrivalTime'],
        defaults.showArrivalTime,
      ),
      managerRootPath: _readNullableString(json['managerRootPath']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'facilityName': facilityName,
      'bookingSourceName': bookingSourceName,
      'timeZone': timeZone,
      'showPrice': showPrice,
      'showReservationNumber': showReservationNumber,
      'showArrivalTime': showArrivalTime,
      'managerRootPath': managerRootPath,
    };
  }

  AppSettings copyWith({
    String? appName,
    String? facilityName,
    String? bookingSourceName,
    String? timeZone,
    bool? showPrice,
    bool? showReservationNumber,
    bool? showArrivalTime,
    String? managerRootPath,
    bool clearManagerRootPath = false,
  }) {
    return AppSettings(
      appName: appName ?? this.appName,
      facilityName: facilityName ?? this.facilityName,
      bookingSourceName: bookingSourceName ?? this.bookingSourceName,
      timeZone: timeZone ?? this.timeZone,
      showPrice: showPrice ?? this.showPrice,
      showReservationNumber:
          showReservationNumber ?? this.showReservationNumber,
      showArrivalTime: showArrivalTime ?? this.showArrivalTime,
      managerRootPath: clearManagerRootPath
          ? null
          : managerRootPath ?? this.managerRootPath,
    );
  }

  String get displayManagerRootPath {
    final value = managerRootPath?.trim();

    if (value == null || value.isEmpty) {
      return '自動検索';
    }

    return value;
  }

  static String _readString(dynamic value, String fallback) {
    if (value == null) {
      return fallback;
    }

    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static String? _readNullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _readBool(dynamic value, bool fallback) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'on') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no' ||
          normalized == 'off') {
        return false;
      }
    }

    return fallback;
  }
}
