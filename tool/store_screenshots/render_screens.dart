// Renders the raw store screens: the real screens of the app with the fixture data of fixtures.dart, one PNG per
// screen, language, and platform, under build/store_screenshots/raw/<platform>/<language>/.
//
// Run it with `flutter test tool/store_screenshots/render_screens.dart`; render.sh runs it before it frames the
// screens. It lives outside test/, so the test suite, the coverage gate, and CI never run it.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/gen/assets.gen.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../test/helpers/helpers.dart';
import 'fixtures.dart';

/// A store size of a platform: the size of the screen in logical pixels and the pixel ratio of the image.
typedef _Device = ({String name, TargetPlatform platform, Size logicalSize, double pixelRatio});

const _devices = <_Device>[
  // 1320 x 2868, the iPhone 6.9-inch size of App Store Connect.
  (name: 'ios', platform: TargetPlatform.iOS, logicalSize: Size(440, 956), pixelRatio: 3),
  // 1080 x 1920, the 9:16 phone size of Google Play.
  (name: 'android', platform: TargetPlatform.android, logicalSize: Size(432, 768), pixelRatio: 2.5),
];

const _languages = <(String, Locale, StoreFixtures)>[
  ('ko', Locale('ko'), StoreFixtures.korean),
  ('en', Locale('en'), StoreFixtures.english),
];

/// The font families that the theme of the app asks for: Roboto on Android, and the system families on iOS.
///
/// The test binding draws every family as boxes, so the render loads the font of the app under each of these names.
/// Only the regular weight is bundled, so bold text renders at the regular weight.
const _textFamilies = ['Roboto', 'CupertinoSystemText', 'CupertinoSystemDisplay'];

final String _photoDirectory = p.absolute('tool', 'store_screenshots', 'photos');
final String _outputDirectory = p.absolute('build', 'store_screenshots', 'raw');

/// A photo store over the fixture photos, which reads real files.
class _FixturePhotoStore extends FakePhotoStore {
  @override
  Future<String> directoryPath() async => _photoDirectory;

  @override
  Future<Uint8List> read(PhotoRef photo) async => File(p.join(_photoDirectory, photo.path)).readAsBytesSync();
}

void main() {
  setUpAll(() async {
    final notoSans = rootBundle.load(Assets.fonts.notoSansKRRegular);
    for (final family in _textFamilies) {
      await (FontLoader(family)..addFont(notoSans)).load();
    }
    // The Material Icons font that the Flutter SDK puts into the assets of every app that uses Material Design.
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final device in _devices) {
    for (final (language, locale, fixtures) in _languages) {
      testWidgets(timeout: const Timeout(Duration(minutes: 2)), '${device.name} $language', (tester) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        WidgetsApp.debugAllowBannerOverride = false;
        debugDefaultTargetPlatformOverride = device.platform;
        tester.view
          ..physicalSize = device.logicalSize * device.pixelRatio
          ..devicePixelRatio = device.pixelRatio;
        try {
          final directory = p.join(_outputDirectory, device.name, language);
          Directory(directory).createSync(recursive: true);

          await _pumpScreen(tester, locale, fixtures, VisitCapturePage.route(visitId: StoreFixtures.latestVisitId));
          await _write(tester, p.join(directory, '01_capture.png'));

          await _pumpScreen(tester, locale, fixtures, VisitReportPage.route(visitId: StoreFixtures.latestVisitId));
          await _write(tester, p.join(directory, '02_report.png'));

          await _pumpScreen(tester, locale, fixtures, ClientDetailPage.route(clientId: StoreFixtures.clientId));
          await _write(tester, p.join(directory, '03_client.png'));

          await _pumpScreen(tester, locale, fixtures, null);
          await _write(tester, p.join(directory, '04_clients.png'));
        } finally {
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = shadows;
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }
}

/// Shows the client list, and then opens [route] over it when one is given, so that the screen has its back button.
Future<void> _pumpScreen(WidgetTester tester, Locale locale, StoreFixtures fixtures, Route<void>? route) async {
  final repositories = Repositories(
    clients: FakeClientRepository(clients: fixtures.clients, zones: [fixtures.zones]),
    visits: FakeVisitRepository(visits: fixtures.visits),
    companyProfile: FakeCompanyProfileRepository(profile: CompanyProfile(name: fixtures.companyName)),
    publishing: FakePublishRepository(),
    openCaptures: FakeOpenCaptureRepository(),
    localData: FakeLocalDataRepository(),
  );
  final photoStore = _FixturePhotoStore();
  // An empty tree first, so that no state of the previous screen stays.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpApp(
    const ClientListPage(),
    locale: locale,
    repositories: repositories,
    // The production flavor: a backend that is available, so the screens offer the report link.
    publishQueue: publishQueueOf(repositories, publisher: FakePublisher(), photoStore: photoStore),
    photoStore: photoStore,
    clock: FixedClock(DateTime.utc(2026, 10, 2, 9)),
  );
  await tester.pumpAndSettle();
  if (route != null) {
    tester.state<NavigatorState>(find.byType(Navigator)).push(route);
    await tester.pumpAndSettle();
  }
  // A photo file is read and decoded in real time, and its result reaches the screen at the next pump of the fake
  // time, so the render waits in real time and pumps until every image on the screen shows its picture.
  bool loaded() => tester.widgetList<RawImage>(find.byType(RawImage)).every((image) => image.image != null);
  for (var attempt = 0; attempt < 100 && !loaded(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  if (!loaded()) throw StateError('A photo on the screen did not load');
  await tester.pumpAndSettle();
}

/// Writes what the screen shows to [path] as a PNG at the pixel ratio of the screen.
Future<void> _write(WidgetTester tester, String path) async {
  final renderView = tester.binding.renderViews.single;
  final layer = renderView.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(renderView.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
