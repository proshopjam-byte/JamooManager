class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    required this.stayCount,
    required this.totalSpendYen,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.phone,
    this.postalCode,
    this.address,
    this.country,
    this.reservationSources = const <String>[],
    this.activeReservationCount = 0,
    this.cancelledReservationCount = 0,
    this.firstStayDate,
    this.lastStayDate,
    this.notes,
  });

  final int id;
  final String fullName;
  final String? email;
  final String? phone;
  final String? postalCode;
  final String? address;
  final String? country;
  final List<String> reservationSources;
  final int activeReservationCount;
  final int cancelledReservationCount;
  final DateTime? firstStayDate;
  final DateTime? lastStayDate;
  final int stayCount;
  final int totalSpendYen;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get reservationSourceLabel {
    if (reservationSources.isEmpty) {
      return '未連携';
    }
    return reservationSources.map(_reservationSourceLabel).join(' / ');
  }

  String get reservationStatusLabel {
    if (activeReservationCount > 0) {
      return cancelledReservationCount > 0 ? '有効予約（キャンセル履歴あり）' : '有効予約';
    }
    if (cancelledReservationCount > 0) {
      return 'キャンセル';
    }
    return '予約未連携';
  }

  bool get isCancelledOnly =>
      activeReservationCount == 0 && cancelledReservationCount > 0;

  factory Customer.fromRow(Map<String, Object?> row) {
    return Customer(
      id: _readInt(row['id']) ?? 0,
      fullName: _readText(row['full_name']) ?? '氏名未設定',
      email: _readText(row['email']),
      phone: _readText(row['phone']),
      postalCode: _readText(row['postal_code']),
      address: _readText(row['address']),
      country: _readText(row['country']),
      reservationSources: _readReservationSources(
        row['calculated_reservation_sources'],
      ),
      activeReservationCount:
          _readInt(row['calculated_active_reservation_count']) ?? 0,
      cancelledReservationCount:
          _readInt(row['calculated_cancelled_reservation_count']) ?? 0,
      firstStayDate: _readDate(
        row['calculated_first_stay_date'] ?? row['first_stay_date'],
      ),
      lastStayDate: _readDate(
        row['calculated_last_stay_date'] ?? row['last_stay_date'],
      ),
      stayCount:
          _readInt(row['calculated_stay_count']) ??
          _readInt(row['stay_count']) ??
          0,
      totalSpendYen:
          _readInt(row['calculated_total_spend_yen']) ??
          _readInt(row['total_spend_yen']) ??
          0,
      notes: _readText(row['notes']),
      createdAt: _readDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _readDate(row['updated_at']) ?? DateTime.now(),
    );
  }
}

List<String> _readReservationSources(Object? value) {
  final raw = _readText(value);
  if (raw == null) {
    return const <String>[];
  }
  final values = <String>[];
  final seen = <String>{};
  for (final source in raw.split(',')) {
    final cleaned = source.trim();
    if (cleaned.isEmpty || !seen.add(cleaned.toLowerCase())) {
      continue;
    }
    values.add(cleaned);
  }
  return List<String>.unmodifiable(values);
}

String _reservationSourceLabel(String source) {
  switch (source.trim().toUpperCase()) {
    case 'MANUAL':
      return '手入力';
    case 'BOOKING':
    case 'BOOKING.COM':
      return 'Booking.com';
    case 'CHILLNN':
      return 'CHILLNN';
    default:
      return source.trim();
  }
}

class CustomerDraft {
  const CustomerDraft({
    required this.fullName,
    this.email,
    this.phone,
    this.postalCode,
    this.address,
    this.country,
    this.notes,
  });

  final String fullName;
  final String? email;
  final String? phone;
  final String? postalCode;
  final String? address;
  final String? country;
  final String? notes;

  factory CustomerDraft.fromCustomer(Customer customer) {
    return CustomerDraft(
      fullName: customer.fullName,
      email: customer.email,
      phone: customer.phone,
      postalCode: customer.postalCode,
      address: customer.address,
      country: customer.country,
      notes: customer.notes,
    );
  }

  factory CustomerDraft.fromReservation(CustomerReservationCandidate value) {
    return CustomerDraft(
      fullName: value.guestName,
      email: value.email,
      phone: value.phone,
      postalCode: value.postalCode,
      address: value.address,
    );
  }
}

class CustomerReservationCandidate {
  const CustomerReservationCandidate({
    required this.databaseId,
    required this.source,
    required this.reservationNumber,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.roomName,
    required this.priceYen,
    this.email,
    this.phone,
    this.postalCode,
    this.address,
  });

  final int databaseId;
  final String source;
  final String reservationNumber;
  final String guestName;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String? roomName;
  final int? priceYen;
  final String? email;
  final String? phone;
  final String? postalCode;
  final String? address;
}

class CustomerStay {
  const CustomerStay({
    required this.source,
    required this.reservationNumber,
    required this.checkIn,
    required this.checkOut,
    required this.roomName,
    required this.priceYen,
  });

  final String source;
  final String reservationNumber;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String? roomName;
  final int? priceYen;
}

class CustomerDocument {
  const CustomerDocument({
    required this.id,
    required this.customerId,
    required this.originalFileName,
    required this.storedFilePath,
    required this.ocrStatus,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType,
    this.ocrText,
  });

  final int id;
  final int customerId;
  final String originalFileName;
  final String storedFilePath;
  final String? mimeType;
  final String? ocrText;
  final String ocrStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasOcrText => ocrText != null && ocrText!.trim().isNotEmpty;

  factory CustomerDocument.fromRow(Map<String, Object?> row) {
    return CustomerDocument(
      id: _readInt(row['id']) ?? 0,
      customerId: _readInt(row['customer_id']) ?? 0,
      originalFileName: _readText(row['original_file_name']) ?? '添付ファイル',
      storedFilePath: _readText(row['stored_file_path']) ?? '',
      mimeType: _readText(row['mime_type']),
      ocrText: _readText(row['ocr_text']),
      ocrStatus: _readText(row['ocr_status']) ?? 'not_processed',
      createdAt: _readDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _readDate(row['updated_at']) ?? DateTime.now(),
    );
  }
}

class CustomerOcrResult {
  const CustomerOcrResult({
    required this.rawText,
    this.pages = const <CustomerOcrPageResult>[],
    this.fullName,
    this.email,
    this.phone,
    this.postalCode,
    this.address,
    this.country,
    this.warning,
  });

  final String rawText;
  final List<CustomerOcrPageResult> pages;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? postalCode;
  final String? address;
  final String? country;
  final String? warning;

  factory CustomerOcrResult.fromJson(Map<String, dynamic> json) {
    final suggestions = json['suggestions'];
    final values = suggestions is Map<String, dynamic>
        ? suggestions
        : const <String, dynamic>{};
    final rawPages = json['pages'];
    final pages = rawPages is List
        ? rawPages
              .whereType<Map<String, dynamic>>()
              .map(CustomerOcrPageResult.fromJson)
              .toList(growable: false)
        : const <CustomerOcrPageResult>[];
    return CustomerOcrResult(
      rawText: json['text']?.toString() ?? '',
      pages: pages,
      fullName: customerCleanText(values['fullName']),
      email: customerCleanText(values['email']),
      phone: customerCleanText(values['phone']),
      postalCode: customerCleanText(values['postalCode']),
      address: customerCleanText(values['address']),
      country: customerCleanText(values['country']),
      warning: customerCleanText(json['warning']),
    );
  }
}

class CustomerOcrPageResult {
  const CustomerOcrPageResult({
    required this.pageNumber,
    required this.rawText,
    this.fullName,
    this.email,
    this.phone,
    this.postalCode,
    this.address,
    this.country,
    this.attachmentPath,
    this.attachmentFileName,
    this.attachmentMimeType,
  });

  final int pageNumber;
  final String rawText;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? postalCode;
  final String? address;
  final String? country;
  final String? attachmentPath;
  final String? attachmentFileName;
  final String? attachmentMimeType;

  factory CustomerOcrPageResult.fromJson(Map<String, dynamic> json) {
    final suggestions = json['suggestions'];
    final values = suggestions is Map<String, dynamic>
        ? suggestions
        : const <String, dynamic>{};
    return CustomerOcrPageResult(
      pageNumber: _readInt(json['pageNumber']) ?? 1,
      rawText: json['text']?.toString() ?? '',
      fullName: customerCleanText(values['fullName']),
      email: customerCleanText(values['email']),
      phone: customerCleanText(values['phone']),
      postalCode: customerCleanText(values['postalCode']),
      address: customerCleanText(values['address']),
      country: customerCleanText(values['country']),
      attachmentPath: customerCleanText(json['attachmentPath']),
      attachmentFileName: customerCleanText(json['attachmentFileName']),
      attachmentMimeType: customerCleanText(json['attachmentMimeType']),
    );
  }
}

String? customerCleanText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _readText(Object? value) => customerCleanText(value);

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _readDate(Object? value) {
  final text = _readText(value);
  return text == null ? null : DateTime.tryParse(text);
}
