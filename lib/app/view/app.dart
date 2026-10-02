import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';

/// The name of the initial route that opens the visit of [App.recovery] over the client list.
const _recoveredVisitRouteName = '/recovered-visit';

class App extends StatelessWidget {
  const new({
    required this.repositories,
    required this.identity,
    required this.publishQueue,
    this.recovery,
    this.idGenerator = const RandomIdGenerator(),
    this.clock = const SystemClock(),
    this.photoCapture = const ImagePickerPhotoCapture(),
    this.photoStore = const DocumentsPhotoStore(),
    this.reportFont = const AssetReportFont(),
    this.reportShare = const PrintingReportShare(),
    this.linkShare = const SharePlusLinkShare(),
    super.key,
  });

  /// The repositories that the widgets below read through `RepositoryProvider`.
  final Repositories repositories;

  /// The source of the user ID, which the widgets below read through `RepositoryProvider`.
  ///
  /// It has no default, because the flavor decides it: only the production entry point gives the Firebase adapter.
  final Identity identity;

  /// The one publish queue of the app, which `bootstrap` starts and the widgets below read through
  /// `RepositoryProvider`.
  final PublishQueue publishQueue;

  /// What `bootstrap` did with the photo of a capture whose answer the app lost, or null when it found none.
  ///
  /// When it is set, the app opens the visit of that capture over the client list, and the visit screen says what
  /// became of the photo.
  final LostCaptureRecovery? recovery;

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

  /// The share sheet for a report link, which the widgets below read through `RepositoryProvider`.
  final LinkShare linkShare;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ClientRepository>.value(value: repositories.clients),
        RepositoryProvider<VisitRepository>.value(value: repositories.visits),
        RepositoryProvider<CompanyProfileRepository>.value(value: repositories.companyProfile),
        RepositoryProvider<OpenCaptureRepository>.value(value: repositories.openCaptures),
        RepositoryProvider<Identity>.value(value: identity),
        RepositoryProvider<PublishQueue>.value(value: publishQueue),
        RepositoryProvider<IdGenerator>.value(value: idGenerator),
        RepositoryProvider<Clock>.value(value: clock),
        RepositoryProvider<PhotoCapture>.value(value: photoCapture),
        RepositoryProvider<PhotoStore>.value(value: photoStore),
        RepositoryProvider<ReportFont>.value(value: reportFont),
        RepositoryProvider<ReportShare>.value(value: reportShare),
        RepositoryProvider<LinkShare>.value(value: linkShare),
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
        // The navigator makes a route for each segment of the initial route: `home` for `/`, and the visit for the
        // segment under it, so that back from the visit leads to the client list. No other route has a name.
        initialRoute: recovery == null ? null : _recoveredVisitRouteName,
        onGenerateRoute: switch (recovery) {
          null => null,
          final recovery => (_) => VisitCapturePage.route(visitId: recovery.visitId, recovery: recovery),
        },
      ),
    );
  }
}
