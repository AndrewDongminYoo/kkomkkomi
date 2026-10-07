// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/shared/notice.dart';

import '../../helpers/helpers.dart';

void main() {
  group('Notice', () {
    Future<void> pumpNotice(WidgetTester tester, {NoticeTone? tone}) => tester.pumpApp(
      Scaffold(
        body: SingleChildScrollView(
          child: tone == null
              ? Notice(
                  children: [
                    const Text('Uploading the report.'),
                    TextButton(onPressed: () {}, child: const Text('Act')),
                  ],
                )
              : Notice(
                  tone: tone,
                  children: [
                    const Text('Uploading the report.'),
                    TextButton(onPressed: () {}, child: const Text('Act')),
                  ],
                ),
        ),
      ),
    );

    BoxDecoration decorationOf(WidgetTester tester) =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(of: find.byType(Notice), matching: find.byType(DecoratedBox)).first,
                )
                .decoration
            as BoxDecoration;

    Color? textColorOf(WidgetTester tester, String text) => tester
        .widget<RichText>(find.descendant(of: find.text(text), matching: find.byType(RichText)))
        .text
        .style
        ?.color;

    testWidgets('tells a fact in the info tone unless it is given another', (tester) async {
      await pumpNotice(tester);

      final colors = Theme.of(tester.element(find.byType(Notice))).colorScheme;
      expect(decorationOf(tester).color, colors.surfaceContainerHighest);
      expect(decorationOf(tester).borderRadius, BorderRadius.circular(10));
      expect(textColorOf(tester, 'Uploading the report.'), colors.onSurface);
      expect(textColorOf(tester, 'Act'), colors.onSurface);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('tells a failure in the error tone, with an icon of its own', (tester) async {
      await pumpNotice(tester, tone: NoticeTone.error);

      final colors = Theme.of(tester.element(find.byType(Notice))).colorScheme;
      expect(decorationOf(tester).color, colors.errorContainer);
      expect(textColorOf(tester, 'Uploading the report.'), colors.onErrorContainer);
      expect(textColorOf(tester, 'Act'), colors.onErrorContainer);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });

    testWidgets('keeps the shape of the text buttons of the theme', (tester) async {
      await pumpNotice(tester, tone: NoticeTone.error);

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(TextButton), matching: find.byType(Material)),
      );
      expect(material.shape, const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))));
    });

    testWidgets('fits a screen 320 pixels wide at the largest text size', (tester) async {
      tester.useNarrowScreenWithLargestText();

      await pumpNotice(tester, tone: NoticeTone.error);

      expect(tester.takeException(), isNull);
      tester
        ..expectWholeText('Uploading the report.')
        ..expectWholeText('Act');
    });
  });
}
