// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

import '../../helpers/helpers.dart';

void main() {
  group('NameDialog', () {
    Future<List<String>> pumpDialog(
      WidgetTester tester, {
      NameEntry entry = NameEntry.editing,
      String initialName = '',
    }) async {
      final submitted = <String>[];
      await tester.pumpApp(
        NameDialog(
          title: 'Add Zone',
          fieldLabel: 'Zone name',
          submitLabel: 'Add',
          initialName: initialName,
          entry: entry,
          onSubmit: submitted.add,
        ),
      );
      return submitted;
    }

    testWidgets('shows the title, the field with its label and the initial name, and both buttons', (tester) async {
      await pumpDialog(tester, initialName: 'Lobby');

      expect(find.text('Add Zone'), findsOneWidget);
      expect(find.text('Zone name'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Lobby');
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    });

    testWidgets('submits the text of the field from the button and from the keyboard', (tester) async {
      final submitted = await pumpDialog(tester);

      await tester.enterText(find.byType(TextField), 'Lobby');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.enterText(find.byType(TextField), 'Hall');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(submitted, ['Lobby', 'Hall']);
    });

    testWidgets('takes no name from the button or the keyboard while a name is on its way to storage', (tester) async {
      final submitted = await pumpDialog(tester, entry: NameEntry.saving, initialName: 'Lobby');

      await tester.enterText(find.byType(TextField), 'Hall');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'), warnIfMissed: false);
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(submitted, isEmpty);
      // The field keeps the name that is on its way, so the saved name is the name on the screen.
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Lobby');
    });

    for (final (entry, message) in [
      (NameEntry.empty, 'Enter a name.'),
      (NameEntry.duplicate, 'Another zone has this name. Enter a different name.'),
      (NameEntry.failed, "Can't save right now. Try again."),
    ]) {
      testWidgets('shows the problem of the ${entry.name} entry under the field', (tester) async {
        await pumpDialog(tester, entry: entry);

        expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage, message);
        expect(find.text(message), findsOneWidget);
      });
    }

    for (final entry in [NameEntry.editing, NameEntry.saving, NameEntry.saved]) {
      testWidgets('shows no problem for the ${entry.name} entry', (tester) async {
        await pumpDialog(tester, entry: entry);

        expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage, isNull);
      });
    }
  });

  group('showNameDialog', () {
    Future<(NameEntryCubit, List<String>)> openDialog(WidgetTester tester) async {
      final cubit = NameEntryCubit();
      addTearDown(cubit.close);
      final submitted = <String>[];
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNameDialog<NameEntryCubit, NameEntry>(
              context: context,
              cubit: cubit,
              entryOf: (state) => state,
              title: 'Rename Zone',
              fieldLabel: 'Zone name',
              submitLabel: 'Save',
              initialName: 'Lobby',
              onSubmit: submitted.add,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (cubit, submitted);
    }

    testWidgets('shows a dialog that submits the name and follows the entry of the cubit', (tester) async {
      final (cubit, submitted) = await openDialog(tester);

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Lobby');
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      cubit.become(NameEntry.empty);
      await tester.pumpAndSettle();

      expect(submitted, ['']);
      expect(find.byType(NameDialog), findsOneWidget);
      expect(find.text('Enter a name.'), findsOneWidget);
    });

    testWidgets('closes the dialog when the name is saved', (tester) async {
      final (cubit, _) = await openDialog(tester);

      cubit.become(NameEntry.saving);
      await tester.pumpAndSettle();
      expect(find.byType(NameDialog), findsOneWidget);

      cubit.become(NameEntry.saved);
      await tester.pumpAndSettle();
      expect(find.byType(NameDialog), findsNothing);
    });

    testWidgets('stays open while a name is on its way to storage, and closes only itself when it is saved', (
      tester,
    ) async {
      final (cubit, _) = await openDialog(tester);

      cubit.become(NameEntry.saving);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel')).onPressed, isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(NameDialog), findsOneWidget);

      cubit.become(NameEntry.saved);
      await tester.pumpAndSettle();

      expect(find.byType(NameDialog), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('closes from the back press and from a tap outside it while no name is on its way', (tester) async {
      final (cubit, _) = await openDialog(tester);

      cubit.become(NameEntry.empty);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(NameDialog), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('closes the dialog from its cancel button and changes nothing', (tester) async {
      final (cubit, submitted) = await openDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(NameDialog), findsNothing);
      expect(submitted, isEmpty);
      expect(cubit.state, NameEntry.editing);
    });

    testWidgets('fits a screen 320 pixels wide at the largest text size, with a problem under the field', (
      tester,
    ) async {
      tester.useNarrowScreenWithLargestText();
      final (cubit, _) = await openDialog(tester);

      cubit.become(NameEntry.duplicate);
      await tester.pumpAndSettle();

      tester
        ..expectWholeText('Rename Zone')
        ..expectWholeText('Zone name')
        ..expectWholeText('Another zone has this name. Enter a different name.')
        ..expectWholeText('Cancel')
        ..expectWholeText('Save');
    });
  });
}
