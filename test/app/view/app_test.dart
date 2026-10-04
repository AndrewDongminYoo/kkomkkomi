import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
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
          entitlements: FakeEntitlements(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClientListPage), findsOneWidget);
      expect(Navigator.of(tester.element(find.byType(ClientListPage))).canPop(), isFalse);
      expect(find.widgetWithText(AppBar, 'Clients'), findsOneWidget);
    });

    testWidgets('gives the screens the theme of the app, with the app bar on the surface color', (tester) async {
      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );
      await tester.pumpAndSettle();

      final expected = appTheme();
      final theme = Theme.of(tester.element(find.byType(ClientListPage)));
      expect(theme.colorScheme, expected.colorScheme);
      expect(theme.appBarTheme, expected.appBarTheme);
      final appBar = tester.widget<Material>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first,
      );
      expect(appBar.color, expected.colorScheme.surface);
    });

    testWidgets('provides each repository to the widgets below it', (tester) async {
      final repositories = mockRepositories();

      await tester.pumpWidget(
        App(
          repositories: repositories,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publishQueue: publishQueueOf(repositories),
        ),
      );

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<ClientRepository>(), same(repositories.clients));
      expect(context.read<VisitRepository>(), same(repositories.visits));
      expect(context.read<CompanyProfileRepository>(), same(repositories.companyProfile));
    });

    testWidgets('provides the identity that it is given', (tester) async {
      final identity = FakeIdentity(userId: 'user-1');

      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: identity,
          entitlements: FakeEntitlements(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );

      expect(tester.element(find.byType(ClientListPage)).read<Identity>(), same(identity));
    });

    testWidgets('provides the entitlements that it is given and does not ask them for the plan', (tester) async {
      final entitlements = FakeEntitlements(plan: Plan.basic);

      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          entitlements: entitlements,
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.element(find.byType(ClientListPage)).read<Entitlements>(), same(entitlements));
      expect(entitlements.calls, 0);
    });

    testWidgets('provides the random identifiers and the device time unless it is given others', (tester) async {
      await tester.pumpWidget(
        App(
          repositories: mockRepositories(),
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
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
          entitlements: FakeEntitlements(),
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
          entitlements: FakeEntitlements(),
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
            entitlements: FakeEntitlements(),
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
          entitlements: FakeEntitlements(),
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

      await tester.pumpWidget(
        App(
          repositories: repositories,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publishQueue: publishQueue,
        ),
      );

      expect(tester.element(find.byType(ClientListPage)).read<PublishQueue>(), same(publishQueue));
    });

    testWidgets('provides one deletion of all data over its stores, for the life of the app', (tester) async {
      final repositories = mockRepositories();
      final publishQueue = publishQueueOf(repositories);
      final photoStore = FakePhotoStore();
      final localData = repositories.localData as FakeLocalDataRepository;
      final app = App(
        repositories: repositories,
        identity: FakeIdentity(),
        entitlements: FakeEntitlements(),
        publishQueue: publishQueue,
        photoStore: photoStore,
      );

      await tester.pumpWidget(app);
      final deletion = tester.element(find.byType(ClientListPage)).read<DeleteAllData>();
      await tester.pumpWidget(app);
      expect(tester.element(find.byType(ClientListPage)).read<DeleteAllData>(), same(deletion));

      // The queue of the app has no backend, so the deletion reaches the stores of the device only.
      await tester.runAsync(deletion.call);
      expect(localData.erasures, 1);
      expect(photoStore.deletionsOfAll, 1);
    });

    testWidgets('provides the camera and the photo store that it is given', (tester) async {
      final repositories = mockRepositories();
      final photoCapture = FakePhotoCapture();
      final photoStore = FakePhotoStore();

      await tester.pumpWidget(
        App(
          repositories: repositories,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
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
          entitlements: FakeEntitlements(),
          publishQueue: publishQueueOf(mockRepositories()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '거래처'), findsOneWidget);
      expect(MaterialLocalizations.of(tester.element(find.byType(ClientListPage))).backButtonTooltip, '뒤로');
    });

    testWidgets('provides the store of the open capture', (tester) async {
      final repositories = mockRepositories();

      await tester.pumpWidget(
        App(
          repositories: repositories,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publishQueue: publishQueueOf(repositories),
        ),
      );

      expect(
        tester.element(find.byType(ClientListPage)).read<OpenCaptureRepository>(),
        same(repositories.openCaptures),
      );
    });

    group('with a recovery of a lost capture', () {
      final visit = Visit(
        id: 'visit-1',
        clientId: 'client-1',
        visitDate: VisitDate(2026, 10, 2),
        createdAt: DateTime.utc(2026, 10, 2, 1),
        zoneRecords: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비')],
      );
      final client = Client(id: 'client-1', name: '한빛빌딩', createdAt: DateTime.utc(2026, 9, 2));

      Future<void> pumpWithRecovery(WidgetTester tester, LostCaptureRecovery recovery) async {
        final mocks = mockRepositories();
        final repositories = Repositories(
          clients: FakeClientRepository(clients: [client]),
          visits: FakeVisitRepository(visits: [visit]),
          companyProfile: mocks.companyProfile,
          publishing: mocks.publishing,
          openCaptures: FakeOpenCaptureRepository(),
          localData: FakeLocalDataRepository(),
        );
        await tester.pumpWidget(
          App(
            repositories: repositories,
            identity: FakeIdentity(),
            entitlements: FakeEntitlements(),
            publishQueue: publishQueueOf(repositories),
            recovery: recovery,
            photoCapture: FakePhotoCapture(),
            photoStore: FakePhotoStore(),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('opens the visit of the capture over the client list and says that it holds the photo', (
        tester,
      ) async {
        const recovery = LostCaptureRecovery(visitId: 'visit-1');

        await pumpWithRecovery(tester, recovery);

        expect(tester.widget<VisitCapturePage>(find.byType(VisitCapturePage)).visitId, 'visit-1');
        expect(tester.widget<VisitCapturePage>(find.byType(VisitCapturePage)).recovery, same(recovery));
        // No client detail screen is under the visit, so the title is what tells which client the photo went to.
        expect(find.descendant(of: find.byType(AppBar), matching: find.text('한빛빌딩')), findsOneWidget);
        expect(find.descendant(of: find.byType(AppBar), matching: find.text('October 2, 2026')), findsOneWidget);
        expect(
          find.text('The app restarted while the camera was open. The photo you took is in this visit.'),
          findsOneWidget,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(VisitCapturePage), findsNothing);
        expect(find.byType(ClientListPage), findsOneWidget);
        expect(Navigator.of(tester.element(find.byType(ClientListPage))).canPop(), isFalse);
      });

      testWidgets('opens the visit of the capture and asks for the photo again when it did not reach the visit', (
        tester,
      ) async {
        await pumpWithRecovery(tester, LostCaptureRecovery(visitId: 'visit-1', failure: Exception('disk full')));

        expect(find.byType(VisitCapturePage), findsOneWidget);
        expect(
          find.text(
            "The app restarted while the camera was open, and the photo you took couldn't be added. Take it again.",
          ),
          findsOneWidget,
        );
      });
    });
  });
}
