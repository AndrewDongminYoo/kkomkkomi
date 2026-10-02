import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  const lobbyBefore = OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.before);
  const hallAfter = OpenCapture(visitId: 'visit-2', zoneId: 'zone-2', slot: PhotoSlot.after);

  late Database database;
  late SqliteOpenCaptureRepository repository;

  setUp(() async {
    database = await openMemoryDatabase();
    repository = SqliteOpenCaptureRepository(database);
  });

  tearDown(() => database.close());

  group('SqliteOpenCaptureRepository', () {
    test('loads null before a capture is stored', () async {
      expect(await repository.load(), isNull);
    });

    test('round-trips the visit, the zone, and each slot', () async {
      await repository.save(lobbyBefore);
      expect(await repository.load(), lobbyBefore);

      await repository.save(hallAfter);
      expect(await repository.load(), hallAfter);
    });

    test('keeps one row, so a new capture replaces the stored one', () async {
      await repository.save(lobbyBefore);
      await repository.save(hallAfter);

      expect(await database.query('open_capture'), [
        {'id': 1, 'visit_id': 'visit-2', 'zone_id': 'zone-2', 'slot': 'after'},
      ]);
    });

    test('stores a capture for a visit that the database does not hold', () async {
      // The table declares no foreign key, so a failed capture never fails for its record.
      await repository.save(lobbyBefore);

      expect(await database.query('visits'), isEmpty);
      expect(await repository.load(), lobbyBefore);
    });

    test('removes the stored capture, and a removal without one is no failure', () async {
      await repository.save(lobbyBefore);

      await repository.clear();
      expect(await repository.load(), isNull);

      await repository.clear();
      expect(await repository.load(), isNull);
    });
  });
}
