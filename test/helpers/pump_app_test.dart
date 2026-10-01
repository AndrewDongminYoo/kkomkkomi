import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  group('pumpApp', () {
    testWidgets('serves the Material widgets and the app strings under the Korean locale', (tester) async {
      await tester.pumpApp(
        Scaffold(appBar: AppBar(leading: const BackButton())),
        locale: const Locale('ko'),
      );

      final context = tester.element(find.byType(BackButton));
      expect(Localizations.localeOf(context).languageCode, 'ko');
      expect(MaterialLocalizations.of(context).backButtonTooltip, '뒤로');
      expect(context.l10n.startupFailureRetryButton, '다시 시도하기');
    });

    testWidgets('shows the English strings when no locale is given', (tester) async {
      await tester.pumpApp(Scaffold(appBar: AppBar(leading: const BackButton())));

      final context = tester.element(find.byType(BackButton));
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Back');
      expect(context.l10n.startupFailureRetryButton, 'Try Again');
    });

    testWidgets('provides the repositories, an identifier generator, and a clock when repositories are given', (
      tester,
    ) async {
      final repositories = mockRepositories();
      final clock = FixedClock(DateTime.utc(2026, 10, 1, 9));

      await tester.pumpApp(const SizedBox(), repositories: repositories, clock: clock);

      final context = tester.element(find.byType(SizedBox));
      expect(context.read<ClientRepository>(), same(repositories.clients));
      expect(context.read<VisitRepository>(), same(repositories.visits));
      expect(context.read<CompanyProfileRepository>(), same(repositories.companyProfile));
      expect(context.read<IdGenerator>().newId(), 'id-1');
      expect(context.read<Clock>(), same(clock));
    });
  });

  group('useNarrowScreenWithLargestText', () {
    testWidgets('makes the screen 320 pixels wide and the text as large as the largest system size', (tester) async {
      tester.useNarrowScreenWithLargestText();

      await tester.pumpApp(const SizedBox());

      final media = MediaQuery.of(tester.element(find.byType(SizedBox)));
      expect(media.size.width, 320);
      expect(media.textScaler.scale(17), moreOrLessEquals(53));
    });

    testWidgets('makes a layout that is wider than the screen fail', (tester) async {
      tester.useNarrowScreenWithLargestText();

      await tester.pumpApp(const Row(children: [SizedBox(width: 321, height: 10)]));

      expect(tester.takeException(), isFlutterError.having((error) => '$error', 'message', contains('overflowed')));
    });

    testWidgets('lets a test tell whole text from text that the framework cuts without an overflow error', (
      tester,
    ) async {
      tester.useNarrowScreenWithLargestText();

      await tester.pumpApp(
        const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                Text('whole text that wraps over more than one line'),
                Text('cut text that ends in an ellipsis', overflow: TextOverflow.ellipsis, maxLines: 1),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      tester.expectWholeText('whole text that wraps over more than one line');
      expect(
        () => tester.expectWholeText('cut text that ends in an ellipsis'),
        throwsA(isA<TestFailure>()),
      );
      expect(() => tester.expectWholeText('text that is not there'), throwsA(isA<TestFailure>()));
    });

    testWidgets('makes text that cannot wrap fail at the largest text size, although it fits at the default size', (
      tester,
    ) async {
      const row = Row(children: [Text('0123456789', softWrap: false)]);
      await tester.pumpApp(row);
      expect(tester.takeException(), isNull);

      tester.useNarrowScreenWithLargestText();
      await tester.pumpApp(row);

      expect(tester.takeException(), isFlutterError.having((error) => '$error', 'message', contains('overflowed')));
    });
  });
}
