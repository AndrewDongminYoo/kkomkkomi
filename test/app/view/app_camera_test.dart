// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../helpers/fake_still_camera.dart';
import '../../helpers/helpers.dart';
import '../../persistence/support.dart';

void main() {
  testWidgets('captures through the App route, saves observed UTC and clears it on gallery replacement', (
    tester,
  ) async {
    final time = DateTime.utc(2026, 10, 7, 9, 12, 30, 123, 456);
    final mocks = mockRepositories();
    final visit = Visit(
      id: 'visit-1',
      clientId: 'client-1',
      visitDate: VisitDate(2026, 10, 7),
      createdAt: time,
      zoneRecords: [ZoneRecord(zoneId: 'zone-1', zoneName: 'Lobby')],
    );
    final visits = FakeVisitRepository(visits: [visit]);
    final open = FakeOpenCaptureRepository();
    final repositories = Repositories(
      clients: FakeClientRepository(
        clients: [Client(id: 'client-1', name: 'Office', createdAt: time)],
      ),
      visits: visits,
      companyProfile: mocks.companyProfile,
      publishing: mocks.publishing,
      openCaptures: open,
      localData: FakeLocalDataRepository(),
    );
    final driver = FakeStillCameraDriver();
    final files = FakeCameraPhotoFiles();
    final picker = FakePhotoCapture()..results.add('/cache/gallery.jpg');
    final store = FakePhotoStore();
    await tester.pumpWidget(
      App(
        repositories: repositories,
        identity: FakeIdentity(),
        entitlements: FakeEntitlements(),
        publishQueue: publishQueueOf(repositories),
        recovery: const LostCaptureRecovery(visitId: 'visit-1'),
        clock: FixedClock(time),
        idGenerator: SequenceIdGenerator(),
        photoStore: store,
        cameraDriverFactory: () => driver,
        cameraPhotoFiles: files,
        externalPhotoCapture: picker,
      ),
    );
    await tester.pumpAndSettle();
    expect(driver.initializations, 0);
    final before = (await visits.visitById('visit-1'))!;
    await tester.tap(find.text('Take Before Photo'));
    await tester.pumpAndSettle();
    expect(find.byType(StillCameraPage), findsOneWidget);
    expect(open.saved, isEmpty);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    final saved = (await visits.visitById('visit-1'))!;
    expect(saved.recordFor('zone-1')!.beforeCapturedAt, time);
    expect(saved.recordFor('zone-1')!.beforePhotoSource, PhotoSource.camera);
    expect(saved, isNot(before));
    expect(store.sources.values, ['/cache/normalized.jpg']);
    expect(driver.disposals, 1);
    expect(files.discarded, ['/cache/normalized.jpg']);
    // Re-read actual SQLite, separately from widget fake time, with the result of the real UI/adapter/Cubit path.
    await tester.runAsync(() async {
      final database = await openMemoryDatabase();
      try {
        final actual = sqliteRepositories(database);
        await actual.clients.save(
          Client(id: 'client-1', name: 'Office', createdAt: time),
          zones: ClientZones(
            clientId: 'client-1',
            zones: [Zone(id: 'zone-1', clientId: 'client-1', name: 'Lobby', position: 0)],
          ),
        );
        await actual.visits.save(saved);
        expect((await actual.visits.visitById('visit-1'))!.recordFor('zone-1')!.beforeCapturedAt, time);
      } finally {
        await database.close();
      }
    });
    await tester.tap(find.text('Select before photo from gallery'));
    await tester.pumpAndSettle();
    final gallery = (await visits.visitById('visit-1'))!.recordFor('zone-1')!;
    expect(gallery.beforePhotoSource, PhotoSource.gallery);
    expect(gallery.beforeCapturedAt, isNull);
    expect(driver.captures, 1);
    expect(picker.galleryCalls, 1);
    expect(open.saved.single.source, PhotoSource.gallery);
    expect(files.discarded, ['/cache/normalized.jpg']);
  });
}
