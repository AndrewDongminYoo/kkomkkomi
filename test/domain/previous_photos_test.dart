// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  const clientId = 'client-1';

  ZoneRecord record(String zoneId, {String? before, String? after}) => ZoneRecord(
    zoneId: zoneId,
    zoneName: zoneId,
    beforePhoto: before == null ? null : PhotoRef(before),
    afterPhoto: after == null ? null : PhotoRef(after),
  );

  Visit visit(String id, VisitDate date, {required List<ZoneRecord> records, int hour = 9}) => Visit(
    id: id,
    clientId: clientId,
    visitDate: date,
    createdAt: DateTime.utc(2026, 10, 1, hour),
    zoneRecords: records,
  );

  PreviousPhotos photos(String visitId, VisitDate date, {String? before, String? after}) => PreviousPhotos(
    visitId: visitId,
    visitDate: date,
    beforePhoto: before == null ? null : PhotoRef(before),
    afterPhoto: after == null ? null : PhotoRef(after),
  );

  final september = VisitDate(2026, 9, 1);
  final midSeptember = VisitDate(2026, 9, 15);
  final october = VisitDate(2026, 10, 1);
  final november = VisitDate(2026, 11, 1);

  group('previousPhotosByZone', () {
    final current = visit('current', october, records: [record('lobby'), record('hall')]);

    test('returns no entry when no visit is earlier', () {
      expect(previousPhotosByZone(current, const []), isEmpty);
    });

    test('takes the photos of the newest earlier visit, whatever the order of the history', () {
      final older = visit(
        'older',
        september,
        records: [record('lobby', before: 'old-b.jpg', after: 'old-a.jpg')],
      );
      final newer = visit(
        'newer',
        midSeptember,
        records: [record('lobby', before: 'new-b.jpg', after: 'new-a.jpg')],
      );
      final expected = {'lobby': photos('newer', midSeptember, before: 'new-b.jpg', after: 'new-a.jpg')};

      expect(previousPhotosByZone(current, [older, newer]), expected);
      expect(previousPhotosByZone(current, [newer, older]), expected);
    });

    test('ignores the visit itself and every later visit', () {
      final later = visit('later', november, records: [record('lobby', before: 'later.jpg')]);
      final itself = visit('current', october, records: [record('lobby', before: 'same.jpg')]);

      expect(previousPhotosByZone(current, [later, itself]), isEmpty);
    });

    test('ignores an older state of the visit itself, even when its date was earlier', () {
      final stored = visit('current', september, records: [record('lobby', before: 'own.jpg')]);

      expect(previousPhotosByZone(current, [stored]), isEmpty);
    });

    test('orders the visits of one date by creation time', () {
      final morning = visit('morning', october, hour: 7, records: [record('lobby', before: 'morning.jpg')]);
      final earlyMorning = visit('early', october, hour: 6, records: [record('lobby', before: 'early.jpg')]);
      final evening = visit('evening', october, hour: 18, records: [record('lobby', before: 'evening.jpg')]);

      final previous = previousPhotosByZone(current, [earlyMorning, evening, morning]);

      expect(previous['lobby'], photos('morning', october, before: 'morning.jpg'));
    });

    test('looks past a newer visit that holds no record for the zone', () {
      final older = visit(
        'older',
        september,
        records: [
          record('hall', after: 'hall.jpg'),
          record('lobby'),
        ],
      );
      final newer = visit('newer', midSeptember, records: [record('lobby', before: 'lobby.jpg')]);

      final previous = previousPhotosByZone(current, [older, newer]);

      expect(previous, {
        'lobby': photos('newer', midSeptember, before: 'lobby.jpg'),
        'hall': photos('older', september, after: 'hall.jpg'),
      });
    });

    test('takes the newest earlier record even when it holds no photo', () {
      final older = visit('older', september, records: [record('lobby', before: 'old.jpg')]);
      final newer = visit('newer', midSeptember, records: [record('lobby')]);

      expect(previousPhotosByZone(current, [older, newer]), {'lobby': photos('newer', midSeptember)});
    });

    test('returns entries only for the zones of the current visit', () {
      final older = visit('older', september, records: [record('storage', before: 'storage.jpg')]);

      expect(previousPhotosByZone(current, [older]), isEmpty);
    });
  });

  group('PreviousPhotos', () {
    test('is equal to previous photos with the same fields', () {
      expect(
        photos('visit-1', october, before: 'b.jpg', after: 'a.jpg'),
        photos('visit-1', october, before: 'b.jpg', after: 'a.jpg'),
      );
      expect(
        photos('visit-1', october, before: 'b.jpg', after: 'a.jpg').hashCode,
        photos('visit-1', october, before: 'b.jpg', after: 'a.jpg').hashCode,
      );
    });

    test('differs from previous photos with another field value', () {
      final base = photos('visit-1', october, before: 'b.jpg', after: 'a.jpg');

      expect(base, isNot(photos('visit-2', october, before: 'b.jpg', after: 'a.jpg')));
      expect(base, isNot(photos('visit-1', november, before: 'b.jpg', after: 'a.jpg')));
      expect(base, isNot(photos('visit-1', october, after: 'a.jpg')));
      expect(base, isNot(photos('visit-1', october, before: 'b.jpg')));
    });
  });
}
