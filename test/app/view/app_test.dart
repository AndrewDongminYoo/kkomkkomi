import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/counter/counter.dart';

import '../../helpers/helpers.dart';

void main() {
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      await tester.pumpWidget(App(repositories: mockRepositories()));
      expect(find.byType(CounterPage), findsOneWidget);
    });

    testWidgets('provides each repository to the widgets below it', (tester) async {
      final repositories = mockRepositories();

      await tester.pumpWidget(App(repositories: repositories));

      final context = tester.element(find.byType(CounterPage));
      expect(context.read<ClientRepository>(), same(repositories.clients));
      expect(context.read<VisitRepository>(), same(repositories.visits));
      expect(context.read<CompanyProfileRepository>(), same(repositories.companyProfile));
    });
  });
}
