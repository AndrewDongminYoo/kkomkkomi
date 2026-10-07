// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';

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

    testWidgets('serves the theme of the app', (tester) async {
      await tester.pumpApp(const SizedBox());

      final theme = Theme.of(tester.element(find.byType(SizedBox)));
      expect(theme.colorScheme, appTheme().colorScheme);
      expect(theme.appBarTheme, appTheme().appBarTheme);
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

    testWidgets('provides an identity that is unavailable unless it is given another', (tester) async {
      await tester.pumpApp(const SizedBox(), repositories: mockRepositories());

      final identity = tester.element(find.byType(SizedBox)).read<Identity>();
      expect(identity, isA<FakeIdentity>());
      expect(await identity.currentUserId(), isNull);
    });

    testWidgets('provides the identity that it is given', (tester) async {
      final identity = FakeIdentity(userId: 'user-1');

      await tester.pumpApp(const SizedBox(), repositories: mockRepositories(), identity: identity);

      expect(tester.element(find.byType(SizedBox)).read<Identity>(), same(identity));
    });

    testWidgets('provides entitlements of the Free plan unless it is given others', (tester) async {
      await tester.pumpApp(const SizedBox(), repositories: mockRepositories());

      final entitlements = tester.element(find.byType(SizedBox)).read<Entitlements>();
      expect(entitlements, isA<FakeEntitlements>());
      expect(await entitlements.currentPlan(), Plan.free);
    });

    testWidgets('provides the entitlements that it is given', (tester) async {
      final entitlements = FakeEntitlements(plan: Plan.pro);

      await tester.pumpApp(const SizedBox(), repositories: mockRepositories(), entitlements: entitlements);

      expect(tester.element(find.byType(SizedBox)).read<Entitlements>(), same(entitlements));
    });

    testWidgets('provides a fake camera and a fake photo store unless it is given others', (tester) async {
      await tester.pumpApp(const SizedBox(), repositories: mockRepositories());

      final context = tester.element(find.byType(SizedBox));
      expect(context.read<PhotoCapture>(), isA<FakePhotoCapture>());
      expect(context.read<PhotoStore>(), isA<FakePhotoStore>());
    });

    testWidgets('provides the camera and the photo store that it is given', (tester) async {
      final photoCapture = FakePhotoCapture();
      final photoStore = FakePhotoStore();

      await tester.pumpApp(
        const SizedBox(),
        repositories: mockRepositories(),
        photoCapture: photoCapture,
        photoStore: photoStore,
      );

      final context = tester.element(find.byType(SizedBox));
      expect(context.read<PhotoCapture>(), same(photoCapture));
      expect(context.read<PhotoStore>(), same(photoStore));
    });

    testWidgets('provides the font file of the source tree and a fake share sheet unless it is given others', (
      tester,
    ) async {
      await tester.pumpApp(const SizedBox(), repositories: mockRepositories());

      final context = tester.element(find.byType(SizedBox));
      expect(context.read<ReportFont>(), isA<FileReportFont>());
      expect(context.read<ReportShare>(), isA<FakeReportShare>());
    });

    testWidgets('provides the report font and the share sheet that it is given', (tester) async {
      const reportFont = FailingReportFont();
      final reportShare = FakeReportShare();

      await tester.pumpApp(
        const SizedBox(),
        repositories: mockRepositories(),
        reportFont: reportFont,
        reportShare: reportShare,
      );

      final context = tester.element(find.byType(SizedBox));
      expect(context.read<ReportFont>(), same(reportFont));
      expect(context.read<ReportShare>(), same(reportShare));
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
