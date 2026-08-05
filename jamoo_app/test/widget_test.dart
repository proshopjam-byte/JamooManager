import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/main.dart';

void main() {
  testWidgets(
    'JamooManagerの本日のチェックイン画面が表示される',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JamooManagerApp());

      expect(
        find.text('本日のチェックイン'),
        findsOneWidget,
      );
    },
  );
}
