import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  late Database database;
  late SqliteClientRepository repository;

  setUp(() async {
    database = await openMemoryDatabase();
    repository = SqliteClientRepository(database);
  });

  tearDown(() => database.close());

  Client client(String id, {String name = '한빛 사무실', int day = 1, bool isArchived = false}) => Client(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 9, day, 8, 30, 15, 123, 456),
    isArchived: isArchived,
  );

  Zone zone(String id, String name, int position, {String clientId = 'client-1', bool isActive = true}) =>
      Zone(id: id, clientId: clientId, name: name, position: position, isActive: isActive);

  group('SqliteClientRepository', () {
    test('returns null for a client that does not exist', () async {
      expect(await repository.clientById('client-1'), isNull);
    });

    test('round-trips a client', () async {
      final saved = client('client-1', isArchived: true);

      await repository.save(saved);

      expect(await repository.clientById('client-1'), saved);
    });

    test('saves a changed client over the stored one', () async {
      await repository.save(client('client-1'));

      await repository.save(client('client-1').rename('새 이름').archive());

      expect(await repository.clientById('client-1'), client('client-1', name: '새 이름', isArchived: true));
      expect(await database.query('clients'), hasLength(1));
    });

    test('lists the clients that are not archived, oldest first', () async {
      await repository.save(client('client-new', day: 20));
      await repository.save(client('client-archived', day: 10, isArchived: true));
      await repository.save(client('client-old', day: 5));

      expect(await repository.activeClients(), [client('client-old', day: 5), client('client-new', day: 20)]);
    });

    test('returns an empty zone list for a client without zones', () async {
      expect(await repository.zonesOf('client-1'), ClientZones(clientId: 'client-1'));
    });

    test('round-trips the zones of a client, removed zones included', () async {
      final zones = ClientZones(
        clientId: 'client-1',
        zones: [zone('zone-1', '로비', 1), zone('zone-2', '창고', 0, isActive: false), zone('zone-3', '복도', 2)],
      );

      await repository.save(client('client-1'), zones: zones);

      expect(await repository.zonesOf('client-1'), zones);
    });

    test('keeps the zones of each client apart', () async {
      final first = ClientZones(clientId: 'client-1', zones: [zone('zone-1', '로비', 0)]);
      final second = ClientZones(
        clientId: 'client-2',
        zones: [zone('zone-2', '로비', 0, clientId: 'client-2')],
      );

      await repository.save(client('client-1'), zones: first);
      await repository.save(client('client-2'), zones: second);

      expect(await repository.zonesOf('client-1'), first);
      expect(await repository.zonesOf('client-2'), second);
    });

    test('saves a renamed zone and a removed zone over the stored ones', () async {
      final zones = ClientZones(clientId: 'client-1', zones: [zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);
      await repository.save(client('client-1'), zones: zones);

      final changed = zones.rename('zone-1', '현관').remove('zone-2');
      await repository.save(client('client-1'), zones: changed);

      expect(await repository.zonesOf('client-1'), changed);
      expect(await database.query('zones'), hasLength(2));
    });

    test('leaves the stored zones as they are when no zones are given', () async {
      final zones = ClientZones(clientId: 'client-1', zones: [zone('zone-1', '로비', 0)]);
      await repository.save(client('client-1'), zones: zones);

      await repository.save(client('client-1').rename('새 이름'));

      expect(await repository.zonesOf('client-1'), zones);
    });

    test('never deletes a stored zone that the given zones do not hold', () async {
      final zones = ClientZones(clientId: 'client-1', zones: [zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);
      await repository.save(client('client-1'), zones: zones);

      await repository.save(
        client('client-1'),
        zones: ClientZones(clientId: 'client-1', zones: [zone('zone-2', '복도', 1)]),
      );

      expect(await repository.zonesOf('client-1'), zones);
    });

    test('refuses zones that belong to another client and writes nothing', () async {
      final zones = ClientZones(
        clientId: 'client-2',
        zones: [zone('zone-1', '로비', 0, clientId: 'client-2')],
      );

      await expectLater(repository.save(client('client-1'), zones: zones), throwsArgumentError);

      expect(await repository.clientById('client-1'), isNull);
    });

    test('rolls the client write back when a zone write fails in the same transaction', () async {
      await repository.save(
        client('client-1'),
        zones: ClientZones(clientId: 'client-1', zones: [zone('zone-1', '로비', 0)]),
      );
      // The identifier `zone-1` is taken by a zone of `client-1`, so the write to `zones` fails after the write to
      // `clients` ran.
      final clashing = ClientZones(
        clientId: 'client-2',
        zones: [
          zone('zone-2', '복도', 0, clientId: 'client-2'),
          zone('zone-1', '현관', 1, clientId: 'client-2'),
        ],
      );

      await expectLater(repository.save(client('client-2'), zones: clashing), throwsA(isA<DatabaseException>()));

      expect(await repository.clientById('client-2'), isNull);
      expect(await repository.zonesOf('client-2'), ClientZones(clientId: 'client-2'));
      expect(await repository.zonesOf('client-1'), ClientZones(clientId: 'client-1', zones: [zone('zone-1', '로비', 0)]));
    });

    test('refuses a save from an older read that would store two active zones with one name', () async {
      final stale = ClientZones(clientId: 'client-1');
      final first = stale.add(id: 'zone-a', name: '로비');
      await repository.save(client('client-1'), zones: first);

      // Each list is valid alone, and together the stored zones would hold the name twice.
      await expectLater(
        repository.save(
          client('client-1').rename('새 이름'),
          zones: stale.add(id: 'zone-b', name: '로비'),
        ),
        throwsA(isA<DuplicateZoneNameException>()),
      );

      expect(await repository.zonesOf('client-1'), first);
      expect(await repository.clientById('client-1'), client('client-1'));
    });
  });
}
