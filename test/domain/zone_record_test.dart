import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  ZoneRecord record({
    String zoneId = 'zone-1',
    String zoneName = '로비',
    String? before = 'photos/visit-1/before.jpg',
    String? after = 'photos/visit-1/after.jpg',
    String note = '바닥 왁스',
    ZoneStatus status = ZoneStatus.done,
    String reason = '',
  }) => ZoneRecord(
    zoneId: zoneId,
    zoneName: zoneName,
    beforePhoto: before == null ? null : PhotoRef(before),
    afterPhoto: after == null ? null : PhotoRef(after),
    note: note,
    status: status,
    reason: reason,
  );

  group('ZoneRecord', () {
    test('replaces provenance with the photo and keeps it through other edits', () {
      final photo = PhotoRef('photos/visit/a.jpg');
      final record = ZoneRecord(
        zoneId: 'zone',
        zoneName: 'Lobby',
      ).withPhoto(PhotoSlot.before, photo, source: PhotoSource.gallery);
      expect(record.sourceIn(PhotoSlot.before), PhotoSource.gallery);
      expect(record.sourceIn(PhotoSlot.after), PhotoSource.unknown);
      expect(
        record.withNote('note').withStatus(ZoneStatus.partlyDone).withReason('reason').beforePhotoSource,
        PhotoSource.gallery,
      );
      expect(record, isNot(record.withPhoto(PhotoSlot.before, photo, source: PhotoSource.camera)));
      expect(record.hashCode, record.withNote('').hashCode);
    });
    test('starts without photos and with an empty note', () {
      final empty = ZoneRecord(zoneId: 'zone-1', zoneName: '로비');

      expect(empty.beforePhoto, isNull);
      expect(empty.afterPhoto, isNull);
      expect(empty.note, isEmpty);
      expect(empty.status, ZoneStatus.done);
      expect(empty.reason, isEmpty);
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
      expect(record(), isNot(record(status: ZoneStatus.partlyDone)));
      expect(record(), isNot(record(reason: '다음 방문에')));
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

    test('hasContent is also true for a record with an exception, without a photo and without a note', () {
      final empty = record(before: null, after: null, note: '');

      expect(empty.withStatus(ZoneStatus.partlyDone).hasContent, isTrue);
      expect(empty.withStatus(ZoneStatus.notDone).hasContent, isTrue);
      expect(empty.withStatus(ZoneStatus.done).hasContent, isFalse);
      // A reason alone is no content: a done record ignores its reason.
      expect(empty.withReason('공사 중').hasContent, isFalse);
    });

    test('withPhoto replaces the photo of one slot and keeps the rest', () {
      final retaken = PhotoRef('photos/visit-1/retaken.jpg');

      expect(record().withPhoto(PhotoSlot.before, retaken), record(before: 'photos/visit-1/retaken.jpg'));
      expect(record().withPhoto(PhotoSlot.after, retaken), record(after: 'photos/visit-1/retaken.jpg'));
      expect(record(after: null).withPhoto(PhotoSlot.after, retaken), record(after: 'photos/visit-1/retaken.jpg'));
      expect(
        record(status: ZoneStatus.partlyDone, reason: '다음 방문에').withPhoto(PhotoSlot.before, retaken),
        record(before: 'photos/visit-1/retaken.jpg', status: ZoneStatus.partlyDone, reason: '다음 방문에'),
      );
    });

    test('withNote replaces the note as it is written and keeps the rest', () {
      expect(record().withNote(' 유리 닦음\n'), record(note: ' 유리 닦음\n'));
      expect(record().withNote(''), record(note: ''));
      expect(
        record(status: ZoneStatus.notDone, reason: '공사 중').withNote('잠김'),
        record(note: '잠김', status: ZoneStatus.notDone, reason: '공사 중'),
      );
    });

    test('withStatus replaces the status and keeps the reason, also when the status goes back to done', () {
      final partly = record().withReason('전자레인지는 다음 방문에').withStatus(ZoneStatus.partlyDone);

      expect(partly, record(status: ZoneStatus.partlyDone, reason: '전자레인지는 다음 방문에'));
      expect(partly.withStatus(ZoneStatus.done), record(reason: '전자레인지는 다음 방문에'));
      expect(partly.withStatus(ZoneStatus.done).withStatus(ZoneStatus.partlyDone), partly);
    });

    test('withReason replaces the reason as it is written and keeps the rest', () {
      expect(
        record(status: ZoneStatus.notDone).withReason(' 공사 중\n'),
        record(status: ZoneStatus.notDone, reason: ' 공사 중\n'),
      );
    });
  });
}
