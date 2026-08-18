import '../models/checkin_sheet.dart';
import '../models/reservation.dart';

class RoomAssignmentResult {
  const RoomAssignmentResult({required this.rows, required this.warnings});

  final List<CheckinSheetRow> rows;
  final List<String> warnings;
}

class RoomAssignmentService {
  const RoomAssignmentService({required this.sheetDate});

  final DateTime sheetDate;

  CheckinSheetRow assignReservation({
    required int roomNumber,
    required Reservation reservation,
    required int guestCount,
    required bool includeBookingDetails,
  }) {
    return _rowForReservation(
      roomNumber: roomNumber,
      reservation: reservation,
      guestCount: guestCount,
      includeBookingDetails: includeBookingDetails,
    );
  }

  RoomAssignmentResult create(
    List<Reservation> reservations, {
    List<CheckinSheetRow> previousRows = const [],
  }) {
    final rows = GuestRoomSpec.rooms
        .map((room) => CheckinSheetRow.empty(room.number))
        .toList(growable: false);
    _carryOver(rows, previousRows, reservations);
    return _assignMissing(rows, reservations);
  }

  void _carryOver(
    List<CheckinSheetRow> rows,
    List<CheckinSheetRow> previousRows,
    List<Reservation> reservations,
  ) {
    final reservationByKey = {
      for (final reservation in reservations)
        reservationKey(reservation): reservation,
    };
    final detailKeys = rows
        .where((row) => row.reservationKey != null)
        .map((row) => row.reservationKey!)
        .toSet();
    for (final previous in previousRows) {
      final key = previous.reservationKey;
      if (key == null || previous.guestCount <= 0) {
        continue;
      }
      final reservation = reservationByKey[key];
      if (reservation == null || !_isStayover(reservation)) {
        continue;
      }
      final index = rows.indexWhere(
        (row) => row.roomNumber == previous.roomNumber,
      );
      if (index < 0 ||
          rows[index].hasReservation ||
          !GuestRoomSpec.byNumber(previous.roomNumber).isAvailable) {
        continue;
      }
      final assigned = rows
          .where((row) => row.reservationKey == key)
          .fold<int>(0, (sum, row) => sum + row.guestCount);
      final remaining = guestCount(reservation) - assigned;
      if (remaining <= 0) {
        continue;
      }
      final count = previous.guestCount > remaining
          ? remaining
          : previous.guestCount;
      rows[index] = _rowForReservation(
        roomNumber: previous.roomNumber,
        reservation: reservation,
        guestCount: count,
        includeBookingDetails: detailKeys.add(key),
      );
    }
  }

  RoomAssignmentResult reconcile(
    List<CheckinSheetRow> savedRows,
    List<Reservation> reservations, {
    List<CheckinSheetRow> previousRows = const [],
  }) {
    final activeKeys = reservations.map(reservationKey).toSet();
    final byRoom = <int, CheckinSheetRow>{
      for (final row in savedRows)
        row.roomNumber:
            row.hasReservation && activeKeys.contains(row.reservationKey)
            ? row
            : CheckinSheetRow.empty(row.roomNumber),
    };
    final rows = GuestRoomSpec.rooms
        .map(
          (room) => byRoom[room.number] ?? CheckinSheetRow.empty(room.number),
        )
        .toList(growable: false);
    _carryOver(rows, previousRows, reservations);
    return _assignMissing(rows, reservations);
  }

  List<String> validate(
    List<CheckinSheetRow> rows,
    List<Reservation> reservations,
  ) {
    final warnings = <String>[];
    final reservationByKey = {
      for (final reservation in reservations)
        reservationKey(reservation): reservation,
    };

    for (final row in rows) {
      if (!row.room.isAvailable && row.hasReservation) {
        warnings.add('${row.roomNumber}号室は使用不可です。');
      }
      if (row.guestCount > row.room.capacity && row.room.isAvailable) {
        warnings.add('${row.roomNumber}号室は定員${row.room.capacity}名を超えています。');
      }
    }

    for (final entry in reservationByKey.entries) {
      final assigned = rows
          .where((row) => row.reservationKey == entry.key)
          .fold<int>(0, (sum, row) => sum + row.guestCount);
      final expected = guestCount(entry.value);
      if (assigned < expected) {
        warnings.add(
          '${entry.value.displayGuestName}様が${expected - assigned}名分、未配室です。',
        );
      } else if (assigned > expected) {
        warnings.add(
          '${entry.value.displayGuestName}様の配室人数が${assigned - expected}名多くなっています。',
        );
      }
    }

    return warnings;
  }

  RoomAssignmentResult _assignMissing(
    List<CheckinSheetRow> sourceRows,
    List<Reservation> reservations,
  ) {
    final rows = List<CheckinSheetRow>.from(sourceRows);
    final warnings = <String>[];
    final sortedReservations = List<Reservation>.from(reservations)
      ..sort((first, second) {
        final firstLarge = _prefersLoft(first) ? 0 : 1;
        final secondLarge = _prefersLoft(second) ? 0 : 1;
        final typeOrder = firstLarge.compareTo(secondLarge);
        if (typeOrder != 0) {
          return typeOrder;
        }
        return guestCount(second).compareTo(guestCount(first));
      });

    for (final reservation in sortedReservations) {
      final key = reservationKey(reservation);
      final alreadyAssigned = rows
          .where((row) => row.reservationKey == key)
          .fold<int>(0, (sum, row) => sum + row.guestCount);
      var remainingGuests = guestCount(reservation) - alreadyAssigned;
      var isFirstRoom = !rows.any((row) => row.reservationKey == key);

      if (alreadyAssigned == 0) {
        for (final planned in _specifiedRoomPlan(reservation)) {
          if (remainingGuests <= 0) {
            break;
          }
          final index = rows.indexWhere(
            (row) => row.roomNumber == planned.roomNumber,
          );
          if (index < 0 || rows[index].hasReservation) {
            continue;
          }
          final room = GuestRoomSpec.byNumber(planned.roomNumber);
          if (!room.isAvailable) {
            continue;
          }
          final count = planned.guestCount > remainingGuests
              ? remainingGuests
              : planned.guestCount;
          if (count <= 0) {
            continue;
          }
          rows[index] = _rowForReservation(
            roomNumber: planned.roomNumber,
            reservation: reservation,
            guestCount: count,
            includeBookingDetails: isFirstRoom,
          );
          remainingGuests -= count;
          isFirstRoom = false;
        }
      }

      for (final roomNumber in _candidateRoomNumbers(reservation)) {
        if (remainingGuests <= 0) {
          break;
        }
        final index = rows.indexWhere((row) => row.roomNumber == roomNumber);
        if (index < 0 || rows[index].hasReservation) {
          continue;
        }
        final room = GuestRoomSpec.byNumber(roomNumber);
        if (!room.isAvailable) {
          continue;
        }
        final automaticCapacity = room.isLoft ? 4 : 2;
        final count = remainingGuests > automaticCapacity
            ? automaticCapacity
            : remainingGuests;
        rows[index] = _rowForReservation(
          roomNumber: roomNumber,
          reservation: reservation,
          guestCount: count,
          includeBookingDetails: isFirstRoom,
        );
        remainingGuests -= count;
        isFirstRoom = false;
      }

      if (remainingGuests > 0) {
        warnings.add(
          '${reservation.displayGuestName}様が$remainingGuests名分、未配室です。',
        );
      }
    }

    warnings.addAll(validate(rows, reservations));
    return RoomAssignmentResult(rows: rows, warnings: _unique(warnings));
  }

  CheckinSheetRow _rowForReservation({
    required int roomNumber,
    required Reservation reservation,
    required int guestCount,
    required bool includeBookingDetails,
  }) {
    final stayover = _isStayover(reservation);
    return CheckinSheetRow(
      roomNumber: roomNumber,
      reservationKey: reservationKey(reservation),
      reservationSource: reservation.source,
      reservationNumber: reservation.reservationNumber ?? reservation.id,
      guestName: reservation.displayGuestName,
      guestCount: guestCount,
      checkedIn: stayover,
      amountYen: includeBookingDetails && !stayover
          ? reservation.priceYen
          : null,
      payment: includeBookingDetails && !stayover
          ? _defaultPayment(reservation)
          : '',
      dinnerAndTable: reservation.hasDinner == true ? 'あり' : '',
      bathTime: '',
      breakfastTime: '',
      checkedOut: false,
      notes: includeBookingDetails ? _notesFor(reservation, stayover) : '',
    );
  }

  bool _isStayover(Reservation reservation) {
    final checkIn = reservation.checkIn;
    if (checkIn == null) {
      return false;
    }
    final arrival = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final target = DateTime(sheetDate.year, sheetDate.month, sheetDate.day);
    return target.isAfter(arrival);
  }

  String _notesFor(Reservation reservation, bool stayover) {
    final original = reservation.specialRequests?.trim() ?? '';
    if (!stayover || reservation.checkIn == null) {
      return original;
    }
    final arrival = DateTime(
      reservation.checkIn!.year,
      reservation.checkIn!.month,
      reservation.checkIn!.day,
    );
    final target = DateTime(sheetDate.year, sheetDate.month, sheetDate.day);
    final stayDay = target.difference(arrival).inDays + 1;
    final nights = reservation.nights;
    final label = nights != null && nights > 0
        ? '連泊 $stayDay日目（全$nights泊）'
        : '連泊 $stayDay日目';
    return original.isEmpty ? label : '$label / $original';
  }

  static List<int> _candidateRoomNumbers(Reservation reservation) {
    if (_prefersLoft(reservation)) {
      return const [2, 3, 8, 7, 1, 4, 5];
    }
    return const [1, 3, 4, 5, 7, 2, 8];
  }

  static List<_PlannedRoom> _specifiedRoomPlan(Reservation reservation) {
    final roomName = reservation.roomName?.trim() ?? '';
    if (roomName.isEmpty) {
      return const [];
    }

    final requests = <_RequestedRoom>[];
    for (final rawSegment in roomName.split(RegExp(r'[,、\n]+'))) {
      final segment = rawSegment.trim();
      if (segment.isEmpty) {
        continue;
      }
      final lower = segment.toLowerCase();
      final isLoft = lower.contains('ロフト') || lower.contains('loft');
      final isTwin =
          lower.contains('スタンダード') ||
          lower.contains('ツイン') ||
          lower.contains('standard twin') ||
          lower.contains('twin room');
      if (!isLoft && !isTwin) {
        continue;
      }

      final countMatch = RegExp(
        r'(\d+)\s*[x×]',
        caseSensitive: false,
      ).firstMatch(segment);
      final roomCount = int.tryParse(countMatch?.group(1) ?? '') ?? 1;
      final japaneseGuests = RegExp(
        r'(\d+)\s*名(?!\s*(?:室|部屋))',
      ).firstMatch(segment);
      final englishGuests = RegExp(
        r'(\d+)\s*(?:guests?|persons?)(?!\s*room)',
        caseSensitive: false,
      ).firstMatch(segment);
      final specifiedGuests = int.tryParse(
        japaneseGuests?.group(1) ?? englishGuests?.group(1) ?? '',
      );

      for (var index = 0; index < roomCount; index++) {
        requests.add(
          _RequestedRoom(
            isLoft: isLoft,
            specifiedGuests: roomCount == 1 ? specifiedGuests : null,
          ),
        );
      }
    }
    if (requests.isEmpty) {
      return const [];
    }

    final counts = List<int>.filled(requests.length, 0);
    var remaining = guestCount(reservation);
    if (requests.length == 1 && requests.first.specifiedGuests == null) {
      final maximumCapacity = requests.first.isLoft ? 5 : 3;
      final count = remaining > maximumCapacity ? maximumCapacity : remaining;
      counts[0] = count;
      remaining -= count;
    }
    for (var index = 0; index < requests.length; index++) {
      final specified = requests[index].specifiedGuests;
      if (specified == null || remaining <= 0) {
        continue;
      }
      final count = specified > remaining ? remaining : specified;
      counts[index] = count;
      remaining -= count;
    }

    final unspecified =
        <int>[
          for (var index = 0; index < requests.length; index++)
            if (requests[index].specifiedGuests == null && counts[index] == 0)
              index,
        ]..sort((first, second) {
          if (requests[first].isLoft == requests[second].isLoft) {
            return first.compareTo(second);
          }
          return requests[first].isLoft ? 1 : -1;
        });

    for (var position = 0; position < unspecified.length; position++) {
      final index = unspecified[position];
      final roomsAfter = unspecified.length - position - 1;
      final available = remaining - roomsAfter;
      final capacity = requests[index].isLoft ? 4 : 2;
      final count = available <= 0
          ? 0
          : available > capacity
          ? capacity
          : available;
      counts[index] = count;
      remaining -= count;
    }

    final hasLoft = requests.any((request) => request.isLoft);
    final loftNumbers = <int>[2, 8];
    final twinNumbers = hasLoft ? <int>[3, 7, 1, 4, 5] : <int>[1, 3, 4, 5, 7];
    var loftIndex = 0;
    var twinIndex = 0;
    final plan = <_PlannedRoom>[];
    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      final roomNumber = request.isLoft
          ? loftIndex < loftNumbers.length
                ? loftNumbers[loftIndex++]
                : null
          : twinIndex < twinNumbers.length
          ? twinNumbers[twinIndex++]
          : null;
      if (roomNumber != null && counts[index] > 0) {
        plan.add(
          _PlannedRoom(roomNumber: roomNumber, guestCount: counts[index]),
        );
      }
    }

    const roomOrder = <int>[2, 3, 8, 7, 1, 4, 5];
    plan.sort(
      (first, second) => roomOrder
          .indexOf(first.roomNumber)
          .compareTo(roomOrder.indexOf(second.roomNumber)),
    );
    return plan;
  }

  static bool _prefersLoft(Reservation reservation) {
    final roomName = reservation.roomName?.toLowerCase() ?? '';
    return guestCount(reservation) >= 3 ||
        roomName.contains('ロフト') ||
        roomName.contains('loft') ||
        roomName.contains('4名');
  }

  static String _defaultPayment(Reservation reservation) {
    final source = reservation.source.trim().toUpperCase();
    if (source == 'CHILLNN') {
      return 'OL';
    }
    if (source == 'MANUAL') {
      return '現地';
    }
    return '';
  }

  static int guestCount(Reservation reservation) {
    final count =
        reservation.totalGuests ??
        ((reservation.adults ?? 0) + reservation.children);
    return count <= 0 ? 1 : count;
  }

  static String reservationKey(Reservation reservation) {
    return '${reservation.source}::${reservation.reservationNumber ?? reservation.id}';
  }

  static List<String> _unique(List<String> values) {
    final seen = <String>{};
    return values.where(seen.add).toList(growable: false);
  }
}

class _RequestedRoom {
  const _RequestedRoom({required this.isLoft, this.specifiedGuests});

  final bool isLoft;
  final int? specifiedGuests;
}

class _PlannedRoom {
  const _PlannedRoom({required this.roomNumber, required this.guestCount});

  final int roomNumber;
  final int guestCount;
}
