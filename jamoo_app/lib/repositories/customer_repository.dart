import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/customer.dart';
import '../services/database_service.dart';

class CustomerRepository {
  const CustomerRepository();

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await DatabaseService.instance.database;
    final cleaned = query.trim();
    final where = cleaned.isEmpty
        ? ''
        : 'WHERE c.full_name LIKE ? OR c.phone LIKE ? OR c.email LIKE ? '
              'OR c.postal_code LIKE ? OR c.address LIKE ? '
              'OR c.country LIKE ?';
    final args = cleaned.isEmpty
        ? <Object?>[]
        : List<Object?>.filled(6, '%$cleaned%');

    final rows = await db.rawQuery('''
      SELECT
        c.*,
        MIN(
          CASE WHEN LOWER(COALESCE(r.status, 'confirmed'))
            NOT IN ('cancelled', 'canceled') THEN r.check_in END
        ) AS calculated_first_stay_date,
        MAX(
          CASE WHEN LOWER(COALESCE(r.status, 'confirmed'))
            NOT IN ('cancelled', 'canceled') THEN r.check_in END
        ) AS calculated_last_stay_date,
        COALESCE(SUM(
          CASE WHEN r.id IS NOT NULL
            AND LOWER(COALESCE(r.status, 'confirmed'))
              NOT IN ('cancelled', 'canceled') THEN 1 ELSE 0 END
        ), 0) AS calculated_stay_count,
        COALESCE(SUM(
          CASE WHEN LOWER(COALESCE(r.status, 'confirmed'))
            NOT IN ('cancelled', 'canceled')
            THEN COALESCE(r.price_yen, 0) ELSE 0 END
        ), 0) AS calculated_total_spend_yen,
        COALESCE(SUM(
          CASE WHEN r.id IS NOT NULL
            AND LOWER(COALESCE(r.status, 'confirmed'))
              NOT IN ('cancelled', 'canceled') THEN 1 ELSE 0 END
        ), 0) AS calculated_active_reservation_count,
        COALESCE(SUM(
          CASE WHEN r.id IS NOT NULL
            AND LOWER(COALESCE(r.status, 'confirmed'))
              IN ('cancelled', 'canceled') THEN 1 ELSE 0 END
        ), 0) AS calculated_cancelled_reservation_count,
        GROUP_CONCAT(DISTINCT CASE WHEN r.id IS NOT NULL THEN r.source END)
          AS calculated_reservation_sources
      FROM customers c
      LEFT JOIN reservations r
        ON (
         r.id IN (
           SELECT linked.reservation_id
           FROM stays linked
           WHERE linked.customer_id = c.id
         )
         OR
         (COALESCE(TRIM(c.email), '') <> ''
           AND LOWER(TRIM(r.email)) = LOWER(TRIM(c.email)))
         OR
         (COALESCE(TRIM(c.phone), '') <> ''
           AND TRIM(r.phone) = TRIM(c.phone))
         OR
         (COALESCE(TRIM(c.email), '') = ''
           AND COALESCE(TRIM(c.phone), '') = ''
           AND TRIM(r.guest_name) = TRIM(c.full_name))
       )
      $where
      GROUP BY c.id
      ORDER BY
        CASE WHEN MAX(
          CASE WHEN LOWER(COALESCE(r.status, 'confirmed'))
            NOT IN ('cancelled', 'canceled') THEN r.check_in END
        ) IS NULL THEN 1 ELSE 0 END,
        MAX(
          CASE WHEN LOWER(COALESCE(r.status, 'confirmed'))
            NOT IN ('cancelled', 'canceled') THEN r.check_in END
        ) DESC,
        MAX(r.check_in) DESC,
        c.full_name COLLATE NOCASE ASC
    ''', args);

    return rows.map(Customer.fromRow).toList(growable: false);
  }

  Future<Customer?> findDuplicate(
    CustomerDraft draft, {
    int? excludingCustomerId,
  }) async {
    final db = await DatabaseService.instance.database;
    final conditions = <String>[];
    final args = <Object?>[];
    final email = customerCleanText(draft.email);
    final phone = customerCleanText(draft.phone);

    if (email != null) {
      conditions.add('LOWER(email) = LOWER(?)');
      args.add(email);
    }
    if (phone != null) {
      conditions.add('phone = ?');
      args.add(phone);
    }
    if (conditions.isEmpty) {
      conditions.add('full_name = ?');
      args.add(draft.fullName.trim());
    }
    if (excludingCustomerId != null) {
      conditions.add('id <> ?');
      args.add(excludingCustomerId);
    }

    final duplicateWhere = conditions.length > 1 && excludingCustomerId != null
        ? '(${conditions.take(conditions.length - 1).join(' OR ')}) '
              'AND ${conditions.last}'
        : conditions.join(' OR ');
    final rows = await db.query(
      'customers',
      where: duplicateWhere,
      whereArgs: args,
      limit: 1,
    );
    return rows.isEmpty ? null : Customer.fromRow(rows.first);
  }

  Future<int> saveCustomer(
    CustomerDraft draft, {
    int? customerId,
    CustomerReservationCandidate? reservation,
  }) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'full_name': draft.fullName.trim(),
      'email': customerCleanText(draft.email),
      'phone': customerCleanText(draft.phone),
      'postal_code': customerCleanText(draft.postalCode),
      'address': customerCleanText(draft.address),
      'country': customerCleanText(draft.country),
      'notes': customerCleanText(draft.notes),
      'updated_at': now,
    };

    return db.transaction((txn) async {
      late final int savedId;
      if (customerId == null) {
        savedId = await txn.insert('customers', {
          ...values,
          'first_stay_date': _formatDate(reservation?.checkIn),
          'last_stay_date': _formatDate(reservation?.checkIn),
          'stay_count': reservation == null ? 0 : 1,
          'total_spend_yen': reservation?.priceYen ?? 0,
          'created_at': now,
        });
      } else {
        savedId = customerId;
        await txn.update(
          'customers',
          values,
          where: 'id = ?',
          whereArgs: [customerId],
        );
      }

      if (reservation != null) {
        await _linkReservation(txn, savedId, draft, reservation, now);
      }
      return savedId;
    });
  }

  Future<void> _linkReservation(
    Transaction txn,
    int customerId,
    CustomerDraft draft,
    CustomerReservationCandidate reservation,
    String now,
  ) async {
    final existing = await txn.query(
      'stays',
      columns: const ['id'],
      where: 'reservation_id = ?',
      whereArgs: [reservation.databaseId],
      limit: 1,
    );
    final values = <String, Object?>{
      'reservation_id': reservation.databaseId,
      'customer_id': customerId,
      'representative_name': draft.fullName.trim(),
      'address': customerCleanText(draft.address),
      'phone': customerCleanText(draft.phone),
      'email': customerCleanText(draft.email),
      'updated_at': now,
    };
    if (existing.isEmpty) {
      await txn.insert('stays', {...values, 'created_at': now});
    } else {
      await txn.update(
        'stays',
        values,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<List<CustomerStay>> loadHistory(Customer customer) async {
    final db = await DatabaseService.instance.database;
    final match = _reservationMatch(customer);
    final rows = await db.rawQuery(
      'SELECT DISTINCT r.* FROM reservations r '
      'LEFT JOIN stays s ON s.reservation_id = r.id '
      'WHERE LOWER(COALESCE(r.status, \'confirmed\')) '
      "NOT IN ('cancelled', 'canceled') AND "
      '(s.customer_id = ? OR ${match.sql}) '
      'ORDER BY r.check_in DESC, r.id DESC',
      [customer.id, ...match.args],
    );

    return rows
        .map(
          (row) => CustomerStay(
            source: row['source']?.toString() ?? '',
            reservationNumber: row['external_reservation_id']?.toString() ?? '',
            checkIn: DateTime.tryParse(row['check_in']?.toString() ?? ''),
            checkOut: DateTime.tryParse(row['check_out']?.toString() ?? ''),
            roomName: customerCleanText(row['room_name']),
            priceYen: _readInt(row['price_yen']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<CustomerReservationCandidate>> loadReservationCandidates(
    String query,
  ) async {
    final db = await DatabaseService.instance.database;
    final cleaned = query.trim();
    final where = cleaned.isEmpty
        ? ''
        : 'AND (r.guest_name LIKE ? OR r.phone LIKE ? OR r.email LIKE ? '
              'OR r.external_reservation_id LIKE ?)';
    final args = cleaned.isEmpty
        ? <Object?>[]
        : List<Object?>.filled(4, '%$cleaned%');
    final rows = await db.rawQuery(
      'SELECT r.* FROM reservations r '
      "WHERE LOWER(COALESCE(r.status, 'confirmed')) "
      "NOT IN ('cancelled', 'canceled') $where "
      'ORDER BY r.check_in DESC, r.id DESC LIMIT 300',
      args,
    );

    return rows.map(_candidateFromRow).toList(growable: false);
  }

  Future<CustomerDocument> addCustomerDocument({
    required int customerId,
    required String originalFileName,
    required String storedFilePath,
    required String mimeType,
  }) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('customer_documents', {
      'customer_id': customerId,
      'original_file_name': originalFileName,
      'stored_file_path': storedFilePath,
      'mime_type': mimeType,
      'ocr_text': null,
      'ocr_status': 'not_processed',
      'created_at': now,
      'updated_at': now,
    });
    final rows = await db.query(
      'customer_documents',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return CustomerDocument.fromRow(rows.single);
  }

  Future<List<CustomerDocument>> loadCustomerDocuments(int customerId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'customer_documents',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(CustomerDocument.fromRow).toList(growable: false);
  }

  Future<void> updateDocumentOcr({
    required int documentId,
    required String status,
    String? ocrText,
  }) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'customer_documents',
      {
        'ocr_status': status,
        'ocr_text': customerCleanText(ocrText),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  Future<String?> deleteCustomerDocument(int documentId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'customer_documents',
      columns: const ['stored_file_path'],
      where: 'id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final path = customerCleanText(rows.single['stored_file_path']);
    await db.delete(
      'customer_documents',
      where: 'id = ?',
      whereArgs: [documentId],
    );
    return path;
  }

  CustomerReservationCandidate _candidateFromRow(Map<String, Object?> row) {
    final raw = _readJson(row['raw_payload']);
    return CustomerReservationCandidate(
      databaseId: _readInt(row['id']) ?? 0,
      source: row['source']?.toString() ?? '',
      reservationNumber: row['external_reservation_id']?.toString() ?? '',
      guestName: customerCleanText(row['guest_name']) ?? '氏名未設定',
      checkIn: DateTime.tryParse(row['check_in']?.toString() ?? ''),
      checkOut: DateTime.tryParse(row['check_out']?.toString() ?? ''),
      roomName: customerCleanText(row['room_name']),
      priceYen: _readInt(row['price_yen']),
      email:
          customerCleanText(row['email']) ?? customerCleanText(raw?['email']),
      phone:
          customerCleanText(row['phone']) ?? customerCleanText(raw?['phone']),
      postalCode: customerCleanText(raw?['postalCode'] ?? raw?['postal_code']),
      address: customerCleanText(raw?['address']),
    );
  }

  _SqlMatch _reservationMatch(Customer customer) {
    final email = customerCleanText(customer.email);
    final phone = customerCleanText(customer.phone);
    if (email != null && phone != null) {
      return _SqlMatch(
        '(LOWER(TRIM(r.email)) = LOWER(?) OR TRIM(r.phone) = ?)',
        [email, phone],
      );
    }
    if (email != null) {
      return _SqlMatch('LOWER(TRIM(r.email)) = LOWER(?)', [email]);
    }
    if (phone != null) {
      return _SqlMatch('TRIM(r.phone) = ?', [phone]);
    }
    return _SqlMatch('TRIM(r.guest_name) = ?', [customer.fullName.trim()]);
  }

  static String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic>? _readJson(Object? value) {
    final text = customerCleanText(value);
    if (text == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class _SqlMatch {
  const _SqlMatch(this.sql, this.args);

  final String sql;
  final List<Object?> args;
}
