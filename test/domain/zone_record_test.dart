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

    test('photoIn gives the photo of the slot, or null when the record has none', () {
      expect(record().photoIn(PhotoSlot.before), PhotoRef('photos/visit-1/before.jpg'));
      expect(record().photoIn(PhotoSlot.after), PhotoRef('photos/visit-1/after.jpg'));
      expect(record(before: null).photoIn(PhotoSlot.before), isNull);
      expect(record(after: null).photoIn(PhotoSlot.after), isNull);
    });

    test('emptySlots lists the slots without a photo, the before slot first', () {
      expect(record().emptySlots, isEmpty);
      expect(record(before: null).emptySlots, [PhotoSlot.before]);
      expect(record(after: null).emptySlots, [PhotoSlot.after]);
      expect(record(before: null, after: null).emptySlots, [PhotoSlot.before, PhotoSlot.after]);
    });

    test('hasNote is true for a note with text, and false for a note of spaces and line breaks', () {
      expect(record().hasNote, isTrue);
      expect(record(note: ' 왁스 ').hasNote, isTrue);
      expect(record(note: '').hasNote, isFalse);
      expect(record(note: ' \n\t ').hasNote, isFalse);
    });

    test('hasContent is true for a record with a photo or a note', () {
      expect(record().hasContent, isTrue);
      expect(record(after: null, note: '').hasContent, isTrue);
      expect(record(before: null, note: '').hasContent, isTrue);
      expect(record(before: null, after: null).hasContent, isTrue);
      expect(record(before: null, after: null, note: '').hasContent, isFalse);
      expect(record(before: null, after: null, note: ' \n').hasContent, isFalse);
    });

    test('withPhoto replaces the photo of one slot and keeps the rest', () {
      final retaken = PhotoRef('photos/visit-1/retaken.jpg');

      expect(record().withPhoto(PhotoSlot.before, retaken), record(before: 'photos/visit-1/retaken.jpg'));
      expect(record().withPhoto(PhotoSlot.after, retaken), record(after: 'photos/visit-1/retaken.jpg'));
      expect(record(after: null).withPhoto(PhotoSlot.after, retaken), record(after: 'photos/visit-1/retaken.jpg'));
    });

    test('withNote replaces the note as it is written and keeps the rest', () {
      expect(record().withNote(' 유리 닦음\n'), record(note: ' 유리 닦음\n'));
      expect(record().withNote(''), record(note: ''));
    });
  });
}
