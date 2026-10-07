// 🎯 Dart imports:
import 'dart:async';

// 🐦 Flutter imports:
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';

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
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';

import '../../../helpers/helpers.dart';

class _MockClientDetailCubit extends MockCubit<ClientDetailState> implements ClientDetailCubit;

class _MockClientLinkCubit extends MockCubit<ClientLinkState> implements ClientLinkCubit;

void main() {
  const clientId = 'client-a';
  final office = Client(id: clientId, name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final zones = ClientZones(
    clientId: clientId,
    zones: [
      Zone(id: 'zone-1', clientId: clientId, name: '로비', position: 0),
      Zone(id: 'zone-2', clientId: clientId, name: '복도', position: 1),
      Zone(id: 'zone-3', clientId: clientId, name: '탕비실', position: 2),
      Zone(id: 'zone-4', clientId: clientId, name: '옛 창고', position: 3, isActive: false),
    ],
  );
  Visit visitOn(String id, VisitDate date) =>
      Visit.start(id: id, zones: zones, visitDate: date, createdAt: DateTime.utc(2026, 9, 1, 1));
  final september = visitOn('visit-1', VisitDate(2026, 9, 16));
  final october = visitOn('visit-2', VisitDate(2026, 10, 1));
  final failure = Exception('storage failed');
  const noZonesInEnglish =
      'No zones yet. A zone is a place that gets a before photo and an after photo on each visit, '
      'such as a lobby or a restroom.';

  late FakeClientRepository clients;
  late FakeVisitRepository visitRepository;

  /// Opens the client screen from a host screen, so that the client screen can close itself.
  ///
  /// The clock shows noon of [today] in the time zone of the test, so that the day does not depend on that zone.
  Future<void> pumpPage(
    WidgetTester tester, {
    ClientZones? savedZones,
    List<Visit> visits = const [],
    Locale? locale,
    Exception? loadFailure,
    VisitDate? today,
  }) async {
    clients = FakeClientRepository(clients: [office], zones: [savedZones ?? zones])..failure = loadFailure;
    visitRepository = FakeVisitRepository(visits: visits);
    final day = today ?? VisitDate(2026, 10, 20);
    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(ClientDetailPage.route(clientId: clientId)),
            child: const Text('host'),
          ),
        ),
      ),
      locale: locale,
      repositories: Repositories(
        clients: clients,
        visits: visitRepository,
        companyProfile: FakeCompanyProfileRepository(),
        publishing: MockPublishRepository(),
        openCaptures: FakeOpenCaptureRepository(),
        localData: FakeLocalDataRepository(),
      ),
      clock: FixedClock(DateTime(day.year, day.month, day.day, 12)),
    );
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();
  }

  List<String?> listedZoneNames(WidgetTester tester) => tester
      .widgetList<ListTile>(find.descendant(of: find.byType(ReorderableListView), matching: find.byType(ListTile)))
      // A zone row has the drag handle in front, and a visit row has none.
      .where((tile) => tile.leading != null)
      .map((tile) => (tile.title! as Text).data)
      .toList();

  final clientMenu = find.byWidgetPredicate((widget) => widget is PopupMenuButton);

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(clientMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  Future<void> submitName(WidgetTester tester, String name, {required String button}) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.widgetWithText(FilledButton, button));
    await tester.pumpAndSettle();
  }

  String? fieldError(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).decoration!.errorMessage;

  /// Drags the handle of the zone at [index] by [rows] rows, where a row is the height of the first zone tile.
  ///
  /// The list gives the dragged zone the place of a neighbor when more than half of that neighbor is covered, so
  /// three quarters of a row move the zone by one place.
  ///
  /// The pointer rests on the handle for [hold] before it moves.
  Future<void> dragZone(
    WidgetTester tester, {
    required int index,
    required double rows,
    Duration hold = kPressTimeout,
  }) async {
    final handle = find.byIcon(Icons.drag_handle).at(index);
    final distance = rows * tester.getSize(find.byType(ListTile).first).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(hold);
    // The list starts the drag only after the pointer has moved past the touch slop, so the move has two steps.
    await gesture.moveBy(Offset(0, rows.sign * kTouchSlop));
    await tester.pump();
    await gesture.moveBy(Offset(0, distance - rows.sign * kTouchSlop));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('ClientDetailPage', () {
    testWidgets('renders ClientDetailView with the client name, the listed zones, and the start control', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.byType(ClientDetailView), findsOneWidget);
      expect(find.widgetWithText(AppBar, '한빛 사무실'), findsOneWidget);
      expect(find.text('Zones'), findsOneWidget);
      expect(listedZoneNames(tester), ['로비', '복도', '탕비실']);
      expect(find.text('옛 창고'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Add Zone'), findsOneWidget);
    });

    testWidgets('shows the control that starts a visit as disabled while the client has no zone', (tester) async {
      await pumpPage(tester, savedZones: ClientZones(clientId: clientId));

      final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Visit'));
      expect(start.onPressed, isNull);
    });

    group('visit start', () {
      final startButton = find.widgetWithText(FilledButton, 'Start Visit');
      final confirmButton = find.widgetWithText(TextButton, 'Start Visit');

      testWidgets('asks for the visit date with today picked, starts the visit, and opens its screen', (tester) async {
        await pumpPage(tester, visits: [september]);

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('Visit date')), findsOneWidget);
        expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).initialDate, DateTime(2026, 10, 20));
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(find.byType(VisitCapturePage), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'October 20, 2026'), findsOneWidget);
        final started = (await visitRepository.visitsOf(clientId)).first;
        expect(started.id, 'id-1');
        expect(started.visitDate, VisitDate(2026, 10, 20));
        expect(started.zoneRecords.map((record) => record.zoneName), ['로비', '복도', '탕비실']);
      });

      testWidgets('lists the started visit when the person comes back from its screen', (tester) async {
        await pumpPage(tester, visits: [september]);

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('September 16, 2026'), 100);

        expect(find.byType(VisitCapturePage), findsNothing);
        expect(
          tester.getTopLeft(find.text('October 20, 2026')).dy,
          lessThan(tester.getTopLeft(find.text('September 16, 2026')).dy),
        );
      });

      testWidgets('starts the visit on an earlier day that the person picks', (tester) async {
        await pumpPage(tester);

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('15'));
        await tester.pumpAndSettle();
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(find.widgetWithText(AppBar, 'October 15, 2026'), findsOneWidget);
        expect((await visitRepository.visitsOf(clientId)).single.visitDate, VisitDate(2026, 10, 15));
      });

      testWidgets('offers no day after today, because a visit records a cleaning that took place', (tester) async {
        await pumpPage(tester);

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate, DateTime(2026, 10, 20));
        await tester.tap(find.text('21'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect((await visitRepository.visitsOf(clientId)).single.visitDate, VisitDate(2026, 10, 20));
      });

      testWidgets('starts no visit when the person closes the date picker', (tester) async {
        await pumpPage(tester);

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.byType(VisitCapturePage), findsNothing);
        expect(await visitRepository.visitsOf(clientId), isEmpty);
      });

      testWidgets('stays on the client screen and shows a message when storage does not take the visit', (
        tester,
      ) async {
        await pumpPage(tester);
        visitRepository.failure = failure;

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(find.byType(VisitCapturePage), findsNothing);
        expect(find.widgetWithText(SnackBar, "Can't save right now. Try again."), findsOneWidget);
      });

      testWidgets('takes no touch and no back press while the visit is on its way to storage', (tester) async {
        await pumpPage(tester);
        visitRepository.gate = Completer<void>();

        await tester.tap(startButton);
        await tester.pumpAndSettle();
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(NameDialog), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsOneWidget);

        visitRepository.gate!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(VisitCapturePage), findsOneWidget);
        expect(await visitRepository.visitsOf(clientId), hasLength(1));
      });

      testWidgets('names the date picker and its buttons in Korean', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        await tester.tap(find.widgetWithText(FilledButton, '방문 시작하기'));
        await tester.pumpAndSettle();

        final picker = find.byType(DatePickerDialog);
        expect(find.descendant(of: picker, matching: find.text('방문 날짜')), findsOneWidget);
        expect(find.descendant(of: picker, matching: find.widgetWithText(TextButton, '닫기')), findsOneWidget);
        expect(find.descendant(of: picker, matching: find.widgetWithText(TextButton, '방문 시작하기')), findsOneWidget);
      });
    });

    testWidgets('reopens a past visit from the list', (tester) async {
      await pumpPage(tester, visits: [september, october]);
      await tester.scrollUntilVisible(find.text('September 16, 2026'), 100);

      await tester.tap(find.text('September 16, 2026'));
      await tester.pumpAndSettle();

      expect(find.byType(VisitCapturePage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'September 16, 2026'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ClientDetailPage), findsOneWidget);
      expect(find.byType(VisitCapturePage), findsNothing);
    });

    testWidgets('lists the past visits by date, newest first', (tester) async {
      await pumpPage(tester, visits: [september, october]);
      await tester.scrollUntilVisible(find.text('September 16, 2026'), 100);

      expect(find.text('Past visits'), findsOneWidget);
      expect(find.text('No visits yet.'), findsNothing);
      expect(
        tester.getTopLeft(find.text('October 1, 2026')).dy,
        lessThan(tester.getTopLeft(find.text('September 16, 2026')).dy),
      );
    });

    testWidgets('says so when the client has no zone and no visit', (tester) async {
      await pumpPage(tester, savedZones: ClientZones(clientId: clientId));

      expect(listedZoneNames(tester), isEmpty);
      expect(find.text(noZonesInEnglish), findsOneWidget);
      expect(find.text('No visits yet.'), findsOneWidget);
    });

    testWidgets('shows the screen in Korean', (tester) async {
      await pumpPage(
        tester,
        savedZones: ClientZones(clientId: clientId),
        visits: [october],
        locale: const Locale('ko'),
      );

      expect(find.widgetWithText(FilledButton, '방문 시작하기'), findsOneWidget);
      expect(find.text('구역'), findsOneWidget);
      expect(find.text('아직 구역이 없어요. 구역은 방문할 때마다 청소 전후 사진을 찍는 곳이에요. 로비, 화장실처럼 나눠서 추가해 주세요.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '구역 추가하기'), findsOneWidget);
      expect(find.text('지난 방문'), findsOneWidget);
      expect(find.text('2026년 10월 1일'), findsOneWidget);
    });

    testWidgets('says in Korean that the client has no visit', (tester) async {
      await pumpPage(tester, locale: const Locale('ko'));
      await tester.scrollUntilVisible(find.text('아직 방문 기록이 없어요.'), 100);

      expect(find.text('아직 방문 기록이 없어요.'), findsOneWidget);
    });

    testWidgets('shows a message and a retry control when the client does not load, and loads it on retry', (
      tester,
    ) async {
      await pumpPage(tester, loadFailure: failure);

      expect(find.text("Can't load this client. Try again."), findsOneWidget);
      expect(clientMenu, findsNothing);

      clients.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Try Again'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '한빛 사무실'), findsOneWidget);
    });

    group('zone list', () {
      testWidgets('adds a zone from the dialog at the end of the list', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AlertDialog, 'Add Zone'), findsOneWidget);
        expect(find.text('Zone name'), findsOneWidget);
        await submitName(tester, ' 화장실 ', button: 'Add');

        expect(find.byType(NameDialog), findsNothing);
        expect(listedZoneNames(tester), ['로비', '복도', '탕비실', '화장실']);
        expect((await clients.zonesOf(clientId)).active.last.id, 'id-1');
      });

      testWidgets('shows the validation message for a duplicate name under the name field', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'));
        await tester.pumpAndSettle();
        await submitName(tester, '복도', button: 'Add');

        expect(find.byType(NameDialog), findsOneWidget);
        expect(fieldError(tester), 'Another zone has this name. Enter a different name.');
        expect(await clients.zonesOf(clientId), zones);
      });

      testWidgets('shows the validation messages in Korean', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        await tester.tap(find.widgetWithText(OutlinedButton, '구역 추가하기'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AlertDialog, '구역 추가'), findsOneWidget);
        await submitName(tester, '', button: '추가하기');
        expect(fieldError(tester), '이름을 입력해 주세요.');
        await submitName(tester, '로비', button: '추가하기');
        expect(fieldError(tester), '같은 이름의 구역이 있어요. 다른 이름을 입력해 주세요.');
      });

      testWidgets('opens a name dialog again without the problem of the name before', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'));
        await tester.pumpAndSettle();
        await submitName(tester, '복도', button: 'Add');
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Rename 로비'));
        await tester.pumpAndSettle();

        expect(fieldError(tester), isNull);
      });

      testWidgets('renames a zone from the dialog, which opens with the name of the zone', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.byTooltip('Rename 복도'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AlertDialog, 'Rename Zone'), findsOneWidget);
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '복도');
        await submitName(tester, '긴 복도', button: 'Save');

        expect(find.byType(NameDialog), findsNothing);
        expect(listedZoneNames(tester), ['로비', '긴 복도', '탕비실']);
        expect((await clients.zonesOf(clientId)).active.map((zone) => zone.name), ['로비', '긴 복도', '탕비실']);
      });

      testWidgets('moves a zone down when its handle is dragged past the next zone', (tester) async {
        await pumpPage(tester);

        await dragZone(tester, index: 0, rows: 0.75);

        expect(listedZoneNames(tester), ['복도', '로비', '탕비실']);
        expect((await clients.zonesOf(clientId)).active.map((zone) => zone.id), ['zone-2', 'zone-1', 'zone-3']);
      });

      testWidgets('moves a zone when the person holds the handle for a moment before the drag', (tester) async {
        await pumpPage(tester);

        await dragZone(tester, index: 0, rows: 0.75, hold: kLongPressTimeout + const Duration(milliseconds: 200));

        expect(listedZoneNames(tester), ['복도', '로비', '탕비실']);
      });

      testWidgets('moves a zone up when its handle is dragged to the top of the list', (tester) async {
        await pumpPage(tester);

        await dragZone(tester, index: 2, rows: -1.75);

        expect(listedZoneNames(tester), ['탕비실', '로비', '복도']);
        expect((await clients.zonesOf(clientId)).active.map((zone) => zone.id), ['zone-3', 'zone-1', 'zone-2']);
      });

      testWidgets('shows the old order and a message when storage does not take the new order', (tester) async {
        await pumpPage(tester);
        clients.failure = failure;

        await dragZone(tester, index: 0, rows: 0.75);

        expect(listedZoneNames(tester), ['로비', '복도', '탕비실']);
        expect(find.widgetWithText(SnackBar, "Can't save right now. Try again."), findsOneWidget);
      });

      testWidgets('takes no touch and no back press while a change is on its way to storage', (tester) async {
        await pumpPage(tester);
        clients.gate = Completer<void>();

        await dragZone(tester, index: 0, rows: 0.75);
        expect(listedZoneNames(tester), ['복도', '로비', '탕비실']);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(NameDialog), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsOneWidget);

        clients.gate!.complete();
        clients.gate = null;
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'));
        await tester.pumpAndSettle();

        expect(find.byType(NameDialog), findsOneWidget);
        expect((await clients.zonesOf(clientId)).active.map((zone) => zone.id), ['zone-2', 'zone-1', 'zone-3']);
      });

      testWidgets('removes a zone after the person confirms', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.byTooltip('Remove 복도'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AlertDialog, 'Remove 복도?'), findsOneWidget);
        expect(find.text('New visits leave this zone out. Past visits keep their records of it.'), findsOneWidget);
        expect(tester.filledButtonColor('Remove'), appTheme().colorScheme.error);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
        await tester.pumpAndSettle();

        expect(listedZoneNames(tester), ['로비', '탕비실']);
        final saved = await clients.zonesOf(clientId);
        expect(saved.active.map((zone) => zone.id), ['zone-1', 'zone-3']);
        expect(saved.all.map((zone) => zone.id), contains('zone-2'));
      });

      testWidgets('keeps a zone when the person closes the question', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        await tester.tap(find.byTooltip('복도 삭제하기'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AlertDialog, '복도 구역을 삭제할까요?'), findsOneWidget);
        expect(find.text('새로 시작하는 방문부터 이 구역이 빠져요. 지난 방문 기록에는 그대로 남아요.'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '삭제하기'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, '닫기'));
        await tester.pumpAndSettle();

        expect(listedZoneNames(tester), ['로비', '복도', '탕비실']);
        expect(await clients.zonesOf(clientId), zones);
      });

      testWidgets('names each zone in the tooltips of its buttons, in Korean', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        expect(find.byTooltip('로비 이름 바꾸기'), findsOneWidget);
        expect(find.byTooltip('로비 삭제하기'), findsOneWidget);
      });

      testWidgets('gives a screen reader the zone name and the actions that move the zone', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(tester);

        final first = tester.getSemantics(find.text('로비')).getSemanticsData();
        final last = tester.getSemantics(find.text('탕비실')).getSemanticsData();

        expect(first.label, '로비');
        expect(first.customSemanticsActionIds!.map((id) => CustomSemanticsAction.getAction(id)!.label), [
          'Move down',
          'Move to the end',
        ]);
        expect(last.customSemanticsActionIds!.map((id) => CustomSemanticsAction.getAction(id)!.label), [
          'Move to the start',
          'Move up',
        ]);
        semantics.dispose();
      });
    });

    group('client menu', () {
      testWidgets('renames the client from the dialog, which opens with the name of the client', (tester) async {
        await pumpPage(tester);

        await openMenu(tester, 'Rename');
        expect(find.widgetWithText(AlertDialog, 'Rename Client'), findsOneWidget);
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '한빛 사무실');
        await submitName(tester, '한빛 본사', button: 'Save');

        expect(find.byType(NameDialog), findsNothing);
        expect(find.widgetWithText(AppBar, '한빛 본사'), findsOneWidget);
        expect((await clients.clientById(clientId))!.name, '한빛 본사');
        expect(await clients.zonesOf(clientId), zones);
      });

      testWidgets('shows the validation message for an empty client name under the name field', (tester) async {
        await pumpPage(tester);

        await openMenu(tester, 'Rename');
        await submitName(tester, ' ', button: 'Save');

        expect(fieldError(tester), 'Enter a name.');
        expect((await clients.clientById(clientId))!.name, '한빛 사무실');
      });

      testWidgets('opens the rename dialog again without the problem of the name before', (tester) async {
        await pumpPage(tester);

        await openMenu(tester, 'Rename');
        await submitName(tester, '', button: 'Save');
        expect(fieldError(tester), 'Enter a name.');
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        await openMenu(tester, 'Rename');

        expect(fieldError(tester), isNull);
      });

      testWidgets('archives the client after the person confirms, and closes the screen', (tester) async {
        await pumpPage(tester);

        await openMenu(tester, 'Archive');
        expect(find.widgetWithText(AlertDialog, 'Archive this client?'), findsOneWidget);
        expect(
          find.text("It leaves the client list, and you can't bring it back yet. Its visit records are kept."),
          findsOneWidget,
        );
        // An archive deletes nothing, so its question is not destructive.
        expect(tester.filledButtonColor('Archive'), appTheme().colorScheme.primary);
        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await tester.pumpAndSettle();

        expect(find.byType(ClientDetailPage), findsNothing);
        expect(find.text('host'), findsOneWidget);
        expect((await clients.clientById(clientId))!.isArchived, isTrue);
        expect(await clients.activeClients(), isEmpty);
      });

      testWidgets('closes only the client screen when the person presses back while the archive is on its way', (
        tester,
      ) async {
        await pumpPage(tester);
        await openMenu(tester, 'Archive');
        clients.gate = Completer<void>();

        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.tap(find.byType(BackButton), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsOneWidget);

        clients.gate!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ClientDetailPage), findsNothing);
        expect(find.text('host'), findsOneWidget);
      });

      testWidgets('keeps the client when the person closes the question', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        await openMenu(tester, '보관하기');
        expect(find.widgetWithText(AlertDialog, '거래처를 보관할까요?'), findsOneWidget);
        expect(find.text('거래처 목록에서 사라지고, 아직은 다시 꺼낼 수 없어요. 방문 기록은 그대로 남아요.'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '보관하기'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, '닫기'));
        await tester.pumpAndSettle();

        expect(find.byType(ClientDetailPage), findsOneWidget);
        expect((await clients.clientById(clientId))!.isArchived, isFalse);
      });

      testWidgets('keeps the screen open and shows a message when storage does not archive the client', (
        tester,
      ) async {
        await pumpPage(tester);
        clients.failure = failure;

        await openMenu(tester, 'Archive');
        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await tester.pumpAndSettle();

        expect(find.byType(ClientDetailPage), findsOneWidget);
        expect(find.widgetWithText(SnackBar, "Can't save right now. Try again."), findsOneWidget);
      });

      testWidgets('names the rename dialog in Korean', (tester) async {
        await pumpPage(tester, locale: const Locale('ko'));

        await openMenu(tester, '이름 바꾸기');

        expect(find.widgetWithText(AlertDialog, '거래처 이름 바꾸기'), findsOneWidget);
        expect(find.text('거래처 이름'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
      });
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      const longZoneName = '1층 로비와 엘리베이터 앞 복도';
      final longZones = ClientZones(
        clientId: clientId,
        zones: [
          Zone(id: 'zone-1', clientId: clientId, name: longZoneName, position: 0),
          Zone(id: 'zone-2', clientId: clientId, name: '화장실', position: 1),
        ],
      );

      Future<void> expectWholeTextAfterScroll(WidgetTester tester, String text) async {
        await tester.scrollUntilVisible(find.text(text), 100);
        tester.expectWholeText(text);
      }

      testWidgets('fits the zones and the visits and cuts none of their text', (tester) async {
        tester.useNarrowScreenWithLargestText();

        await pumpPage(tester, savedZones: longZones, visits: [september, october], locale: const Locale('ko'));

        for (final text in ['방문 시작하기', '구역', longZoneName, '화장실', '구역 추가하기', '지난 방문', '2026년 10월 1일', '2026년 9월 16일']) {
          await expectWholeTextAfterScroll(tester, text);
        }
      });

      for (final (locale, texts) in [
        (
          const Locale('en'),
          [
            'Start Visit',
            'Zones',
            noZonesInEnglish,
            'Add Zone',
            'Past visits',
            'No visits yet.',
          ],
        ),
        (
          const Locale('ko'),
          [
            '방문 시작하기',
            '구역',
            '아직 구역이 없어요. 구역은 방문할 때마다 청소 전후 사진을 찍는 곳이에요. 로비, 화장실처럼 나눠서 추가해 주세요.',
            '구역 추가하기',
            '지난 방문',
            '아직 방문 기록이 없어요.',
          ],
        ),
      ]) {
        testWidgets('fits the messages of a client without zones and visits in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(
            tester,
            savedZones: ClientZones(clientId: clientId),
            locale: locale,
          );

          for (final text in texts) {
            await expectWholeTextAfterScroll(tester, text);
          }
        });
      }

      for (final (locale, start, help, cancel) in [
        (const Locale('en'), 'Start Visit', 'Visit date', 'Cancel'),
        (const Locale('ko'), '방문 시작하기', '방문 날짜', '닫기'),
      ]) {
        testWidgets('fits the date picker of a visit and its buttons in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, savedZones: longZones, locale: locale);

          await tester.tap(find.widgetWithText(FilledButton, start));
          await tester.pumpAndSettle();

          // The picker has a text scale limit of its own, without which its header overflows on this screen.
          final picker = find.byType(DatePickerDialog);
          expect(find.descendant(of: picker, matching: find.text(help)), findsOneWidget);
          expect(find.descendant(of: picker, matching: find.widgetWithText(TextButton, cancel)), findsOneWidget);
          tester
            ..expectWholeText(help)
            ..expectWholeText(cancel)
            ..expectWholeText(start);
          expect(MediaQuery.textScalerOf(tester.element(picker)).scale(10), 20);
          await tester.tap(find.descendant(of: picker, matching: find.widgetWithText(TextButton, start)));
          await tester.pumpAndSettle();

          expect(find.byType(VisitCapturePage), findsOneWidget);
        });
      }

      for (final (locale, rename, archive, title, message, cancel) in [
        (
          const Locale('en'),
          'Rename',
          'Archive',
          'Archive this client?',
          "It leaves the client list, and you can't bring it back yet. Its visit records are kept.",
          'Cancel',
        ),
        (
          const Locale('ko'),
          '이름 바꾸기',
          '보관하기',
          '거래처를 보관할까요?',
          '거래처 목록에서 사라지고, 아직은 다시 꺼낼 수 없어요. 방문 기록은 그대로 남아요.',
          '닫기',
        ),
      ]) {
        testWidgets('fits the client menu and the question before the client is archived in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, savedZones: longZones, locale: locale);

          await tester.tap(clientMenu);
          await tester.pumpAndSettle();
          tester
            ..expectWholeText(rename)
            ..expectWholeText(archive);
          await tester.tap(find.text(archive));
          await tester.pumpAndSettle();

          tester
            ..expectWholeText(title)
            ..expectWholeText(message)
            ..expectWholeText(cancel);
          expect(find.widgetWithText(FilledButton, archive), findsOneWidget);
        });
      }

      testWidgets('fits the question before a zone with a long name is removed', (tester) async {
        tester.useNarrowScreenWithLargestText();
        await pumpPage(tester, savedZones: longZones, locale: const Locale('ko'));

        await tester.tap(find.byTooltip('$longZoneName 삭제하기'));
        await tester.pumpAndSettle();

        tester
          ..expectWholeText('$longZoneName 구역을 삭제할까요?')
          ..expectWholeText('새로 시작하는 방문부터 이 구역이 빠져요. 지난 방문 기록에는 그대로 남아요.')
          ..expectWholeText('삭제하기');
      });

      testWidgets('fits the dialog for a zone name and cuts neither its label nor a problem under the field', (
        tester,
      ) async {
        tester.useNarrowScreenWithLargestText();
        await pumpPage(tester, savedZones: longZones, locale: const Locale('ko'));

        await tester.scrollUntilVisible(find.byTooltip('화장실 이름 바꾸기'), 100);
        await tester.tap(find.byTooltip('화장실 이름 바꾸기'));
        await tester.pumpAndSettle();
        await submitName(tester, longZoneName, button: '저장하기');

        tester
          ..expectWholeText('구역 이름 바꾸기')
          ..expectWholeText('구역 이름')
          ..expectWholeText('같은 이름의 구역이 있어요. 다른 이름을 입력해 주세요.');
      });

      testWidgets('fits the dialog for a new zone with a failure of storage under the field, in English', (
        tester,
      ) async {
        tester.useNarrowScreenWithLargestText();
        await pumpPage(
          tester,
          savedZones: ClientZones(
            clientId: clientId,
            zones: [Zone(id: 'zone-1', clientId: clientId, name: 'Lobby', position: 0)],
          ),
        );

        await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Add Zone'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'));
        await tester.pumpAndSettle();
        await submitName(tester, 'Lobby', button: 'Add');
        tester
          ..expectWholeText('Zone name')
          ..expectWholeText('Another zone has this name. Enter a different name.');

        clients.failure = failure;
        await submitName(tester, 'Hall', button: 'Add');
        tester.expectWholeText("Can't save right now. Try again.");
      });

      testWidgets('fits the dialog for the client name with a problem under the field', (tester) async {
        tester.useNarrowScreenWithLargestText();
        await pumpPage(tester, savedZones: longZones, locale: const Locale('ko'));

        await openMenu(tester, '이름 바꾸기');
        await submitName(tester, '', button: '저장하기');

        tester
          ..expectWholeText('거래처 이름 바꾸기')
          ..expectWholeText('거래처 이름')
          ..expectWholeText('이름을 입력해 주세요.');
      });

      for (final (locale, removeTooltip, confirm, message) in [
        (const Locale('en'), 'Remove 화장실', 'Remove', "Can't save right now. Try again."),
        (const Locale('ko'), '화장실 삭제하기', '삭제하기', '저장하지 못했어요. 다시 시도해 주세요.'),
      ]) {
        testWidgets('fits the message of a failed save in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();
          await pumpPage(tester, savedZones: longZones, locale: locale);
          clients.failure = failure;

          await tester.scrollUntilVisible(find.byTooltip(removeTooltip), 100);
          await tester.tap(find.byTooltip(removeTooltip));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, confirm));
          await tester.pumpAndSettle();

          expect(find.byType(SnackBar), findsOneWidget);
          tester.expectWholeText(message);
        });
      }

      for (final (locale, message, retry) in [
        (const Locale('en'), "Can't load this client. Try again.", 'Try Again'),
        (const Locale('ko'), '거래처를 불러오지 못했어요. 다시 시도해 주세요.', '다시 불러오기'),
      ]) {
        testWidgets('fits the message of a failed load in ${locale.languageCode}', (tester) async {
          tester.useNarrowScreenWithLargestText();

          await pumpPage(tester, locale: locale, loadFailure: failure);

          tester
            ..expectWholeText(message)
            ..expectWholeText(retry);
        });
      }
    });
  });

  group('report link', () {
    const en = (
      title: 'Report link',
      none: 'No link shared yet. When you share a link from a visit report, this client gets one.',
      open: 'The link is open. Anyone who has it can open the reports of this client.',
      closed:
          'The link is closed. The links you sent no longer open. The next time you share a link, a new one is made.',
      closing: 'Closing the links you sent. They can still open the reports until this is done.',
      failed:
          "Can't close a link you sent, so it can still open the reports. To have it closed, write to the contact in "
          'the privacy policy at the bottom of a report page.',
      deletionUnfinished:
          'A previous link may still open because its deletion is unconfirmed. A new link does not close it. To finish '
          'deleting all data, use Delete All Data in Company profile again.',
      loadFailed: "Can't load the link. Try again.",
      retry: 'Try Again',
      close: 'Close Link',
      reissue: 'Make New Link',
      closeTitle: 'Close the link?',
      closeMessage:
          'The current link of this client stops opening, and its photos are deleted from the server. The '
          'next time you share a link, a new one is made.',
      reissueTitle: 'Make a new link?',
      reissueMessage:
          'The current link stops opening, and its reports are uploaded again under a new link. To send the new '
          'link, share it from a visit report.',
      requestFailed: "Can't change the link. Try again.",
      dismiss: 'Cancel',
    );
    const ko = (
      title: '보고서 링크',
      none: '아직 공유한 링크가 없어요. 방문 보고서에서 링크로 공유하면 이 거래처의 링크가 만들어져요.',
      open: '링크가 열려 있어요. 링크가 있으면 누구나 이 거래처의 보고서를 볼 수 있어요.',
      closed: '링크를 막았어요. 보낸 링크는 더 이상 열리지 않아요. 다음에 링크로 공유하면 새 링크가 만들어져요.',
      closing: '보낸 링크를 막고 있어요. 다 막을 때까지는 그 링크로 보고서가 열릴 수 있어요.',
      failed: '보낸 링크를 막지 못해서 그 링크로 보고서가 아직 열릴 수 있어요. 링크를 막으려면 보고서 페이지 아래의 개인정보 처리방침에 있는 연락처로 요청해 주세요.',
      deletionUnfinished:
          '이전 링크가 지워졌는지 확인되지 않아 보고서가 아직 열릴 수 있어요. 새 링크를 만들어도 이전 링크는 닫히지 않아요. 회사 정보에서 모든 데이터 지우기를 다시 해 주세요.',
      loadFailed: '링크를 불러오지 못했어요. 다시 시도해 주세요.',
      retry: '다시 불러오기',
      close: '링크 막기',
      reissue: '새 링크 만들기',
      closeTitle: '링크를 막을까요?',
      closeMessage: '이 거래처의 현재 링크가 더 이상 열리지 않고, 그 링크로 올린 사진을 서버에서 지워요. 다음에 링크로 공유하면 새 링크가 만들어져요.',
      reissueTitle: '새 링크를 만들까요?',
      reissueMessage: '현재 링크는 더 이상 열리지 않고, 그 링크의 보고서를 새 링크로 다시 올려요. 새 링크는 방문 보고서에서 링크로 공유해서 보낼 수 있어요.',
      requestFailed: '링크를 바꾸지 못했어요. 다시 시도해 주세요.',
      dismiss: '닫기',
    );
    final created = DateTime.utc(2026, 9, 20);
    final openPage = ClientPage(id: 'page-1', clientId: clientId, createdAt: created);
    const refused = PublishException(PublishErrorKind.refused, 'The rules refused the write');

    late FakePublishRepository publishing;
    late FakePublisher publisher;
    late PublishQueue linkQueue;

    setUp(() {
      publishing = FakePublishRepository();
      publisher = FakePublisher();
    });

    /// Stores [page], and a done publish job of the September visit under it, as a publish leaves them.
    void storePage(ClientPage page) {
      publishing.pagesById[page.id] = page;
      final job = PublishJob(
        id: 'publish-${page.id}',
        kind: PublishJobKind.publish,
        pageId: page.id,
        visitId: september.id,
        createdAt: page.createdAt,
      ).succeed();
      publishing.jobs[job.id] = job;
    }

    /// Stores a revoked page with a revoke job of [status], which stopped for [failure] when it failed.
    void storeRevokedPage(String id, PublishJobStatus status, {PublishFailure failure = PublishFailure.refused}) {
      storePage(ClientPage(id: id, clientId: clientId, createdAt: created, revokedAt: created));
      final job = PublishJob(id: 'revoke-$id', kind: PublishJobKind.revoke, pageId: id, createdAt: created);
      publishing.jobs[job.id] = switch (status) {
        PublishJobStatus.pending => job,
        PublishJobStatus.done => job.succeed(),
        PublishJobStatus.failed => job.fail(failure),
      };
    }

    /// Opens the client screen from a host screen in a flavor that publishes, over the store of the test.
    Future<void> pumpLinkPage(WidgetTester tester, {Locale? locale}) async {
      clients = FakeClientRepository(clients: [office], zones: [zones]);
      visitRepository = FakeVisitRepository(visits: [september]);
      final repositories = Repositories(
        clients: clients,
        visits: visitRepository,
        companyProfile: FakeCompanyProfileRepository(),
        publishing: publishing,
        openCaptures: FakeOpenCaptureRepository(),
        localData: FakeLocalDataRepository(),
      );
      final queue = linkQueue = publishQueueOf(repositories, publisher: publisher);
      addTearDown(queue.dispose);
      await tester.pumpApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(ClientDetailPage.route(clientId: clientId)),
              child: const Text('host'),
            ),
          ),
        ),
        locale: locale,
        repositories: repositories,
        publishQueue: queue,
        clock: FixedClock(DateTime(2026, 10, 20, 12)),
      );
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();
    }

    /// Drags the list until [text] is inside it.
    ///
    /// `scrollUntilVisible` does not move the list for a widget in the footer of a reorderable list, which it finds
    /// before the drag, so the test drags until the text is in view.
    Future<void> scrollTo(WidgetTester tester, String text) async {
      final finder = find.text(text);
      final list = find.byType(Scrollable).first;
      for (var drags = 0; drags < 50; drags++) {
        final view = tester.getRect(list);
        final found = finder.evaluate().isEmpty ? null : tester.getRect(finder);
        // At the largest text size a message can be taller than the list, and its start at the top is enough then.
        final move = switch (found) {
          null => -100.0,
          _ when found.top < view.top => view.top - found.top,
          _ when found.height > view.height => view.top - found.top,
          _ when found.bottom > view.bottom => view.bottom - found.bottom,
          _ => 0.0,
        };
        if (move.abs() < 1) return;
        await tester.drag(list, Offset(0, move));
        await tester.pumpAndSettle();
      }
      fail('"$text" did not come into view');
    }

    /// Presses [button] of the link section, and then [confirm] in the question that it opens.
    Future<void> pressAndConfirm(WidgetTester tester, String button, {String? confirm}) async {
      await scrollTo(tester, button);
      await tester.tap(find.widgetWithText(OutlinedButton, button));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, confirm ?? button));
      await tester.pumpAndSettle();
    }

    testWidgets('intent-only page warns without old link controls', (tester) async {
      storePage(openPage.requestServerDeletion(created));
      await pumpLinkPage(tester);
      await scrollTo(tester, en.deletionUnfinished);
      expect(find.text(en.close), findsNothing);
      expect(find.text(en.reissue), findsNothing);
      expect(find.text(en.open), findsNothing);
      expect(find.text(en.closed), findsNothing);
    });

    testWidgets('confirmed deletion uses closed copy without a revoke job', (tester) async {
      storePage(openPage.confirmServerDeletion(created));
      await pumpLinkPage(tester);
      await scrollTo(tester, en.closed);
      expect(find.text(en.close), findsNothing);
      expect(find.text(en.deletionUnfinished), findsNothing);
    });

    for (final confirmed in [false, true]) {
      testWidgets('fresh open controls coexist with old page confirmed=$confirmed', (tester) async {
        final old = ClientPage(
          id: 'old',
          clientId: clientId,
          createdAt: created,
          serverDeleteRequestedAt: created,
          serverDeletedAt: confirmed ? created : null,
        );
        storePage(old);
        storePage(openPage);
        await pumpLinkPage(tester);
        await scrollTo(tester, en.open);
        expect(find.text(en.close), findsOneWidget);
        expect(find.text(en.reissue), findsOneWidget);
        expect(find.text(en.closed), findsNothing);
        if (!confirmed) {
          await scrollTo(tester, en.deletionUnfinished);
          expect(find.text(en.deletionUnfinished), findsOneWidget);
        } else {
          expect(find.text(en.deletionUnfinished), findsNothing);
        }
      });
    }

    testWidgets('failed link read shows retry and no stale controls, then reloads', (tester) async {
      storePage(openPage);
      publishing.failure = Exception('read failed');
      await pumpLinkPage(tester);
      await scrollTo(tester, en.retry);
      expect(find.text(en.close), findsNothing);
      publishing.failure = null;
      await tester.tap(find.text(en.retry));
      await tester.pumpAndSettle();
      await scrollTo(tester, en.open);
      expect(find.text(en.close), findsOneWidget);
    });

    for (final button in [en.close, en.reissue]) {
      testWidgets('$button dialog describes only the current link when an old deletion is unconfirmed', (tester) async {
        storePage(ClientPage(id: 'old', clientId: clientId, createdAt: created, serverDeleteRequestedAt: created));
        storePage(openPage);
        await pumpLinkPage(tester);
        await scrollTo(tester, button);
        await tester.tap(find.widgetWithText(OutlinedButton, button));
        await tester.pumpAndSettle();
        final message = button == en.close
            ? 'The current link of this client stops opening, and its photos are deleted from the server. The next time you share a link, a new one is made.'
            : 'The current link stops opening, and its reports are uploaded again under a new link. To send the new link, share it from a visit report.';
        expect(find.text('$message\n\n${en.deletionUnfinished}'), findsOneWidget);
        expect(find.textContaining('Every link'), findsNothing);
        expect(find.textContaining('The links you sent stop opening'), findsNothing);
      });
    }

    for (final fails in [false, true]) {
      testWidgets('request guard remains through an unrelated refresh failure=$fails', (tester) async {
        storePage(openPage);
        await pumpLinkPage(tester);
        final requestGate = publishing.revokeGate = Completer<void>();
        await pressAndConfirm(tester, en.close);
        final other = ClientPage(
          id: 'other',
          clientId: 'other-client',
          createdAt: created,
          serverDeleteRequestedAt: created,
        );
        publishing.pagesById[other.id] = other;
        publishing.jobs['other-job'] = PublishJob(
          id: 'other-job',
          kind: PublishJobKind.publish,
          pageId: other.id,
          visitId: september.id,
          createdAt: created,
        );
        final readGate = publishing.pagesGate = Completer<void>();
        await linkQueue.start();
        await tester.pumpAndSettle();
        if (fails) {
          readGate.completeError(Exception('refresh failed'));
        } else {
          readGate.complete();
        }
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsOneWidget);
        final cubit = tester.element(find.byType(ClientDetailView)).read<ClientLinkCubit>();
        expect(cubit.state.takesAction, isFalse);
        if (fails) {
          expect(find.text(en.loadFailed), findsOneWidget);
          expect(find.text(en.close), findsNothing);
        }
        requestGate.complete();
        await tester.pumpAndSettle();
        expect(cubit.state.isRequesting, isFalse);
      });
    }

    testWidgets('shows no link section in a flavor without a backend', (tester) async {
      await pumpPage(tester, visits: [september]);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(find.text(en.title), findsNothing);
      expect(find.text(en.close), findsNothing);
    });

    testWidgets('says that the client has no link yet, and offers no action', (tester) async {
      await pumpLinkPage(tester);

      await scrollTo(tester, en.none);

      expect(find.text(en.title), findsOneWidget);
      expect(find.text(en.close), findsNothing);
      expect(find.text(en.reissue), findsNothing);
    });

    testWidgets('closes the link after the person confirms, and says it is closed only when the job is done', (
      tester,
    ) async {
      storePage(openPage);
      final gate = publisher.gates['revokePage'] = Completer<void>();
      await pumpLinkPage(tester);
      await scrollTo(tester, en.open);

      await scrollTo(tester, en.close);
      await tester.tap(find.widgetWithText(OutlinedButton, en.close));
      await tester.pumpAndSettle();
      expect(find.text(en.closeTitle), findsOneWidget);
      expect(find.text(en.closeMessage), findsOneWidget);
      expect(tester.filledButtonColor(en.close), appTheme().colorScheme.error);
      await tester.tap(find.widgetWithText(FilledButton, en.close));
      await tester.pumpAndSettle();

      expect(publisher.calls, ['revokePage ${openPage.id}']);
      await scrollTo(tester, en.closing);
      expect(tester.noticeToneOf(en.closing), NoticeTone.info);
      expect(find.text(en.open), findsNothing);
      expect(find.text(en.closed), findsNothing);
      expect(find.text(en.close), findsNothing);
      expect(find.text(en.reissue), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      await scrollTo(tester, en.closed);
      expect(find.text(en.closing), findsNothing);
      expect(publishing.pagesById[openPage.id]!.isRevoked, isTrue);
    });

    testWidgets('keeps the link when the person closes the question', (tester) async {
      storePage(openPage);
      await pumpLinkPage(tester);

      await scrollTo(tester, en.close);
      await tester.tap(find.widgetWithText(OutlinedButton, en.close));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, en.dismiss));
      await tester.pumpAndSettle();
      await scrollTo(tester, en.reissue);
      await tester.tap(find.widgetWithText(OutlinedButton, en.reissue));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, en.dismiss));
      await tester.pumpAndSettle();

      expect(find.text(en.open), findsOneWidget);
      expect(publishing.pagesById.values.single.isRevoked, isFalse);
      expect(publisher.calls, isEmpty);
    });

    testWidgets('makes a new link after the person confirms, and says that the old links are closing', (
      tester,
    ) async {
      storePage(openPage);
      final gate = publisher.gates['revokePage'] = Completer<void>();
      await pumpLinkPage(tester);

      await scrollTo(tester, en.reissue);
      await tester.tap(find.widgetWithText(OutlinedButton, en.reissue));
      await tester.pumpAndSettle();
      expect(find.text(en.reissueTitle), findsOneWidget);
      expect(find.text(en.reissueMessage), findsOneWidget);
      // A new link closes the links that were sent.
      expect(tester.filledButtonColor(en.reissue), appTheme().colorScheme.error);
      await tester.tap(find.widgetWithText(FilledButton, en.reissue));
      await tester.pumpAndSettle();

      await scrollTo(tester, en.closing);
      expect(find.text(en.open), findsOneWidget);
      expect(find.text(en.close), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(en.closing), findsNothing);
      expect(find.text(en.closed), findsNothing);
      expect(find.text(en.open), findsOneWidget);
      final replacement = publishing.pagesById.values.singleWhere((page) => !page.isRevoked);
      expect(publisher.reports.keys, ['${replacement.id}/${september.id}']);
    });

    testWidgets('says that the link did not close when its revoke job stops', (tester) async {
      storePage(openPage);
      publisher.failures['revokePage'] = [refused];
      await pumpLinkPage(tester);

      await pressAndConfirm(tester, en.close);

      await scrollTo(tester, en.failed);
      expect(tester.noticeToneOf(en.failed), NoticeTone.error);
      expect(find.text(en.closing), findsNothing);
      expect(find.text(en.closed), findsNothing);
      expect(find.text(en.none), findsNothing);
      expect(find.text(en.deletionUnfinished), findsNothing);
    });

    testWidgets('says that the deletion of all data did not finish when it stopped the revoke job', (tester) async {
      storeRevokedPage('page-0', PublishJobStatus.failed, failure: PublishFailure.deletion);
      await pumpLinkPage(tester);

      await scrollTo(tester, en.deletionUnfinished);
      expect(tester.noticeToneOf(en.deletionUnfinished), NoticeTone.error);
      expect(find.text(en.failed), findsNothing);
      expect(find.text(en.closing), findsNothing);
      expect(find.text(en.closed), findsNothing);
      expect(find.text(en.none), findsNothing);
    });

    testWidgets('takes no touch and no back press while the close is on its way to storage', (tester) async {
      storePage(openPage);
      final gate = publishing.revokeGate = Completer<void>();
      await pumpLinkPage(tester);

      await pressAndConfirm(tester, en.close);
      await tester.tap(find.widgetWithText(OutlinedButton, en.reissue), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(en.reissueTitle), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ClientDetailPage), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      await scrollTo(tester, en.closed);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ClientDetailPage), findsNothing);
    });

    testWidgets('keeps the link and shows a message when storage does not take the new link', (tester) async {
      storePage(openPage);
      publishing.revokeFailure = Exception('storage failed');
      await pumpLinkPage(tester);

      await pressAndConfirm(tester, en.reissue);

      expect(find.widgetWithText(SnackBar, en.requestFailed), findsOneWidget);
      expect(find.text(en.open), findsOneWidget);
      expect(publishing.pagesById.values.single.isRevoked, isFalse);
    });

    testWidgets('shows a message and a retry control when the link does not load, and loads it on retry', (
      tester,
    ) async {
      storePage(openPage);
      publishing.failure = Exception('storage failed');
      await pumpLinkPage(tester);

      await scrollTo(tester, en.loadFailed);
      expect(tester.noticeToneOf(en.loadFailed), NoticeTone.error);
      publishing.failure = null;
      await scrollTo(tester, en.retry);
      await tester.tap(find.widgetWithText(OutlinedButton, en.retry));
      await tester.pumpAndSettle();

      await scrollTo(tester, en.open);
      expect(find.text(en.loadFailed), findsNothing);
    });

    testWidgets('shows the link section and its questions in Korean', (tester) async {
      storePage(openPage);
      await pumpLinkPage(tester, locale: const Locale('ko'));

      await scrollTo(tester, ko.open);
      expect(find.text(ko.title), findsOneWidget);
      await scrollTo(tester, ko.close);
      await tester.tap(find.widgetWithText(OutlinedButton, ko.close));
      await tester.pumpAndSettle();
      expect(find.text(ko.closeTitle), findsOneWidget);
      expect(find.text(ko.closeMessage), findsOneWidget);
      expect(find.widgetWithText(TextButton, ko.dismiss), findsOneWidget);
      expect(find.widgetWithText(FilledButton, ko.close), findsOneWidget);
      // The dismiss button of every question says 닫기, so the button that closes the link must not use that word.
      expect(ko.close, isNot(contains(ko.dismiss)));
    });

    group('on a screen 320 pixels wide at the largest text size', () {
      for (final (locale, texts) in [(const Locale('en'), en), (const Locale('ko'), ko)]) {
        testWidgets('fits an open link, a closing link, failed closes, and both questions in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          storeRevokedPage('page-0', PublishJobStatus.failed);
          storeRevokedPage('page-00', PublishJobStatus.pending);
          storeRevokedPage('page-000', PublishJobStatus.failed, failure: PublishFailure.deletion);
          storePage(openPage);
          // The queue of the test runs no job until a request, so the revoke job stays pending.
          await pumpLinkPage(tester, locale: locale);

          for (final text in [
            texts.title,
            texts.open,
            texts.closing,
            texts.failed,
            texts.deletionUnfinished,
            texts.reissue,
            texts.close,
          ]) {
            await scrollTo(tester, text);
            tester.expectWholeText(text);
          }
          for (final (button, title, message) in [
            (texts.close, texts.closeTitle, '${texts.closeMessage}\n\n${texts.deletionUnfinished}'),
            (texts.reissue, texts.reissueTitle, '${texts.reissueMessage}\n\n${texts.deletionUnfinished}'),
          ]) {
            await scrollTo(tester, button);
            await tester.tap(find.widgetWithText(OutlinedButton, button));
            await tester.pumpAndSettle();
            tester
              ..expectWholeText(title)
              ..expectWholeText(message)
              ..expectWholeText(texts.dismiss)
              // The page behind the question shows the same label, and the check covers both.
              ..expectWholeText(button);
            expect(find.widgetWithText(FilledButton, button), findsOneWidget);
            await tester.tap(find.widgetWithText(TextButton, texts.dismiss));
            await tester.pumpAndSettle();
          }
        });

        testWidgets('fits the message of a close that storage does not take in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          storePage(openPage);
          publishing.revokeFailure = Exception('storage failed');
          await pumpLinkPage(tester, locale: locale);

          await pressAndConfirm(tester, texts.close);

          expect(find.byType(SnackBar), findsOneWidget);
          tester.expectWholeText(texts.requestFailed);
        });

        testWidgets('fits a closed link, a client without a link, and a failed load in ${locale.languageCode}', (
          tester,
        ) async {
          tester.useNarrowScreenWithLargestText();
          storeRevokedPage('page-0', PublishJobStatus.done);
          await pumpLinkPage(tester, locale: locale);
          await scrollTo(tester, texts.closed);
          tester.expectWholeText(texts.closed);

          publishing
            ..pagesById.clear()
            ..jobs.clear();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await tester.tap(find.text('host'));
          await tester.pumpAndSettle();
          await scrollTo(tester, texts.none);
          tester.expectWholeText(texts.none);

          publishing.failure = Exception('storage failed');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await tester.tap(find.text('host'));
          await tester.pumpAndSettle();
          for (final text in [texts.loadFailed, texts.retry]) {
            await scrollTo(tester, text);
            tester.expectWholeText(text);
          }
        });
      }
    });
  });

  group('ClientDetailView', () {
    late ClientDetailCubit cubit;
    late ClientLinkCubit linkCubit;

    setUpAll(() => registerFallbackValue(VisitDate(2026, 10, 1)));

    setUp(() {
      cubit = _MockClientDetailCubit();
      linkCubit = _MockClientLinkCubit();
      when(() => linkCubit.state).thenReturn(const ClientLinkState(status: ClientLinkStatus.unavailable));
    });

    /// Pumps the view under the repositories and the clock that its date picker and the visit screen read.
    Future<void> pumpClientView(WidgetTester tester) => tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider.value(value: linkCubit),
        ],
        child: const ClientDetailView(),
      ),
      repositories: Repositories(
        clients: FakeClientRepository(),
        visits: FakeVisitRepository(visits: [october]),
        companyProfile: FakeCompanyProfileRepository(),
        publishing: MockPublishRepository(),
        openCaptures: FakeOpenCaptureRepository(),
        localData: FakeLocalDataRepository(),
      ),
      clock: FixedClock(DateTime(2026, 10, 20, 12)),
    );

    Future<void> pumpView(WidgetTester tester, ClientDetailState state) async {
      when(() => cubit.state).thenReturn(state);
      await pumpClientView(tester);
    }

    testWidgets('shows a progress indicator and no client menu while the client loads', (tester) async {
      await pumpView(tester, const ClientDetailState());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(clientMenu, findsNothing);
    });

    for (final status in [
      ClientDetailStatus.saving,
      ClientDetailStatus.saveFailed,
      ClientDetailStatus.archived,
      ClientDetailStatus.visitStarted,
    ]) {
      testWidgets('keeps the client on the screen in the ${status.name} status', (tester) async {
        await pumpView(tester, ClientDetailState(status: status, client: office, zones: zones));

        expect(find.widgetWithText(AppBar, '한빛 사무실'), findsOneWidget);
        expect(listedZoneNames(tester), ['로비', '복도', '탕비실']);
      });
    }

    testWidgets('passes each change of the zone list to the cubit', (tester) async {
      when(() => cubit.addZone(any())).thenAnswer((_) async {});
      when(() => cubit.renameZone(any(), any())).thenAnswer((_) async {});
      when(() => cubit.removeZone(any())).thenAnswer((_) async {});
      when(() => cubit.moveZone(any(), any())).thenAnswer((_) async {});
      await pumpView(tester, ClientDetailState(status: ClientDetailStatus.ready, client: office, zones: zones));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Add Zone'));
      await tester.pumpAndSettle();
      await submitName(tester, '화장실', button: 'Add');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rename 로비'));
      await tester.pumpAndSettle();
      await submitName(tester, '현관', button: 'Save');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove 탕비실'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      await dragZone(tester, index: 0, rows: 0.75);

      verifyInOrder([
        () => cubit.startNameEntry(),
        () => cubit.addZone('화장실'),
        () => cubit.startNameEntry(),
        () => cubit.renameZone('zone-1', '현관'),
        () => cubit.removeZone('zone-3'),
        () => cubit.moveZone(0, 1),
      ]);
    });

    testWidgets('passes the picked visit date to the cubit', (tester) async {
      when(() => cubit.startVisit(any())).thenAnswer((_) async {});
      await pumpView(tester, ClientDetailState(status: ClientDetailStatus.ready, client: office, zones: zones));

      await tester.tap(find.widgetWithText(FilledButton, 'Start Visit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Start Visit'));
      await tester.pumpAndSettle();

      verify(() => cubit.startVisit(VisitDate(2026, 10, 7))).called(1);
    });

    testWidgets('opens the screen of a started visit once, when the status changes to it', (tester) async {
      final states = StreamController<ClientDetailState>();
      addTearDown(states.close);
      final ready = ClientDetailState(status: ClientDetailStatus.ready, client: office, zones: zones);
      whenListen(cubit, states.stream, initialState: ready);
      await pumpClientView(tester);

      states.add(ready.copyWith(status: ClientDetailStatus.visitStarted, visits: [october], startedVisitId: 'visit-2'));
      await tester.pumpAndSettle();
      expect(find.byType(VisitCapturePage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'October 1, 2026'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // A later state with the same status, such as a refused name, is no new visit.
      states.add(
        ready.copyWith(
          status: ClientDetailStatus.visitStarted,
          visits: [october],
          startedVisitId: 'visit-2',
          entry: NameEntry.empty,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VisitCapturePage), findsNothing);
    });

    testWidgets('shows the message of a failed save once, when the status changes to it', (tester) async {
      final states = StreamController<ClientDetailState>();
      addTearDown(states.close);
      final ready = ClientDetailState(status: ClientDetailStatus.ready, client: office, zones: zones);
      whenListen(cubit, states.stream, initialState: ready);
      await pumpClientView(tester);

      states.add(ready.copyWith(status: ClientDetailStatus.saveFailed));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SnackBar, "Can't save right now. Try again."), findsOneWidget);
      // The message leaves after its time on the screen, which starts when it has come in.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      // A later state with the same status, such as a refused name, is no new failure.
      states.add(ready.copyWith(status: ClientDetailStatus.saveFailed, entry: NameEntry.empty));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
