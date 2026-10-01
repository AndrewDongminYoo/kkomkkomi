import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockVisitCaptureCubit extends MockCubit<VisitCaptureState> implements VisitCaptureCubit;

void main() {
  const clientId = 'client-a';
  const visitId = 'visit-2';
  const picked = '/cache/scaled_camera.jpg';
  const beforeFile = '/documents/photos/visit-2/before.jpg';
  const afterFile = '/documents/photos/visit-2/after.jpg';
  final beforePhoto = PhotoRef('photos/visit-2/before.jpg');
  final afterPhoto = PhotoRef('photos/visit-2/after.jpg');
  final failure = Exception('storage failed');

  Visit visitWith(List<ZoneRecord> records, {String id = visitId, VisitDate? date}) => Visit(
    id: id,
    clientId: clientId,
    visitDate: date ?? VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 1),
    zoneRecords: records,
  );

  /// A visit with one zone for each case: no photo, one photo, and both photos.
  final current = visitWith([
    ZoneRecord(zoneId: 'zone-1', zoneName: '로비'),
    ZoneRecord(zoneId: 'zone-2', zoneName: '복도', beforePhoto: beforePhoto, note: '왁스'),
    ZoneRecord(zoneId: 'zone-3', zoneName: '탕비실', beforePhoto: beforePhoto, afterPhoto: afterPhoto),
  ]);

  Visit earlierVisit({String? before, String? after}) => visitWith(
    [
      ZoneRecord(
        zoneId: 'zone-1',
        zoneName: '로비',
        beforePhoto: before == null ? null : PhotoRef(before),
        afterPhoto: after == null ? null : PhotoRef(after),
      ),
    ],
    id: 'visit-1',
    date: VisitDate(2026, 9, 16),
  );

  late FakeVisitRepository visits;
  late FakePhotoCapture photoCapture;
  late FakePhotoStore photoStore;

  /// Makes the screen as wide as a phone and tall enough for every zone of [current], until the test ends.
  ///
  /// The list builds only the zones that the screen has room for, and a test reads zones that the default screen
  /// leaves out.
  void useTallPhoneScreen(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(400, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Opens the visit screen from a host screen, so that the visit screen can close.
  ///
  /// The screen is a tall phone unless [keepScreen] is true, which a test sets after it chose the screen itself.
  Future<void> pumpPage(
    WidgetTester tester, {
    Visit? visit,
    List<Visit> history = const [],
    Locale? locale,
    Exception? loadFailure,
    bool keepScreen = false,
  }) async {
    if (!keepScreen) useTallPhoneScreen(tester);
    visits = FakeVisitRepository(visits: [visit ?? current, ...history])..failure = loadFailure;
    photoCapture = FakePhotoCapture();
    photoStore = FakePhotoStore();
    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(VisitCapturePage.route(visitId: visitId)),
            child: const Text('host'),
          ),
        ),
      ),
      locale: locale,
      repositories: Repositories(
        clients: FakeClientRepository(),
        visits: visits,
        companyProfile: FakeCompanyProfileRepository(),
        publishing: MockPublishRepository(),
      ),
      photoCapture: photoCapture,
      photoStore: photoStore,
    );
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();
  }

  Finder zone(String zoneId) => find.byKey(ValueKey(zoneId));

  Finder control(String zoneId, String label) =>
      find.descendant(of: zone(zoneId), matching: find.widgetWithText(OutlinedButton, label));

  Finder noteField(String zoneId) => find.descendant(of: zone(zoneId), matching: find.byType(TextField));

  /// Scrolls the list of zones until [finder] is on the screen. A note field is a scrollable too, so the list is
  /// named.
  Future<void> scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
    finder,
    100,
    scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
  );

  Future<ZoneRecord> savedRecord(String zoneId) async => (await visits.visitById(visitId))!.recordFor(zoneId)!;

  group('VisitCapturePage', () {
    testWidgets('renders VisitCaptureView with the visit date as the title and one row for each zone record', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.byType(VisitCaptureView), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'October 1, 2026'), findsOneWidget);
      for (final (zoneId, name) in [('zone-1', '로비'), ('zone-2', '복도'), ('zone-3', '탕비실')]) {
        expect(find.descendant(of: zone(zoneId), matching: find.text(name)), findsOneWidget);
        expect(find.descendant(of: zone(zoneId), matching: find.byType(OutlinedButton)), findsNWidgets(2));
        expect(noteField(zoneId), findsOneWidget);
      }
      expect(
        tester.getTopLeft(zone('zone-1')).dy,
        lessThan(tester.getTopLeft(zone('zone-2')).dy),
      );
    });

    testWidgets('shows a zone with no photo as two controls that take a photo, without a picture', (tester) async {
      await pumpPage(tester);

      expect(control('zone-1', 'Take Before Photo'), findsOneWidget);
      expect(control('zone-1', 'Take After Photo'), findsOneWidget);
      expect(tester.photoPathsIn(zone('zone-1')), isEmpty);
      expect(find.descendant(of: zone('zone-1'), matching: find.byIcon(Icons.photo_camera_outlined)), findsNWidgets(2));
    });

    testWidgets('shows a zone with one photo as that photo, which can be taken again, and an empty after slot', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(control('zone-2', 'Retake Before Photo'), findsOneWidget);
      expect(control('zone-2', 'Take After Photo'), findsOneWidget);
      expect(tester.photoPathsIn(control('zone-2', 'Retake Before Photo')), [beforeFile]);
      expect(tester.photoPathsIn(control('zone-2', 'Take After Photo')), isEmpty);
    });

    testWidgets('shows a zone with both photos as two photos that can be taken again', (tester) async {
      await pumpPage(tester);

      expect(tester.photoPathsIn(control('zone-3', 'Retake Before Photo')), [beforeFile]);
      expect(tester.photoPathsIn(control('zone-3', 'Retake After Photo')), [afterFile]);
      expect(find.descendant(of: zone('zone-3'), matching: find.byIcon(Icons.photo_camera_outlined)), findsNothing);
    });

    group('previous photos', () {
      testWidgets('shows the photos of the earlier visit under its date, after the photos of this visit', (
        tester,
      ) async {
        await pumpPage(
          tester,
          history: [earlierVisit(before: 'photos/visit-1/before.jpg', after: 'photos/visit-1/after.jpg')],
        );

        expect(
          find.descendant(of: zone('zone-1'), matching: find.text('Photos from the visit on September 16, 2026')),
          findsOneWidget,
        );
        expect(tester.photoPathsIn(zone('zone-1')), [
          '/documents/photos/visit-1/before.jpg',
          '/documents/photos/visit-1/after.jpg',
        ]);
        expect(find.descendant(of: zone('zone-2'), matching: find.textContaining('Photos from')), findsNothing);
        expect(tester.photoPathsIn(zone('zone-2')), [beforeFile]);
      });

      testWidgets('gives a screen reader a label for each previous photo', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(
          tester,
          history: [earlierVisit(before: 'photos/visit-1/before.jpg', after: 'photos/visit-1/after.jpg')],
        );

        expect(find.bySemanticsLabel('Before photo from the earlier visit'), findsOneWidget);
        expect(find.bySemanticsLabel('After photo from the earlier visit'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('shows only the photo that the earlier visit took, under the control of its slot', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(tester, history: [earlierVisit(after: 'photos/visit-1/after.jpg')]);

        expect(tester.photoPathsIn(zone('zone-1')), ['/documents/photos/visit-1/after.jpg']);
        expect(find.bySemanticsLabel('Before photo from the earlier visit'), findsNothing);
        expect(
          tester.getTopLeft(find.bySemanticsLabel('After photo from the earlier visit')).dx,
          tester.getTopLeft(control('zone-1', 'Take After Photo')).dx,
        );
        semantics.dispose();
      });

      testWidgets('shows nothing for an earlier record without a photo', (tester) async {
        await pumpPage(tester, history: [earlierVisit()]);

        expect(find.textContaining('Photos from'), findsNothing);
        expect(tester.photoPathsIn(zone('zone-1')), isEmpty);
      });

      testWidgets('names the date of the earlier visit in Korean', (tester) async {
        await pumpPage(
          tester,
          history: [earlierVisit(before: 'photos/visit-1/before.jpg')],
          locale: const Locale('ko'),
        );

        expect(find.text('2026년 9월 16일 방문 사진'), findsOneWidget);
      });
    });

    group('capture', () {
      testWidgets('takes a photo from the control, shows it, and saves it at once', (tester) async {
        await pumpPage(tester);
        photoCapture.results.add(picked);

        await tester.tap(control('zone-1', 'Take Before Photo'));
        await tester.pumpAndSettle();

        expect(control('zone-1', 'Retake Before Photo'), findsOneWidget);
        expect(tester.photoPathsIn(zone('zone-1')), ['/documents/photos/visit-2/id-1.jpg']);
        expect((await savedRecord('zone-1')).beforePhoto, PhotoRef('photos/visit-2/id-1.jpg'));
        expect(photoStore.sources, {PhotoRef('photos/visit-2/id-1.jpg'): picked});
      });

      testWidgets('takes a photo again, shows the new photo, and deletes the old file', (tester) async {
        await pumpPage(tester);
        photoCapture.results.add(picked);

        await tester.tap(control('zone-2', 'Retake Before Photo'));
        await tester.pumpAndSettle();

        expect(tester.photoPathsIn(zone('zone-2')), ['/documents/photos/visit-2/id-1.jpg']);
        expect((await savedRecord('zone-2')).beforePhoto, PhotoRef('photos/visit-2/id-1.jpg'));
        expect((await savedRecord('zone-2')).note, '왁스');
        expect(photoStore.deleted, [beforePhoto]);
      });

      testWidgets('changes nothing when the person closes the camera without a photo', (tester) async {
        await pumpPage(tester);
        photoCapture.results.add(null);

        await tester.tap(control('zone-2', 'Retake Before Photo'));
        await tester.pumpAndSettle();

        expect(photoCapture.calls, 1);
        expect(tester.photoPathsIn(zone('zone-2')), [beforeFile]);
        expect(await visits.visitById(visitId), current);
        expect(photoStore.deleted, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('shows a message when the capture fails, and takes a photo after that', (tester) async {
        await pumpPage(tester);
        photoCapture.results.addAll([const PhotoCaptureException(), picked]);

        await tester.tap(control('zone-1', 'Take After Photo'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(SnackBar, "Can't take the photo right now. Try again."), findsOneWidget);
        expect(await visits.visitById(visitId), current);

        await tester.tap(control('zone-1', 'Take After Photo'));
        await tester.pumpAndSettle();

        expect(control('zone-1', 'Retake After Photo'), findsOneWidget);
        expect((await savedRecord('zone-1')).afterPhoto, PhotoRef('photos/visit-2/id-1.jpg'));
      });

      testWidgets('says how to allow the camera when the person did not allow it', (tester) async {
        await pumpPage(tester);
        photoCapture.results.add(const PhotoCaptureException(isAccessDenied: true));

        await tester.tap(control('zone-1', 'Take Before Photo'));
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(SnackBar, 'Camera access is off. To take photos, turn it on in Settings.'),
          findsOneWidget,
        );
        expect(control('zone-1', 'Take Before Photo'), findsOneWidget);
      });

      testWidgets('shows a message and keeps the old photo when storage does not take the new photo', (tester) async {
        await pumpPage(tester);
        photoCapture.results.add(picked);
        visits.failure = failure;

        await tester.tap(control('zone-2', 'Retake Before Photo'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SnackBar, "Can't save right now. Try again."), findsOneWidget);
        expect(tester.photoPathsIn(zone('zone-2')), [beforeFile]);
        expect(photoStore.deleted, [PhotoRef('photos/visit-2/id-1.jpg')]);
      });

      testWidgets('takes no touch, no note, and no back press while a photo is on its way', (tester) async {
        await pumpPage(tester);
        photoCapture
          ..results.add(picked)
          ..gate = Completer<void>();

        await tester.tap(control('zone-1', 'Take Before Photo'));
        await tester.pump();
        await tester.tap(control('zone-1', 'Take After Photo'), warnIfMissed: false);
        await tester.pump();
        expect(photoCapture.calls, 1);
        expect(tester.widget<TextField>(noteField('zone-1')).readOnly, isTrue);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(VisitCapturePage), findsOneWidget);

        photoCapture.gate!.complete();
        await tester.pumpAndSettle();

        expect(control('zone-1', 'Retake Before Photo'), findsOneWidget);
        expect(tester.widget<TextField>(noteField('zone-1')).readOnly, isFalse);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(VisitCapturePage), findsNothing);
      });

      testWidgets('closes the keyboard of a note before the camera opens', (tester) async {
        await pumpPage(tester);
        photoCapture.results.add(null);
        await tester.tap(noteField('zone-1'));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);

        await tester.tap(control('zone-1', 'Take Before Photo'));
        await tester.pumpAndSettle();

        expect(tester.testTextInput.isVisible, isFalse);
      });

      testWidgets('gives a screen reader each control as a button with its label', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(tester);

        expect(
          tester.getSemantics(control('zone-2', 'Retake Before Photo')),
          isSemantics(label: 'Retake Before Photo', isButton: true, hasTapAction: true),
        );
        semantics.dispose();
      });
    });

    group('note', () {
      testWidgets('opens with the saved note of each zone under the note label', (tester) async {
        await pumpPage(tester);

        expect(find.descendant(of: zone('zone-2'), matching: find.text('Note')), findsOneWidget);
        expect(tester.widget<TextField>(noteField('zone-1')).controller!.text, isEmpty);
        expect(tester.widget<TextField>(noteField('zone-2')).controller!.text, '왁스');
      });

      testWidgets('saves each edit of a note at once, as it is written', (tester) async {
        await pumpPage(tester);

        await tester.enterText(noteField('zone-1'), '유리 ');
        await tester.pump();
        expect((await savedRecord('zone-1')).note, '유리 ');

        await tester.enterText(noteField('zone-1'), '유리 닦음');
        await tester.pump();

        expect((await savedRecord('zone-1')).note, '유리 닦음');
        expect((await savedRecord('zone-2')).note, '왁스');
      });

      testWidgets('keeps the text and shows a notice with a save control while storage does not take a note', (
        tester,
      ) async {
        await pumpPage(tester);
        visits.failure = failure;

        await tester.enterText(noteField('zone-1'), '유');
        await tester.pumpAndSettle();
        expect(find.text("Can't save your notes right now."), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);

        // The notice does not leave after a time, and a later edit that storage does not take keeps it.
        await tester.pump(const Duration(seconds: 10));
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        expect(find.text("Can't save your notes right now."), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Save Again'), findsOneWidget);
        expect(tester.widget<TextField>(noteField('zone-1')).controller!.text, '유리');
        visits.failure = null;
        expect((await savedRecord('zone-1')).note, isEmpty);
      });

      testWidgets('saves the notes again from the notice, which then leaves', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();
        visits.failure = null;

        await tester.tap(find.widgetWithText(TextButton, 'Save Again'));
        await tester.pumpAndSettle();

        expect(find.text("Can't save your notes right now."), findsNothing);
        expect((await savedRecord('zone-1')).note, '유리');
      });

      testWidgets('takes the notice away when storage takes a later edit', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();
        visits.failure = null;

        await tester.enterText(noteField('zone-1'), '유리 닦음');
        await tester.pumpAndSettle();

        expect(find.text("Can't save your notes right now."), findsNothing);
        expect((await savedRecord('zone-1')).note, '유리 닦음');
      });

      testWidgets('keeps the keyboard and the text of the note when the notice comes', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.showKeyboard(noteField('zone-2'));
        await tester.pump();

        tester.testTextInput.enterText('왁스 두 번');
        await tester.pumpAndSettle();

        expect(find.text("Can't save your notes right now."), findsOneWidget);
        expect(tester.testTextInput.isVisible, isTrue);
        final editable = find.descendant(of: zone('zone-2'), matching: find.byType(EditableText));
        expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
        expect(tester.widget<TextField>(noteField('zone-2')).controller!.text, '왁스 두 번');
      });

      testWidgets('keeps the notice when a capture fails after a note that storage did not take', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        photoCapture.results.add(const PhotoCaptureException());
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        await tester.tap(control('zone-1', 'Take Before Photo'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(SnackBar, "Can't take the photo right now. Try again."), findsOneWidget);
        expect(find.text("Can't save your notes right now."), findsOneWidget);
      });

      testWidgets('announces the notice to a screen reader and names it in Korean', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(tester, locale: const Locale('ko'));
        visits.failure = failure;

        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextButton, '다시 저장하기'), findsOneWidget);
        expect(
          tester.getSemantics(find.text('메모를 저장하지 못했어요.')),
          isSemantics(label: '메모를 저장하지 못했어요.', isLiveRegion: true),
        );
        semantics.dispose();
      });

      testWidgets('takes no back press while a note is on its way to storage, and leaves after storage took it', (
        tester,
      ) async {
        await pumpPage(tester);
        visits.gate = Completer<void>();

        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(VisitCapturePage), findsOneWidget);
        // The person can still type while the note is on its way.
        await tester.enterText(noteField('zone-1'), '유리 닦음');
        await tester.pump();

        visits.gate!.complete();
        visits.gate = null;
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(VisitCapturePage), findsNothing);
        expect((await savedRecord('zone-1')).note, '유리 닦음');
      });

      testWidgets('asks before the person leaves with a note that storage did not take, and stays on a no', (
        tester,
      ) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.widgetWithText(AlertDialog, 'Leave without saving?'), findsOneWidget);
        expect(find.text('Your unsaved notes will be lost.'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(VisitCapturePage), findsOneWidget);
        expect(tester.widget<TextField>(noteField('zone-1')).controller!.text, '유리');
      });

      testWidgets('leaves with a note that storage did not take when the person says so', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
        await tester.pumpAndSettle();

        expect(find.byType(VisitCapturePage), findsNothing);
        expect(find.text('host'), findsOneWidget);
      });

      testWidgets('leaves without a question after storage took the notes again', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();
        visits.failure = null;
        await tester.tap(find.widgetWithText(TextButton, 'Save Again'));
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(VisitCapturePage), findsNothing);
      });

      testWidgets('asks nothing while the camera is open over a note that storage did not take', (tester) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();
        photoCapture
          ..results.add(null)
          ..gate = Completer<void>();
        await tester.tap(control('zone-1', 'Take Before Photo'));
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(VisitCapturePage), findsOneWidget);
        photoCapture.gate!.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('asks in Korean before the person leaves with a note that storage did not take', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.widgetWithText(AlertDialog, '저장하지 않고 나갈까요?'), findsOneWidget);
        expect(find.text('저장하지 못한 메모가 사라져요.'), findsOneWidget);
        expect(find.widgetWithText(TextButton, '닫기'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '나가기'), findsOneWidget);
      });

      testWidgets('takes more than one line', (tester) async {
        await pumpPage(tester);

        final field = tester.widget<TextField>(noteField('zone-1'));

        expect(field.maxLines, isNull);
        expect(field.keyboardType, TextInputType.multiline);
      });

      testWidgets('gives a screen reader the label as the name of the field', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(tester);

        expect(
          tester.getSemantics(noteField('zone-2')),
          isSemantics(label: 'Note', value: '왁스', isTextField: true),
        );
        semantics.dispose();
      });
    });

    group('report', () {
      Finder reportButton([String label = 'View Report']) => find.widgetWithText(FilledButton, label);

      testWidgets('opens the report of the visit from the control under the zones', (tester) async {
        await pumpPage(tester);

        expect(tester.getTopLeft(reportButton()).dy, greaterThan(tester.getBottomLeft(zone('zone-3')).dy));
        await tester.tap(reportButton());
        await tester.pumpAndSettle();

        expect(tester.widget<VisitReportPage>(find.byType(VisitReportPage)).visitId, visitId);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(VisitReportPage), findsNothing);
        expect(find.byType(VisitCapturePage), findsOneWidget);
      });

      testWidgets('opens the report with the note that the person wrote just before', (tester) async {
        await pumpPage(tester);
        await tester.enterText(noteField('zone-1'), '유리 닦음');
        await tester.pump();

        await tester.tap(reportButton());
        await tester.pumpAndSettle();

        expect((await savedRecord('zone-1')).note, '유리 닦음');
        expect(find.byType(VisitReportPage), findsOneWidget);
      });

      testWidgets('opens no report while storage does not hold a note, and opens it after storage took the note', (
        tester,
      ) async {
        await pumpPage(tester);
        visits.failure = failure;
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pumpAndSettle();

        expect(tester.widget<FilledButton>(reportButton()).onPressed, isNull);
        await tester.tap(reportButton(), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(VisitReportPage), findsNothing);

        visits.failure = null;
        await tester.tap(find.widgetWithText(TextButton, 'Save Again'));
        await tester.pumpAndSettle();
        await tester.tap(reportButton());
        await tester.pumpAndSettle();

        expect(find.byType(VisitReportPage), findsOneWidget);
      });

      testWidgets('opens no report while a note is on its way to storage, so that no report lacks a note that '
          'storage then does not take', (tester) async {
        await pumpPage(tester);
        visits.gate = Completer<void>();
        await tester.enterText(noteField('zone-1'), '유리');
        await tester.pump();

        expect(tester.widget<FilledButton>(reportButton()).onPressed, isNull);
        await tester.tap(reportButton(), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(VisitReportPage), findsNothing);

        visits.gate!.completeError(failure);
        await tester.pumpAndSettle();
        expect(find.text("Can't save your notes right now."), findsOneWidget);
        expect(tester.widget<FilledButton>(reportButton()).onPressed, isNull);
      });

      testWidgets('closes the keyboard of a note before the report opens, and keeps it closed on the way back', (
        tester,
      ) async {
        await pumpPage(tester);
        await tester.tap(noteField('zone-1'));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);

        await tester.tap(reportButton());
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
      });

      testWidgets('names the control in Korean', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        expect(reportButton('보고서 보기'), findsOneWidget);
      });
    });

    testWidgets('shows the screen in Korean', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'));

      expect(find.widgetWithText(AppBar, '2026년 10월 1일'), findsOneWidget);
      expect(control('zone-1', '청소 전 사진 찍기'), findsOneWidget);
      expect(control('zone-1', '청소 후 사진 찍기'), findsOneWidget);
      expect(control('zone-2', '청소 전 사진 다시 찍기'), findsOneWidget);
      expect(find.descendant(of: zone('zone-1'), matching: find.text('메모')), findsOneWidget);
      expect(control('zone-3', '청소 후 사진 다시 찍기'), findsOneWidget);
    });

    testWidgets('says so when the visit holds no zone', (tester) async {
      await pumpPage(tester, visit: visitWith([]));

      expect(
        find.text('This visit has no zones. To take photos, add zones to the client, then start a new visit.'),
        findsOneWidget,
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows a message and a retry control when the visit does not load, and loads it on retry', (
      tester,
    ) async {
      await pumpPage(tester, loadFailure: failure);

      expect(find.text("Can't load this visit. Try again."), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);

      visits.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'October 1, 2026'), findsOneWidget);
      expect(control('zone-1', 'Take Before Photo'), findsOneWidget);
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      const longZoneName = '1층 로비와 엘리베이터 앞 복도';
      final longVisit = visitWith([
        ZoneRecord(zoneId: 'zone-1', zoneName: longZoneName, note: '바닥 왁스 작업을 마쳤고 유리창은 다음 방문에 닦기로 했어요'),
        ZoneRecord(zoneId: 'zone-2', zoneName: '화장실', beforePhoto: beforePhoto, afterPhoto: afterPhoto),
      ]);
      final history = [
        visitWith(
          [
            ZoneRecord(
              zoneId: 'zone-1',
              zoneName: longZoneName,
              beforePhoto: PhotoRef('photos/visit-1/before.jpg'),
              afterPhoto: PhotoRef('photos/visit-1/after.jpg'),
            ),
          ],
          id: 'visit-1',
          date: VisitDate(2026, 9, 16),
        ),
      ];

      /// Scrolls to [text] in the zone with [zoneId], because each zone has a note label and the list builds a
      /// zone only near the screen.
      Future<void> expectWholeTextAfterScroll(WidgetTester tester, String zoneId, String text) async {
        await scrollTo(tester, find.descendant(of: zone(zoneId), matching: find.text(text)));
        tester.expectWholeText(text);
      }

      for (final (locale, firstZoneTexts, secondZoneTexts) in [
        (
          const Locale('en'),
          [
            longZoneName,
            'Take Before Photo',
            'Take After Photo',
            'Photos from the visit on September 16, 2026',
            'Note',
          ],
          ['화장실', 'Retake Before Photo', 'Retake After Photo', 'Note'],
        ),
        (
          const Locale('ko'),
          [longZoneName, '청소 전 사진 찍기', '청소 후 사진 찍기', '2026년 9월 16일 방문 사진', '메모'],
          ['화장실', '청소 전 사진 다시 찍기', '청소 후 사진 다시 찍기', '메모'],
        ),
      ]) {
        testWidgets('fits the zones, the photo controls, and the notes in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, visit: longVisit, history: history, locale: locale, keepScreen: true);

          for (final text in firstZoneTexts) {
            await expectWholeTextAfterScroll(tester, 'zone-1', text);
          }
          for (final text in secondZoneTexts) {
            await expectWholeTextAfterScroll(tester, 'zone-2', text);
          }
        });
      }

      for (final (locale, label) in [(const Locale('en'), 'View Report'), (const Locale('ko'), '보고서 보기')]) {
        testWidgets('fits the control that opens the report in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, visit: longVisit, history: history, locale: locale, keepScreen: true);

          await scrollTo(tester, find.text(label));
          tester.expectWholeText(label);
        });
      }

      for (final (locale, button, messages) in [
        (
          const Locale('en'),
          'Take Before Photo',
          [
            "Can't take the photo right now. Try again.",
            'Camera access is off. To take photos, turn it on in Settings.',
            "Can't save right now. Try again.",
          ],
        ),
        (
          const Locale('ko'),
          '청소 전 사진 찍기',
          [
            '사진을 찍지 못했어요. 다시 시도해 주세요.',
            '카메라를 쓸 수 없어요. 설정에서 카메라를 허용하면 사진을 찍을 수 있어요.',
            '저장하지 못했어요. 다시 시도해 주세요.',
          ],
        ),
      ]) {
        testWidgets('fits the message of each failure in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, visit: longVisit, locale: locale, keepScreen: true);
          photoCapture.results.addAll([
            const PhotoCaptureException(),
            const PhotoCaptureException(isAccessDenied: true),
            picked,
          ]);

          for (final message in messages) {
            if (message == messages.last) visits.failure = failure;
            await tester.ensureVisible(control('zone-1', button));
            await tester.pumpAndSettle();
            await tester.tap(control('zone-1', button));
            await tester.pumpAndSettle();

            expect(find.byType(SnackBar), findsOneWidget);
            tester.expectWholeText(message);
            // The message covers the control at this text size, so the next tap waits until the message has left.
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
          }
        });
      }

      for (final (locale, message, saveAgain) in [
        (const Locale('en'), "Can't save your notes right now.", 'Save Again'),
        (const Locale('ko'), '메모를 저장하지 못했어요.', '다시 저장하기'),
      ]) {
        testWidgets('fits the notice of unsaved notes and keeps the zones in reach in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, visit: longVisit, locale: locale, keepScreen: true);
          visits.failure = failure;

          await tester.enterText(noteField('zone-1'), '유리');
          await tester.pumpAndSettle();

          tester.expectWholeText(message);
          final button = find.widgetWithText(TextButton, saveAgain);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          tester.expectWholeText(saveAgain);
          // The notice takes at most half of the body, so the list of zones keeps the other half.
          expect(tester.getSize(find.byType(ListView)).height, greaterThanOrEqualTo(200));
          visits.failure = null;
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.text(message), findsNothing);
        });
      }

      for (final (locale, title, message, cancel, leave) in [
        (const Locale('en'), 'Leave without saving?', 'Your unsaved notes will be lost.', 'Cancel', 'Leave'),
        (const Locale('ko'), '저장하지 않고 나갈까요?', '저장하지 못한 메모가 사라져요.', '닫기', '나가기'),
      ]) {
        testWidgets('fits the question before the person leaves with unsaved notes in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, visit: longVisit, locale: locale, keepScreen: true);
          visits.failure = failure;
          await tester.enterText(noteField('zone-1'), '유리');
          await tester.pumpAndSettle();

          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();

          tester
            ..expectWholeText(title)
            ..expectWholeText(message)
            ..expectWholeText(cancel)
            ..expectWholeText(leave);
        });
      }

      for (final (locale, empty, loadFailed, retry) in [
        (
          const Locale('en'),
          'This visit has no zones. To take photos, add zones to the client, then start a new visit.',
          "Can't load this visit. Try again.",
          'Try Again',
        ),
        (
          const Locale('ko'),
          '이 방문에는 구역이 없어요. 거래처에 구역을 추가한 뒤 방문을 새로 시작하면 사진을 찍을 수 있어요.',
          '방문 기록을 불러오지 못했어요. 다시 시도해 주세요.',
          '다시 불러오기',
        ),
      ]) {
        testWidgets('fits the message of a visit without zones in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, visit: visitWith([]), locale: locale, keepScreen: true);

          tester.expectWholeText(empty);
        });

        testWidgets('fits the message of a failed load in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, locale: locale, loadFailure: failure, keepScreen: true);

          tester
            ..expectWholeText(loadFailed)
            ..expectWholeText(retry);
        });
      }
    });
  });

  group('VisitCaptureView', () {
    late VisitCaptureCubit cubit;

    VisitCaptureState shown(VisitCaptureStatus status) =>
        VisitCaptureState(status: status, visit: current, photoDirectory: FakePhotoStore.directory);

    setUpAll(() => registerFallbackValue(PhotoSlot.before));

    setUp(() => cubit = _MockVisitCaptureCubit());

    Future<void> pumpView(WidgetTester tester, VisitCaptureState state) async {
      useTallPhoneScreen(tester);
      when(() => cubit.state).thenReturn(state);
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const VisitCaptureView()));
    }

    testWidgets('shows a progress indicator and no title while the visit loads', (tester) async {
      await pumpView(tester, const VisitCaptureState());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
    });

    for (final status in [
      VisitCaptureStatus.capturing,
      VisitCaptureStatus.captureFailed,
      VisitCaptureStatus.captureDenied,
      VisitCaptureStatus.saveFailed,
    ]) {
      testWidgets('keeps the visit on the screen in the ${status.name} status', (tester) async {
        await pumpView(tester, shown(status));

        expect(find.widgetWithText(AppBar, 'October 1, 2026'), findsOneWidget);
        expect(control('zone-1', 'Take Before Photo'), findsOneWidget);
        expect(tester.photoPathsIn(zone('zone-2')), [beforeFile]);
      });
    }

    testWidgets('shows the notice of unsaved notes while the state tells so, and passes its control to the cubit', (
      tester,
    ) async {
      when(() => cubit.saveAgain()).thenAnswer((_) async {});
      await pumpView(tester, shown(VisitCaptureStatus.ready).copyWith(isStored: false));

      expect(find.text("Can't save your notes right now."), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save Again'));

      verify(() => cubit.saveAgain()).called(1);
    });

    testWidgets('takes no back press while the state tells that a note is on its way', (tester) async {
      when(() => cubit.state).thenReturn(shown(VisitCaptureStatus.ready).copyWith(isSavingNote: true));
      useTallPhoneScreen(tester);
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BlocProvider.value(value: cubit, child: const VisitCaptureView()),
              ),
            ),
            child: const Text('host'),
          ),
        ),
      );
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(VisitCaptureView), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows no notice while storage holds the notes', (tester) async {
      await pumpView(tester, shown(VisitCaptureStatus.saveFailed));

      expect(find.text("Can't save your notes right now."), findsNothing);
      expect(find.widgetWithText(TextButton, 'Save Again'), findsNothing);
    });

    testWidgets('offers the report while storage holds the notes', (tester) async {
      await pumpView(tester, shown(VisitCaptureStatus.saveFailed));

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'View Report')).onPressed, isNotNull);
    });

    testWidgets('offers no report while the state tells that storage does not hold a note', (tester) async {
      await pumpView(tester, shown(VisitCaptureStatus.ready).copyWith(isStored: false));

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'View Report')).onPressed, isNull);
    });

    testWidgets('offers no report while the state tells that a note is on its way to storage', (tester) async {
      await pumpView(tester, shown(VisitCaptureStatus.ready).copyWith(isSavingNote: true));

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'View Report')).onPressed, isNull);
    });

    testWidgets('passes a capture and each edit of a note to the cubit', (tester) async {
      when(() => cubit.capturePhoto(any(), any())).thenAnswer((_) async {});
      when(() => cubit.editNote(any(), any())).thenAnswer((_) async {});
      await pumpView(tester, shown(VisitCaptureStatus.ready));

      await tester.tap(control('zone-1', 'Take Before Photo'));
      await tester.tap(control('zone-2', 'Take After Photo'));
      await tester.tap(control('zone-2', 'Retake Before Photo'));
      await tester.enterText(noteField('zone-2'), '왁스 두 번');

      verifyInOrder([
        () => cubit.capturePhoto('zone-1', PhotoSlot.before),
        () => cubit.capturePhoto('zone-2', PhotoSlot.after),
        () => cubit.capturePhoto('zone-2', PhotoSlot.before),
        () => cubit.editNote('zone-2', '왁스 두 번'),
      ]);
    });

    testWidgets('shows the message of a failure once, when the status changes to it', (tester) async {
      final states = StreamController<VisitCaptureState>();
      addTearDown(states.close);
      whenListen(cubit, states.stream, initialState: shown(VisitCaptureStatus.ready));
      useTallPhoneScreen(tester);
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const VisitCaptureView()));

      states.add(shown(VisitCaptureStatus.capturing));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      states.add(shown(VisitCaptureStatus.captureFailed));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SnackBar, "Can't take the photo right now. Try again."), findsOneWidget);
      // The message leaves after its time on the screen, which starts when it has come in.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      // A later state with the same status, such as an edited note, is no new failure.
      states.add(
        shown(VisitCaptureStatus.captureFailed).copyWith(
          visit: current.withRecord(current.recordFor('zone-1')!.withNote('유리')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      // A new failure takes the place of a message that is still on the screen.
      states.add(shown(VisitCaptureStatus.saveFailed));
      await tester.pumpAndSettle();
      states.add(shown(VisitCaptureStatus.captureDenied));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.widgetWithText(SnackBar, 'Camera access is off. To take photos, turn it on in Settings.'),
        findsOneWidget,
      );
    });
  });
}
