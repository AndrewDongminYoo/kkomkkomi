// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';

import '../../../helpers/helpers.dart';

class _MockClientListCubit extends MockCubit<ClientListState> implements ClientListCubit;

void main() {
  final now = DateTime.utc(2026, 10, 1, 9);
  final office = Client(id: 'client-a', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final shop = Client(id: 'client-b', name: '새봄 매장', createdAt: DateTime.utc(2026, 9, 2));
  final failure = Exception('storage failed');

  late FakeClientRepository clients;
  late FakeCompanyProfileRepository companyProfile;
  late FakeEntitlements entitlements;

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Client> saved = const [],
    Locale? locale,
    Exception? loadFailure,
    Plan plan = Plan.free,
  }) async {
    clients = FakeClientRepository(clients: saved)..failure = loadFailure;
    entitlements = FakeEntitlements(plan: plan);
    companyProfile = FakeCompanyProfileRepository();
    await tester.pumpApp(
      const ClientListPage(),
      locale: locale,
      repositories: Repositories(
        clients: clients,
        visits: FakeVisitRepository(),
        companyProfile: companyProfile,
        publishing: MockPublishRepository(),
        openCaptures: FakeOpenCaptureRepository(),
        localData: FakeLocalDataRepository(),
      ),
      clock: FixedClock(now),
      entitlements: entitlements,
    );
    await tester.pumpAndSettle();
  }

  /// [count] active clients, oldest first.
  List<Client> clientsOf(int count) => [
    for (var index = 0; index < count; index++)
      Client(id: 'client-$index', name: '거래처 $index', createdAt: DateTime.utc(2026, 9, 1 + index)),
  ];

  const freeLimitMessage =
      'The Free plan keeps up to 2 clients. To add a client, change your plan or archive a client.';

  Finder addButton() => find.widgetWithText(FilledButton, 'Add Client');

  Future<void> submitName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
  }

  group('ClientListPage', () {
    testWidgets('renders ClientListView under the title of the screen', (tester) async {
      await pumpPage(tester);

      expect(find.byType(ClientListView), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Clients'), findsOneWidget);
    });

    testWidgets('explains what a client is and offers the add control when no client exists', (tester) async {
      await pumpPage(tester);

      expect(find.text('No clients yet'), findsOneWidget);
      expect(
        find.text('A client is an office or a shop that you clean. Add one, then set up the zones to clean there.'),
        findsOneWidget,
      );
      expect(addButton(), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('shows the empty state in Korean', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'));

      expect(find.widgetWithText(AppBar, '거래처'), findsOneWidget);
      expect(find.text('아직 거래처가 없어요'), findsOneWidget);
      expect(find.text('거래처는 청소하러 가는 사무실이나 매장이에요. 거래처를 추가하면 청소할 구역을 정할 수 있어요.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '거래처 추가하기'), findsOneWidget);
    });

    testWidgets('lists the active clients, oldest first, without the empty state', (tester) async {
      final archived = Client(id: 'client-c', name: '옛 거래처', createdAt: DateTime.utc(2026, 8), isArchived: true);

      await pumpPage(tester, saved: [shop, archived, office]);

      final names = tester.widgetList<ListTile>(find.byType(ListTile)).map((tile) => (tile.title! as Text).data);
      expect(names, ['한빛 사무실', '새봄 매장']);
      expect(find.text('No clients yet'), findsNothing);
      expect(addButton(), findsOneWidget);
    });

    testWidgets('adds a client from the dialog and lists it', (tester) async {
      await pumpPage(tester, saved: [office]);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AlertDialog, 'Add Client'), findsOneWidget);
      expect(find.text('Client name'), findsOneWidget);
      await submitName(tester, ' 다온 카페 ');

      expect(find.byType(NameDialog), findsNothing);
      expect(find.widgetWithText(ListTile, '다온 카페'), findsOneWidget);
      expect(await clients.clientById('id-1'), Client(id: 'id-1', name: '다온 카페', createdAt: now));
    });

    testWidgets('shows the validation message under the name field and keeps the dialog open', (tester) async {
      await pumpPage(tester);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await submitName(tester, '   ');

      expect(find.byType(NameDialog), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage, 'Enter a name.');
      expect(await clients.activeClients(), isEmpty);
    });

    testWidgets('shows the validation message in Korean', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'));

      await tester.tap(find.widgetWithText(FilledButton, '거래처 추가하기'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AlertDialog, '거래처 추가'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '닫기'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '추가하기'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage, '이름을 입력해 주세요.');
    });

    testWidgets('opens the dialog again without the problem of the name before', (tester) async {
      await pumpPage(tester);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await submitName(tester, '');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(addButton());
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage, isNull);
    });

    testWidgets('shows a failure of storage under the name field and adds the client on the next try', (tester) async {
      await pumpPage(tester);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      clients.failure = failure;
      await submitName(tester, '다온 카페');

      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage,
        "Can't save right now. Try again.",
      );

      clients.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.byType(NameDialog), findsNothing);
      expect(find.widgetWithText(ListTile, '다온 카페'), findsOneWidget);
    });

    group('at the client limit of the plan', () {
      testWidgets('adds a client of a Free company with 1 active client without asking for the plan', (tester) async {
        await pumpPage(tester, saved: [office]);

        await tester.tap(addButton());
        await tester.pumpAndSettle();
        await submitName(tester, '다온 카페');

        expect(find.widgetWithText(ListTile, '다온 카페'), findsOneWidget);
        expect(entitlements.touched, isEmpty);
      });

      testWidgets('shows the limit of the Free plan and the way to the plans in place of the dialog, and saves '
          'nothing', (tester) async {
        final archived = Client(id: 'client-c', name: '옛 거래처', createdAt: DateTime.utc(2026, 8), isArchived: true);
        await pumpPage(tester, saved: [office, shop, archived]);

        await tester.tap(addButton());
        await tester.pumpAndSettle();

        expect(find.byType(NameDialog), findsNothing);
        expect(find.text(freeLimitMessage), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'See Plans'), findsOneWidget);
        expect(await clients.activeClients(), [office, shop]);
      });

      testWidgets('keeps every client of a company above the Free limit after a downgrade, and adds none', (
        tester,
      ) async {
        await pumpPage(tester, saved: clientsOf(3));

        await tester.tap(addButton());
        await tester.pumpAndSettle();

        expect(find.byType(NameDialog), findsNothing);
        expect(find.text(freeLimitMessage), findsOneWidget);
        expect(find.byType(ListTile), findsNWidgets(3));
        expect(await clients.activeClients(), hasLength(3));
      });

      testWidgets('lets a Basic company with 4 active clients add the fifth, and stops it at the sixth', (
        tester,
      ) async {
        await pumpPage(tester, saved: clientsOf(4), plan: Plan.basic);

        await tester.tap(addButton());
        await tester.pumpAndSettle();
        await submitName(tester, '다섯째');
        expect(await clients.activeClients(), hasLength(5));

        await tester.tap(addButton());
        await tester.pumpAndSettle();

        expect(find.byType(NameDialog), findsNothing);
        expect(
          find.text('The Basic plan keeps up to 5 clients. To add a client, change your plan or archive a client.'),
          findsOneWidget,
        );
      });

      testWidgets('lets a Pro company with 12 active clients add the thirteenth', (tester) async {
        await pumpPage(tester, saved: clientsOf(12), plan: Plan.pro);

        await tester.tap(addButton());
        await tester.pumpAndSettle();
        await submitName(tester, '열셋째');

        expect(await clients.activeClients(), hasLength(13));
      });

      testWidgets('refuses the name when the plan ended while the dialog was open, and shows the limit after it '
          'closes', (tester) async {
        await pumpPage(tester, saved: clientsOf(4), plan: Plan.basic);

        await tester.tap(addButton());
        await tester.pumpAndSettle();
        entitlements.plan = Plan.free;
        await submitName(tester, '다온 카페');

        expect(find.byType(NameDialog), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage,
          "Your plan can't keep more clients.",
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.text(freeLimitMessage), findsOneWidget);
        expect(await clients.activeClients(), hasLength(4));
      });

      testWidgets('opens the plans, and forgets the limit when the plans screen closes', (tester) async {
        await pumpPage(tester, saved: [office, shop]);
        await tester.tap(addButton());
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'See Plans'));
        await tester.pumpAndSettle();
        expect(find.byType(PlansPage), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(PlansPage), findsNothing);
        expect(find.text(freeLimitMessage), findsNothing);
      });

      for (final (screen, open) in [
        ('a client', find.widgetWithText(ListTile, '한빛 사무실')),
        ('the company profile', find.byTooltip('Company profile')),
      ]) {
        testWidgets('opens no dialog over $screen when the plan answers after the person left', (tester) async {
          await pumpPage(tester, saved: [office, shop], plan: Plan.basic);
          entitlements.planGate = Completer<void>();

          await tester.tap(addButton());
          await tester.pump();
          await tester.tap(open);
          await tester.pumpAndSettle();
          entitlements.planGate!.complete();
          await tester.pumpAndSettle();
          expect(find.byType(NameDialog), findsNothing);

          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(NameDialog), findsNothing);

          await tester.tap(addButton());
          await tester.pumpAndSettle();
          expect(find.byType(NameDialog), findsOneWidget);
        });
      }

      testWidgets('shows the limit in Korean', (tester) async {
        await pumpPage(tester, saved: [office, shop], locale: const Locale('ko'));

        await tester.tap(find.widgetWithText(FilledButton, '거래처 추가하기'));
        await tester.pumpAndSettle();

        expect(
          find.text('무료 요금제는 거래처를 2곳까지 둘 수 있어요. 거래처를 추가하려면 요금제를 바꾸거나 거래처를 보관해 주세요.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, '요금제 보기'), findsOneWidget);
      });
    });

    testWidgets('shows a message and a retry control when the clients do not load, and loads them on retry', (
      tester,
    ) async {
      await pumpPage(tester, saved: [office], loadFailure: failure);

      expect(find.text("Can't load your clients. Try again."), findsOneWidget);
      expect(addButton(), findsNothing);

      clients.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, '한빛 사무실'), findsOneWidget);
    });

    testWidgets('opens the company profile from the app bar', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Company profile'));
      await tester.pumpAndSettle();

      expect(find.byType(CompanyProfilePage), findsOneWidget);
    });

    testWidgets('reads the list again when the company profile closes, which can delete all data', (tester) async {
      await pumpPage(tester, saved: [office]);
      await tester.tap(find.byTooltip('Company profile'));
      await tester.pumpAndSettle();

      // The deletion erases the stores, which the fake client store shows as a list without the client.
      await clients.save(office.archive());
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, '한빛 사무실'), findsNothing);
      expect(find.text('No clients yet'), findsOneWidget);
    });

    testWidgets('opens a client, and reads the list again when the client screen closes', (tester) async {
      await pumpPage(tester, saved: [office, shop]);

      await tester.tap(find.widgetWithText(ListTile, '한빛 사무실'));
      await tester.pumpAndSettle();
      expect(tester.widget<ClientDetailPage>(find.byType(ClientDetailPage)).clientId, 'client-a');

      await clients.save(office.rename('한빛 본사'));
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(ClientDetailPage), findsNothing);
      expect(find.widgetWithText(ListTile, '한빛 본사'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '한빛 사무실'), findsNothing);
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      const longName = '서울특별시 강남구 테헤란로 한빛타워 12층 공유오피스';

      for (final (locale, title, message, add) in [
        (
          const Locale('en'),
          'No clients yet',
          'A client is an office or a shop that you clean. Add one, then set up the zones to clean there.',
          'Add Client',
        ),
        (
          const Locale('ko'),
          '아직 거래처가 없어요',
          '거래처는 청소하러 가는 사무실이나 매장이에요. 거래처를 추가하면 청소할 구역을 정할 수 있어요.',
          '거래처 추가하기',
        ),
      ]) {
        testWidgets('fits the empty state and cuts none of its text in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, locale: locale);

          tester
            ..expectWholeText(title)
            ..expectWholeText(message)
            ..expectWholeText(add);
        });
      }

      testWidgets('fits a list of clients and cuts no name, however long', (tester) async {
        tester.useNarrowScreenWithLargestText();

        await pumpPage(
          tester,
          saved: [
            Client(id: 'client-d', name: longName, createdAt: DateTime.utc(2026, 8)),
            office,
            shop,
          ],
          locale: const Locale('ko'),
        );

        tester
          ..expectWholeText(longName)
          ..expectWholeText('거래처 추가하기');
        await tester.scrollUntilVisible(find.text('새봄 매장'), 100, scrollable: find.byType(Scrollable).first);
        tester.expectWholeText('새봄 매장');
      });

      for (final (locale, add, label, submit, cancel, emptyProblem, failedProblem) in [
        (
          const Locale('en'),
          'Add Client',
          'Client name',
          'Add',
          'Cancel',
          'Enter a name.',
          "Can't save right now. Try again.",
        ),
        (const Locale('ko'), '거래처 추가하기', '거래처 이름', '추가하기', '닫기', '이름을 입력해 주세요.', '저장하지 못했어요. 다시 시도해 주세요.'),
      ]) {
        testWidgets('fits the dialog for a new client and cuts neither its label nor a problem under the field in '
            '${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, locale: locale);

          await tester.tap(find.widgetWithText(FilledButton, add));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, submit));
          await tester.pumpAndSettle();
          tester
            ..expectWholeText(label)
            ..expectWholeText(emptyProblem)
            ..expectWholeText(cancel);

          clients.failure = failure;
          await tester.enterText(find.byType(TextField), '다온 카페');
          await tester.tap(find.widgetWithText(FilledButton, submit));
          await tester.pumpAndSettle();
          tester.expectWholeText(failedProblem);
        });
      }

      for (final (locale, add, submit, problem) in [
        (
          const Locale('en'),
          'Add Client',
          'Add',
          "Your plan can't keep more clients.",
        ),
        (
          const Locale('ko'),
          '거래처 추가하기',
          '추가하기',
          '지금 요금제로는 거래처를 더 둘 수 없어요.',
        ),
      ]) {
        testWidgets('fits the problem of a plan that ended while the dialog was open in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, saved: clientsOf(4), plan: Plan.basic, locale: locale);

          await tester.tap(find.widgetWithText(FilledButton, add));
          await tester.pumpAndSettle();
          entitlements.plan = Plan.free;
          await tester.enterText(find.byType(TextField), '다온 카페');
          await tester.tap(find.widgetWithText(FilledButton, submit));
          await tester.pumpAndSettle();

          tester.expectWholeText(problem);
        });
      }

      for (final (locale, message, plans) in [
        (const Locale('en'), freeLimitMessage, 'See Plans'),
        (
          const Locale('ko'),
          '무료 요금제는 거래처를 2곳까지 둘 수 있어요. 거래처를 추가하려면 요금제를 바꾸거나 거래처를 보관해 주세요.',
          '요금제 보기',
        ),
      ]) {
        testWidgets('fits the notice of the limit in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, saved: [office, shop], locale: locale);

          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();

          tester.expectWholeText(message);
          await tester.scrollUntilVisible(find.text(plans), 100, scrollable: find.byType(Scrollable).last);
          tester.expectWholeText(plans);
        });
      }

      for (final (locale, message, retry) in [
        (const Locale('en'), "Can't load your clients. Try again.", 'Try Again'),
        (const Locale('ko'), '거래처 목록을 불러오지 못했어요. 다시 시도해 주세요.', '다시 불러오기'),
      ]) {
        testWidgets('fits the message of a failed load in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, locale: locale, loadFailure: failure);

          tester
            ..expectWholeText(message)
            ..expectWholeText(retry);
        });
      }
    });
  });

  group('ClientListView', () {
    late ClientListCubit cubit;

    setUp(() => cubit = _MockClientListCubit());

    Future<void> pumpView(WidgetTester tester, ClientListState state) async {
      when(() => cubit.state).thenReturn(state);
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const ClientListView()));
    }

    testWidgets('shows a progress indicator while the clients load', (tester) async {
      await pumpView(tester, const ClientListState());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(addButton(), findsNothing);
    });

    testWidgets('asks the cubit for a new client when the add control is pressed', (tester) async {
      when(() => cubit.requestNewClient()).thenAnswer((_) async {});
      await pumpView(tester, const ClientListState(status: ClientListStatus.ready));

      await tester.tap(addButton());
      await tester.pumpAndSettle();

      verify(() => cubit.requestNewClient()).called(1);
      expect(find.byType(NameDialog), findsNothing);
    });

    testWidgets('opens the dialog when the plan allows a client, and passes the name from it to the cubit', (
      tester,
    ) async {
      when(() => cubit.addClient(any())).thenAnswer((_) async {});
      whenListen(
        cubit,
        Stream.value(const ClientListState(status: ClientListStatus.ready, addition: ClientAddition.allowed)),
        initialState: const ClientListState(status: ClientListStatus.ready),
      );
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const ClientListView()));
      await tester.pumpAndSettle();

      await submitName(tester, '다온 카페');

      verifyInOrder([() => cubit.startNameEntry(), () => cubit.addClient('다온 카페')]);
    });

    testWidgets('takes no press of the add control while the plan is on its way', (tester) async {
      await pumpView(tester, const ClientListState(status: ClientListStatus.ready, addition: ClientAddition.checking));

      expect(tester.widget<ButtonStyleButton>(addButton()).onPressed, isNull);
    });
  });
}
