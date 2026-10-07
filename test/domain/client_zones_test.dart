// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  const clientId = 'client-1';

  Zone zone(String id, String name, int position, {bool isActive = true, String client = clientId}) =>
      Zone(id: id, clientId: client, name: name, position: position, isActive: isActive);

  ClientZones zones(List<Zone> zones) => ClientZones(clientId: clientId, zones: zones);

  group('ClientZones', () {
    test('holds no zone by default', () {
      final empty = ClientZones(clientId: clientId);

      expect(empty.all, isEmpty);
      expect(empty.active, isEmpty);
    });

    test('lists every zone in position order, and zones with one position in identifier order', () {
      final lobby = zone('zone-b', '로비', 2);
      final kitchen = zone('zone-c', '탕비실', 0);
      final hall = zone('zone-a', '복도', 2);

      expect(zones([lobby, kitchen, hall]).all, [kitchen, hall, lobby]);
    });

    test('lists the active zones in position order without the removed zones', () {
      final lobby = zone('zone-1', '로비', 2);
      final kitchen = zone('zone-2', '탕비실', 1, isActive: false);
      final hall = zone('zone-3', '복도', 0);

      expect(zones([lobby, kitchen, hall]).active, [hall, lobby]);
    });

    test('refuses a zone of another client', () {
      expect(() => zones([zone('zone-1', '로비', 0, client: 'client-2')]), throwsArgumentError);
    });

    test('refuses two zones with one identifier', () {
      expect(() => zones([zone('zone-1', '로비', 0), zone('zone-1', '복도', 1)]), throwsArgumentError);
    });

    test('refuses two active zones that share a name after trimming', () {
      expect(
        () => zones([zone('zone-1', '로비', 0), zone('zone-2', ' 로비 ', 1)]),
        throwsA(isA<DuplicateZoneNameException>().having((e) => e.name, 'name', '로비')),
      );
    });

    test('accepts an active zone with the name of a removed zone', () {
      final removed = zone('zone-1', '로비', 0, isActive: false);
      final current = zone('zone-2', '로비', 1);

      expect(zones([removed, current]).active, [current]);
    });

    test('treats names that differ only in letter case as different names', () {
      expect(zones([zone('zone-1', 'Lobby', 0), zone('zone-2', 'lobby', 1)]).active, hasLength(2));
    });

    group('add', () {
      test('puts the first zone at position 0', () {
        expect(ClientZones(clientId: clientId).add(id: 'zone-1', name: '로비').all, [zone('zone-1', '로비', 0)]);
      });

      test('puts a new zone after every zone, removed zones included', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 4, isActive: false)]);

        expect(existing.add(id: 'zone-3', name: ' 탕비실 ').all.last, zone('zone-3', '탕비실', 5));
      });

      test('does not change the list it is called on', () {
        final existing = zones([zone('zone-1', '로비', 0)]);

        existing.add(id: 'zone-2', name: '복도');

        expect(existing.all, [zone('zone-1', '로비', 0)]);
      });

      test('refuses an empty name', () {
        expect(() => ClientZones(clientId: clientId).add(id: 'zone-1', name: ' '), throwsA(isA<EmptyNameException>()));
      });

      test('refuses the name of an active zone', () {
        final existing = zones([zone('zone-1', '로비', 0)]);

        expect(() => existing.add(id: 'zone-2', name: '로비 '), throwsA(isA<DuplicateZoneNameException>()));
      });

      test('accepts the name of a removed zone', () {
        final existing = zones([zone('zone-1', '로비', 0)]).remove('zone-1');

        expect(existing.add(id: 'zone-2', name: '로비').active, [zone('zone-2', '로비', 1)]);
      });
    });

    group('rename', () {
      test('renames the zone and keeps its place', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);

        expect(existing.rename('zone-1', ' 현관 ').all, [zone('zone-1', '현관', 0), zone('zone-2', '복도', 1)]);
      });

      test('accepts the name that the zone has', () {
        final existing = zones([zone('zone-1', '로비', 0)]);

        expect(existing.rename('zone-1', '로비'), existing);
      });

      test('refuses the name of another active zone', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);

        expect(() => existing.rename('zone-2', '로비'), throwsA(isA<DuplicateZoneNameException>()));
      });

      test('refuses an empty name', () {
        final existing = zones([zone('zone-1', '로비', 0)]);

        expect(() => existing.rename('zone-1', ''), throwsA(isA<EmptyNameException>()));
      });

      test('refuses a zone that the client does not have', () {
        expect(() => ClientZones(clientId: clientId).rename('zone-9', '로비'), throwsArgumentError);
      });
    });

    group('remove', () {
      test('takes the zone out of the active zones and keeps it as an inactive zone', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);

        final removed = existing.remove('zone-1');

        expect(removed.active, [zone('zone-2', '복도', 1)]);
        expect(removed.all, [zone('zone-1', '로비', 0, isActive: false), zone('zone-2', '복도', 1)]);
      });

      test('refuses a zone that the client does not have', () {
        expect(() => ClientZones(clientId: clientId).remove('zone-9'), throwsArgumentError);
      });
    });

    group('move', () {
      test('moves an active zone down and gives the zones between it new positions', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1), zone('zone-3', '탕비실', 2)]);

        expect(existing.move(from: 0, to: 2).all, [
          zone('zone-2', '복도', 0),
          zone('zone-3', '탕비실', 1),
          zone('zone-1', '로비', 2),
        ]);
      });

      test('moves an active zone up', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1), zone('zone-3', '탕비실', 2)]);

        expect(existing.move(from: 2, to: 0).active.map((zone) => zone.id), ['zone-3', 'zone-1', 'zone-2']);
      });

      test('counts the active zones only and keeps a removed zone in its place', () {
        final existing = zones([
          zone('zone-1', '로비', 0),
          zone('zone-2', '복도', 1, isActive: false),
          zone('zone-3', '탕비실', 2),
          zone('zone-4', '화장실', 3),
        ]);

        expect(existing.move(from: 2, to: 0).all, [
          zone('zone-4', '화장실', 0),
          zone('zone-2', '복도', 1, isActive: false),
          zone('zone-1', '로비', 2),
          zone('zone-3', '탕비실', 3),
        ]);
      });

      test('gives every zone its own position when zones shared one', () {
        final existing = zones([zone('zone-a', '로비', 4), zone('zone-b', '복도', 4), zone('zone-c', '탕비실', 9)]);

        expect(existing.move(from: 1, to: 0).all, [
          zone('zone-b', '복도', 0),
          zone('zone-a', '로비', 1),
          zone('zone-c', '탕비실', 2),
        ]);
      });

      test('keeps the order when a zone moves to its own place', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);

        expect(existing.move(from: 1, to: 1), existing);
      });

      test('does not change the list it is called on', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);

        existing.move(from: 0, to: 1);

        expect(existing.all, [zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);
      });

      test('refuses an index that is not an index of the active zones', () {
        final existing = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1, isActive: false)]);

        expect(() => existing.move(from: 1, to: 0), throwsRangeError);
        expect(() => existing.move(from: 0, to: 1), throwsRangeError);
        expect(() => existing.move(from: -1, to: 0), throwsRangeError);
      });
    });

    test('is equal to a list of the same client with equal zones', () {
      final a = zones([zone('zone-1', '로비', 0), zone('zone-2', '복도', 1)]);
      final b = zones([zone('zone-2', '복도', 1), zone('zone-1', '로비', 0)]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs from a list of another client or with other zones', () {
      final a = zones([zone('zone-1', '로비', 0)]);

      expect(a, isNot(ClientZones(clientId: 'client-2')));
      expect(a, isNot(ClientZones(clientId: clientId)));
      expect(a, isNot(zones([zone('zone-1', '현관', 0)])));
    });
  });
}
