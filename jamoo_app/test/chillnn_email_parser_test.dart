import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/services/chillnn_email_parser.dart';

void main() {
  test('CHILLNN新規予約メールを解析できる', () {
    const body = '''
Vegetarian House Jamoo(菜食の宿ジャムー）

CHILLNNから新規ご予約【Sample Guest様(2026/08/11〜2026/08/12)】のお知らせです。

ゲスト氏名：Sample Guest
ゲスト氏名（フリガナ）：未記入
電話番号：09000000000
メールアドレス：sample@example.com
住所：東京都サンプル区

予約番号：TEST123456
チェックイン日：2026/08/11
チェックアウト日：2026/08/12
適応プラン名：ヴィーガンガレットの朝食付プラン - ￥2,200
予約詳細URL：https://admin.chillnn.com/example

お部屋詳細：
【2026/08/11】
スタンダードツインルーム - （大人: 1人 , 子供: 0人, )
￥9,500

オプション詳細：
なし

決済方法：クレジットカード事前決済
決済金額：￥11,700（税サ込）
''';

    final result = const ChillnnEmailParser().parse(body: body);

    expect(result.type, ChillnnEmailType.newReservation);
    expect(result.guestName, 'Sample Guest');
    expect(result.guestKana, isNull);
    expect(result.reservationNumber, 'TEST123456');
    expect(result.checkIn, DateTime(2026, 8, 11));
    expect(result.checkOut, DateTime(2026, 8, 12));
    expect(result.nights, 1);
    expect(result.planPriceYen, 2200);
    expect(result.totalPriceYen, 11700);
    expect(result.rooms, hasLength(1));
    expect(result.rooms.first.roomName, 'スタンダードツインルーム');
    expect(result.rooms.first.adults, 1);
    expect(result.rooms.first.children, 0);
    expect(result.rooms.first.priceYen, 9500);
  });
}
