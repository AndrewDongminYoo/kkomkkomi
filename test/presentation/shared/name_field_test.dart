import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';
import 'package:kkomkkomi/presentation/shared/name_field.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group('NameField', () {
    const helper = '보고서 맨 위에 들어갈 이름이에요.';

    /// The paragraph that shows [text] under the [KeepAllText] or the [Text] that holds it.
    RenderParagraph paragraphOf(WidgetTester tester, String text) =>
        tester.renderObject(find.descendant(of: find.text(text), matching: find.byType(RichText)).first);

    /// Pumps a [NameField] with [entry] and [helper], over a reference field that gives the same messages to the
    /// decoration as strings, so that Flutter shows them with its own style.
    Future<void> pumpFields(WidgetTester tester, {required NameEntry entry, String? reference}) async {
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: [
              NameField(
                controller: TextEditingController(),
                label: '이름',
                entry: entry,
                onSubmitted: () {},
                helper: helper,
              ),
              TextField(
                decoration: InputDecoration(
                  helperText: entry == NameEntry.editing ? reference : null,
                  errorText: entry == NameEntry.editing ? null : reference,
                ),
              ),
            ],
          ),
        ),
        locale: const Locale('ko'),
      );
    }

    testWidgets('shows the helper with the joiners and the style of a helper text', (tester) async {
      await pumpFields(tester, entry: NameEntry.editing, reference: 'Reference');

      final shown = paragraphOf(tester, helper);
      expect(shown.text.toPlainText(), keepAll(helper));
      expect(shown.text.style, paragraphOf(tester, 'Reference').text.style);
    });

    testWidgets('shows the error with the joiners and the style of an error text', (tester) async {
      const error = '같은 이름의 구역이 있어요. 다른 이름을 입력해 주세요.';
      await pumpFields(tester, entry: NameEntry.duplicate, reference: 'Reference');

      final shown = paragraphOf(tester, error);
      expect(shown.text.toPlainText(), keepAll(error));
      expect(shown.text.style, paragraphOf(tester, 'Reference').text.style);
      expect(find.text(helper), findsNothing);
    });

    testWidgets('gives a screen reader the messages without the joiners', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFields(tester, entry: NameEntry.editing);

      expect(find.bySemanticsLabel(RegExp(helper)), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(wordJoiner)), findsNothing);
      semantics.dispose();
    });
  });
}
