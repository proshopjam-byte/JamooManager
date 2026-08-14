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
              'OR c.postal_code LIKE ? OR c.address LIKE ?';
    final args = cleaned.isEmpty
        ? <Object?>[]
        : List<Object?>.filled(5, '%$cleaned%');

    final rows = await db.rawQuery('''
      SELECT
        c.*,
        MIN(r.check_in) AS calculated_first_stay_date,
        MAX(r.check_in) AS calculated_last_stay_date,
        COUNT(r.id) AS calculated_stay_count,
        COALESCE(SUM(COALESCE(r.price_yen, 0)), 0)
          AS calculated_total_spend_yen
      FROM customers c
      LEFT JOIN reservations r
        ON LOWER(COALESCE(r.status, 'confirmed'))
             NOT IN ('cancelled', 'canceled')
       AND (
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
        CASE WHEN MAX(r.check_in) IS NULL THEN 1 ELSE 0 END,
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
      await txn.insert('stays', {
        ...values,
        'created_at': now,
      });
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
            reservationNumber:
                row['external_reservation_id']?.toString() ?? '',
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
      postalCode: customerCleanText(
        raw?['postalCode'] ?? raw?['postal_code'],
      ),
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
