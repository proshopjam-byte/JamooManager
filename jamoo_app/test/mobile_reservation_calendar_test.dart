import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/services/inventory_mobile_page.dart';

void main() {
  test('iPhone端末画面に予約カレンダーと日付詳細を表示する', () {
    expect(inventoryMobilePageHtml, contains('予約カレンダー'));
    expect(inventoryMobilePageHtml, contains('calendarView'));
    expect(inventoryMobilePageHtml, contains('calendar-grid'));
    expect(inventoryMobilePageHtml, contains('selectedDateReservations'));
    expect(inventoryMobilePageHtml, contains('/api/v1/reservations/calendar'));
    expect(inventoryMobilePageHtml, contains('チェックイン'));
    expect(inventoryMobilePageHtml, contains('チェックアウト'));
    expect(inventoryMobilePageHtml, contains('連泊中'));
  });
}
