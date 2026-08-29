import '../models/checkin_sheet.dart';
import '../models/reservation.dart';

class RoomAssignmentResult {
  const RoomAssignmentResult({required this.rows, required this.warnings});

  final List<CheckinSheetRow> rows;
  final List<String> warnings;
}

class RoomAssignmentService {
  RoomAssignmentService({
    required List<GuestRoomSpec> rooms,
    required DateTime stayDate,
  }) : stayDate = DateTime(stayDate.year, stayDate.month, stayDate.day),
       rooms = List.unmodifiable(
         List<GuestRoomSpec>.from(rooms)
           ..sort((first, second) => first.number.compareTo(second.number)),
       );

  final List<GuestRoomSpec> rooms;
  final DateTime stayDate;

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

  RoomAssignmentResult create(List<Reservation> reservations) {
    final rows = rooms
        .map((room) => CheckinSheetRow.empty(room.number))
        .toList(growable: false);
    return _assignMissing(rows, reservations);
  }

  RoomAssignmentResult reconcile(
    List<CheckinSheetRow> savedRows,
    List<Reservation> reservations,
  ) {
    final activeKeys = reservations.map(reservationKey).toSet();
    final byRoom = <int, CheckinSheetRow>{
      for (final row in savedRows)
        row.roomNumber:
            row.hasReservation && activeKeys.contains(row.reservationKey)
            ? row
            : CheckinSheetRow.empty(row.roomNumber),
    };
    final rows = rooms
        .map(
          (room) => byRoom[room.number] ?? CheckinSheetRow.empty(room.number),
        )
        .toList(growable: false);
    return _assignMissing(rows, reservations);
  }

  /// Carries continuing guests into a new day's sheet while keeping their
  /// previous room numbers. Daily fields are rebuilt so yesterday's payment,
  /// check-in state, and service times are not copied accidentally.
  RoomAssignmentResult carryForward(
    List<CheckinSheetRow> previousRows,
    List<Reservation> reservations,
  ) {
    final emptyRows = rooms
        .map((room) => CheckinSheetRow.empty(room.number))
        .toList(growable: false);
    return reconcileWithCarryForward(emptyRows, previousRows, reservations);
  }

  /// Preserves edits already saved for [stayDate], then fills empty rooms from
  /// the previous day's assignment before assigning newly arriving guests.
  RoomAssignmentResult reconcileWithCarryForward(
    List<CheckinSheetRow> currentRows,
    List<CheckinSheetRow> previousRows,
    List<Reservation> reservations,
  ) {
    final reservationByKey = {
      for (final reservation in reservations)
        reservationKey(reservation): reservation,
    };
    final activeKeys = reservationByKey.keys.toSet();
    final currentByRoom = <int, CheckinSheetRow>{
      for (final row in currentRows)
        row.roomNumber:
            row.hasReservation && activeKeys.contains(row.reservationKey)
            ? _refreshSavedRow(row, reservationByKey[row.reservationKey]!)
            : CheckinSheetRow.empty(row.roomNumber),
    };
    final rows = rooms
        .map(
          (room) =>
              currentByRoom[room.number] ?? CheckinSheetRow.empty(room.number),
        )
        .toList(growable: false);
    final assignedCounts = <String, int>{};
    final detailsAdded = <String>{};
    for (final row in rows.where((row) => row.hasReservation)) {
      final key = row.reservationKey!;
      assignedCounts[key] = (assignedCounts[key] ?? 0) + row.guestCount;
      detailsAdded.add(key);
    }

    for (final previousRow in previousRows) {
      final key = previousRow.reservationKey;
      if (key == null) continue;
      final reservation = reservationByKey[key];
      if (reservation == null || !_isStayover(reservation)) continue;

      final room = _roomByNumber(previousRow.roomNumber);
      if (room == null || !room.isAvailable) continue;
      final rowIndex = rows.indexWhere(
        (row) => row.roomNumber == previousRow.roomNumber,
      );
      if (rowIndex < 0 || rows[rowIndex].hasReservation) continue;

      final expected = guestCount(reservation);
      final alreadyAssigned = assignedCounts[key] ?? 0;
      final remaining = expected - alreadyAssigned;
      if (remaining <= 0) continue;

      final maximumForRoom = remaining < room.capacity
          ? remaining
          : room.capacity;
      final count = previousRow.guestCount <= 0
          ? maximumForRoom
          : previousRow.guestCount.clamp(1, maximumForRoom).toInt();
      rows[rowIndex] = _rowForReservation(
        roomNumber: room.number,
        reservation: reservation,
        guestCount: count,
        includeBookingDetails: detailsAdded.add(key),
      );
      assignedCounts[key] = alreadyAssigned + count;
    }

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
      final room = _roomByNumber(row.roomNumber);
      if (room == null) {
        warnings.add('${row.roomNumber}号室は施設設定にありません。');
        continue;
      }
      if (!room.isAvailable && row.hasReservation) {
        warnings.add('${room.displayName}は使用不可です。');
      }
      if (row.guestCount > room.capacity && room.isAvailable) {
        warnings.add('${room.displayName}は定員${room.capacity}名を超えています。');
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
        final guestOrder = guestCount(second).compareTo(guestCount(first));
        if (guestOrder != 0) return guestOrder;
        return second.roomCount.compareTo(first.roomCount);
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
          final room = _roomByNumber(planned.roomNumber);
          if (room == null || !room.isAvailable) {
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

      final occupiedRoomNumbers = rows
          .where((row) => row.hasReservation)
          .map((row) => row.roomNumber)
          .toSet();
      final assignedRoomNumbers = rows
          .where((row) => row.reservationKey == key)
          .map((row) => row.roomNumber)
          .toSet();
      for (final roomNumber in _candidateRoomNumbers(
        reservation,
        excludedRoomNumbers: occupiedRoomNumbers,
        preferredAdjacentTo: assignedRoomNumbers,
        guestsToAssign: remainingGuests,
      )) {
        if (remainingGuests <= 0) {
          break;
        }
        final index = rows.indexWhere((row) => row.roomNumber == roomNumber);
        if (index < 0 || rows[index].hasReservation) {
          continue;
        }
        final room = _roomByNumber(roomNumber);
        if (room == null || !room.isAvailable) {
          continue;
        }
        final count = remainingGuests > room.normalCapacity
            ? room.normalCapacity
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

  List<int> _candidateRoomNumbers(
    Reservation reservation, {
    Set<int> excludedRoomNumbers = const {},
    Set<int> preferredAdjacentTo = const {},
    int? guestsToAssign,
  }) {
    final requestedGuests = guestsToAssign ?? guestCount(reservation);
    if (requestedGuests <= 0) return const [];
    final available = rooms
        .where(
          (room) =>
              room.isAvailable && !excludedRoomNumbers.contains(room.number),
        )
        .toList();
    if (available.isEmpty) return const [];

    available.sort((first, second) {
      final firstAdjacent = _isAdjacentToAny(first, preferredAdjacentTo);
      final secondAdjacent = _isAdjacentToAny(second, preferredAdjacentTo);
      if (firstAdjacent != secondAdjacent) return firstAdjacent ? -1 : 1;

      if (preferredAdjacentTo.isEmpty) {
        final firstNamed = _roomMatchesReservationName(first, reservation);
        final secondNamed = _roomMatchesReservationName(second, reservation);
        if (firstNamed != secondNamed) return firstNamed ? -1 : 1;
      }

      final firstDifference = (first.normalCapacity - requestedGuests).abs();
      final secondDifference = (second.normalCapacity - requestedGuests).abs();
      final differenceOrder = firstDifference.compareTo(secondDifference);
      if (differenceOrder != 0) return differenceOrder;

      final capacityOrder = first.normalCapacity.compareTo(
        second.normalCapacity,
      );
      if (capacityOrder != 0) return capacityOrder;
      if (preferredAdjacentTo.isNotEmpty) {
        final firstDistance = _distanceToAny(first, preferredAdjacentTo);
        final secondDistance = _distanceToAny(second, preferredAdjacentTo);
        final distanceOrder = firstDistance.compareTo(secondDistance);
        if (distanceOrder != 0) return distanceOrder;
        return second.number.compareTo(first.number);
      }
      return first.number.compareTo(second.number);
    });

    final primary = available.first;
    final remainingGuests = (requestedGuests - primary.normalCapacity)
        .clamp(1, requestedGuests)
        .toInt();
    final remainingRooms = available.skip(1).toList()
      ..sort((first, second) {
        final firstAdjacent = _areAdjacent(primary, first);
        final secondAdjacent = _areAdjacent(primary, second);
        if (firstAdjacent != secondAdjacent) return firstAdjacent ? -1 : 1;

        final firstDifference = (first.normalCapacity - remainingGuests).abs();
        final secondDifference = (second.normalCapacity - remainingGuests)
            .abs();
        final differenceOrder = firstDifference.compareTo(secondDifference);
        if (differenceOrder != 0) return differenceOrder;
        return _compareDistance(first, second, primary.number);
      });
    return [primary.number, ...remainingRooms.map((room) => room.number)];
  }

  List<_PlannedRoom> _specifiedRoomPlan(Reservation reservation) {
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
      final configuredRoom = _configuredRoomForSegment(segment);
      final legacyType = _legacyRoomTypeForSegment(segment);
      if (configuredRoom == null && legacyType == null) {
        continue;
      }

      final countMatch = RegExp(
        r'(\d+)\s*[x×]',
        caseSensitive: false,
      ).firstMatch(segment);
      final suffixCountMatch = RegExp(
        r'[x×]\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(segment);
      final roomCount =
          int.tryParse(
            countMatch?.group(1) ?? suffixCountMatch?.group(1) ?? '',
          ) ??
          1;
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
            roomTypeKey: configuredRoom == null
                ? null
                : _roomTypeKey(configuredRoom.label),
            fallbackType: configuredRoom?.type ?? legacyType!,
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
      final normalCapacity = _capacityForRequest(requests.first);
      final count = remaining > normalCapacity ? normalCapacity : remaining;
      counts[0] = count;
      remaining -= count;
    }
    for (var index = 0; index < requests.length; index++) {
      final specified = requests[index].specifiedGuests;
      if (specified == null || remaining <= 0) {
        continue;
      }
      final maximum = _capacityForRequest(requests[index], maximum: true);
      final limited = specified > maximum ? maximum : specified;
      final count = limited > remaining ? remaining : limited;
      counts[index] = count;
      remaining -= count;
    }

    final unspecified = <int>[
      for (var index = 0; index < requests.length; index++)
        if (requests[index].specifiedGuests == null && counts[index] == 0)
          index,
    ];

    for (var position = 0; position < unspecified.length; position++) {
      final index = unspecified[position];
      final roomsAfter = unspecified.length - position - 1;
      final available = remaining - roomsAfter;
      final capacity = _capacityForRequest(requests[index]);
      final count = available <= 0
          ? 0
          : available > capacity
          ? capacity
          : available;
      counts[index] = count;
      remaining -= count;
    }

    final roomNumbers = List<int?>.filled(requests.length, null);
    final selectedRooms = <GuestRoomSpec>[];
    final usedRoomNumbers = <int>{};
    for (var index = 0; index < requests.length; index++) {
      final candidates = _roomsForRequest(
        requests[index],
      ).where((room) => !usedRoomNumbers.contains(room.number)).toList();
      if (candidates.isEmpty) continue;
      candidates.sort((first, second) {
        final firstAdjacent = selectedRooms.any(
          (selected) => _areAdjacent(selected, first),
        );
        final secondAdjacent = selectedRooms.any(
          (selected) => _areAdjacent(selected, second),
        );
        if (firstAdjacent != secondAdjacent) return firstAdjacent ? -1 : 1;
        if (selectedRooms.isNotEmpty) {
          final distanceOrder = _compareDistance(
            first,
            second,
            selectedRooms.last.number,
          );
          if (distanceOrder != 0) return distanceOrder;
        }
        return first.number.compareTo(second.number);
      });
      final selected = candidates.first;
      roomNumbers[index] = selected.number;
      selectedRooms.add(selected);
      usedRoomNumbers.add(selected.number);
    }

    final plan = <_PlannedRoom>[];
    for (var index = 0; index < requests.length; index++) {
      final roomNumber = roomNumbers[index];
      if (roomNumber != null && counts[index] > 0) {
        plan.add(
          _PlannedRoom(roomNumber: roomNumber, guestCount: counts[index]),
        );
      }
    }

    return plan;
  }

  int _capacityForRequest(_RequestedRoom request, {bool maximum = false}) {
    final matching = _roomsForRequest(request);
    if (matching.isEmpty) {
      return 1;
    }
    return matching
        .map((room) => maximum ? room.capacity : room.normalCapacity)
        .reduce((first, second) => first > second ? first : second);
  }

  List<GuestRoomSpec> _roomsForRequest(_RequestedRoom request) {
    final matchingLabel = request.roomTypeKey;
    return rooms
        .where(
          (room) =>
              room.isAvailable &&
              (matchingLabel != null
                  ? _roomTypeKey(room.label) == matchingLabel
                  : room.type == request.fallbackType),
        )
        .toList(growable: false);
  }

  GuestRoomSpec? _configuredRoomForSegment(String segment) {
    final normalized = _roomTypeKey(segment);
    final matching =
        rooms
            .where(
              (room) =>
                  room.isAvailable &&
                  _roomTypeKey(room.label).length >= 2 &&
                  normalized.contains(_roomTypeKey(room.label)),
            )
            .toList()
          ..sort(
            (first, second) =>
                second.label.length.compareTo(first.label.length),
          );
    return matching.isEmpty ? null : matching.first;
  }

  GuestRoomType? _legacyRoomTypeForSegment(String segment) {
    final lower = segment.toLowerCase();
    if (lower.contains('ロフト') || lower.contains('loft')) {
      return GuestRoomType.loft;
    }
    if (lower.contains('スタンダード') ||
        lower.contains('ツイン') ||
        lower.contains('standard twin') ||
        lower.contains('twin room')) {
      return GuestRoomType.standardTwin;
    }
    return null;
  }

  bool _roomMatchesReservationName(
    GuestRoomSpec room,
    Reservation reservation,
  ) {
    final name = reservation.roomName?.trim() ?? '';
    if (name.isEmpty) return false;
    final normalizedName = _roomTypeKey(name);
    final roomKey = _roomTypeKey(room.label);
    if (roomKey.length >= 2 && normalizedName.contains(roomKey)) return true;
    return _legacyRoomTypeForSegment(name) == room.type;
  }

  bool _areAdjacent(GuestRoomSpec first, GuestRoomSpec second) {
    return first.adjacentRoomNumbers.contains(second.number) ||
        second.adjacentRoomNumbers.contains(first.number);
  }

  bool _isAdjacentToAny(GuestRoomSpec room, Set<int> roomNumbers) {
    for (final roomNumber in roomNumbers) {
      final assignedRoom = _roomByNumber(roomNumber);
      if (assignedRoom != null && _areAdjacent(assignedRoom, room)) return true;
    }
    return false;
  }

  int _distanceToAny(GuestRoomSpec room, Set<int> roomNumbers) {
    var minimum = 1 << 30;
    for (final roomNumber in roomNumbers) {
      final distance = (room.number - roomNumber).abs();
      if (distance < minimum) minimum = distance;
    }
    return minimum;
  }

  static String _roomTypeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s　・\-_/]+'), '');
  }

  GuestRoomSpec? _roomByNumber(int roomNumber) {
    for (final room in rooms) {
      if (room.number == roomNumber) {
        return room;
      }
    }
    return null;
  }

  static int _compareDistance(
    GuestRoomSpec first,
    GuestRoomSpec second,
    int anchor,
  ) {
    final firstDistance = (first.number - anchor).abs();
    final secondDistance = (second.number - anchor).abs();
    final distanceOrder = firstDistance.compareTo(secondDistance);
    if (distanceOrder != 0) {
      return distanceOrder;
    }
    return second.number.compareTo(first.number);
  }

  CheckinSheetRow _rowForReservation({
    required int roomNumber,
    required Reservation reservation,
    required int guestCount,
    required bool includeBookingDetails,
  }) {
    final stayProgressLabel = _stayProgressLabel(reservation);
    final isStayover = _isStayover(reservation);
    final reservationNotes = includeBookingDetails
        ? reservation.specialRequests?.trim() ?? ''
        : '';
    final notes = [
      stayProgressLabel ?? '',
      reservationNotes,
    ].where((value) => value.isNotEmpty).join('・');

    return CheckinSheetRow(
      roomNumber: roomNumber,
      reservationKey: reservationKey(reservation),
      reservationSource: reservation.source,
      reservationNumber: reservation.reservationNumber ?? reservation.id,
      guestName: reservation.displayGuestName,
      guestCount: guestCount,
      checkedIn: isStayover,
      amountYen: includeBookingDetails && !isStayover
          ? reservation.priceYen
          : null,
      payment: includeBookingDetails && !isStayover
          ? _defaultPayment(reservation)
          : '',
      dinnerAndTable: reservation.hasDinner == true ? 'あり' : '',
      bathTime: '',
      breakfastTime: '',
      checkedOut: false,
      notes: notes,
    );
  }

  CheckinSheetRow _refreshSavedRow(
    CheckinSheetRow row,
    Reservation reservation,
  ) {
    final progressLabel = _stayProgressLabel(reservation);
    if (progressLabel == null) return row;

    final savedNotes = row.notes
        .replaceAll(RegExp(r'連泊(?:開始|中)（\d+泊目／全\d+泊）'), '')
        .split('・')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('・');
    final notes = [
      progressLabel,
      savedNotes,
    ].where((value) => value.isNotEmpty).join('・');
    final isStayover = _isStayover(reservation);

    return row.copyWith(
      checkedIn: isStayover ? true : row.checkedIn,
      clearAmount: isStayover,
      payment: isStayover ? '' : row.payment,
      notes: notes,
    );
  }

  bool _isStayover(Reservation reservation) {
    final checkIn = reservation.checkIn;
    if (checkIn == null || !reservation.staysOn(stayDate)) return false;
    final arrival = DateTime(checkIn.year, checkIn.month, checkIn.day);
    return stayDate.isAfter(arrival);
  }

  String? _stayProgressLabel(Reservation reservation) {
    if (!reservation.staysOn(stayDate)) return null;
    final checkIn = reservation.checkIn!;
    final checkOut = reservation.checkOut!;
    final arrival = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final departure = DateTime(checkOut.year, checkOut.month, checkOut.day);
    final currentNight = stayDate.difference(arrival).inDays + 1;
    final totalNights = departure.difference(arrival).inDays;
    if (totalNights <= 1) return null;
    if (currentNight == 1) {
      return '連泊開始（1泊目／全$totalNights泊）';
    }
    return '連泊中（$currentNight泊目／全$totalNights泊）';
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
  const _RequestedRoom({
    required this.roomTypeKey,
    required this.fallbackType,
    this.specifiedGuests,
  });

  final String? roomTypeKey;
  final GuestRoomType fallbackType;
  final int? specifiedGuests;
}

class _PlannedRoom {
  const _PlannedRoom({required this.roomNumber, required this.guestCount});

  final int roomNumber;
  final int guestCount;
}
