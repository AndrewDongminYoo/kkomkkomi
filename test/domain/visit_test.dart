import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  const clientId = 'client-1';
  final createdAt = DateTime.utc(2026, 10, 1, 9);
  final visitDate = VisitDate(2026, 10, 1);

  Visit visit({
    String id = 'visit-1',
    String client = clientId,
    VisitDate? date,
    DateTime? created,
    List<ZoneRecord> records = const [],
  }) => Visit(
    id: id,
    clientId: client,
    visitDate: date ?? visitDate,
    createdAt: created ?? createdAt,
    zoneRecords: records,
  );

  group('Visit', () {
    test('holds no zone record by default', () {
      expect(Visit(id: 'visit-1', clientId: clientId, visitDate: visitDate, createdAt: createdAt).zoneRecords, isEmpty);
    });

    test('keeps the zone records in the given order', () {
      final lobby = ZoneRecord(zoneId: 'zone-2', zoneName: '로비');
      final hall = ZoneRecord(zoneId: 'zone-1', zoneName: '복도');

      expect(visit(records: [lobby, hall]).zoneRecords, [lobby, hall]);
    });

    test('refuses two records for one zone', () {
      expect(
        () => visit(
          records: [
            ZoneRecord(zoneId: 'zone-1', zoneName: '로비'),
            ZoneRecord(zoneId: 'zone-1', zoneName: '복도'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('keeps the creation time as the same moment in UTC', () {
      final local = DateTime(2026, 10, 1, 9, 30);

      final created = visit(created: local).createdAt;

      expect(created.isUtc, isTrue);
      expect(created.isAtSameMomentAs(local), isTrue);
    });

    group('start', () {
      final zones = ClientZones(
        clientId: clientId,
        zones: [
          Zone(id: 'zone-1', clientId: clientId, name: '로비', position: 2),
          Zone(id: 'zone-2', clientId: clientId, name: '창고', position: 1, isActive: false),
          Zone(id: 'zone-3', clientId: clientId, name: '복도', position: 0),
        ],
      );

      test('copies the active zones in position order into empty records', () {
        final started = Visit.start(id: 'visit-1', zones: zones, visitDate: visitDate, createdAt: createdAt);

        expect(
          started,
          visit(
            records: [
              ZoneRecord(zoneId: 'zone-3', zoneName: '복도'),
              ZoneRecord(zoneId: 'zone-1', zoneName: '로비'),
            ],
          ),
        );
      });

      test('copies the zone name, so a later rename does not change the visit', () {
        final started = Visit.start(id: 'visit-1', zones: zones, visitDate: visitDate, createdAt: createdAt);

        final renamed = zones.rename('zone-1', '현관');

        expect(renamed.active.last.name, '현관');
        expect(started.recordFor('zone-1')!.zoneName, '로비');
      });

      test('keeps the record of a zone that is removed after the visit started', () {
        final started = Visit.start(id: 'visit-1', zones: zones, visitDate: visitDate, createdAt: createdAt);

        final removed = zones.remove('zone-1');

        expect(removed.active.map((zone) => zone.id), ['zone-3']);
        expect(started.recordFor('zone-1'), ZoneRecord(zoneId: 'zone-1', zoneName: '로비'));
      });

      test('starts a visit without records when the client has no active zone', () {
        final started = Visit.start(
          id: 'visit-1',
          zones: ClientZones(clientId: clientId),
          visitDate: visitDate,
          createdAt: createdAt,
        );

        expect(started.zoneRecords, isEmpty);
      });
    });

    test('recordFor returns the record of the zone, or null when the visit has none', () {
      final lobby = ZoneRecord(zoneId: 'zone-1', zoneName: '로비');
      final hall = ZoneRecord(zoneId: 'zone-2', zoneName: '복도');
      final recorded = visit(records: [lobby, hall]);

      expect(recorded.recordFor('zone-2'), hall);
      expect(recorded.recordFor('zone-9'), isNull);
    });

    test('compareChronologically orders by visit date, then by creation time', () {
      final first = visit(date: VisitDate(2026, 9, 30), created: DateTime.utc(2026, 10, 5));
      final second = visit(created: DateTime.utc(2026, 10, 1, 8));
      final third = visit(created: DateTime.utc(2026, 10, 1, 9));

      expect(first.compareChronologically(second), isNegative);
      expect(third.compareChronologically(second), isPositive);
      expect(second.compareChronologically(third), isNegative);
      expect(third.compareChronologically(visit()), isZero);
    });

    test('is equal to a visit with the same fields and records', () {
      final records = [ZoneRecord(zoneId: 'zone-1', zoneName: '로비')];

      expect(
        visit(records: records),
        visit(
          records: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비')],
        ),
      );
      expect(
        visit(records: records).hashCode,
        visit(
          records: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비')],
        ).hashCode,
      );
    });

    test('differs from a visit with another field value or other records', () {
      final lobby = ZoneRecord(zoneId: 'zone-1', zoneName: '로비');
      final hall = ZoneRecord(zoneId: 'zone-2', zoneName: '복도');

      expect(visit(), isNot(visit(id: 'visit-2')));
      expect(visit(), isNot(visit(client: 'client-2')));
      expect(visit(), isNot(visit(date: VisitDate(2026, 10, 2))));
      expect(visit(), isNot(visit(created: DateTime.utc(2026, 10, 1, 10))));
      expect(visit(records: [lobby]), isNot(visit()));
      expect(visit(records: [lobby, hall]), isNot(visit(records: [hall, lobby])));
    });
  });
}
