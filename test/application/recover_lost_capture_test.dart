// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

import '../helpers/helpers.dart';

void main() {
  const lost = OpenCapture(visitId: 'visit-1', zoneId: 'zone-2', slot: PhotoSlot.after);
  const picked = '/cache/lost_scaled.jpg';
  final oldPhoto = PhotoRef('photos/visit-1/old.jpg');
  final newPhoto = PhotoRef('photos/visit-1/id-1.jpg');
  final lobby = ZoneRecord(zoneId: 'zone-1', zoneName: '로비');
  final hall = ZoneRecord(zoneId: 'zone-2', zoneName: '복도', beforePhoto: PhotoRef('photos/visit-1/b.jpg'));
  final visit = Visit(
    id: 'visit-1',
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 2),
    createdAt: DateTime.utc(2026, 10, 2, 1),
    zoneRecords: [lobby, hall],
  );
  final failure = Exception('storage failed');

  late FakeOpenCaptureRepository openCaptures;
  late FakeVisitRepository visits;
  late FakePhotoCapture photoCapture;
  late FakePhotoStore photoStore;

  RecoverLostCapture recover() => RecoverLostCapture(
    openCaptures: openCaptures,
    visits: visits,
    photoCapture: photoCapture,
    photoStore: photoStore,
    idGenerator: SequenceIdGenerator(),
    retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
  );

  Visit withAfterPhoto(Visit of, PhotoRef photo) =>
      of.withRecord(of.recordFor('zone-2')!.withPhoto(PhotoSlot.after, photo, source: PhotoSource.camera));

  setUp(() {
    openCaptures = FakeOpenCaptureRepository(capture: lost);
    visits = FakeVisitRepository(visits: [visit]);
    photoCapture = FakePhotoCapture()..lostPhoto = picked;
    photoStore = FakePhotoStore();
  });

  group('LostCaptureRecovery', () {
    test('is a recovery while it holds no failure', () {
      expect(const LostCaptureRecovery(visitId: 'visit-1').isRecovered, isTrue);
      expect(LostCaptureRecovery(visitId: 'visit-1', failure: failure).isRecovered, isFalse);
    });
  });

  group('RecoverLostCapture', () {
    test('keeps recovered picker photos untimed and clears the replaced observation', () async {
      final old = hall.withPhoto(
        PhotoSlot.after,
        oldPhoto,
        source: PhotoSource.camera,
        capturedAt: DateTime.utc(2026, 10, 7, 9, 12),
      );
      visits = FakeVisitRepository(visits: [visit.withRecord(old)]);
      await recover()();
      final recovered = (await visits.visitById('visit-1'))!.recordFor('zone-2')!;
      expect(recovered.afterPhoto, newPhoto);
      expect(recovered.afterPhotoSource, PhotoSource.camera);
      expect(recovered.afterCapturedAt, isNull);
    });

    test('keeps the gallery source of an Android lost pick', () async {
      openCaptures.capture = const OpenCapture(
        visitId: 'visit-1',
        zoneId: 'zone-2',
        slot: PhotoSlot.after,
        source: PhotoSource.gallery,
      );
      await recover()();
      expect((await visits.visitById('visit-1'))!.recordFor('zone-2')!.afterPhotoSource, PhotoSource.gallery);
    });
    test(
      'keeps the lost photo, saves the visit with it in its slot, removes the capture, and names the visit',
      () async {
        final recovery = await recover()();

        expect(recovery?.visitId, 'visit-1');
        expect(recovery?.isRecovered, isTrue);
        expect(await visits.visitById('visit-1'), withAfterPhoto(visit, newPhoto));
        expect(photoStore.sources, {newPhoto: picked});
        expect(photoStore.deleted, isEmpty);
        expect(openCaptures.capture, isNull);
        expect(photoCapture.lostPhotoCalls, 1);
      },
    );

    test('removes the capture only after storage took the visit', () async {
      visits.gate = Completer<void>();

      final recovery = recover()();
      await pumpEventQueue();

      expect(openCaptures.capture, lost);
      visits.gate!.complete();
      expect((await recovery)?.isRecovered, isTrue);
      expect(openCaptures.capture, isNull);
    });

    test('replaces a photo that the slot held, and deletes its file only after storage took the new one', () async {
      final retaken = withAfterPhoto(visit, oldPhoto);
      visits = FakeVisitRepository(visits: [retaken])..gate = Completer<void>();

      final recovery = recover()();
      await pumpEventQueue();

      expect(photoStore.deleted, isEmpty);
      visits.gate!.complete();
      expect((await recovery)?.isRecovered, isTrue);
      expect(await visits.visitById('visit-1'), withAfterPhoto(visit, newPhoto));
      expect(photoStore.deleted, [oldPhoto]);
    });

    test('answers with the recovery when the file of the replaced photo is not deleted', () async {
      visits = FakeVisitRepository(visits: [withAfterPhoto(visit, oldPhoto)]);
      photoStore.deleteFailure = failure;

      final recovery = await recover()();

      expect(recovery?.isRecovered, isTrue);
      expect(await visits.visitById('visit-1'), withAfterPhoto(visit, newPhoto));
    });

    test('does nothing, and does not ask the camera, while no capture is stored', () async {
      openCaptures.capture = null;

      expect(await recover()(), isNull);
      expect(photoCapture.lostPhotoCalls, 0);
      expect(openCaptures.clears, 0);
      expect(await visits.visitById('visit-1'), visit);
    });

    for (final (description, capture) in [
      ('a visit', const OpenCapture(visitId: 'visit-9', zoneId: 'zone-2', slot: PhotoSlot.after)),
      ('a zone record', const OpenCapture(visitId: 'visit-1', zoneId: 'zone-9', slot: PhotoSlot.after)),
    ]) {
      test('removes a capture for $description that does not exist, and changes nothing else', () async {
        openCaptures.capture = capture;

        expect(await recover()(), isNull);
        expect(openCaptures.capture, isNull);
        expect(photoCapture.lostPhotoCalls, 0);
        expect(photoStore.sources, isEmpty);
        expect(await visits.visitById('visit-1'), visit);
      });
    }

    test('asks the camera again after each delay, and keeps the capture for the next start, while the camera has '
        'no photo for it', () async {
      photoCapture.lostPhoto = null;

      expect(await recover()(), isNull);
      expect(photoCapture.lostPhotoCalls, 4);
      expect(openCaptures.capture, lost);
      expect(openCaptures.clears, 0);
      expect(photoStore.sources, isEmpty);
      expect(await visits.visitById('visit-1'), visit);
    });

    test('recovers a photo that the camera gives only on a later question', () async {
      // The camera of Android writes the lost answer on a background thread after the app started again.
      photoCapture.lostAnswers.addAll([null, null]);

      final recovery = await recover()();

      expect(recovery?.isRecovered, isTrue);
      expect(photoCapture.lostPhotoCalls, 3);
      expect(await visits.visitById('visit-1'), withAfterPhoto(visit, newPhoto));
      expect(openCaptures.capture, isNull);
    });

    test('waits 2 seconds in all by default before it leaves the capture to the next start', () {
      expect(
        RecoverLostCapture.defaultRetryDelays.fold(Duration.zero, (total, delay) => total + delay),
        const Duration(seconds: 2),
      );
    });

    test('removes the capture without asking the camera where the camera keeps no lost photo', () async {
      photoCapture.keepsLostPhotos = false;

      expect(await recover()(), isNull);
      expect(photoCapture.lostPhotoCalls, 0);
      expect(openCaptures.capture, isNull);
      expect(await visits.visitById('visit-1'), visit);
    });

    test('keeps the capture for the next start when the camera cannot be asked', () async {
      photoCapture.lostPhoto = const PhotoCaptureException(cause: 'no_activity');

      await expectLater(recover()(), throwsA(isA<PhotoCaptureException>()));
      expect(openCaptures.capture, lost);
      expect(await visits.visitById('visit-1'), visit);
    });

    test('keeps the capture when it cannot be read', () async {
      openCaptures.loadFailure = failure;

      await expectLater(recover()(), throwsA(same(failure)));
      expect(photoCapture.lostPhotoCalls, 0);
      expect(openCaptures.capture, lost);
    });

    test('keeps the capture when the visit cannot be read', () async {
      visits.failure = failure;

      await expectLater(recover()(), throwsA(same(failure)));
      expect(photoCapture.lostPhotoCalls, 0);
      expect(openCaptures.capture, lost);
    });

    test('names the failure, and removes the capture, when the photo store does not take the photo', () async {
      photoStore.saveFailure = failure;

      final recovery = await recover()();

      expect(recovery?.visitId, 'visit-1');
      expect(recovery?.failure, same(failure));
      expect(openCaptures.capture, isNull);
      expect(await visits.visitById('visit-1'), visit);
      expect(photoStore.deleted, isEmpty);
    });

    test('names the failure, deletes the new file, keeps the old photo, and removes the capture, when storage does '
        'not take the visit', () async {
      visits = FakeVisitRepository(visits: [withAfterPhoto(visit, oldPhoto)])..gate = Completer<void>();

      final recovering = recover()();
      await pumpEventQueue();
      visits.gate!.completeError(failure);
      final recovery = await recovering;

      expect(recovery?.visitId, 'visit-1');
      expect(recovery?.failure, same(failure));
      expect(photoStore.deleted, [newPhoto]);
      expect(await visits.visitById('visit-1'), withAfterPhoto(visit, oldPhoto));
      expect(openCaptures.capture, isNull);
    });

    test('names the storage failure when the new file is not deleted either', () async {
      visits.gate = Completer<void>();
      photoStore.deleteFailure = Exception('disk busy');

      final recovering = recover()();
      await pumpEventQueue();
      visits.gate!.completeError(failure);
      final recovery = await recovering;

      expect(recovery?.failure, same(failure));
      expect(openCaptures.capture, isNull);
    });

    test('answers with the recovery when the capture cannot be removed after the visit took the photo', () async {
      openCaptures.clearFailure = failure;

      final recovery = await recover()();

      expect(recovery?.isRecovered, isTrue);
      expect(await visits.visitById('visit-1'), withAfterPhoto(visit, newPhoto));
    });
  });
}
