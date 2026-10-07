// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';

import '../../../helpers/helpers.dart';

class _MockVisitReportCubit extends MockCubit<VisitReportState> implements VisitReportCubit;

class _MockReportLinkCubit extends MockCubit<ReportLinkState> implements ReportLinkCubit;

void main() {
  const visitId = 'visit-1';
  final client = Client(id: 'client-1', name: '행복빌딩', createdAt: DateTime.utc(2026, 9));
  final beforePhoto = PhotoRef('photos/visit-1/before.jpg');
  final afterPhoto = PhotoRef('photos/visit-1/after.jpg');
  const beforeFile = '/documents/photos/visit-1/before.jpg';
  const afterFile = '/documents/photos/visit-1/after.jpg';

  Visit visitWith(List<ZoneRecord> records) => Visit(
    id: visitId,
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 1),
    zoneRecords: records,
  );

  /// A visit with one zone for each case: both photos, the before photo alone, the after photo alone, a note
  /// alone, and nothing.
  final current = visitWith([
    ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: beforePhoto, afterPhoto: afterPhoto, note: ' 바닥 왁스 '),
    ZoneRecord(zoneId: 'zone-2', zoneName: '복도', beforePhoto: beforePhoto),
    ZoneRecord(zoneId: 'zone-3', zoneName: '화장실', afterPhoto: afterPhoto),
    ZoneRecord(zoneId: 'zone-4', zoneName: '탕비실', note: '공사 중'),
    ZoneRecord(zoneId: 'zone-5', zoneName: '창고'),
  ]);

  /// A visit whose zones all have both photos.
  final complete = visitWith([
    ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: beforePhoto, afterPhoto: afterPhoto, note: '바닥 왁스'),
  ]);

  late FakeVisitRepository visits;
  late FakeCompanyProfileRepository companyProfile;
  late FakePhotoStore photoStore;
  late FakeReportShare reportShare;
  late FakePublishRepository publishing;
  late FakeLinkShare linkShare;

  /// Makes the screen as wide as a phone and tall enough for the whole report of [current], until the test ends.
  void useTallPhoneScreen(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(400, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Opens the report screen from a host screen, so that the report screen can close.
  ///
  /// The screen is a tall phone unless [keepScreen] is true, which a test sets after it chose the screen itself.
  Future<void> pumpPage(
    WidgetTester tester, {
    Visit? visit,
    String? companyName = '깔끔클린',
    String companyPhone = '',
    Locale? locale,
    Exception? loadFailure,
    bool keepScreen = false,
    FakePublisher? publisher,
    Identity? identity,
  }) async {
    if (!keepScreen) useTallPhoneScreen(tester);
    visits = FakeVisitRepository(visits: [visit ?? current])..failure = loadFailure;
    companyProfile = FakeCompanyProfileRepository(
      profile: companyName == null ? null : CompanyProfile(name: companyName, phone: companyPhone),
    );
    photoStore = FakePhotoStore();
    reportShare = FakeReportShare();
    linkShare = FakeLinkShare();
    final repositories = Repositories(
      clients: FakeClientRepository(clients: [client]),
      visits: visits,
      companyProfile: companyProfile,
      publishing: publishing,
      openCaptures: FakeOpenCaptureRepository(),
      localData: FakeLocalDataRepository(),
    );
    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(VisitReportPage.route(visitId: visitId)),
            child: const Text('host'),
          ),
        ),
      ),
      locale: locale,
      repositories: repositories,
      // The queue has no backend unless the test gives one, as in the development and staging flavors.
      publishQueue: publishQueueOf(repositories, publisher: publisher, photoStore: photoStore),
      photoStore: photoStore,
      reportShare: reportShare,
      linkShare: linkShare,
      identity: identity,
    );
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();
  }

  setUp(() => publishing = FakePublishRepository());

  Finder shareButton([String label = 'Share PDF']) => find.widgetWithText(FilledButton, label);

  bool isEnabled(WidgetTester tester, Finder button) => tester.widget<FilledButton>(button).onPressed != null;

  /// Scrolls the report until [text] is on the screen.
  Future<void> scrollTo(WidgetTester tester, String text) => tester.scrollUntilVisible(
    find.text(text),
    100,
    scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
  );

  group('VisitReportPage', () {
    for (final (locale, beforeCaption, afterCaption) in [
      (const Locale('en'), 'Captured 09:12', 'Captured 09:41'),
      (const Locale('ko'), '촬영 09:12', '촬영 09:41'),
    ]) {
      testWidgets('shows observed camera times in preview and PDF in ${locale.languageCode}', (tester) async {
        final visit = visitWith([
          ZoneRecord(
            zoneId: 'zone-1',
            zoneName: 'Lobby',
            beforePhoto: beforePhoto,
            afterPhoto: afterPhoto,
            beforePhotoSource: PhotoSource.camera,
            afterPhotoSource: PhotoSource.camera,
            beforeCapturedAt: DateTime(2026, 10, 7, 9, 12).toUtc(),
            afterCapturedAt: DateTime(2026, 10, 7, 9, 41).toUtc(),
          ),
        ]);
        tester.useNarrowScreenWithLargestText();
        await pumpPage(tester, visit: visit, locale: locale, keepScreen: true);
        await scrollTo(tester, beforeCaption);
        tester.expectWholeText(beforeCaption);
        await scrollTo(tester, afterCaption);
        tester.expectWholeText(afterCaption);
        final button = locale.languageCode == 'ko' ? 'PDF로 공유하기' : 'Share PDF';
        await scrollTo(tester, button);
        await tester.tap(shareButton(button));
        await tester.pumpAndSettle();
        final text = PdfSummary.read(reportShare.shared.single.bytes).text;
        expect(text, contains(beforeCaption));
        expect(text, contains(afterCaption));
      });
    }

    testWidgets('marks gallery provenance in preview and shared PDF', (tester) async {
      final visit = visitWith([
        ZoneRecord(
          zoneId: 'zone-1',
          zoneName: 'Lobby',
          beforePhoto: beforePhoto,
          afterPhoto: afterPhoto,
          beforePhotoSource: PhotoSource.gallery,
          afterPhotoSource: PhotoSource.gallery,
        ),
      ]);
      await pumpPage(tester, visit: visit);
      expect(find.text('Selected from gallery'), findsNWidgets(2));
      await tester.tap(shareButton());
      await tester.pumpAndSettle();
      expect(PdfSummary.read(reportShare.shared.single.bytes).text, contains('Selected from gallery'));
    });
    testWidgets('shows the optional phone in the preview and PDF', (tester) async {
      await pumpPage(tester, visit: complete, companyPhone: '02-1234-5678');
      expect(find.text('02-1234-5678'), findsOneWidget);
      await tester.tap(shareButton());
      await tester.pumpAndSettle();
      expect(PdfSummary.read(reportShare.shared.single.bytes).text, contains('02-1234-5678'));
    });

    testWidgets('renders VisitReportView with a preview of the report: the names, the date, and each zone', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.byType(VisitReportView), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Report'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      for (final text in ['깔끔클린', 'Cleaning Report', '행복빌딩', 'October 1, 2026', 'Report made with Kkomkkomi']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      // The zones are in the order of the visit, and the zone without a photo and a note is left out.
      final zoneNames = ['로비', '복도', '화장실', '탕비실'];
      for (final name in zoneNames) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('창고'), findsNothing);
      final tops = [for (final name in zoneNames) tester.getTopLeft(find.text(name)).dy];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(tester.getTopLeft(find.text('깔끔클린')).dy, lessThan(tester.getTopLeft(find.text('Cleaning Report')).dy));
    });

    testWidgets('leaves the footer text out of the preview and of the PDF for a user with a paid entitlement', (
      tester,
    ) async {
      final identity = FakeIdentity()..paid = true;
      await pumpPage(tester, visit: complete, identity: identity);

      expect(find.text('Cleaning Report'), findsOneWidget);
      expect(find.text('Report made with Kkomkkomi'), findsNothing);

      await tester.tap(shareButton());
      await tester.pumpAndSettle();

      final summary = PdfSummary.read(reportShare.shared.single.bytes);
      expect(summary.pages.single.text, startsWith('1 / 1 '));
      expect(summary.text, isNot(contains('Report made with Kkomkkomi')));
      expect(identity.paidChecks, 1);
    });

    testWidgets('shows each photo in its slot, an empty slot for a photo that a zone lacks, and the notes', (
      tester,
    ) async {
      await pumpPage(tester);

      // 로비 has both photos, 복도 the before photo, and 화장실 the after photo.
      expect(tester.photoPathsIn(find.byType(VisitReportView)), [beforeFile, afterFile, beforeFile, afterFile]);
      // The PDF prints the whole photo, so the preview cuts nothing of it.
      for (final thumbnail in tester.widgetList<PhotoThumbnail>(find.byType(PhotoThumbnail))) {
        expect(thumbnail.fit, BoxFit.contain);
      }
      expect(find.text('Before'), findsNWidgets(4));
      expect(find.text('After'), findsNWidgets(4));
      // 복도 and 화장실 each have one empty slot, and 탕비실 has two.
      expect(find.byIcon(Icons.no_photography_outlined), findsNWidgets(4));
      expect(find.text('바닥 왁스'), findsOneWidget);
      expect(find.text('공사 중'), findsOneWidget);
      expect(find.text('Note'), findsNWidgets(2));
    });

    testWidgets('shows the summary, each exception with its reason, the status after the name of an exception, and '
        'the text of the PDF for an empty slot to a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(
        tester,
        visit: visitWith([
          ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: beforePhoto, afterPhoto: afterPhoto),
          ZoneRecord(
            zoneId: 'zone-2',
            zoneName: '탕비실',
            beforePhoto: beforePhoto,
            status: ZoneStatus.partlyDone,
            reason: '전자레인지는 다음 방문에',
          ),
          ZoneRecord(zoneId: 'zone-3', zoneName: '창고', status: ZoneStatus.notDone),
        ]),
      );

      expect(find.text('1 of 3 zones done'), findsOneWidget);
      expect(find.text('탕비실 · Partly done: 전자레인지는 다음 방문에'), findsOneWidget);
      expect(find.text('창고 · Not done'), findsOneWidget);
      // The badge after the name of each exception, and none for the done zone.
      expect(find.text('Partly done'), findsOneWidget);
      expect(find.text('Not done'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Not photographed')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Not done')), findsNWidgets(3));
      semantics.dispose();
    });

    testWidgets('shows no summary for a report without a zone', (tester) async {
      await pumpPage(
        tester,
        visit: visitWith([ZoneRecord(zoneId: 'zone-1', zoneName: '로비')]),
      );

      expect(find.textContaining('zones done'), findsNothing);
    });

    testWidgets('puts the before slot of a zone left of its after slot, each in the ratio of a slot of the PDF', (
      tester,
    ) async {
      await pumpPage(
        tester,
        visit: visitWith([ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: beforePhoto)]),
      );

      expect(tester.getTopLeft(find.text('Before')).dx, lessThan(tester.getTopLeft(find.text('After')).dx));
      expect(tester.getTopLeft(find.text('Before')).dy, tester.getTopLeft(find.text('After')).dy);
      expect(reportSlotAspectRatio, 1);
      final photo = tester.getSize(find.byType(PhotoThumbnail));
      final empty = tester.getSize(
        find.ancestor(of: find.byIcon(Icons.no_photography_outlined), matching: find.byType(ColoredBox)).first,
      );
      expect(photo.width / photo.height, moreOrLessEquals(1, epsilon: 0.01));
      expect(empty, photo);
    });

    testWidgets('puts a photo on white inside an edge, and keeps the grey of a slot without a photo apart from it', (
      tester,
    ) async {
      await pumpPage(
        tester,
        visit: visitWith([ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: beforePhoto)]),
      );

      final colorScheme = Theme.of(tester.element(find.byType(PhotoThumbnail))).colorScheme;
      final ground = tester.widget<ColoredBox>(
        find.ancestor(of: find.byType(PhotoThumbnail), matching: find.byType(ColoredBox)).first,
      );
      expect(ground.color, colorScheme.surfaceContainerLowest);
      final edge = tester.widget<DecoratedBox>(
        find.ancestor(of: find.byType(PhotoThumbnail), matching: find.byType(DecoratedBox)).first,
      );
      expect((edge.decoration as BoxDecoration).border, Border.all(color: colorScheme.outlineVariant));
      // The edge is painted over the photo, which reaches two sides of the square slot and would hide them.
      expect(edge.position, DecorationPosition.foreground);
      final emptySlot = tester.widget<ColoredBox>(
        find.ancestor(of: find.byIcon(Icons.no_photography_outlined), matching: find.byType(ColoredBox)).first,
      );
      expect(emptySlot.color, colorScheme.surfaceContainerHighest);
      expect(emptySlot.color, isNot(ground.color));
    });

    testWidgets('gives a screen reader each slot with its label, and each note with its label, as one node', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(tester);

      // 로비 has both photos, and 복도 lacks the after photo.
      final lobbyBefore = tester.getSemantics(find.byType(PhotoThumbnail).first);
      expect(lobbyBefore.label, 'Before');
      expect(lobbyBefore.flagsCollection.isImage, isTrue);
      final hallAfter = tester.getSemantics(find.byIcon(Icons.no_photography_outlined).first);
      expect(hallAfter.label, 'After\nNot photographed');
      expect(hallAfter.flagsCollection.isImage, isFalse);
      expect(tester.getSemantics(find.text('바닥 왁스')).label, 'Note\n바닥 왁스');
      semantics.dispose();
    });

    testWidgets('gives a screen reader the heading of each part and the name of each zone as a header', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(tester);

      for (final header in ['Some zones are missing photos', 'Preview', '로비', '복도', '화장실', '탕비실']) {
        expect(tester.getSemantics(find.text(header)).flagsCollection.isHeader, isTrue, reason: header);
      }
      expect(tester.getSemantics(find.text('바닥 왁스')).flagsCollection.isHeader, isFalse);
      semantics.dispose();
    });

    group('zones that lack a photo', () {
      testWidgets('lists each zone with what it lacks, in the order of the visit, above the preview', (tester) async {
        await pumpPage(tester);

        expect(find.text('Some zones are missing photos'), findsOneWidget);
        expect(find.text('The report shows an empty slot where a photo is missing.'), findsOneWidget);
        final items = [
          '복도: after photo',
          '화장실: before photo',
          '탕비실: before photo and after photo',
          '창고: not in the report, because it has no photo and no note.',
        ];
        for (final item in items) {
          expect(find.text(item), findsOneWidget, reason: item);
        }
        final tops = [for (final item in items) tester.getTopLeft(find.text(item)).dy];
        expect(tops, orderedEquals([...tops]..sort()));
        expect(tops.last, lessThan(tester.getTopLeft(find.text('Preview')).dy));
        expect(find.textContaining('로비:'), findsNothing);
      });

      testWidgets('shows no list when every zone has both photos', (tester) async {
        await pumpPage(tester, visit: complete);

        expect(find.text('Some zones are missing photos'), findsNothing);
        expect(find.text('Preview'), findsOneWidget);
      });

      testWidgets('does not block the share', (tester) async {
        await pumpPage(tester);

        await tester.tap(shareButton());
        await tester.pumpAndSettle();

        expect(reportShare.shared, hasLength(1));
      });
    });

    group('company name', () {
      testWidgets('asks for the company name when none is saved, and leaves the company line out of the preview', (
        tester,
      ) async {
        await pumpPage(tester, companyName: null);

        expect(find.text('No company name yet. Add one, and the report shows it at the top.'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Add Company Name'), findsOneWidget);
        expect(find.text('깔끔클린'), findsNothing);
        expect(find.text('Cleaning Report'), findsOneWidget);
      });

      testWidgets('asks for nothing when a company name is saved', (tester) async {
        await pumpPage(tester);

        expect(find.widgetWithText(TextButton, 'Add Company Name'), findsNothing);
      });

      testWidgets('shares the report without the company name', (tester) async {
        await pumpPage(tester, companyName: null);

        expect(isEnabled(tester, shareButton()), isTrue);
        await tester.tap(shareButton());
        await tester.pumpAndSettle();

        expect(reportShare.shared, hasLength(1));
        final summary = PdfSummary.read(reportShare.shared.single.bytes);
        expect(summary.text, contains('Cleaning Report'));
        expect(summary.text, isNot(contains('깔끔클린')));
      });

      testWidgets('opens the company profile, and shows the name that the person saved there on the way back', (
        tester,
      ) async {
        await pumpPage(tester, companyName: null);

        await tester.tap(find.widgetWithText(TextButton, 'Add Company Name'));
        await tester.pumpAndSettle();
        expect(find.byType(CompanyProfilePage), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, '새로클린');
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(CompanyProfilePage), findsNothing);
        expect(find.widgetWithText(TextButton, 'Add Company Name'), findsNothing);
        expect(find.text('새로클린'), findsOneWidget);
      });

      testWidgets('keeps asking when the person comes back without a saved name', (tester) async {
        await pumpPage(tester, companyName: null);

        await tester.tap(find.widgetWithText(TextButton, 'Add Company Name'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextButton, 'Add Company Name'), findsOneWidget);
      });
    });

    group('share', () {
      testWidgets('gives the share sheet the PDF of the report, named after the client and the date', (tester) async {
        await pumpPage(tester, visit: complete);

        await tester.tap(shareButton());
        await tester.pumpAndSettle();

        final shared = reportShare.shared.single;
        expect(shared.fileName, 'Cleaning Report_행복빌딩_2026-10-01.pdf');
        final summary = PdfSummary.read(shared.bytes);
        expect(summary.pageCount, 1);
        expect(summary.pages.single.images, hasLength(2));
        expect(summary.pages.single.text, startsWith('Report made with Kkomkkomi 1 / 1 '));
        expect(
          summary.text,
          stringContainsInOrder(['Report made with Kkomkkomi', '깔끔클린', 'Cleaning Report', '행복빌딩', 'October 1, 2026']),
        );
        expect(summary.text, stringContainsInOrder(['로비', 'Before', 'After', 'Note', '바닥 왁스']));
        expect(photoStore.readPhotos, [beforePhoto, afterPhoto]);
        expect(find.byType(SnackBar), findsNothing);
        expect(isEnabled(tester, shareButton()), isTrue);
      });

      testWidgets('names the file in Korean under the Korean locale', (tester) async {
        await pumpPage(tester, visit: complete, locale: const Locale('ko'));

        await tester.tap(shareButton('PDF로 공유하기'));
        await tester.pumpAndSettle();

        expect(reportShare.shared.single.fileName, '청소 완료 보고서_행복빌딩_2026-10-01.pdf');
      });

      testWidgets('shows a message when the share fails, and shares on the next try', (tester) async {
        await pumpPage(tester, visit: complete);
        reportShare.failure = const ReportShareException();

        await tester.tap(shareButton());
        await tester.pumpAndSettle();
        expect(find.widgetWithText(SnackBar, "Can't share the report right now. Try again."), findsOneWidget);
        expect(reportShare.shared, isEmpty);

        reportShare.failure = null;
        await tester.tap(shareButton());
        await tester.pumpAndSettle();

        expect(reportShare.shared, hasLength(1));
      });

      testWidgets('shows the message of a second failed share in place of the first, and not after it', (tester) async {
        await pumpPage(tester, visit: complete);
        reportShare.failure = const ReportShareException();

        await tester.tap(shareButton());
        await tester.pumpAndSettle();
        await tester.tap(shareButton());
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);

        // A message stays four seconds. A second message that waited for the first would be on the screen now.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('shows a message when a photo file does not read', (tester) async {
        await pumpPage(tester, visit: complete);
        photoStore.readFailure = Exception('The file is gone');

        await tester.tap(shareButton());
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SnackBar, "Can't share the report right now. Try again."), findsOneWidget);
        expect(reportShare.shared, isEmpty);
        expect(isEnabled(tester, shareButton()), isTrue);
      });

      testWidgets('takes no touch and no back press while the PDF is on its way to the share sheet', (tester) async {
        await pumpPage(tester, visit: complete, companyName: null);
        reportShare.gate = Completer<void>();

        // The progress indicator of the share control never settles, so each step pumps a second, which is
        // longer than a route takes to open or to close.
        await tester.tap(shareButton());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.descendant(of: find.byType(FilledButton), matching: find.byType(CircularProgressIndicator)),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Add Company Name'), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(CompanyProfilePage), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(VisitReportPage), findsOneWidget);

        reportShare.gate!.complete();
        await tester.pumpAndSettle();

        expect(reportShare.shared, hasLength(1));
        expect(shareButton(), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(VisitReportPage), findsNothing);
      });
    });

    group('link share', () {
      const notice =
          'Anyone who has the link can open the reports of this client without signing in. '
          'Send it only to the people who receive the reports.';
      Finder linkButton([String label = 'Share link']) => find.widgetWithText(FilledButton, label);
      Finder pdfButton([String label = 'Share PDF']) => find.widgetWithText(OutlinedButton, label);

      testWidgets('offers the link first and the PDF under it in a flavor with a backend', (tester) async {
        await pumpPage(tester, publisher: FakePublisher());

        expect(isEnabled(tester, linkButton()), isTrue);
        expect(tester.widget<OutlinedButton>(pdfButton()).onPressed, isNotNull);
        expect(tester.getTopLeft(linkButton()).dy, lessThan(tester.getTopLeft(pdfButton()).dy));
      });

      testWidgets('offers the PDF alone in a flavor without a backend', (tester) async {
        await pumpPage(tester);

        expect(find.text('Share link'), findsNothing);
        expect(isEnabled(tester, shareButton()), isTrue);
      });

      testWidgets('says before the first link of a client that anyone with the link can open the reports, and '
          'publishes nothing when the person closes the notice', (tester) async {
        final publisher = FakePublisher();
        await pumpPage(tester, publisher: publisher);

        await tester.tap(linkButton());
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AlertDialog, 'Share a link?'), findsOneWidget);
        expect(find.text(notice), findsOneWidget);
        // The notice warns, and the share deletes nothing, so its question is not destructive.
        expect(tester.filledButtonColor('Share'), appTheme().colorScheme.primary);

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(publishing.jobs, isEmpty);
        expect(publisher.calls, isEmpty);
        expect(linkShare.shared, isEmpty);
      });

      testWidgets('publishes the visit after the notice, and then shares the link of its report', (tester) async {
        final publisher = FakePublisher();
        await pumpPage(tester, publisher: publisher);

        await tester.tap(linkButton());
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Share'));
        await tester.pumpAndSettle();

        final page = publishing.pagesById.values.single;
        expect(publisher.reports.keys, ['${page.id}/$visitId']);
        expect(linkShare.shared, [Uri.parse('https://kkomkkomi.web.app/r/${page.id}/$visitId')]);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('shares without the notice when the client has a page', (tester) async {
        final page = ClientPage(id: 'page-1', clientId: client.id, createdAt: DateTime.utc(2026, 10));
        publishing.pagesById[page.id] = page;
        await pumpPage(tester, publisher: FakePublisher());

        await tester.tap(linkButton());
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(linkShare.shared, [Uri.parse('https://kkomkkomi.web.app/r/page-1/$visitId')]);
      });

      testWidgets('shows that the report uploads while the job runs, and takes no second press', (tester) async {
        final publisher = FakePublisher();
        final gate = Completer<void>();
        publisher.gates['writeReport'] = gate;
        publishing.pagesById['page-1'] = ClientPage(
          id: 'page-1',
          clientId: client.id,
          createdAt: DateTime.utc(2026, 10),
        );
        await pumpPage(tester, publisher: publisher);

        await tester.tap(linkButton());
        await tester.pump();

        expect(find.text("Uploading the report. The share sheet opens when it's done."), findsOneWidget);
        final button = find.ancestor(of: find.byType(CircularProgressIndicator), matching: find.byType(FilledButton));
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        // The PDF does not wait for the link.
        expect(tester.widget<OutlinedButton>(pdfButton()).onPressed, isNotNull);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text("Uploading the report. The share sheet opens when it's done."), findsNothing);
        expect(linkShare.shared, hasLength(1));
      });

      testWidgets('opens no share sheet over another screen, and shares on the next press', (tester) async {
        final publisher = FakePublisher();
        final gate = Completer<void>();
        publisher.gates['writeReport'] = gate;
        publishing.pagesById['page-1'] = ClientPage(
          id: 'page-1',
          clientId: client.id,
          createdAt: DateTime.utc(2026, 10),
        );
        await pumpPage(tester, companyName: null, publisher: publisher);

        await tester.tap(linkButton());
        await tester.pump();
        await tester.tap(find.text('Add Company Name'));
        await tester.pumpAndSettle();
        expect(find.byType(CompanyProfilePage), findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
        expect(linkShare.shared, isEmpty);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('The report is uploaded. Press Share link to open the share sheet.'), findsOneWidget);
        await tester.tap(linkButton());
        await tester.pumpAndSettle();

        expect(linkShare.shared, [Uri.parse('https://kkomkkomi.web.app/r/page-1/$visitId')]);
        // The second press published the visit again, with the page as it is now.
        expect(publisher.calls.where((call) => call == 'writePage page-1'), hasLength(2));
      });

      testWidgets('opens no share sheet of the link while the share sheet of the PDF is on its way', (tester) async {
        final publisher = FakePublisher();
        final uploadGate = Completer<void>();
        publisher.gates['writeReport'] = uploadGate;
        publishing.pagesById['page-1'] = ClientPage(
          id: 'page-1',
          clientId: client.id,
          createdAt: DateTime.utc(2026, 10),
        );
        await pumpPage(tester, publisher: publisher);
        final pdfGate = Completer<void>();
        reportShare.gate = pdfGate;

        await tester.tap(linkButton());
        await tester.pump();
        await tester.tap(pdfButton());
        await tester.pump();
        uploadGate.complete();
        await tester.pump();
        pdfGate.complete();
        await tester.pumpAndSettle();

        expect(reportShare.shared, hasLength(1));
        expect(linkShare.shared, isEmpty);
        expect(find.text('The report is uploaded. Press Share link to open the share sheet.'), findsOneWidget);
      });

      testWidgets('shows why the upload stopped, and shares nothing', (tester) async {
        final publisher = FakePublisher();
        publisher.failures['writePage'] = [const PublishException(PublishErrorKind.refused, 'permission-denied')];
        publishing.pagesById['page-1'] = ClientPage(
          id: 'page-1',
          clientId: client.id,
          createdAt: DateTime.utc(2026, 10),
        );
        await pumpPage(tester, publisher: publisher);

        await tester.tap(linkButton());
        await tester.pumpAndSettle();

        expect(find.text("Can't upload the report. You can share the PDF for now."), findsOneWidget);
        expect(isEnabled(tester, linkButton()), isTrue);
        expect(linkShare.shared, isEmpty);
      });

      testWidgets('shows a message when the share sheet does not open with the link', (tester) async {
        publishing.pagesById['page-1'] = ClientPage(
          id: 'page-1',
          clientId: client.id,
          createdAt: DateTime.utc(2026, 10),
        );
        await pumpPage(tester, publisher: FakePublisher());
        linkShare.failure = const ReportShareException();

        await tester.tap(linkButton());
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SnackBar, "Can't share the report right now. Try again."), findsOneWidget);
      });

      testWidgets('offers no link when no zone has a photo or a note', (tester) async {
        await pumpPage(
          tester,
          visit: visitWith([ZoneRecord(zoneId: 'zone-1', zoneName: '로비')]),
          publisher: FakePublisher(),
        );

        expect(isEnabled(tester, linkButton()), isFalse);
      });
    });

    testWidgets('says so and offers no share when no zone has a photo or a note', (tester) async {
      await pumpPage(
        tester,
        visit: visitWith([ZoneRecord(zoneId: 'zone-1', zoneName: '로비'), ZoneRecord(zoneId: 'zone-2', zoneName: '복도')]),
      );

      expect(
        find.text(
          'Nothing to put in the report yet. Take a photo or write a note on the visit screen, and it shows here.',
        ),
        findsOneWidget,
      );
      expect(find.text('로비: not in the report, because it has no photo and no note.'), findsOneWidget);
      expect(isEnabled(tester, shareButton()), isFalse);
      await tester.tap(shareButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(reportShare.shared, isEmpty);
    });

    testWidgets('shows the screen in Korean, with the footer that the report prints', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'));

      expect(find.widgetWithText(AppBar, '보고서'), findsOneWidget);
      for (final text in [
        '사진이 없는 구역이 있어요',
        '사진이 없는 자리는 보고서에 빈칸으로 나와요.',
        '복도: 청소 후 사진',
        '화장실: 청소 전 사진',
        '탕비실: 청소 전 사진, 청소 후 사진',
        '창고: 사진과 메모가 없어서 보고서에서 빠져요.',
        '미리보기',
        '청소 완료 보고서',
        '2026년 10월 1일',
        '꼼꼬미로 작성됨',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('청소 전'), findsNWidgets(4));
      expect(find.text('청소 후'), findsNWidgets(4));
      expect(find.text('메모'), findsNWidgets(2));
      expect(shareButton('PDF로 공유하기'), findsOneWidget);
    });

    testWidgets('shows a message and a retry control when the report does not load, and loads it on retry', (
      tester,
    ) async {
      await pumpPage(tester, loadFailure: Exception('storage failed'));

      expect(find.text("Can't load this report. Try again."), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(shareButton(), findsNothing);

      visits.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Preview'), findsOneWidget);
      expect(shareButton(), findsOneWidget);
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      const longZoneName = '1층 로비와 엘리베이터 앞 복도';
      const longNote = '바닥 왁스 작업을 마쳤고 유리창은 다음 방문에 닦기로 했어요';
      final longVisit = visitWith([
        ZoneRecord(zoneId: 'zone-1', zoneName: longZoneName, beforePhoto: beforePhoto, note: longNote),
        ZoneRecord(zoneId: 'zone-2', zoneName: '화장실'),
      ]);

      for (final (locale, texts, share) in [
        (
          const Locale('en'),
          [
            'No company name yet. Add one, and the report shows it at the top.',
            'Add Company Name',
            'Some zones are missing photos',
            'The report shows an empty slot where a photo is missing.',
            '$longZoneName: after photo',
            '화장실: not in the report, because it has no photo and no note.',
            'Preview',
            'Cleaning Report',
            '행복빌딩',
            'October 1, 2026',
            longZoneName,
            'Before',
            'After',
            'Note',
            longNote,
            'Report made with Kkomkkomi',
          ],
          'Share PDF',
        ),
        (
          const Locale('ko'),
          [
            '회사 이름이 아직 없어요. 입력하면 보고서 맨 위에 들어가요.',
            '회사 이름 입력하기',
            '사진이 없는 구역이 있어요',
            '사진이 없는 자리는 보고서에 빈칸으로 나와요.',
            '$longZoneName: 청소 후 사진',
            '화장실: 사진과 메모가 없어서 보고서에서 빠져요.',
            '미리보기',
            '청소 완료 보고서',
            '행복빌딩',
            '2026년 10월 1일',
            longZoneName,
            '청소 전',
            '청소 후',
            '메모',
            longNote,
            '꼼꼬미로 작성됨',
          ],
          'PDF로 공유하기',
        ),
      ]) {
        testWidgets('fits the notices, the preview, and the share control in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, visit: longVisit, companyName: null, locale: locale, keepScreen: true);

          tester.expectWholeText(share);
          for (final text in texts) {
            await scrollTo(tester, text);
            tester.expectWholeText(text);
          }
        });
      }

      for (final (locale, share, message) in [
        (const Locale('en'), 'Share PDF', "Can't share the report right now. Try again."),
        (const Locale('ko'), 'PDF로 공유하기', '보고서를 공유하지 못했어요. 다시 시도해 주세요.'),
      ]) {
        testWidgets('fits the message of a failed share in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, visit: longVisit, locale: locale, keepScreen: true);
          reportShare.failure = const ReportShareException();

          await tester.tap(shareButton(share));
          await tester.pumpAndSettle();

          tester.expectWholeText(message);
        });
      }

      for (final (locale, message, retry) in [
        (const Locale('en'), "Can't load this report. Try again.", 'Try Again'),
        (const Locale('ko'), '보고서를 불러오지 못했어요. 다시 시도해 주세요.', '다시 불러오기'),
      ]) {
        testWidgets('fits the message of a failed load in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, locale: locale, loadFailure: Exception('storage failed'), keepScreen: true);

          tester.expectWholeText(message);
          tester.expectWholeText(retry);
        });
      }

      for (final (locale, message) in [
        (
          const Locale('en'),
          'Nothing to put in the report yet. Take a photo or write a note on the visit screen, and it shows here.',
        ),
        (const Locale('ko'), '아직 보고서에 넣을 사진이나 메모가 없어요. 방문 화면에서 사진을 찍거나 메모를 쓰면 여기에 나와요.'),
      ]) {
        testWidgets('fits the message of a report without a zone in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(
            tester,
            visit: visitWith([ZoneRecord(zoneId: 'zone-1', zoneName: '로비')]),
            locale: locale,
            keepScreen: true,
          );

          await scrollTo(tester, message);
          tester.expectWholeText(message);
        });
      }

      for (final (locale, link, title, notice, close, confirm) in [
        (
          const Locale('en'),
          'Share link',
          'Share a link?',
          'Anyone who has the link can open the reports of this client without signing in. '
              'Send it only to the people who receive the reports.',
          'Cancel',
          'Share',
        ),
        (
          const Locale('ko'),
          '링크로 공유하기',
          '링크로 공유할까요?',
          '링크가 있으면 누구나 로그인 없이 이 거래처의 보고서를 볼 수 있어요. 보고서를 받을 분에게만 보내 주세요.',
          '닫기',
          '공유하기',
        ),
      ]) {
        testWidgets('fits the link control and the notice before the first link in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, visit: longVisit, locale: locale, keepScreen: true, publisher: FakePublisher());
          tester.expectWholeText(link);

          await tester.tap(find.text(link));
          await tester.pumpAndSettle();

          for (final text in [title, notice, close, confirm]) {
            await tester.scrollUntilVisible(
              find.text(text),
              100,
              scrollable: find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first,
            );
            tester.expectWholeText(text);
          }
        });
      }
    });
  });

  group('reportLabelsOf', () {
    testWidgets('gives the texts of the report in the language of the app, with the date of the visit', (tester) async {
      await tester.pumpApp(const SizedBox(), locale: const Locale('ko'));
      final l10n = tester.element(find.byType(SizedBox)).l10n;

      final labels = reportLabelsOf(l10n, VisitDate(2026, 10, 1));

      expect(labels.title, '청소 완료 보고서');
      expect(labels.visitDate, '2026년 10월 1일');
      expect(labels.beforePhoto, '청소 전');
      expect(labels.afterPhoto, '청소 후');
      expect(labels.notPhotographed, '촬영하지 않음');
      expect(labels.partlyDone, '일부 완료');
      expect(labels.notDone, '못 함');
      expect(labels.summaryOf(4, 5), '5곳 중 4곳 완료');
      expect(labels.note, '메모');
      expect(labels.footer, '꼼꼬미로 작성됨');
    });
  });

  group('VisitReportView', () {
    late VisitReportCubit cubit;

    VisitReportState shown(VisitReportStatus status, {Visit? visit}) => VisitReportState(
      status: status,
      document: ReportDocument.fromVisit(
        visit: visit ?? complete,
        client: client,
        companyProfile: CompanyProfile(name: '깔끔클린'),
      ),
      photoDirectory: FakePhotoStore.directory,
    );

    setUpAll(
      () => registerFallbackValue(
        ReportLabels(
          title: '',
          clientHeading: '',
          visitDateHeading: '',
          visitDate: '',
          beforePhoto: '',
          afterPhoto: '',
          notPhotographed: '',
          partlyDone: '',
          notDone: '',
          summaryOf: (_, _) => '',
          note: '',
          footer: '',
          galleryPhoto: '',
          captureTimeOf: (_) => '',
        ),
      ),
    );

    late ReportLinkCubit linkCubit;

    setUp(() {
      cubit = _MockVisitReportCubit();
      linkCubit = _MockReportLinkCubit();
      when(() => linkCubit.state).thenReturn(const ReportLinkState(status: ReportLinkStatus.unavailable));
    });

    /// Pumps the view under [cubit] and [linkCubit].
    Future<void> pumpCubits(WidgetTester tester) => tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<VisitReportCubit>.value(value: cubit),
          BlocProvider<ReportLinkCubit>.value(value: linkCubit),
        ],
        child: const VisitReportView(),
      ),
    );

    Future<void> pumpView(WidgetTester tester, VisitReportState state) async {
      useTallPhoneScreen(tester);
      when(() => cubit.state).thenReturn(state);
      await pumpCubits(tester);
    }

    testWidgets('shows a progress indicator and no share control while the report loads', (tester) async {
      await pumpView(tester, const VisitReportState());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.widgetWithText(AppBar, 'Report'), findsOneWidget);
    });

    testWidgets('passes a share to the cubit with the texts of the report', (tester) async {
      when(() => cubit.share(any())).thenAnswer((_) async {});
      await pumpView(tester, shown(VisitReportStatus.ready));

      await tester.tap(shareButton());

      final labels = verify(() => cubit.share(captureAny())).captured.single as ReportLabels;
      expect(labels.title, 'Cleaning Report');
      expect(labels.visitDate, 'October 1, 2026');
      expect(labels.beforePhoto, 'Before');
      expect(labels.afterPhoto, 'After');
      expect(labels.notPhotographed, 'Not photographed');
      expect(labels.partlyDone, 'Partly done');
      expect(labels.notDone, 'Not done');
      expect(labels.summaryOf(4, 5), '4 of 5 zones done');
      expect(labels.note, 'Note');
      expect(labels.footer, 'Report made with Kkomkkomi');
    });

    testWidgets('keeps the report and a share control on the screen after a failed share', (tester) async {
      await pumpView(tester, shown(VisitReportStatus.shareFailed));

      expect(find.text('Cleaning Report'), findsOneWidget);
      expect(isEnabled(tester, shareButton()), isTrue);
    });

    testWidgets('shows a progress indicator in the share control and takes no press while a share is on its way', (
      tester,
    ) async {
      await pumpView(tester, shown(VisitReportStatus.sharing));

      expect(find.text('Cleaning Report'), findsOneWidget);
      expect(find.text('Share PDF'), findsNothing);
      expect(isEnabled(tester, find.byType(FilledButton)), isFalse);
      expect(
        find.descendant(of: find.byType(FilledButton), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
    });

    testWidgets('keeps the name of the share control for a screen reader while a share is on its way', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpView(tester, shown(VisitReportStatus.sharing));

      expect(tester.getSemantics(find.byType(FilledButton)).label, 'Share PDF');
      semantics.dispose();
    });

    testWidgets('shows the message of a failed share once, when the status changes to it', (tester) async {
      final states = StreamController<VisitReportState>();
      addTearDown(states.close);
      whenListen(cubit, states.stream, initialState: shown(VisitReportStatus.sharing));
      useTallPhoneScreen(tester);
      await pumpCubits(tester);

      states.add(shown(VisitReportStatus.shareFailed));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SnackBar, "Can't share the report right now. Try again."), findsOneWidget);

      // A second state with the same status, which differs in another field, shows no second message.
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      states.add(shown(VisitReportStatus.shareFailed, visit: current));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    group('link share', () {
      /// What the screen says in each state of the link share, in English and in Korean.
      final messages = <ReportLinkState, (String, String)>{
        const ReportLinkState(status: ReportLinkStatus.publishing): (
          "Uploading the report. The share sheet opens when it's done.",
          '보고서를 올리고 있어요. 다 올리면 공유 창이 열려요.',
        ),
        const ReportLinkState(status: ReportLinkStatus.waitingForRetry): (
          "Can't upload the report yet. It tries again soon, and the share sheet opens when it's done.",
          '아직 보고서를 올리지 못했어요. 잠시 뒤에 다시 올리고, 다 올리면 공유 창이 열려요.',
        ),
        for (final failure in [null, PublishFailure.refused, PublishFailure.unavailable])
          ReportLinkState(status: ReportLinkStatus.failed, failure: failure): (
            "Can't upload the report. You can share the PDF for now.",
            '보고서를 올리지 못했어요. 지금은 PDF로 공유할 수 있어요.',
          ),
        const ReportLinkState(status: ReportLinkStatus.failed, failure: PublishFailure.revoked): (
          'The link of this client changed during the upload. Try again.',
          '올리는 동안 이 거래처의 링크가 바뀌었어요. 다시 시도해 주세요.',
        ),
        const ReportLinkState(status: ReportLinkStatus.failed, failure: PublishFailure.deletion): (
          'The upload stopped because you started to delete all data. Press Share link again to upload it.',
          '모든 데이터 지우기를 시작해서 보고서 올리기를 멈췄어요. 링크로 공유하기를 다시 누르면 다시 올려요.',
        ),
        const ReportLinkState(status: ReportLinkStatus.failed, failure: PublishFailure.photoMissing): (
          'A photo of this visit is missing. Retake it on the visit screen, then try again.',
          '이 방문의 사진 파일을 찾지 못했어요. 방문 화면에서 사진을 다시 찍은 뒤 다시 시도해 주세요.',
        ),
        const ReportLinkState(status: ReportLinkStatus.published): (
          'The report is uploaded. Press Share link to open the share sheet.',
          '보고서를 올렸어요. 링크로 공유하기를 누르면 공유 창이 열려요.',
        ),
        for (final failure in [PublishFailure.photoNotJpeg, PublishFailure.photoTooLarge])
          ReportLinkState(status: ReportLinkStatus.failed, failure: failure): (
            "A photo of this visit can't be uploaded. Retake it on the visit screen, then try again.",
            '올릴 수 없는 사진이 있어요. 방문 화면에서 사진을 다시 찍은 뒤 다시 시도해 주세요.',
          ),
      };

      for (final MapEntry(key: linkState, value: (english, _)) in messages.entries) {
        testWidgets('says "$english" for $linkState', (tester) async {
          when(() => linkCubit.state).thenReturn(linkState);

          await pumpView(tester, shown(VisitReportStatus.ready));

          expect(find.text(english), findsOneWidget);
          // Only a job that stopped is a failure. One that waits for its next try is still on its way.
          expect(
            tester.noticeToneOf(english),
            linkState.status == ReportLinkStatus.failed ? NoticeTone.error : NoticeTone.info,
          );
        });
      }

      testWidgets('keeps the name of the link control for a screen reader while the report uploads', (tester) async {
        final semantics = tester.ensureSemantics();
        when(() => linkCubit.state).thenReturn(const ReportLinkState(status: ReportLinkStatus.publishing));

        await pumpView(tester, shown(VisitReportStatus.ready));

        expect(find.text('Share link'), findsNothing);
        expect(tester.getSemantics(find.byType(FilledButton)).label, 'Share link');
        semantics.dispose();
      });

      for (final linkState in const [
        ReportLinkState(),
        ReportLinkState(status: ReportLinkStatus.ready),
        ReportLinkState(status: ReportLinkStatus.shareFailed),
      ]) {
        testWidgets('says nothing about the link for $linkState', (tester) async {
          when(() => linkCubit.state).thenReturn(linkState);

          await pumpView(tester, shown(VisitReportStatus.ready));

          final bar = find.ancestor(of: find.text('Share link'), matching: find.byType(Column)).first;
          expect(find.descendant(of: bar, matching: find.byType(KeepAllText)), findsNWidgets(2));
        });
      }

      testWidgets('passes a press to the cubit, which may open the share sheet while the screen is on top', (
        tester,
      ) async {
        when(() => linkCubit.state).thenReturn(const ReportLinkState(status: ReportLinkStatus.ready));
        when(
          () => linkCubit.share(mayOpenShareSheet: any(named: 'mayOpenShareSheet')),
        ).thenAnswer((_) async {});
        await pumpView(tester, shown(VisitReportStatus.ready));

        await tester.tap(find.widgetWithText(FilledButton, 'Share link'));
        await tester.pumpAndSettle();

        final mayOpen =
            verify(
                  () => linkCubit.share(mayOpenShareSheet: captureAny(named: 'mayOpenShareSheet')),
                ).captured.single
                as bool Function();
        expect(mayOpen(), isTrue);

        // A share of the PDF on its way keeps the share sheet of the link closed.
        when(() => cubit.state).thenReturn(shown(VisitReportStatus.sharing));
        expect(mayOpen(), isFalse);
      });

      testWidgets('shows the message of a link that did not reach the share sheet once', (tester) async {
        final states = StreamController<ReportLinkState>();
        addTearDown(states.close);
        whenListen(linkCubit, states.stream, initialState: const ReportLinkState(status: ReportLinkStatus.publishing));
        await pumpView(tester, shown(VisitReportStatus.ready));

        states.add(const ReportLinkState(status: ReportLinkStatus.shareFailed));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(SnackBar, "Can't share the report right now. Try again."), findsOneWidget);

        ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        states.add(const ReportLinkState(status: ReportLinkStatus.shareFailed, isFirstShare: true));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
      });

      group('on a screen 320 pixels wide at the largest text size', () {
        for (final (locale, link, pdf) in [
          (const Locale('en'), 'Share link', 'Share PDF'),
          (const Locale('ko'), '링크로 공유하기', 'PDF로 공유하기'),
        ]) {
          for (final MapEntry(key: linkState, value: (english, korean)) in messages.entries) {
            testWidgets('fits the message and both controls in ${locale.languageCode} for $linkState', (tester) async {
              tester.useNarrowScreenWithLargestText();
              when(() => linkCubit.state).thenReturn(linkState);
              when(() => cubit.state).thenReturn(shown(VisitReportStatus.ready));

              await tester.pumpApp(
                MultiBlocProvider(
                  providers: [
                    BlocProvider<VisitReportCubit>.value(value: cubit),
                    BlocProvider<ReportLinkCubit>.value(value: linkCubit),
                  ],
                  child: const VisitReportView(),
                ),
                locale: locale,
              );

              tester
                ..expectWholeText(locale.languageCode == 'en' ? english : korean)
                ..expectWholeText(pdf);
              if (linkState.status != ReportLinkStatus.publishing) tester.expectWholeText(link);
            });
          }
        }
      });
    });

    testWidgets('shows no message when the share sheet opened', (tester) async {
      final states = StreamController<VisitReportState>();
      addTearDown(states.close);
      whenListen(cubit, states.stream, initialState: shown(VisitReportStatus.sharing));
      useTallPhoneScreen(tester);
      await pumpCubits(tester);

      states.add(shown(VisitReportStatus.ready));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
