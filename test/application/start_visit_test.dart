// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

class _MockClientRepository extends Mock implements ClientRepository;

class _MockVisitRepository extends Mock implements VisitRepository;

class _FixedIdGenerator implements IdGenerator {
  @override
  String newId() => 'visit-1';
}

class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 10, 1, 9);
}

void main() {
  const clientId = 'client-1';
  final visitDate = VisitDate(2026, 10, 1);
  final client = Client(id: clientId, name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final zones = ClientZones(
    clientId: clientId,
    zones: [
      Zone(id: 'zone-1', clientId: clientId, name: '로비', position: 1),
      Zone(id: 'zone-2', clientId: clientId, name: '창고', position: 2, isActive: false),
      Zone(id: 'zone-3', clientId: clientId, name: '복도', position: 0),
    ],
  );

  late ClientRepository clients;
  late VisitRepository visits;
  late StartVisit startVisit;

  setUpAll(() {
    registerFallbackValue(
      Visit(id: 'fallback', clientId: clientId, visitDate: visitDate, createdAt: DateTime.utc(2026)),
    );
  });

  setUp(() {
    clients = _MockClientRepository();
    visits = _MockVisitRepository();
    startVisit = StartVisit(clients: clients, visits: visits, idGenerator: _FixedIdGenerator(), clock: _FixedClock());
    when(() => visits.save(any())).thenAnswer((_) async {});
  });

  group('StartVisit', () {
    test('saves and returns a visit that copies the active zones of the client in position order', () async {
      when(() => clients.clientById(clientId)).thenAnswer((_) async => client);
      when(() => clients.zonesOf(clientId)).thenAnswer((_) async => zones);

      final visit = await startVisit(clientId: clientId, visitDate: visitDate);

      expect(
        visit,
        Visit(
          id: 'visit-1',
          clientId: clientId,
          visitDate: visitDate,
          createdAt: DateTime.utc(2026, 10, 1, 9),
          zoneRecords: [
            ZoneRecord(zoneId: 'zone-3', zoneName: '복도'),
            ZoneRecord(zoneId: 'zone-1', zoneName: '로비'),
          ],
        ),
      );
      verify(() => visits.save(visit)).called(1);
    });

    test('refuses a client that does not exist and saves nothing', () async {
      when(() => clients.clientById(clientId)).thenAnswer((_) async => null);

      await expectLater(
        startVisit(clientId: clientId, visitDate: visitDate),
        throwsA(isA<ClientNotFoundException>().having((e) => e.clientId, 'clientId', clientId)),
      );
      verifyNever(() => visits.save(any()));
    });
  });
}
