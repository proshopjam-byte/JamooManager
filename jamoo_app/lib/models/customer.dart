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
  final DateTime? firstStayDate;
  final DateTime? lastStayDate;
  final int stayCount;
  final int totalSpendYen;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Customer.fromRow(Map<String, Object?> row) {
    return Customer(
      id: _readInt(row['id']) ?? 0,
      fullName: _readText(row['full_name']) ?? '氏名未設定',
      email: _readText(row['email']),
      phone: _readText(row['phone']),
      postalCode: _readText(row['postal_code']),
      address: _readText(row['address']),
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

class CustomerDraft {
  const CustomerDraft({
    required this.fullName,
    this.email,
    this.phone,
    this.postalCode,
    this.address,
    this.notes,
  });

  final String fullName;
  final String? email;
  final String? phone;
  final String? postalCode;
  final String? address;
  final String? notes;

  factory CustomerDraft.fromCustomer(Customer customer) {
    return CustomerDraft(
      fullName: customer.fullName,
      email: customer.email,
      phone: customer.phone,
      postalCode: customer.postalCode,
      address: customer.address,
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
