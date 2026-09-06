import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamoo_app/main.dart';

void main() {
  testWidgets(
    'JamooManagerの本日の運営ダッシュボードが表示される',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const JamooManagerApp());

      expect(
        find.text('本日の運営ダッシュボード'),
        findsOneWidget,
      );
    },
  );
}
