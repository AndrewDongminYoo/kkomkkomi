import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

void main() {
  const clientId = 'client-a';
  final office = Client(id: clientId, name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final lobby = Zone(id: 'zone-1', clientId: clientId, name: '로비', position: 0);
  final hall = Zone(id: 'zone-2', clientId: clientId, name: '복도', position: 1);
  final zones = ClientZones(clientId: clientId, zones: [lobby, hall]);
  final visit = Visit.start(
    id: 'visit-1',
    zones: zones,
    visitDate: VisitDate(2026, 9, 30),
    createdAt: DateTime.utc(2026, 9, 30, 1),
  );
  final failure = Exception('storage failed');

  late MockClientRepository clients;
  late MockVisitRepository visits;

  /// The visit that the cubit starts on [date]: the first identifier of the generator and the time of the clock.
  Visit started(VisitDate date) =>
      Visit.start(id: 'id-1', zones: zones, visitDate: date, createdAt: DateTime.utc(2026, 10, 1, 3));

  ClientDetailCubit build() {
    final idGenerator = SequenceIdGenerator();
    return ClientDetailCubit(
      clientId: clientId,
      clients: clients,
      visits: visits,
      idGenerator: idGenerator,
      startVisit: StartVisit(
        clients: clients,
        visits: visits,
        idGenerator: idGenerator,
        clock: FixedClock(DateTime.utc(2026, 10, 1, 3)),
      ),
    );
  }

  ClientDetailState loaded({
    ClientDetailStatus status = ClientDetailStatus.ready,
    Client? client,
    ClientZones? zoneList,
    NameEntry entry = NameEntry.editing,
    List<Visit>? visitList,
    String? startedVisitId,
  }) => ClientDetailState(
    status: status,
    client: client ?? office,
    zones: zoneList ?? zones,
    visits: visitList ?? [visit],
    entry: entry,
    startedVisitId: startedVisitId,
  );

  void stubSave({Object? thrown}) {
    final save = when(() => clients.save(any(), zones: any(named: 'zones')));
    if (thrown == null) {
      save.thenAnswer((_) async {});
    } else {
      save.thenThrow(thrown);
    }
  }

  setUpAll(() {
    registerFallbackValue(office);
    registerFallbackValue(zones);
    registerFallbackValue(visit);
  });

  setUp(() {
    clients = MockClientRepository();
    visits = MockVisitRepository();
    when(() => clients.clientById(clientId)).thenAnswer((_) async => office);
    when(() => clients.zonesOf(clientId)).thenAnswer((_) async => zones);
    when(() => visits.visitsOf(clientId)).thenAnswer((_) async => [visit]);
    when(() => visits.save(any())).thenAnswer((_) async {});
    stubSave();
  });

  group('ClientDetailState', () {
    test('lists no zone while the zones are not loaded, and the active zones after that', () {
      expect(const ClientDetailState().activeZones, isEmpty);
      expect(loaded(zoneList: zones.remove('zone-1')).activeZones, [hall]);
    });

    test('is equal to a state with the same fields', () {
      expect(loaded(), loaded());
      expect(loaded().hashCode, loaded().hashCode);
    });

    test('differs from a state with another field value', () {
      expect(loaded(), isNot(loaded(status: ClientDetailStatus.saving)));
      expect(loaded(), isNot(loaded(client: office.rename('다온 카페'))));
      expect(loaded(), isNot(loaded(zoneList: zones.remove('zone-1'))));
      expect(loaded(), isNot(loaded(entry: NameEntry.saved)));
      expect(loaded(), isNot(loaded().copyWith(visits: [])));
      expect(loaded(), isNot(loaded(startedVisitId: 'visit-1')));
    });

    test('copyWith keeps the started visit unless it is given another', () {
      final started = loaded(startedVisitId: 'visit-1');

      expect(started.copyWith(status: ClientDetailStatus.saving).startedVisitId, 'visit-1');
      expect(started.copyWith(startedVisitId: 'visit-2').startedVisitId, 'visit-2');
    });

    test('takes a change only while the state holds what storage has', () {
      expect(
        ClientDetailStatus.values.where((status) => loaded(status: status).takesChange),
        [ClientDetailStatus.ready, ClientDetailStatus.saveFailed, ClientDetailStatus.visitStarted],
      );
    });
  });

  group('ClientDetailCubit', () {
    test('starts without a client while the first load runs', () {
      expect(build().state, const ClientDetailState());
      expect(build().state.status, ClientDetailStatus.loading);
    });

    group('load', () {
      blocTest<ClientDetailCubit, ClientDetailState>(
        'shows the client, its zones, and its visits',
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [loaded()],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a client that storage does not have as a failed load',
        setUp: () => when(() => clients.clientById(clientId)).thenAnswer((_) async => null),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const ClientDetailState(status: ClientDetailStatus.loadFailed)],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage',
        setUp: () => when(() => visits.visitsOf(clientId)).thenThrow(failure),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const ClientDetailState(status: ClientDetailStatus.loadFailed)],
        errors: () => [failure],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'shows the loading state and then the client when it runs again after a failure',
        build: build,
        seed: () => const ClientDetailState(status: ClientDetailStatus.loadFailed),
        act: (cubit) => cubit.load(),
        expect: () => [const ClientDetailState(), loaded()],
      );

      test('emits nothing when the cubit closes before storage answers', () async {
        final answer = Completer<Client?>();
        when(() => clients.clientById(clientId)).thenAnswer((_) => answer.future);
        final cubit = build();

        final load = cubit.load();
        await cubit.close();
        answer.complete(office);
        await load;

        expect(cubit.state, const ClientDetailState());
      });

      test('emits nothing when the cubit closes before storage fails', () async {
        final answer = Completer<Client?>();
        when(() => clients.clientById(clientId)).thenAnswer((_) => answer.future);
        final cubit = build();

        final load = cubit.load();
        await cubit.close();
        answer.completeError(failure);
        await load;

        expect(cubit.state, const ClientDetailState());
      });
    });

    group('startNameEntry', () {
      blocTest<ClientDetailCubit, ClientDetailState>(
        'forgets the problem of the last submitted name',
        build: build,
        seed: () => loaded(entry: NameEntry.duplicate),
        act: (cubit) => cubit.startNameEntry(),
        expect: () => [loaded()],
      );
    });

    group('renameClient', () {
      final renamed = office.rename('다온 카페');

      blocTest<ClientDetailCubit, ClientDetailState>(
        'shows the trimmed name at once and saves the client without its zone list',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameClient(' 다온 카페 '),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, client: renamed, entry: NameEntry.saving),
          loaded(client: renamed, entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => clients.save(renamed)).called(1),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'refuses an empty name and saves nothing',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameClient(' '),
        expect: () => [loaded(entry: NameEntry.empty)],
        verify: (_) => verifyNever(() => clients.save(any(), zones: any(named: 'zones'))),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the name entry and shows the old name again',
        setUp: () => stubSave(thrown: failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameClient('다온 카페'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, client: renamed, entry: NameEntry.saving),
          loaded(entry: NameEntry.failed),
        ],
        errors: () => [failure],
      );
    });

    group('addZone', () {
      final added = zones.add(id: 'id-1', name: '탕비실');

      blocTest<ClientDetailCubit, ClientDetailState>(
        'adds a zone with a new identifier after every zone and saves the zone list',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.addZone(' 탕비실 '),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: added, entry: NameEntry.saving),
          loaded(zoneList: added, entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => clients.save(office, zones: added)).called(1),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'refuses an empty name',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.addZone(''),
        expect: () => [loaded(entry: NameEntry.empty)],
        verify: (_) => verifyNever(() => clients.save(any(), zones: any(named: 'zones'))),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'refuses the name of a listed zone',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.addZone('로비'),
        expect: () => [loaded(entry: NameEntry.duplicate)],
        verify: (_) => verifyNever(() => clients.save(any(), zones: any(named: 'zones'))),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a name that storage refuses, because the stored zones differ from the zones that were read',
        setUp: () => stubSave(thrown: const DuplicateZoneNameException('탕비실')),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.addZone('탕비실'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: added, entry: NameEntry.saving),
          loaded(entry: NameEntry.duplicate),
        ],
        errors: () => isEmpty,
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the name entry and lists the old zones again',
        setUp: () => stubSave(thrown: failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.addZone('탕비실'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: added, entry: NameEntry.saving),
          loaded(entry: NameEntry.failed),
        ],
        errors: () => [failure],
      );
    });

    group('renameZone', () {
      final renamed = zones.rename('zone-1', '현관');

      blocTest<ClientDetailCubit, ClientDetailState>(
        'renames the zone and saves the zone list',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameZone('zone-1', ' 현관 '),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: renamed, entry: NameEntry.saving),
          loaded(zoneList: renamed, entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => clients.save(office, zones: renamed)).called(1),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'refuses an empty name',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameZone('zone-1', '  '),
        expect: () => [loaded(entry: NameEntry.empty)],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'refuses the name of another listed zone',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameZone('zone-1', '복도'),
        expect: () => [loaded(entry: NameEntry.duplicate)],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the name entry and shows the old name again',
        setUp: () => stubSave(thrown: failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.renameZone('zone-1', '현관'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: renamed, entry: NameEntry.saving),
          loaded(entry: NameEntry.failed),
        ],
        errors: () => [failure],
      );
    });

    group('moveZone', () {
      final moved = zones.move(from: 0, to: 1);

      blocTest<ClientDetailCubit, ClientDetailState>(
        'shows the new order at once and saves the zone list',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.moveZone(0, 1),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: moved),
          loaded(zoneList: moved),
        ],
        verify: (cubit) {
          expect(cubit.state.activeZones.map((zone) => zone.id), ['zone-2', 'zone-1']);
          verify(() => clients.save(office, zones: moved)).called(1);
        },
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the status and shows the old order again',
        setUp: () => stubSave(thrown: failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.moveZone(0, 1),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: moved),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
        errors: () => [failure],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a refusal of storage in the status, because no name field is open',
        setUp: () => stubSave(thrown: const DuplicateZoneNameException('로비')),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.moveZone(0, 1),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: moved),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'keeps the name entry of the moment when a failed save puts the zones back',
        build: build,
        seed: () => loaded(entry: NameEntry.saved),
        act: (cubit) async {
          final answer = Completer<void>();
          when(() => clients.save(any(), zones: any(named: 'zones'))).thenAnswer((_) => answer.future);
          final move = cubit.moveZone(0, 1);
          cubit.startNameEntry();
          answer.completeError(failure);
          await move;
        },
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: moved, entry: NameEntry.saved),
          loaded(status: ClientDetailStatus.saving, zoneList: moved),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
        errors: () => [failure],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'works again after a failed save',
        build: build,
        seed: () => loaded(status: ClientDetailStatus.saveFailed),
        act: (cubit) => cubit.moveZone(0, 1),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: moved),
          loaded(zoneList: moved),
        ],
      );
    });

    group('removeZone', () {
      final removed = zones.remove('zone-1');

      blocTest<ClientDetailCubit, ClientDetailState>(
        'takes the zone out of the listed zones and saves it as a removed zone',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.removeZone('zone-1'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: removed),
          loaded(zoneList: removed),
        ],
        verify: (cubit) {
          expect(cubit.state.activeZones, [hall]);
          verify(() => clients.save(office, zones: removed)).called(1);
        },
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the status and lists the zone again',
        setUp: () => stubSave(thrown: failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.removeZone('zone-1'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: removed),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
        errors: () => [failure],
      );
    });

    group('archive', () {
      final archived = office.archive();

      blocTest<ClientDetailCubit, ClientDetailState>(
        'saves the client as archived without its zone list and ends in the archived status',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.archive(),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, client: archived),
          loaded(status: ClientDetailStatus.archived, client: archived),
        ],
        verify: (_) => verify(() => clients.save(archived)).called(1),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the status and keeps the client active',
        setUp: () => stubSave(thrown: failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.archive(),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, client: archived),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
        errors: () => [failure],
      );
    });

    group('startVisit', () {
      final october = VisitDate(2026, 10, 1);

      blocTest<ClientDetailCubit, ClientDetailState>(
        'saves a visit with the listed zones, lists it before the older visits, and names it',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.startVisit(october),
        expect: () => [
          loaded(status: ClientDetailStatus.saving),
          loaded(
            status: ClientDetailStatus.visitStarted,
            visitList: [started(october), visit],
            startedVisitId: 'id-1',
          ),
        ],
        verify: (cubit) {
          verify(() => visits.save(started(october))).called(1);
          expect(cubit.state.visits.first.zoneRecords.map((record) => record.zoneName), ['로비', '복도']);
        },
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'lists a visit on an earlier date after the newer visits',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.startVisit(VisitDate(2026, 9, 1)),
        expect: () => [
          loaded(status: ClientDetailStatus.saving),
          loaded(
            status: ClientDetailStatus.visitStarted,
            visitList: [visit, started(VisitDate(2026, 9, 1))],
            startedVisitId: 'id-1',
          ),
        ],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'starts a second visit after the first, and names the second',
        build: build,
        seed: () => loaded(status: ClientDetailStatus.visitStarted, startedVisitId: 'visit-1'),
        act: (cubit) => cubit.startVisit(october),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, startedVisitId: 'visit-1'),
          loaded(
            status: ClientDetailStatus.visitStarted,
            visitList: [started(october), visit],
            startedVisitId: 'id-1',
          ),
        ],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a failure of storage in the status and lists no new visit',
        setUp: () => when(() => visits.save(any())).thenThrow(failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.startVisit(october),
        expect: () => [
          loaded(status: ClientDetailStatus.saving),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
        errors: () => [failure],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'reports a client that storage does not have in the status',
        setUp: () => when(() => clients.clientById(clientId)).thenAnswer((_) async => null),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.startVisit(october),
        expect: () => [
          loaded(status: ClientDetailStatus.saving),
          loaded(status: ClientDetailStatus.saveFailed),
        ],
        errors: () => [isA<ClientNotFoundException>()],
        verify: (_) => verifyNever(() => visits.save(any())),
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'does nothing while the client lists no zone, because the visit would hold no record',
        build: build,
        seed: () => loaded(zoneList: zones.remove('zone-1').remove('zone-2')),
        act: (cubit) => cubit.startVisit(october),
        expect: () => isEmpty,
        verify: (_) => verifyNever(() => visits.save(any())),
      );

      for (final (description, answerSave) in <(String, void Function(Completer<void>))>[
        ('storage answers', (answer) => answer.complete()),
        ('storage fails', (answer) => answer.completeError(failure)),
      ]) {
        test('emits nothing more when the cubit closes before $description', () async {
          final answer = Completer<void>();
          when(() => visits.save(any())).thenAnswer((_) => answer.future);
          final cubit = build();
          await cubit.load();

          final start = cubit.startVisit(october);
          await cubit.close();
          answerSave(answer);
          await start;

          expect(cubit.state, loaded(status: ClientDetailStatus.saving));
        });
      }
    });

    group('a change', () {
      for (final status in [
        ClientDetailStatus.loading,
        ClientDetailStatus.loadFailed,
        ClientDetailStatus.saving,
        ClientDetailStatus.archived,
      ]) {
        blocTest<ClientDetailCubit, ClientDetailState>(
          'does nothing in the ${status.name} status',
          build: build,
          seed: () => loaded(status: status),
          act: (cubit) async {
            await cubit.renameClient('다온 카페');
            await cubit.addZone('탕비실');
            await cubit.renameZone('zone-1', '현관');
            await cubit.moveZone(0, 1);
            await cubit.removeZone('zone-1');
            await cubit.archive();
            await cubit.startVisit(VisitDate(2026, 10, 1));
          },
          expect: () => isEmpty,
          verify: (_) {
            verifyNever(() => clients.save(any(), zones: any(named: 'zones')));
            verifyNever(() => visits.save(any()));
          },
        );
      }

      blocTest<ClientDetailCubit, ClientDetailState>(
        'works after a visit was started',
        build: build,
        seed: () => loaded(status: ClientDetailStatus.visitStarted, startedVisitId: 'visit-1'),
        act: (cubit) => cubit.removeZone('zone-1'),
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: zones.remove('zone-1'), startedVisitId: 'visit-1'),
          loaded(zoneList: zones.remove('zone-1'), startedVisitId: 'visit-1'),
        ],
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'does nothing while the client is not loaded',
        build: build,
        act: (cubit) async {
          await cubit.addZone('탕비실');
          await cubit.startVisit(VisitDate(2026, 10, 1));
        },
        expect: () => isEmpty,
      );

      blocTest<ClientDetailCubit, ClientDetailState>(
        'takes no second change while the first is on its way to storage',
        build: build,
        seed: loaded,
        act: (cubit) async {
          final first = cubit.removeZone('zone-1');
          await cubit.removeZone('zone-2');
          await first;
        },
        expect: () => [
          loaded(status: ClientDetailStatus.saving, zoneList: zones.remove('zone-1')),
          loaded(zoneList: zones.remove('zone-1')),
        ],
      );

      for (final (description, answerSave) in <(String, void Function(Completer<void>))>[
        ('storage answers', (answer) => answer.complete()),
        ('storage fails', (answer) => answer.completeError(failure)),
        ('storage refuses', (answer) => answer.completeError(const DuplicateZoneNameException('로비'))),
      ]) {
        test('emits nothing more when the cubit closes before $description', () async {
          final answer = Completer<void>();
          when(() => clients.save(any(), zones: any(named: 'zones'))).thenAnswer((_) => answer.future);
          final cubit = build();
          await cubit.load();

          final change = cubit.removeZone('zone-1');
          await cubit.close();
          answerSave(answer);
          await change;

          expect(cubit.state.status, ClientDetailStatus.saving);
        });
      }
    });
  });
}
