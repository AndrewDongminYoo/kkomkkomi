// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';

// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/view/app_theme.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

/// The name of the initial route that opens the visit of [App.recovery] over the client list.
const _recoveredVisitRouteName = '/recovered-visit';

class App extends StatefulWidget {
  const new({
    required this.repositories,
    required this.identity,
    required this.entitlements,
    required this.publishQueue,
    this.recovery,
    this.idGenerator = const RandomIdGenerator(),
    this.clock = const SystemClock(),
    this.photoCapture,
    this.cameraDriverFactory = CameraDriver.new,
    this.cameraPhotoFiles = const TemporaryCameraPhotoFiles(),
    this.externalPhotoCapture = const ImagePickerPhotoCapture(),
    this.photoStore = const DocumentsPhotoStore(),
    this.reportFont = const AssetReportFont(),
    this.reportShare = const PrintingReportShare(),
    this.linkShare = const SharePlusLinkShare(),
    this.externalLinks = const UrlLauncherExternalLinks(),
    super.key,
  });

  /// The repositories that the widgets below read through `RepositoryProvider`.
  final Repositories repositories;

  /// The source of the user ID, which the widgets below read through `RepositoryProvider`.
  ///
  /// It has no default, because the flavor decides it: only the production entry point gives the Firebase adapter.
  final Identity identity;

  /// The source of the plan of the company, which the widgets below read through `RepositoryProvider`.
  ///
  /// It has no default, because the flavor decides it: only the production entry point gives the RevenueCat adapter.
  final Entitlements entitlements;

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
  final PhotoCapture? photoCapture;

  final StillCameraDriver Function() cameraDriverFactory;
  final CameraPhotoFiles cameraPhotoFiles;
  final PhotoCapture externalPhotoCapture;

  /// The keeper of the photo files, which the widgets below read through `RepositoryProvider`.
  final PhotoStore photoStore;

  /// The font file of the report, which the widgets below read through `RepositoryProvider`.
  final ReportFont reportFont;

  /// The share sheet for a report, which the widgets below read through `RepositoryProvider`.
  final ReportShare reportShare;

  /// The share sheet for a report link, which the widgets below read through `RepositoryProvider`.
  final LinkShare linkShare;

  /// The opener of web pages outside the app, which the widgets below read through `RepositoryProvider`.
  final ExternalLinks externalLinks;

  @override
  State<App> createState() => _AppState();

  Widget _build(BuildContext context, PhotoCapture capture, GlobalKey<NavigatorState> navigatorKey) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ClientRepository>.value(value: repositories.clients),
        RepositoryProvider<VisitRepository>.value(value: repositories.visits),
        RepositoryProvider<CompanyProfileRepository>.value(value: repositories.companyProfile),
        RepositoryProvider<OpenCaptureRepository>.value(value: repositories.openCaptures),
        RepositoryProvider<Identity>.value(value: identity),
        RepositoryProvider<Entitlements>.value(value: entitlements),
        RepositoryProvider<PublishQueue>.value(value: publishQueue),
        RepositoryProvider<IdGenerator>.value(value: idGenerator),
        RepositoryProvider<Clock>.value(value: clock),
        RepositoryProvider<PhotoCapture>.value(value: capture),
        RepositoryProvider<PhotoStore>.value(value: photoStore),
        RepositoryProvider<ReportFont>.value(value: reportFont),
        RepositoryProvider<ReportShare>.value(value: reportShare),
        RepositoryProvider<LinkShare>.value(value: linkShare),
        RepositoryProvider<ExternalLinks>.value(value: externalLinks),
        // One for the life of the app, because a deletion that failed goes on from its failed step at the next try.
        RepositoryProvider<DeleteAllData>(
          create: (_) => DeleteAllData(
            publishQueue: publishQueue,
            identity: identity,
            localData: repositories.localData,
            photoStore: photoStore,
          ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: appTheme(),
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

class _AppState extends State<App> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late PhotoCapture _capture;

  @override
  void initState() {
    super.initState();
    _capture = _configuredCapture();
  }

  @override
  void didUpdateWidget(App oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoCapture != widget.photoCapture ||
        oldWidget.externalPhotoCapture != widget.externalPhotoCapture) {
      _capture = _configuredCapture();
    }
  }

  PhotoCapture _configuredCapture() {
    if (widget.photoCapture case final capture?) return capture;
    final picker = widget.externalPhotoCapture;
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return picker;
    }
    return InAppCameraPhotoCapture(
      picker: picker,
      discardPhoto: (path) => widget.cameraPhotoFiles.discard(path),
      openCamera: () => _navigatorKey.currentState!.push(
        StillCameraPage.route(
          driverFactory: widget.cameraDriverFactory,
          files: widget.cameraPhotoFiles,
          clock: widget.clock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget._build(context, _capture, _navigatorKey);
}
