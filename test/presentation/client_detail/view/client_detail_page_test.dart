import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockClientDetailCubit extends MockCubit<ClientDetailState> implements ClientDetailCubit;

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

  /// Opens the client screen from a host screen, so that the client screen can close itself.
  Future<void> pumpPage(
    WidgetTester tester, {
    ClientZones? savedZones,
    List<Visit> visits = const [],
    Locale? locale,
    Exception? loadFailure,
  }) async {
    clients = FakeClientRepository(clients: [office], zones: [savedZones ?? zones])..failure = loadFailure;
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
        visits: FakeVisitRepository(visits: visits),
        companyProfile: FakeCompanyProfileRepository(),
      ),
    );
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();
  }

  List<String?> listedZoneNames(WidgetTester tester) => tester
      .widgetList<ListTile>(find.descendant(of: find.byType(ReorderableListView), matching: find.byType(ListTile)))
      .where((tile) => tile.trailing != null)
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

  String? fieldError(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).decoration!.errorText;

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

    testWidgets('shows the control that starts a visit as disabled, because its destination is not built', (
      tester,
    ) async {
      await pumpPage(tester);

      final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Visit'));
      expect(start.onPressed, isNull);
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

  group('ClientDetailView', () {
    late ClientDetailCubit cubit;

    setUp(() => cubit = _MockClientDetailCubit());

    Future<void> pumpView(WidgetTester tester, ClientDetailState state) async {
      when(() => cubit.state).thenReturn(state);
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const ClientDetailView()));
    }

    testWidgets('shows a progress indicator and no client menu while the client loads', (tester) async {
      await pumpView(tester, const ClientDetailState());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(clientMenu, findsNothing);
    });

    for (final status in [ClientDetailStatus.saving, ClientDetailStatus.saveFailed, ClientDetailStatus.archived]) {
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

    testWidgets('shows the message of a failed save once, when the status changes to it', (tester) async {
      final states = StreamController<ClientDetailState>();
      addTearDown(states.close);
      final ready = ClientDetailState(status: ClientDetailStatus.ready, client: office, zones: zones);
      whenListen(cubit, states.stream, initialState: ready);
      await tester.pumpApp(BlocProvider.value(value: cubit, child: const ClientDetailView()));

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
