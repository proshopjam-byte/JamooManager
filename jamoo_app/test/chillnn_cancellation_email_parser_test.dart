import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/services/chillnn_email_parser.dart';

void main() {
  test('CHILLNNキャンセルメールを解析できる', () {
    const body = '''
Vegetarian House Jamoo(菜食の宿ジャムー）

CHILLNNからご予約内容のキャンセルのお知らせです。

ゲスト氏名：Sample Cancel Guest
ゲスト氏名（フリガナ）：サンプル
電話番号：09000000000
メールアドレス：cancel@example.com
住所：東京都サンプル区

予約番号：CANCEL1234
チェックイン日：2026/08/28
チェックアウト日：2026/08/29
適応プラン名：なし
変更前のプラン名：シンプルに素泊りプラン - 基本料金なし
予約詳細URL：https://admin.chillnn.com/example

お部屋詳細：

変更前のお部屋詳細：
【2026/08/28】
ロフト付き4名部屋 - （大人: 1人 , 子供: 0人, )
￥27,000

オプション詳細：
なし

決済方法：クレジットカード事前決済
決済金額：￥0（税サ込）
''';

    final result = const ChillnnEmailParser().parse(
      subject: 'ご予約内容のキャンセル',
      body: body,
    );

    expect(result.type, ChillnnEmailType.cancelled);
    expect(result.reservationNumber, 'CANCEL1234');
    expect(result.checkIn, DateTime(2026, 8, 28));
    expect(result.checkOut, DateTime(2026, 8, 29));
    expect(result.totalPriceYen, 0);
    expect(result.rooms, hasLength(1));
    expect(result.rooms.first.roomName, 'ロフト付き4名部屋');
    expect(result.rooms.first.adults, 1);
    expect(result.rooms.first.children, 0);
    expect(result.rooms.first.priceYen, 27000);
  });
}
