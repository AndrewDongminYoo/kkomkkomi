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
      await tester.pumpWidget(App(repositories: mockRepositories()));
      await tester.pumpAndSettle();

      expect(find.byType(ClientListPage), findsOneWidget);
      expect(Navigator.of(tester.element(find.byType(ClientListPage))).canPop(), isFalse);
      expect(find.widgetWithText(AppBar, 'Clients'), findsOneWidget);
    });

    testWidgets('provides each repository to the widgets below it', (tester) async {
      final repositories = mockRepositories();

      await tester.pumpWidget(App(repositories: repositories));

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<ClientRepository>(), same(repositories.clients));
      expect(context.read<VisitRepository>(), same(repositories.visits));
      expect(context.read<CompanyProfileRepository>(), same(repositories.companyProfile));
    });

    testWidgets('provides the random identifiers and the device time unless it is given others', (tester) async {
      await tester.pumpWidget(App(repositories: mockRepositories()));

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<IdGenerator>(), isA<RandomIdGenerator>());
      expect(context.read<Clock>(), isA<SystemClock>());
    });

    testWidgets('provides the identifier generator and the clock that it is given', (tester) async {
      final idGenerator = SequenceIdGenerator();
      final clock = FixedClock(DateTime.utc(2026, 10));

      await tester.pumpWidget(App(repositories: mockRepositories(), idGenerator: idGenerator, clock: clock));

      final context = tester.element(find.byType(ClientListPage));
      expect(context.read<IdGenerator>(), same(idGenerator));
      expect(context.read<Clock>(), same(clock));
    });

    testWidgets('shows the home screen and the Material widgets in Korean under the Korean locale', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(App(repositories: mockRepositories()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '거래처'), findsOneWidget);
      expect(MaterialLocalizations.of(tester.element(find.byType(ClientListPage))).backButtonTooltip, '뒤로');
    });
  });
}
