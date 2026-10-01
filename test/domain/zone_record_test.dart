import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  ZoneRecord record({
    String zoneId = 'zone-1',
    String zoneName = '로비',
    String? before = 'photos/visit-1/before.jpg',
    String? after = 'photos/visit-1/after.jpg',
    String note = '바닥 왁스',
  }) => ZoneRecord(
    zoneId: zoneId,
    zoneName: zoneName,
    beforePhoto: before == null ? null : PhotoRef(before),
    afterPhoto: after == null ? null : PhotoRef(after),
    note: note,
  );

  group('ZoneRecord', () {
    test('starts without photos and with an empty note', () {
      final empty = ZoneRecord(zoneId: 'zone-1', zoneName: '로비');

      expect(empty.beforePhoto, isNull);
      expect(empty.afterPhoto, isNull);
      expect(empty.note, isEmpty);
    });

    test('trims the zone name and refuses an empty one', () {
      expect(record(zoneName: ' 로비 ').zoneName, '로비');
      expect(() => record(zoneName: ' '), throwsA(isA<EmptyNameException>()));
    });

    test('is equal to a record with the same fields', () {
      expect(record(), record());
      expect(record().hashCode, record().hashCode);
    });

    test('differs from a record with another field value', () {
      expect(record(), isNot(record(zoneId: 'zone-2')));
      expect(record(), isNot(record(zoneName: '복도')));
      expect(record(), isNot(record(before: null)));
      expect(record(), isNot(record(after: 'photos/visit-1/other.jpg')));
      expect(record(), isNot(record(note: '')));
    });
  });
}
