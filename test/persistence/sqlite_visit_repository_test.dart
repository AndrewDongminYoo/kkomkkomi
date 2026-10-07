import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  const clientId = 'client-1';

  late Database database;
  late SqliteClientRepository clients;
  late SqliteVisitRepository repository;

  final zones = ClientZones(
    clientId: clientId,
    zones: [
      Zone(id: 'zone-1', clientId: clientId, name: '로비', position: 0),
      Zone(id: 'zone-2', clientId: clientId, name: '복도', position: 1),
    ],
  );

  Client client(String id) => Client(id: id, name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));

  Visit visit(
    String id, {
    VisitDate? date,
    int hour = 9,
    String client = clientId,
    List<ZoneRecord> records = const [],
  }) => Visit(
    id: id,
    clientId: client,
    visitDate: date ?? VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, hour, 30, 15, 123, 456),
    zoneRecords: records,
  );

  setUp(() async {
    database = await openMemoryDatabase();
    clients = SqliteClientRepository(database);
    repository = SqliteVisitRepository(database);
    await clients.save(client(clientId), zones: zones);
  });

  tearDown(() => database.close());

  group('SqliteVisitRepository', () {
    test('returns null for a visit that does not exist', () async {
      expect(await repository.visitById('visit-1'), isNull);
    });

    test('round-trips a visit with its zone records in order', () async {
      final saved = visit(
        'visit-1',
        date: VisitDate(2026, 2, 9),
        records: [
          ZoneRecord(
            zoneId: 'zone-2',
            zoneName: '복도',
            beforePhoto: PhotoRef('photos/visit-1/zone-2-before.jpg'),
            afterPhoto: PhotoRef('photos/visit-1/zone-2-after.jpg'),
            note: '바닥 왁스 작업',
          ),
          ZoneRecord(zoneId: 'zone-1', zoneName: '로비'),
        ],
      );

      await repository.save(saved);

      expect(await repository.visitById('visit-1'), saved);
    });

    test('round-trips the status and the reason of each record', () async {
      final saved = visit(
        'visit-1',
        records: [
          ZoneRecord(zoneId: 'zone-1', zoneName: '로비', status: ZoneStatus.partlyDone, reason: '전자레인지는 다음 방문에'),
          ZoneRecord(zoneId: 'zone-2', zoneName: '복도', status: ZoneStatus.notDone, reason: ' 공사 중\n'),
        ],
      );

      await repository.save(saved);

      expect(await repository.visitById('visit-1'), saved);
      await repository.save(visit('visit-1', records: [saved.zoneRecords.first.withStatus(ZoneStatus.done)]));
      final done = (await repository.visitById('visit-1'))!.zoneRecords.single;
      expect((done.status, done.reason), (ZoneStatus.done, '전자레인지는 다음 방문에'));
    });

    test('reads a stored status that the app does not know as not done', () async {
      await repository.save(
        visit(
          'visit-1',
          records: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비')],
        ),
      );
      await database.update('zone_records', {'status': 'skipped'}, where: 'zone_id = ?', whereArgs: ['zone-1']);

      expect((await repository.visitById('visit-1'))!.zoneRecords.single.status, ZoneStatus.notDone);
    });

    test('round-trips a visit without zone records', () async {
      await repository.save(visit('visit-1'));

      expect(await repository.visitById('visit-1'), visit('visit-1'));
    });

    test('saves a changed visit over the stored one and replaces its records', () async {
      await repository.save(
        visit(
          'visit-1',
          records: [
            ZoneRecord(zoneId: 'zone-1', zoneName: '로비'),
            ZoneRecord(zoneId: 'zone-2', zoneName: '복도'),
          ],
        ),
      );
      final changed = visit(
        'visit-1',
        date: VisitDate(2026, 10, 2),
        records: [
          ZoneRecord(
            zoneId: 'zone-1',
            zoneName: '로비',
            beforePhoto: PhotoRef('photos/visit-1/zone-1-before.jpg'),
            note: '유리 얼룩',
          ),
        ],
      );

      await repository.save(changed);

      expect(await repository.visitById('visit-1'), changed);
      expect(await database.query('visits'), hasLength(1));
      expect(await database.query('zone_records'), hasLength(1));
    });

    test('lists the visits of a client, newest first, with more than one visit on one date', () async {
      final september = visit('visit-september', date: VisitDate(2026, 9, 30), hour: 22);
      final morning = visit('visit-morning', hour: 8);
      final afternoon = visit('visit-afternoon', hour: 15);
      await clients.save(client('client-2'));
      await repository.save(morning);
      await repository.save(september);
      await repository.save(afternoon);
      await repository.save(visit('visit-other', client: 'client-2'));

      expect(await repository.visitsOf(clientId), [afternoon, morning, september]);
    });

    test('lists no visit for a client without visits', () async {
      expect(await repository.visitsOf(clientId), isEmpty);
    });

    test('keeps the record and the copied name of a zone that is renamed and removed after the visit', () async {
      final started = Visit.start(
        id: 'visit-1',
        zones: zones,
        visitDate: VisitDate(2026, 10, 1),
        createdAt: DateTime.utc(2026, 10, 1, 9),
      );
      await repository.save(started);

      await clients.save(client(clientId), zones: zones.rename('zone-1', '현관').remove('zone-1'));

      expect((await clients.zonesOf(clientId)).active.map((zone) => zone.id), ['zone-2']);
      final loaded = await repository.visitById('visit-1');
      expect(loaded, started);
      expect(loaded!.recordFor('zone-1')!.zoneName, '로비');
    });

    test('rolls the visit write back when a record is refused in the same transaction', () async {
      final broken = visit(
        'visit-1',
        records: [ZoneRecord(zoneId: 'zone-unknown', zoneName: '없는 구역')],
      );

      await expectLater(repository.save(broken), throwsArgumentError);

      expect(await repository.visitById('visit-1'), isNull);
      expect(await database.query('zone_records'), isEmpty);
    });

    test('keeps the stored records when a later save of the visit fails', () async {
      final stored = visit(
        'visit-1',
        records: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '첫 기록')],
      );
      await repository.save(stored);
      final broken = visit(
        'visit-1',
        date: VisitDate(2026, 12, 25),
        records: [ZoneRecord(zoneId: 'zone-unknown', zoneName: '없는 구역')],
      );

      await expectLater(repository.save(broken), throwsArgumentError);

      expect(await repository.visitById('visit-1'), stored);
    });

    test('reads a visit in one state while a save of that visit runs', () async {
      final before = visit(
        'visit-1',
        date: VisitDate(2026, 1, 1),
        records: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: 'old')],
      );
      final after = visit(
        'visit-1',
        date: VisitDate(2026, 2, 2),
        records: [
          ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: 'new'),
          ZoneRecord(zoneId: 'zone-2', zoneName: '복도', note: 'new'),
        ],
      );
      await repository.save(before);

      final one = repository.visitById('visit-1');
      final all = repository.visitsOf(clientId);
      final saved = repository.save(after);

      expect(await one, before);
      expect(await all, [before]);
      await saved;
      expect(await repository.visitById('visit-1'), after);
    });

    test('applies saves in the order of the calls, and a read that is called after them reads the last', () async {
      Visit noted(String note) => visit(
        'visit-1',
        records: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: note)],
      );

      // A screen that saves on each change does not wait for a save before it sends the next.
      final saves = [
        for (final note in ['유', '유리', '유리 닦음']) repository.save(noted(note)),
      ];
      final read = repository.visitById('visit-1');

      expect(await read, noted('유리 닦음'));
      await Future.wait(saves);
      expect(await repository.visitById('visit-1'), noted('유리 닦음'));
    });

    test('refuses a record for a zone of another client and saves nothing', () async {
      await clients.save(
        client('client-2'),
        zones: ClientZones(
          clientId: 'client-2',
          zones: [Zone(id: 'zone-other', clientId: 'client-2', name: '로비', position: 0)],
        ),
      );
      final crossed = visit(
        'visit-1',
        records: [ZoneRecord(zoneId: 'zone-other', zoneName: '로비')],
      );

      await expectLater(repository.save(crossed), throwsArgumentError);

      expect(await repository.visitById('visit-1'), isNull);
      expect(await database.query('zone_records'), isEmpty);
    });

    test('refuses a visit of a client that does not exist', () async {
      await expectLater(repository.save(visit('visit-1', client: 'client-9')), throwsA(isA<DatabaseException>()));

      expect(await repository.visitById('visit-1'), isNull);
    });
  });
}
