// 🐦 Flutter imports:
import 'package:flutter/rendering.dart';

// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';

import 'fakes.dart';

/// The text scale of the largest system text size.
///
/// The largest accessibility size of iOS shows body text at 53 points in place of 17, and Android stops at 2.0.
const double largestSystemTextScale = 53 / 17;

extension PumpApp on WidgetTester {
  /// Pumps [widget] as the home of a `MaterialApp` that has the theme and the localization delegates of the app.
  ///
  /// The app shows the strings of [locale] when one is given, and the English strings otherwise.
  /// When [repositories] is given, the widgets read its members (the store of the open capture included), [identity], [entitlements], [publishQueue], [idGenerator], [clock],
  /// [photoCapture], [photoStore], [reportFont], [reportShare], [linkShare], [externalLinks], and [deleteAllData] through
  /// `RepositoryProvider`, as they do under the app. A port that is not given is a fake, the publish queue that is not
  /// given has no backend, and the deletion that is not given acts on the queue, the identity, the stores, and the
  /// photo store of the test.
  Future<void> pumpApp(
    Widget widget, {
    Locale? locale,
    Repositories? repositories,
    Identity? identity,
    Entitlements? entitlements,
    PublishQueue? publishQueue,
    IdGenerator? idGenerator,
    Clock? clock,
    PhotoCapture? photoCapture,
    PhotoStore? photoStore,
    ReportFont? reportFont,
    ReportShare? reportShare,
    LinkShare? linkShare,
    ExternalLinks? externalLinks,
    DeleteAllData? deleteAllData,
  }) {
    final app = MaterialApp(
      theme: appTheme(),
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: widget,
    );
    if (repositories == null) return pumpWidget(app);
    final theIdentity = identity ?? FakeIdentity();
    final theQueue = publishQueue ?? publishQueueOf(repositories);
    final thePhotoStore = photoStore ?? FakePhotoStore();
    return pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ClientRepository>.value(value: repositories.clients),
          RepositoryProvider<VisitRepository>.value(value: repositories.visits),
          RepositoryProvider<CompanyProfileRepository>.value(value: repositories.companyProfile),
          RepositoryProvider<OpenCaptureRepository>.value(value: repositories.openCaptures),
          RepositoryProvider<Identity>.value(value: theIdentity),
          RepositoryProvider<Entitlements>.value(value: entitlements ?? FakeEntitlements()),
          RepositoryProvider<PublishQueue>.value(value: theQueue),
          RepositoryProvider<IdGenerator>.value(value: idGenerator ?? SequenceIdGenerator()),
          RepositoryProvider<Clock>.value(value: clock ?? FixedClock(DateTime.utc(2026, 10))),
          RepositoryProvider<PhotoCapture>.value(value: photoCapture ?? FakePhotoCapture()),
          RepositoryProvider<PhotoStore>.value(value: thePhotoStore),
          RepositoryProvider<ReportFont>.value(value: reportFont ?? const FileReportFont()),
          RepositoryProvider<ReportShare>.value(value: reportShare ?? FakeReportShare()),
          RepositoryProvider<LinkShare>.value(value: linkShare ?? FakeLinkShare()),
          RepositoryProvider<ExternalLinks>.value(value: externalLinks ?? FakeExternalLinks()),
          RepositoryProvider<DeleteAllData>.value(
            value:
                deleteAllData ??
                DeleteAllData(
                  publishQueue: theQueue,
                  identity: theIdentity,
                  localData: repositories.localData,
                  photoStore: thePhotoStore,
                ),
          ),
        ],
        child: app,
      ),
    );
  }

  /// Makes the screen 320 logical pixels wide and sets the text to the largest system size, until the test ends.
  ///
  /// A layout that overflows under these conditions fails the test, because the framework reports the overflow as
  /// an error.
  void useNarrowScreenWithLargestText() {
    view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    platformDispatcher.textScaleFactorTestValue = largestSystemTextScale;
    addTearDown(view.reset);
    addTearDown(platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Expects that [text] is on the screen and that every line of it shows: none is cut and none ends in an ellipsis.
  ///
  /// An overflow error does not report text that the framework cuts by design, such as the label of a text field,
  /// so a layout test checks such text with this method.
  void expectWholeText(String text) {
    final paragraphs = renderObjectList<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    expect(paragraphs, isNotEmpty, reason: '"$text" is not on the screen');
    for (final paragraph in paragraphs) {
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" is cut');
    }
  }
}
