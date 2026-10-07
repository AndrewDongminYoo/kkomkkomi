// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';

void main() {
  final client = Client(id: 'client-1', name: '행복빌딩', createdAt: DateTime.utc(2026, 9));
  final company = CompanyProfile(name: '깔끔클린');

  PhotoRef photo(String name) => PhotoRef('photos/visit-1/$name.jpg');

  Visit visit(List<ZoneRecord> records) => Visit(
    id: 'visit-1',
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 9),
    zoneRecords: records,
  );

  ReportDocument documentOf(List<ZoneRecord> records, {CompanyProfile? companyProfile}) =>
      ReportDocument.fromVisit(visit: visit(records), client: client, companyProfile: companyProfile);

  group('ReportDocument.fromVisit', () {
    test('copies nullable observation times with the camera photo and includes them in equality', () {
      final time = DateTime.utc(2026, 10, 7, 9, 12);
      final record = ZoneRecord(
        zoneId: 'zone-1',
        zoneName: 'Lobby',
        beforePhoto: photo('b'),
        afterPhoto: photo('a'),
        beforePhotoSource: PhotoSource.camera,
        afterPhotoSource: PhotoSource.camera,
        beforeCapturedAt: time,
        afterCapturedAt: time.add(const Duration(minutes: 29)),
      );
      final zone = documentOf([record]).zones.single;
      final same = ReportZone.fromRecord(record);
      expect(zone.beforeCapturedAt, time);
      expect(zone.afterCapturedAt, time.add(const Duration(minutes: 29)));
      expect(zone, same);
      expect(zone.hashCode, same.hashCode);
      expect(
        zone,
        isNot(ReportZone.fromRecord(record.withPhoto(PhotoSlot.before, photo('b'), source: PhotoSource.camera))),
      );
      expect(
        zone,
        isNot(ReportZone.fromRecord(record.withPhoto(PhotoSlot.after, photo('a'), source: PhotoSource.camera))),
      );
    });

    test('holds the company name, the client name, the visit date, and each zone of a full visit in zone order', () {
      final document = documentOf([
        ZoneRecord(
          zoneId: 'zone-1',
          zoneName: '로비',
          beforePhoto: photo('lobby-before'),
          afterPhoto: photo('lobby-after'),
          note: '바닥 왁스',
        ),
        ZoneRecord(
          zoneId: 'zone-2',
          zoneName: '화장실',
          beforePhoto: photo('restroom-before'),
          afterPhoto: photo('restroom-after'),
          note: '세면대 물때 제거',
        ),
      ], companyProfile: company);

      expect(
        document,
        ReportDocument(
          companyName: '깔끔클린',
          clientName: '행복빌딩',
          visitDate: VisitDate(2026, 10, 1),
          zones: [
            ReportZone(
              name: '로비',
              beforePhoto: photo('lobby-before'),
              afterPhoto: photo('lobby-after'),
              note: '바닥 왁스',
            ),
            ReportZone(
              name: '화장실',
              beforePhoto: photo('restroom-before'),
              afterPhoto: photo('restroom-after'),
              note: '세면대 물때 제거',
            ),
          ],
        ),
      );
    });

    test('keeps an empty slot for the photo that a zone lacks, and leaves out a zone without a photo and a note', () {
      final document = documentOf([
        ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: photo('lobby-before')),
        ZoneRecord(zoneId: 'zone-2', zoneName: '화장실'),
        ZoneRecord(zoneId: 'zone-3', zoneName: '탕비실', afterPhoto: photo('pantry-after')),
        ZoneRecord(zoneId: 'zone-4', zoneName: '복도', note: '공사 중이라 청소하지 못함'),
        ZoneRecord(zoneId: 'zone-5', zoneName: '창고', note: ' \n'),
      ], companyProfile: company);

      expect(document.zones, [
        ReportZone(name: '로비', beforePhoto: photo('lobby-before'), afterPhoto: null, note: ''),
        ReportZone(name: '탕비실', beforePhoto: null, afterPhoto: photo('pantry-after'), note: ''),
        const ReportZone(name: '복도', beforePhoto: null, afterPhoto: null, note: '공사 중이라 청소하지 못함'),
      ]);
    });

    test('keeps every character of a long note, without the space around it', () {
      final longNote = List.generate(400, (line) => '$line번째 줄: 바닥을 닦고 유리를 닦았어요.').join('\n');

      final document = documentOf([
        ZoneRecord(zoneId: 'zone-1', zoneName: '로비', beforePhoto: photo('lobby-before'), note: '\n$longNote  '),
      ], companyProfile: company);

      expect(document.zones.single.note, longNote);
      expect(document.zones.single.note.length, greaterThan(8000));
    });

    test('ends each line of a note with a line feed alone', () {
      final document = documentOf([
        ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '첫 줄\r\n둘째 줄\r셋째 줄\n넷째 줄\r\n'),
      ]);

      expect(document.zones.single.note, '첫 줄\n둘째 줄\n셋째 줄\n넷째 줄');
    });

    test('keeps the status of each zone, and the reason only for an exception, in the form of a note', () {
      final document = documentOf([
        ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '왁스', reason: '남은 사유'),
        ZoneRecord(
          zoneId: 'zone-2',
          zoneName: '탕비실',
          beforePhoto: photo('pantry'),
          status: ZoneStatus.partlyDone,
          reason: ' 전자레인지는\r\n다음 방문에\r ',
        ),
        ZoneRecord(zoneId: 'zone-3', zoneName: '창고', status: ZoneStatus.notDone),
      ]);

      expect(document.zones.map((zone) => (zone.name, zone.status, zone.reason)), [
        ('로비', ZoneStatus.done, ''),
        ('탕비실', ZoneStatus.partlyDone, '전자레인지는\n다음 방문에'),
        ('창고', ZoneStatus.notDone, ''),
      ]);
    });

    test('counts the done zones and lists the exceptions in zone order', () {
      final document = documentOf([
        ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '왁스'),
        ZoneRecord(zoneId: 'zone-2', zoneName: '창고', status: ZoneStatus.notDone, reason: '잠김'),
        ZoneRecord(zoneId: 'zone-3', zoneName: '복도', beforePhoto: photo('hall')),
        ZoneRecord(zoneId: 'zone-4', zoneName: '탕비실', status: ZoneStatus.partlyDone),
        // A done zone without a photo and a note was not part of the visit, so the summary does not count it.
        ZoneRecord(zoneId: 'zone-5', zoneName: '계단'),
      ]);

      expect(document.zones, hasLength(4));
      expect(document.doneCount, 2);
      expect(document.exceptions.map((zone) => zone.name), ['창고', '탕비실']);
      expect(documentOf([]).doneCount, 0);
      expect(documentOf([]).exceptions, isEmpty);
    });

    test('has no company name when no company profile is saved', () {
      final document = documentOf([ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '바닥 왁스')]);

      expect(document.companyName, isNull);
      expect(document.clientName, '행복빌딩');
    });

    test('holds no zone for a visit whose zones all lack a photo and a note', () {
      expect(documentOf([ZoneRecord(zoneId: 'zone-1', zoneName: '로비')]).zones, isEmpty);
      expect(documentOf([]).zones, isEmpty);
    });

    test('refuses a visit to another client', () {
      final other = Client(id: 'client-2', name: '다른빌딩', createdAt: DateTime.utc(2026, 9));

      expect(
        () => ReportDocument.fromVisit(visit: visit([]), client: other, companyProfile: company),
        throwsArgumentError,
      );
    });
  });

  group('ReportDocument', () {
    test('copies the optional phone to the device report and includes it in document equality', () {
      final withPhone = documentOf(
        [],
        companyProfile: CompanyProfile(name: '깔끔클린', phone: '02-1234-5678'),
      );
      expect(withPhone.companyPhone, '02-1234-5678');
      expect(withPhone, isNot(documentOf([], companyProfile: CompanyProfile(name: '깔끔클린'))));
      expect(documentOf([]).companyPhone, isEmpty);
    });
    ReportDocument document({
      String? companyName = '깔끔클린',
      String clientName = '행복빌딩',
      int day = 1,
      List<ReportZone>? zones,
    }) => ReportDocument(
      companyName: companyName,
      clientName: clientName,
      visitDate: VisitDate(2026, 10, day),
      zones: zones ?? [ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: '메모')],
    );

    test('lists its photos in zone order, the before photo of a zone first', () {
      final photos = document(
        zones: [
          ReportZone(name: '로비', beforePhoto: photo('a'), afterPhoto: photo('b'), note: ''),
          ReportZone(name: '화장실', beforePhoto: null, afterPhoto: photo('c'), note: ''),
          const ReportZone(name: '복도', beforePhoto: null, afterPhoto: null, note: '메모'),
          ReportZone(name: '탕비실', beforePhoto: photo('d'), afterPhoto: null, note: ''),
        ],
      ).photos;

      expect(photos, [photo('a'), photo('b'), photo('c'), photo('d')]);
    });

    test('does not let a caller change its zones', () {
      expect(() => document().zones.clear(), throwsUnsupportedError);
    });

    test('is equal to a document with the same fields', () {
      expect(document(), document());
      expect(document().hashCode, document().hashCode);
    });

    test('differs from a document with another field value', () {
      expect(document(), isNot(document(companyName: null)));
      expect(document(), isNot(document(clientName: '다른빌딩')));
      expect(document(), isNot(document(day: 2)));
      expect(document(), isNot(document(zones: [])));
    });

    test('names its fields in its text, for a failed expectation', () {
      expect('${document()}', contains('행복빌딩'));
      expect('${document()}', contains('photos/visit-1/a.jpg'));
    });
  });

  group('ReportZone', () {
    ReportZone zone({
      String name = '로비',
      String? before = 'a',
      String? after = 'b',
      String note = '메모',
      ZoneStatus status = ZoneStatus.partlyDone,
      String reason = '사유',
    }) => ReportZone(
      name: name,
      beforePhoto: before == null ? null : photo(before),
      afterPhoto: after == null ? null : photo(after),
      note: note,
      status: status,
      reason: reason,
    );

    test('is done with no reason unless it is given a status', () {
      const plain = ReportZone(name: '로비', beforePhoto: null, afterPhoto: null, note: '');

      expect((plain.status, plain.reason), (ZoneStatus.done, ''));
    });

    test('is equal to a zone with the same fields', () {
      expect(zone(), zone());
      expect(zone().hashCode, zone().hashCode);
    });

    test('differs from a zone with another field value', () {
      expect(zone(), isNot(zone(name: '복도')));
      expect(zone(), isNot(zone(before: null)));
      expect(zone(), isNot(zone(after: 'c')));
      expect(zone(), isNot(zone(note: '')));
      expect(zone(), isNot(zone(status: ZoneStatus.notDone)));
      expect(zone(), isNot(zone(reason: '')));
    });
  });
}
