import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group('showConfirmDialog', () {
    Future<List<bool>> openDialog(WidgetTester tester) async {
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

    testWidgets('completes with true when the confirm button is pressed', (tester) async {
      final answers = await openDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(answers, [true]);
      expect(find.byType(AlertDialog), findsNothing);
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
