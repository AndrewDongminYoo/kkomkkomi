// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

class _MockVisitRepository extends Mock implements VisitRepository;

void main() {
  const clientId = 'client-1';

  Visit visit(String id, VisitDate date, ZoneRecord record) => Visit(
    id: id,
    clientId: clientId,
    visitDate: date,
    createdAt: DateTime.utc(2026, 10, 1, 9),
    zoneRecords: [record],
  );

  group('FindPreviousPhotos', () {
    test('looks the previous photos up in the visits of the same client', () async {
      final september = VisitDate(2026, 9, 1);
      final previous = visit(
        'visit-1',
        september,
        ZoneRecord(zoneId: 'zone-1', zoneName: '로비', afterPhoto: PhotoRef('photos/visit-1/after.jpg')),
      );
      final current = visit('visit-2', VisitDate(2026, 10, 1), ZoneRecord(zoneId: 'zone-1', zoneName: '로비'));
      final visits = _MockVisitRepository();
      when(() => visits.visitsOf(clientId)).thenAnswer((_) async => [current, previous]);

      final photos = await FindPreviousPhotos(visits: visits)(current);

      expect(photos, {
        'zone-1': PreviousPhotos(
          visitId: 'visit-1',
          visitDate: september,
          afterPhoto: PhotoRef('photos/visit-1/after.jpg'),
        ),
      });
    });
  });
}
