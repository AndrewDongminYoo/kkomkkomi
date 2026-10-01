import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockClientListCubit extends MockCubit<ClientListState> implements ClientListCubit;

void main() {
  final now = DateTime.utc(2026, 10, 1, 9);
  final office = Client(id: 'client-a', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final shop = Client(id: 'client-b', name: '새봄 매장', createdAt: DateTime.utc(2026, 9, 2));
  final failure = Exception('storage failed');

  late FakeClientRepository clients;
  late FakeCompanyProfileRepository companyProfile;

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Client> saved = const [],
    Locale? locale,
    Exception? loadFailure,
  }) async {
    clients = FakeClientRepository(clients: saved)..failure = loadFailure;
    companyProfile = FakeCompanyProfileRepository();
    await tester.pumpApp(
      const ClientListPage(),
      locale: locale,
      repositories: Repositories(
        clients: clients,
        visits: FakeVisitRepository(),
        companyProfile: companyProfile,
        publishing: MockPublishRepository(),
      ),
      clock: FixedClock(now),
    );
    await tester.pumpAndSettle();
  }

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
      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorText, 'Enter a name.');
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

      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorText, '이름을 입력해 주세요.');
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

      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorText, isNull);
    });

    testWidgets('shows a failure of storage under the name field and adds the client on the next try', (tester) async {
      await pumpPage(tester);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      clients.failure = failure;
      await submitName(tester, '다온 카페');

      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
        "Can't save right now. Try again.",
      );

      clients.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.byType(NameDialog), findsNothing);
      expect(find.widgetWithText(ListTile, '다온 카페'), findsOneWidget);
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

    testWidgets('passes the name from the dialog to the cubit', (tester) async {
      when(() => cubit.addClient(any())).thenAnswer((_) async {});
      await pumpView(tester, const ClientListState(status: ClientListStatus.ready));

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await submitName(tester, '다온 카페');

      verifyInOrder([() => cubit.startNameEntry(), () => cubit.addClient('다온 카페')]);
    });
  });
}
