import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group('showConfirmDialog', () {
    Future<List<bool>> openDialog(WidgetTester tester, {bool? isDestructive}) async {
      final answers = <bool>[];
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              isDestructive == null
                  ? await showConfirmDialog(
                      context: context,
                      title: 'Remove Lobby?',
                      message: 'Past visits keep their records of it.',
                      confirmLabel: 'Remove',
                    )
                  : await showConfirmDialog(
                      context: context,
                      title: 'Remove Lobby?',
                      message: 'Past visits keep their records of it.',
                      confirmLabel: 'Remove',
                      isDestructive: isDestructive,
                    ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return answers;
    }

    testWidgets('asks the question with the message under it', (tester) async {
      await openDialog(tester);

      expect(find.text('Remove Lobby?'), findsOneWidget);
      expect(find.text('Past visits keep their records of it.'), findsOneWidget);
    });

    testWidgets('shows the details under the message', (tester) async {
      final answers = <bool>[];
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showConfirmDialog(
                context: context,
                title: 'Remove Lobby?',
                message: 'Past visits keep their records of it.',
                confirmLabel: 'Remove',
                details: const Text('Its photos stay on the phone.'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final message = tester.getRect(find.text('Past visits keep their records of it.'));
      final details = tester.getRect(find.text('Its photos stay on the phone.'));
      expect(details.top, greaterThan(message.bottom));
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('completes with true when the confirm button is pressed', (tester) async {
      final answers = await openDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(answers, [true]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('gives the confirm button the primary colors unless the action is destructive', (tester) async {
      await openDialog(tester);

      final colors = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
      expect(tester.filledButtonColor('Remove'), colors.primary);
      final label = tester.widget<RichText>(
        find.descendant(of: find.widgetWithText(FilledButton, 'Remove'), matching: find.byType(RichText)),
      );
      expect(label.text.style?.color, colors.onPrimary);
    });

    testWidgets('gives the confirm button the primary colors when the action is said not to be destructive', (
      tester,
    ) async {
      await openDialog(tester, isDestructive: false);

      final colors = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
      expect(tester.filledButtonColor('Remove'), colors.primary);
    });

    testWidgets('gives the confirm button the error colors and keeps the cancel button for a destructive action', (
      tester,
    ) async {
      final answers = await openDialog(tester, isDestructive: true);

      final colors = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
      expect(tester.filledButtonColor('Remove'), colors.error);
      final label = tester.widget<RichText>(
        find.descendant(of: find.widgetWithText(FilledButton, 'Remove'), matching: find.byType(RichText)),
      );
      expect(label.text.style?.color, colors.onError);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('keeps the Korean dismiss label for a destructive action', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showConfirmDialog(
              context: context,
              title: '로비 구역을 삭제할까요?',
              message: '지난 방문 기록에는 그대로 남아요.',
              confirmLabel: '삭제하기',
              isDestructive: true,
            ),
            child: const Text('open'),
          ),
        ),
        locale: const Locale('ko'),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, '닫기'), findsOneWidget);
    });

    testWidgets('completes with false when the cancel button is pressed', (tester) async {
      final answers = await openDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });

    testWidgets('completes with false when the dialog is closed by a tap outside it', (tester) async {
      final answers = await openDialog(tester);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });

    testWidgets('fits a screen 320 pixels wide at the largest text size', (tester) async {
      tester.useNarrowScreenWithLargestText();

      await openDialog(tester);

      tester
        ..expectWholeText('Remove Lobby?')
        ..expectWholeText('Past visits keep their records of it.')
        ..expectWholeText('Cancel')
        ..expectWholeText('Remove');
    });
  });
}
