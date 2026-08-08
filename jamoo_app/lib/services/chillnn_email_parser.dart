class ChillnnReservationEmail {
  const ChillnnReservationEmail({
    required this.type,
    required this.guestName,
    required this.guestKana,
    required this.phone,
    required this.email,
    required this.address,
    required this.reservationNumber,
    required this.checkIn,
    required this.checkOut,
    required this.planName,
    required this.planPriceYen,
    required this.reservationUrl,
    required this.rooms,
    required this.paymentMethod,
    required this.totalPriceYen,
    required this.rawBody,
  });

  final ChillnnEmailType type;
  final String guestName;
  final String? guestKana;
  final String? phone;
  final String? email;
  final String? address;
  final String reservationNumber;
  final DateTime checkIn;
  final DateTime checkOut;
  final String? planName;
  final int? planPriceYen;
  final String? reservationUrl;
  final List<ChillnnRoomDetail> rooms;
  final String? paymentMethod;
  final int? totalPriceYen;
  final String rawBody;

  int get nights => checkOut.difference(checkIn).inDays;

  int get adults {
    if (rooms.isEmpty) {
      return 0;
    }

    return rooms.first.adults;
  }

  int get children {
    if (rooms.isEmpty) {
      return 0;
    }

    return rooms.first.children;
  }
}

class ChillnnRoomDetail {
  const ChillnnRoomDetail({
    required this.stayDate,
    required this.roomName,
    required this.adults,
    required this.children,
    required this.priceYen,
  });

  final DateTime? stayDate;
  final String roomName;
  final int adults;
  final int children;
  final int? priceYen;
}

enum ChillnnEmailType { newReservation, changed, cancelled, unknown }

class ChillnnEmailParser {
  const ChillnnEmailParser();

  ChillnnReservationEmail parse({String? subject, required String body}) {
    final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .toList(growable: false);

    final guestName = _requiredValue(lines, 'ゲスト氏名：');
    final reservationNumber = _requiredValue(lines, '予約番号：');
    final checkIn = _requiredDate(lines, 'チェックイン日：');
    final checkOut = _requiredDate(lines, 'チェックアウト日：');

    final plan = _parsePlan(lines);
    final rooms = _parseRooms(lines);
    final combinedText = '${subject ?? ''}\n$normalized';

    return ChillnnReservationEmail(
      type: _emailType(combinedText),
      guestName: guestName,
      guestKana: _nullableValue(lines, 'ゲスト氏名（フリガナ）：'),
      phone: _nullableValue(lines, '電話番号：'),
      email: _nullableValue(lines, 'メールアドレス：'),
      address: _nullableValue(lines, '住所：'),
      reservationNumber: reservationNumber,
      checkIn: checkIn,
      checkOut: checkOut,
      planName: plan.name,
      planPriceYen: plan.priceYen,
      reservationUrl: _nullableValue(lines, '予約詳細URL：'),
      rooms: rooms,
      paymentMethod: _nullableValue(lines, '決済方法：'),
      totalPriceYen: _moneyValue(_nullableValue(lines, '決済金額：')),
      rawBody: normalized,
    );
  }

  ChillnnEmailType _emailType(String text) {
    if (text.contains('新規ご予約')) {
      return ChillnnEmailType.newReservation;
    }

    if (text.contains('キャンセル')) {
      return ChillnnEmailType.cancelled;
    }

    if (text.contains('変更')) {
      return ChillnnEmailType.changed;
    }

    return ChillnnEmailType.unknown;
  }

  _PlanResult _parsePlan(List<String> lines) {
    final line = lines.cast<String?>().firstWhere(
      (value) => value?.startsWith('適応プラン名：') ?? false,
      orElse: () => null,
    );

    if (line == null) {
      return const _PlanResult();
    }

    final value = line.substring('適応プラン名：'.length);
    final match = RegExp(r'^(.*?)(?:\s*-\s*[￥¥]([\d,]+))?$').firstMatch(value);

    if (match == null) {
      return _PlanResult(name: _clean(value));
    }

    return _PlanResult(
      name: _clean(match.group(1)),
      priceYen: _moneyValue(match.group(2)),
    );
  }

  List<ChillnnRoomDetail> _parseRooms(List<String> lines) {
    final results = <ChillnnRoomDetail>[];
    DateTime? stayDate;
    var inRoomSection = false;

    final datePattern = RegExp(r'^【(\d{4}/\d{2}/\d{2})】$');
    final roomPattern = RegExp(
      r'^(.+?)\s*-\s*（大人:\s*(\d+)人\s*,'
      r'\s*子供:\s*(\d+)人',
    );

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];

      if (line == 'お部屋詳細：') {
        inRoomSection = true;
        continue;
      }

      if (line == 'オプション詳細：') {
        break;
      }

      if (!inRoomSection) {
        continue;
      }

      final dateMatch = datePattern.firstMatch(line);

      if (dateMatch != null) {
        stayDate = _parseDate(dateMatch.group(1));
        continue;
      }

      final roomMatch = roomPattern.firstMatch(line);

      if (roomMatch == null) {
        continue;
      }

      int? priceYen;

      for (
        var priceIndex = index + 1;
        priceIndex < lines.length;
        priceIndex++
      ) {
        final priceLine = lines[priceIndex];

        if (priceLine.isEmpty) {
          continue;
        }

        if (priceLine.startsWith('￥') || priceLine.startsWith('¥')) {
          priceYen = _moneyValue(priceLine);
        }

        break;
      }

      results.add(
        ChillnnRoomDetail(
          stayDate: stayDate,
          roomName: roomMatch.group(1)!.trim(),
          adults: int.tryParse(roomMatch.group(2)!) ?? 0,
          children: int.tryParse(roomMatch.group(3)!) ?? 0,
          priceYen: priceYen,
        ),
      );
    }

    return List.unmodifiable(results);
  }

  String _requiredValue(List<String> lines, String label) {
    final value = _nullableValue(lines, label);

    if (value == null) {
      throw ChillnnEmailParseException('$label の値を確認できません。');
    }

    return value;
  }

  DateTime _requiredDate(List<String> lines, String label) {
    final value = _requiredValue(lines, label);
    final date = _parseDate(value);

    if (date == null) {
      throw ChillnnEmailParseException('$label の日付形式が正しくありません。');
    }

    return date;
  }

  String? _nullableValue(List<String> lines, String label) {
    for (final line in lines) {
      final labelIndex = line.indexOf(label);

      if (labelIndex < 0) {
        continue;
      }

      final value = _clean(line.substring(labelIndex + label.length));

      if (value == null || value == '未記入') {
        return null;
      }

      return value;
    }

    return null;
  }

  DateTime? _parseDate(String? value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.trim().replaceAll('/', '-'));
  }

  static int? _moneyValue(String? value) {
    if (value == null) {
      return null;
    }

    final digits = value.replaceAll(RegExp(r'[^0-9-]'), '');

    return int.tryParse(digits);
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }
}

class _PlanResult {
  const _PlanResult({this.name, this.priceYen});

  final String? name;
  final int? priceYen;
}

class ChillnnEmailParseException implements Exception {
  const ChillnnEmailParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
