import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('StartupFailureApp', () {
    testWidgets('shows the message and the retry control in English', (tester) async {
      await tester.pumpWidget(StartupFailureApp(onRetry: () {}));

      expect(find.text("Can't open your saved records. Try again."), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try Again'), findsOneWidget);
    });

    testWidgets('shows the message and the retry control in Korean', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(StartupFailureApp(onRetry: () {}));

      expect(find.text('저장한 기록을 열지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '다시 시도하기'), findsOneWidget);
    });

    testWidgets('calls onRetry each time the retry control is pressed', (tester) async {
      var retries = 0;
      await tester.pumpWidget(StartupFailureApp(onRetry: () => retries++));

      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));

      expect(retries, 2);
    });
  });
}
