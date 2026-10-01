import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';

class App extends StatelessWidget {
  const new({
    required this.repositories,
    required this.identity,
    this.idGenerator = const RandomIdGenerator(),
    this.clock = const SystemClock(),
    this.photoCapture = const ImagePickerPhotoCapture(),
    this.photoStore = const DocumentsPhotoStore(),
    this.reportFont = const AssetReportFont(),
    this.reportShare = const PrintingReportShare(),
    super.key,
  });

  /// The repositories that the widgets below read through `RepositoryProvider`.
  final Repositories repositories;

  /// The source of the user ID, which the widgets below read through `RepositoryProvider`.
  ///
  /// It has no default, because the flavor decides it: only the production entry point gives the Firebase adapter.
  final Identity identity;

  /// The source of the identifiers of new entities, which the widgets below read through `RepositoryProvider`.
  final IdGenerator idGenerator;

  /// The source of the time, which the widgets below read through `RepositoryProvider`.
  final Clock clock;

  /// The camera, which the widgets below read through `RepositoryProvider`.
  final PhotoCapture photoCapture;

  /// The keeper of the photo files, which the widgets below read through `RepositoryProvider`.
  final PhotoStore photoStore;

  /// The font file of the report, which the widgets below read through `RepositoryProvider`.
  final ReportFont reportFont;

  /// The share sheet for a report, which the widgets below read through `RepositoryProvider`.
  final ReportShare reportShare;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ClientRepository>.value(value: repositories.clients),
        RepositoryProvider<VisitRepository>.value(value: repositories.visits),
        RepositoryProvider<CompanyProfileRepository>.value(value: repositories.companyProfile),
        RepositoryProvider<Identity>.value(value: identity),
        RepositoryProvider<IdGenerator>.value(value: idGenerator),
        RepositoryProvider<Clock>.value(value: clock),
        RepositoryProvider<PhotoCapture>.value(value: photoCapture),
        RepositoryProvider<PhotoStore>.value(value: photoStore),
        RepositoryProvider<ReportFont>.value(value: reportFont),
        RepositoryProvider<ReportShare>.value(value: reportShare),
      ],
      child: MaterialApp(
        theme: ThemeData(
          appBarTheme: AppBarTheme(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          useMaterial3: true,
        ),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ClientListPage(),
      ),
    );
  }
}
