import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/counter/counter.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

class App extends StatelessWidget {
  const new({required this.repositories, super.key});

  /// The repositories that the widgets below read through `RepositoryProvider`.
  final Repositories repositories;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ClientRepository>.value(value: repositories.clients),
        RepositoryProvider<VisitRepository>.value(value: repositories.visits),
        RepositoryProvider<CompanyProfileRepository>.value(value: repositories.companyProfile),
      ],
      child: MaterialApp(
        theme: ThemeData(
          appBarTheme: AppBarTheme(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          useMaterial3: true,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CounterPage(),
      ),
    );
  }
}
