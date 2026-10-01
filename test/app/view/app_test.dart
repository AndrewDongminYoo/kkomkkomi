import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group('App', () {
    testWidgets('shows the client list as the home screen', (tester) async {
      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClientListPage), findsOneWidget);
      expect(Navigator.of(tester.element(find.byType(ClientListPage))).canPop(), isFalse);
      expect(find.widgetWithText(AppBar, 'Clients'), findsOneWidget);
    });

    testWidgets('provides each repository to the widgets below it', (tester) async {
      final repositories = mockRepositories();

      await tester.pumpWidget(
        App(repositories: repositories, identity: FakeIdentity(), publishQueue: publishQueueOf(repositories)),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<ClientRepository>(), same(repositories.clients));
      expect(context.read<VisitRepository>(), same(repositories.visits));
      expect(context.read<CompanyProfileRepository>(), same(repositories.companyProfile));
    });

    testWidgets('provides the identity that it is given', (tester) async {
      final identity = FakeIdentity(userId: 'user-1');

      await tester.pumpWidget(
        App(repositories: mockRepositories(), identity: identity, publishQueue: publishQueueOf(mockRepositories())),
      );

      expect(tester.element(find.byType(ClientListPage)).read<Identity>(), same(identity));
    });

    testWidgets('provides the random identifiers and the device time unless it is given others', (tester) async {
      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<IdGenerator>(), isA<RandomIdGenerator>());
      expect(context.read<Clock>(), isA<SystemClock>());
    });

    testWidgets('provides the identifier generator and the clock that it is given', (tester) async {
      final idGenerator = SequenceIdGenerator();
      final clock = FixedClock(DateTime.utc(2026, 10));

      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(mockRepositories()),
          idGenerator: idGenerator,
          clock: clock,
        ),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<IdGenerator>(), same(idGenerator));
      expect(context.read<Clock>(), same(clock));
    });

    testWidgets('provides the camera of the picker and the photo store of the documents directory unless it is '
        'given others', (tester) async {
      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<PhotoCapture>(), isA<ImagePickerPhotoCapture>());
      expect(context.read<PhotoStore>(), isA<DocumentsPhotoStore>());
    });

    testWidgets(
      'provides the font of the assets and the share sheets of the plugins unless it is given others',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          App(
            repositories: mockRepositories(),
            identity: FakeIdentity(),
            publishQueue: publishQueueOf(mockRepositories()),
          ),
        );

        final context = tester.element(find.byType(ClientListPage));
        expect(context.read<ReportFont>(), isA<AssetReportFont>());
        expect(context.read<ReportShare>(), isA<PrintingReportShare>());
        expect(context.read<LinkShare>(), isA<SharePlusLinkShare>());
      },
    );

    testWidgets('provides the report font and the share sheets that it is given', (tester) async {
      final repositories = mockRepositories();
      const reportFont = FileReportFont();
      final reportShare = FakeReportShare();
      final linkShare = FakeLinkShare();

      await tester.pumpWidget(
        App(
          repositories: repositories,
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(repositories),
          reportFont: reportFont,
          reportShare: reportShare,
          linkShare: linkShare,
        ),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<ReportFont>(), same(reportFont));
      expect(context.read<ReportShare>(), same(reportShare));
      expect(context.read<LinkShare>(), same(linkShare));
    });

    testWidgets('provides the publish queue that it is given', (tester) async {
      final repositories = mockRepositories();
      final publishQueue = publishQueueOf(repositories);

      await tester.pumpWidget(App(repositories: repositories, identity: FakeIdentity(), publishQueue: publishQueue));

      expect(tester.element(find.byType(ClientListPage)).read<PublishQueue>(), same(publishQueue));
    });

    testWidgets('provides the camera and the photo store that it is given', (tester) async {
      final repositories = mockRepositories();
      final photoCapture = FakePhotoCapture();
      final photoStore = FakePhotoStore();

      await tester.pumpWidget(
        App(
          repositories: repositories,
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(repositories),
          photoCapture: photoCapture,
          photoStore: photoStore,
        ),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<PhotoCapture>(), same(photoCapture));
      expect(context.read<PhotoStore>(), same(photoStore));
    });

    testWidgets('shows the home screen and the Material widgets in Korean under the Korean locale', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '거래처'), findsOneWidget);
      expect(MaterialLocalizations.of(tester.element(find.byType(ClientListPage))).backButtonTooltip, '뒤로');
    });
  });
}
