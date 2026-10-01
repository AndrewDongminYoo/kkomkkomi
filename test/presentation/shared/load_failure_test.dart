import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group('LoadFailure', () {
    testWidgets('shows the message and calls onRetry each time the retry control is pressed', (tester) async {
      var retries = 0;
      await tester.pumpApp(
        Scaffold(
          body: LoadFailure(message: "Can't load your clients. Try again.", onRetry: () => retries++),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));

      expect(find.text("Can't load your clients. Try again."), findsOneWidget);
      expect(retries, 2);
    });

    testWidgets('fits a screen 320 pixels wide at the largest text size in Korean', (tester) async {
      tester.useNarrowScreenWithLargestText();

      await tester.pumpApp(
        Scaffold(
          body: LoadFailure(message: '거래처 목록을 불러오지 못했어요. 다시 시도해 주세요.', onRetry: () {}),
        ),
        locale: const Locale('ko'),
      );

      tester
        ..expectWholeText('거래처 목록을 불러오지 못했어요. 다시 시도해 주세요.')
        ..expectWholeText('다시 불러오기');
    });
  });
}
