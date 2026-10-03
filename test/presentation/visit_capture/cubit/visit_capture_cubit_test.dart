import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

void main() {
  const clientId = 'client-a';
  const visitId = 'visit-2';
  const picked = '/cache/scaled_camera.jpg';
  final oldPhoto = PhotoRef('photos/visit-2/old.jpg');
  final newPhoto = PhotoRef('photos/visit-2/id-1.jpg');
  final lobby = ZoneRecord(zoneId: 'zone-1', zoneName: '로비');
  final hall = ZoneRecord(zoneId: 'zone-2', zoneName: '복도', beforePhoto: oldPhoto, note: '왁스');
  final visit = Visit(
    id: visitId,
    clientId: clientId,
    visitDate: VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 1),
    zoneRecords: [lobby, hall],
  );
  final earlier = Visit(
    id: 'visit-1',
    clientId: clientId,
    visitDate: VisitDate(2026, 9, 16),
    createdAt: DateTime.utc(2026, 9, 16, 1),
    zoneRecords: [
      ZoneRecord(
        zoneId: 'zone-1',
        zoneName: '로비',
        beforePhoto: PhotoRef('photos/visit-1/before.jpg'),
        afterPhoto: PhotoRef('photos/visit-1/after.jpg'),
      ),
    ],
  );
  final previousPhotos = {
    'zone-1': PreviousPhotos(
      visitId: 'visit-1',
      visitDate: VisitDate(2026, 9, 16),
      beforePhoto: PhotoRef('photos/visit-1/before.jpg'),
      afterPhoto: PhotoRef('photos/visit-1/after.jpg'),
    ),
  };
  final failure = Exception('storage failed');
  const clientName = '한빛빌딩';
  final client = Client(id: clientId, name: clientName, createdAt: DateTime.utc(2026, 9, 2));

  late MockVisitRepository visits;
  late MockClientRepository clients;
  late FakePhotoCapture photoCapture;
  late FakePhotoStore photoStore;
  late FakeOpenCaptureRepository openCaptures;

  VisitCaptureCubit build() => VisitCaptureCubit(
    visitId: visitId,
    visits: visits,
    clients: clients,
    photoCapture: photoCapture,
    photoStore: photoStore,
    idGenerator: SequenceIdGenerator(),
    openCaptures: openCaptures,
  );

  VisitCaptureState loaded({
    VisitCaptureStatus status = VisitCaptureStatus.ready,
    Visit? shown,
    bool isStored = true,
    bool isSavingNote = false,
  }) => VisitCaptureState(
    status: status,
    visit: shown ?? visit,
    clientName: clientName,
    previousPhotos: previousPhotos,
    photoDirectory: FakePhotoStore.directory,
    isStored: isStored,
    isSavingNote: isSavingNote,
  );

  Visit withNote(String zoneId, String note, {Visit? of}) {
    final from = of ?? visit;
    return from.withRecord(from.recordFor(zoneId)!.withNote(note));
  }

  Visit withPhoto(String zoneId, PhotoSlot slot, PhotoRef photo) =>
      visit.withRecord(visit.recordFor(zoneId)!.withPhoto(slot, photo));

  /// Makes each save wait for the completer that the returned list holds for it, in the order of the calls.
  List<Completer<void>> holdSaves() {
    final answers = <Completer<void>>[];
    when(() => visits.save(any())).thenAnswer((_) {
      final answer = Completer<void>();
      answers.add(answer);
      return answer.future;
    });
    return answers;
  }

  setUpAll(() => registerFallbackValue(visit));

  setUp(() {
    visits = MockVisitRepository();
    clients = MockClientRepository();
    photoCapture = FakePhotoCapture();
    photoStore = FakePhotoStore();
    openCaptures = FakeOpenCaptureRepository();
    when(() => visits.visitById(visitId)).thenAnswer((_) async => visit);
    when(() => visits.visitsOf(clientId)).thenAnswer((_) async => [visit, earlier]);
    when(() => visits.save(any())).thenAnswer((_) async {});
    when(() => clients.clientById(clientId)).thenAnswer((_) async => client);
  });

  group('VisitCaptureStatus', () {
    test('takes a change only while the visit is on the screen and no capture runs', () {
      expect(
        VisitCaptureStatus.values.where((status) => status.takesChange),
        [
          VisitCaptureStatus.ready,
          VisitCaptureStatus.captureFailed,
          VisitCaptureStatus.captureDenied,
          VisitCaptureStatus.saveFailed,
        ],
      );
    });
  });

  group('VisitCaptureState', () {
    test('is equal to a state with the same fields', () {
      expect(loaded(), loaded());
      expect(loaded().hashCode, loaded().hashCode);
    });

    test('differs from a state with another field value', () {
      expect(loaded(), isNot(loaded(status: VisitCaptureStatus.capturing)));
      expect(loaded(), isNot(loaded(shown: withNote('zone-1', '유리'))));
      expect(loaded(), isNot(loaded(isStored: false)));
      expect(loaded(), isNot(loaded(isSavingNote: true)));
      expect(
        loaded(),
        isNot(
          VisitCaptureState(
            status: VisitCaptureStatus.ready,
            visit: visit,
            previousPhotos: previousPhotos,
            photoDirectory: FakePhotoStore.directory,
          ),
        ),
      );
      expect(
        loaded(),
        isNot(VisitCaptureState(status: VisitCaptureStatus.ready, visit: visit, photoDirectory: '/documents')),
      );
      expect(
        loaded(),
        isNot(VisitCaptureState(status: VisitCaptureStatus.ready, visit: visit, previousPhotos: previousPhotos)),
      );
    });

    test('pathOf gives the file of a photo under the photo directory', () {
      expect(loaded().pathOf(oldPhoto), '/documents/photos/visit-2/old.jpg');
    });

    test('copyWith keeps the client name, the previous photos, the photo directory, and what it is not given', () {
      expect(loaded().copyWith(visit: withNote('zone-1', '유리')).clientName, clientName);
      expect(loaded().copyWith(status: VisitCaptureStatus.saveFailed), loaded(status: VisitCaptureStatus.saveFailed));
      expect(loaded().copyWith(isStored: false), loaded(isStored: false));
      expect(loaded(isStored: false).copyWith(status: VisitCaptureStatus.capturing).isStored, isFalse);
      expect(loaded().copyWith(isSavingNote: true), loaded(isSavingNote: true));
      expect(loaded(isSavingNote: true).copyWith(isStored: false).isSavingNote, isTrue);
    });

    test('lets the person leave only while storage holds every note and none is on its way', () {
      expect(loaded().canLeave, isTrue);
      expect(loaded(isStored: false).canLeave, isFalse);
      expect(loaded(isSavingNote: true).canLeave, isFalse);
      expect(const VisitCaptureState().isSavingNote, isFalse);
    });

    test('holds the notes as stored until a save tells otherwise', () {
      expect(const VisitCaptureState().isStored, isTrue);
    });
  });

  group('VisitCaptureCubit', () {
    test('starts without a visit while the first load runs', () {
      expect(build().state, const VisitCaptureState());
      expect(build().state.status, VisitCaptureStatus.loading);
    });

    group('load', () {
      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reopens the visit with its photos and notes, the previous photos of its zones, and the photo directory',
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [loaded()],
        verify: (cubit) {
          expect(cubit.state.visit!.recordFor('zone-2'), hall);
          expect(cubit.state.previousPhotos.keys, ['zone-1']);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reads the name of the client of the visit',
        build: build,
        act: (cubit) => cubit.load(),
        verify: (cubit) {
          expect(cubit.state.clientName, clientName);
          verify(() => clients.clientById(clientId)).called(1);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'shows the visit without a client name when storage has no such client',
        setUp: () => when(() => clients.clientById(clientId)).thenAnswer((_) async => null),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [
          VisitCaptureState(
            status: VisitCaptureStatus.ready,
            visit: visit,
            previousPhotos: previousPhotos,
            photoDirectory: FakePhotoStore.directory,
          ),
        ],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reports a failure to read the client, and shows the visit without a client name',
        setUp: () => when(() => clients.clientById(clientId)).thenThrow(failure),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [
          VisitCaptureState(
            status: VisitCaptureStatus.ready,
            visit: visit,
            previousPhotos: previousPhotos,
            photoDirectory: FakePhotoStore.directory,
          ),
        ],
        errors: () => [failure],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reports a visit that storage does not have as a failed load',
        setUp: () => when(() => visits.visitById(visitId)).thenAnswer((_) async => null),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const VisitCaptureState(status: VisitCaptureStatus.loadFailed)],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reports a failure of storage',
        setUp: () => when(() => visits.visitsOf(clientId)).thenThrow(failure),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const VisitCaptureState(status: VisitCaptureStatus.loadFailed)],
        errors: () => [failure],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'shows the loading state and then the visit when it runs again after a failure',
        build: build,
        seed: () => const VisitCaptureState(status: VisitCaptureStatus.loadFailed),
        act: (cubit) => cubit.load(),
        expect: () => [const VisitCaptureState(), loaded()],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'does nothing while the visit is on the screen, because storage can be behind the screen',
        build: build,
        seed: () => loaded(shown: withNote('zone-1', '유리')),
        act: (cubit) => cubit.load(),
        expect: () => isEmpty,
        verify: (_) => verifyNever(() => visits.visitById(any())),
      );

      for (final (description, answerLoad) in <(String, void Function(Completer<Visit?>))>[
        ('storage answers', (answer) => answer.complete(visit)),
        ('storage has no such visit', (answer) => answer.complete()),
        ('storage fails', (answer) => answer.completeError(failure)),
      ]) {
        test('emits nothing when the cubit closes before $description', () async {
          final answer = Completer<Visit?>();
          when(() => visits.visitById(visitId)).thenAnswer((_) => answer.future);
          final cubit = build();

          final load = cubit.load();
          await cubit.close();
          answerLoad(answer);
          await load;

          expect(cubit.state, const VisitCaptureState());
        });
      }
    });

    group('capturePhoto', () {
      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'takes a photo, keeps its file under the visit, and saves the visit with it',
        setUp: () => photoCapture.results.add(picked),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.before),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(shown: withPhoto('zone-1', PhotoSlot.before, newPhoto)),
        ],
        verify: (_) {
          verify(() => visits.save(withPhoto('zone-1', PhotoSlot.before, newPhoto))).called(1);
          expect(photoStore.sources, {newPhoto: picked});
          expect(photoStore.deleted, isEmpty);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'takes the after photo of a zone that has a before photo and keeps the before photo',
        setUp: () => photoCapture.results.add(picked),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-2', PhotoSlot.after),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(shown: withPhoto('zone-2', PhotoSlot.after, newPhoto)),
        ],
        verify: (cubit) {
          expect(cubit.state.visit!.recordFor('zone-2')!.beforePhoto, oldPhoto);
          expect(photoStore.deleted, isEmpty);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'retakes a photo: saves the visit with the new file, and deletes the old file only after that',
        setUp: () {
          photoCapture.results.add(picked);
          photoStore.sources[oldPhoto] = '/cache/old.jpg';
          when(() => visits.save(any())).thenAnswer((_) async {
            // The old file is still there while storage does not hold the new photo.
            expect(photoStore.deleted, isEmpty);
          });
        },
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-2', PhotoSlot.before),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(shown: withPhoto('zone-2', PhotoSlot.before, newPhoto)),
        ],
        verify: (_) {
          verify(() => visits.save(withPhoto('zone-2', PhotoSlot.before, newPhoto))).called(1);
          expect(photoStore.deleted, [oldPhoto]);
          expect(photoStore.sources, {newPhoto: picked});
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'changes nothing when the person closes the camera without a photo',
        setUp: () => photoCapture.results.add(null),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-2', PhotoSlot.before),
        expect: () => [loaded(status: VisitCaptureStatus.capturing), loaded()],
        verify: (_) {
          verifyNever(() => visits.save(any()));
          expect(photoStore.sources, isEmpty);
          expect(photoStore.deleted, isEmpty);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reports a camera that gave no photo, and keeps the visit as it was',
        setUp: () => photoCapture.results.add(const PhotoCaptureException()),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-2', PhotoSlot.before),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(status: VisitCaptureStatus.captureFailed),
        ],
        errors: () => [isA<PhotoCaptureException>()],
        verify: (_) {
          verifyNever(() => visits.save(any()));
          expect(photoStore.deleted, isEmpty);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reports a camera that the person did not allow',
        setUp: () => photoCapture.results.add(const PhotoCaptureException(isAccessDenied: true)),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.before),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(status: VisitCaptureStatus.captureDenied),
        ],
        errors: () => [isA<PhotoCaptureException>()],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'reports a photo that the photo store did not keep, and saves nothing',
        setUp: () {
          photoCapture.results.add(picked);
          photoStore.saveFailure = const FileSystemException('disk full');
        },
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.after),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(status: VisitCaptureStatus.captureFailed),
        ],
        errors: () => [isA<FileSystemException>()],
        verify: (_) => verifyNever(() => visits.save(any())),
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'keeps the old photo and deletes the new file when storage does not take the visit',
        setUp: () {
          photoCapture.results.add(picked);
          when(() => visits.save(any())).thenThrow(failure);
        },
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-2', PhotoSlot.before),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(status: VisitCaptureStatus.saveFailed),
        ],
        errors: () => [failure],
        verify: (cubit) {
          expect(cubit.state.visit!.recordFor('zone-2')!.beforePhoto, oldPhoto);
          expect(photoStore.deleted, [newPhoto]);
        },
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'keeps the new photo when the old file cannot be deleted, and reports the file',
        setUp: () {
          photoCapture.results.add(picked);
          photoStore.deleteFailure = const FileSystemException('busy');
        },
        build: build,
        seed: loaded,
        act: (cubit) => cubit.capturePhoto('zone-2', PhotoSlot.before),
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(shown: withPhoto('zone-2', PhotoSlot.before, newPhoto)),
        ],
        errors: () => [isA<FileSystemException>()],
      );

      for (final status in [
        VisitCaptureStatus.captureFailed,
        VisitCaptureStatus.captureDenied,
        VisitCaptureStatus.saveFailed,
      ]) {
        blocTest<VisitCaptureCubit, VisitCaptureState>(
          'works again in the ${status.name} status',
          setUp: () => photoCapture.results.add(picked),
          build: build,
          seed: () => loaded(status: status),
          act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.before),
          expect: () => [
            loaded(status: VisitCaptureStatus.capturing),
            loaded(shown: withPhoto('zone-1', PhotoSlot.before, newPhoto)),
          ],
        );
      }

      for (final status in [
        VisitCaptureStatus.loading,
        VisitCaptureStatus.loadFailed,
        VisitCaptureStatus.capturing,
      ]) {
        blocTest<VisitCaptureCubit, VisitCaptureState>(
          'does nothing in the ${status.name} status',
          build: build,
          seed: () => loaded(status: status),
          act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.before),
          expect: () => isEmpty,
          verify: (_) => expect(photoCapture.calls, 0),
        );
      }

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'does nothing while the visit is not loaded, and for a zone that the visit does not hold',
        build: build,
        act: (cubit) async {
          await cubit.capturePhoto('zone-1', PhotoSlot.before);
          await cubit.load();
          await cubit.capturePhoto('zone-9', PhotoSlot.before);
        },
        expect: () => [loaded()],
        verify: (_) => expect(photoCapture.calls, 0),
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'takes no second photo while the camera is open',
        setUp: () => photoCapture
          ..results.add(picked)
          ..gate = Completer<void>(),
        build: build,
        seed: loaded,
        act: (cubit) async {
          final first = cubit.capturePhoto('zone-1', PhotoSlot.before);
          await cubit.capturePhoto('zone-1', PhotoSlot.after);
          photoCapture.gate!.complete();
          await first;
        },
        expect: () => [
          loaded(status: VisitCaptureStatus.capturing),
          loaded(shown: withPhoto('zone-1', PhotoSlot.before, newPhoto)),
        ],
        verify: (_) => expect(photoCapture.calls, 1),
      );

      test(
        'keeps and saves the photo, and emits nothing more, when the cubit closes while the camera is open',
        () async {
          photoCapture
            ..results.add(picked)
            ..gate = Completer<void>();
          final cubit = build();
          await cubit.load();

          final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
          await cubit.close();
          photoCapture.gate!.complete();
          await capture;

          expect(cubit.state, loaded(status: VisitCaptureStatus.capturing));
          verify(() => visits.save(withPhoto('zone-1', PhotoSlot.before, newPhoto))).called(1);
        },
      );

      for (final (description, result) in <(String, Object?)>[
        ('the person closes the camera', null),
        ('the camera fails', const PhotoCaptureException()),
      ]) {
        test('emits nothing more when the cubit closes before $description', () async {
          photoCapture
            ..results.add(result)
            ..gate = Completer<void>();
          final cubit = build();
          await cubit.load();

          final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
          await cubit.close();
          photoCapture.gate!.complete();
          await capture;

          expect(cubit.state, loaded(status: VisitCaptureStatus.capturing));
        });
      }

      test('deletes the new file, and emits nothing more, when storage fails after the cubit closed', () async {
        photoCapture.results.add(picked);
        final saves = holdSaves();
        final cubit = build();
        await cubit.load();

        final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
        await pumpEventQueue();
        await cubit.close();
        saves.single.completeError(failure);
        await capture;

        expect(cubit.state, loaded(status: VisitCaptureStatus.capturing));
        expect(photoStore.deleted, [newPhoto]);
      });

      group('the stored open capture', () {
        const lobbyBefore = OpenCapture(visitId: visitId, zoneId: 'zone-1', slot: PhotoSlot.before);

        for (final (description, result) in <(String, Object?)>[
          ('gives a photo', picked),
          ('is closed without a photo', null),
          ('fails', const PhotoCaptureException()),
        ]) {
          test(
            'names the visit, the zone, and the slot while the camera is open, and goes when the camera $description',
            () async {
              photoCapture
                ..results.add(result)
                ..gate = Completer<void>();
              final cubit = build();
              addTearDown(cubit.close);
              await cubit.load();

              final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
              await pumpEventQueue();
              expect(photoCapture.calls, 1);
              expect(openCaptures.capture, lobbyBefore);
              photoCapture.gate!.complete();
              await capture;

              expect(openCaptures.saved, [lobbyBefore]);
              expect(openCaptures.capture, isNull);
              expect(openCaptures.clears, 1);
            },
          );
        }

        test('is stored before the camera opens', () async {
          photoCapture.results.add(null);
          final cameraCallsAtSave = <int>[];
          openCaptures.onSave = () => cameraCallsAtSave.add(photoCapture.calls);
          final cubit = build();
          addTearDown(cubit.close);
          await cubit.load();

          await cubit.capturePhoto('zone-1', PhotoSlot.before);

          expect(cameraCallsAtSave, [0]);
          expect(photoCapture.calls, 1);
        });

        blocTest<VisitCaptureCubit, VisitCaptureState>(
          'does not open the camera, and says that storage did not save, when storage does not take the capture',
          setUp: () {
            photoCapture.results.add(picked);
            openCaptures
              ..capture = const OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.after)
              ..saveFailure = failure;
          },
          build: build,
          seed: loaded,
          act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.before),
          expect: () => [
            loaded(status: VisitCaptureStatus.capturing),
            loaded(status: VisitCaptureStatus.saveFailed),
          ],
          errors: () => [failure],
          verify: (_) {
            // A photo that the camera lost would go to the capture that storage still names.
            expect(photoCapture.calls, 0);
            expect(openCaptures.clears, 0);
            verifyNever(() => visits.save(any()));
          },
        );

        blocTest<VisitCaptureCubit, VisitCaptureState>(
          'does not stop a capture when storage does not remove it, and reports the failure',
          setUp: () {
            photoCapture.results.add(picked);
            openCaptures.clearFailure = failure;
          },
          build: build,
          seed: loaded,
          act: (cubit) => cubit.capturePhoto('zone-1', PhotoSlot.before),
          expect: () => [
            loaded(status: VisitCaptureStatus.capturing),
            loaded(shown: withPhoto('zone-1', PhotoSlot.before, newPhoto)),
          ],
          errors: () => [failure],
          verify: (_) => verify(() => visits.save(withPhoto('zone-1', PhotoSlot.before, newPhoto))).called(1),
        );
      });

      test('reports no unsaved change when the person closes the camera after a photo that storage refused', () async {
        photoCapture.results.addAll([picked, null]);
        when(() => visits.save(any())).thenThrow(failure);
        final cubit = build();
        await cubit.load();
        final statuses = <VisitCaptureStatus>[];
        final subscription = cubit.stream.listen((state) => statuses.add(state.status));

        await cubit.capturePhoto('zone-1', PhotoSlot.before);
        await cubit.capturePhoto('zone-1', PhotoSlot.before);
        await pumpEventQueue();
        await subscription.cancel();

        // Storage holds the visit of the state after the refused photo, so the closed camera leaves nothing to report.
        expect(statuses, [
          VisitCaptureStatus.capturing,
          VisitCaptureStatus.saveFailed,
          VisitCaptureStatus.capturing,
          VisitCaptureStatus.ready,
        ]);
        expect(cubit.state, loaded());
      });
    });

    group('editNote', () {
      test('sends each edit to storage at once, so that a screen that opens later reads after every edit', () async {
        final saves = holdSaves();
        final cubit = build();
        await cubit.load();

        final edits = [cubit.editNote('zone-1', '유'), cubit.editNote('zone-1', '유리')];

        // Both saves are with storage before the first answer, in the order of the edits.
        verifyInOrder([
          () => visits.save(withNote('zone-1', '유')),
          () => visits.save(withNote('zone-1', '유리')),
        ]);
        for (final save in saves) {
          save.complete();
        }
        await Future.wait(edits);
      });

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'shows the note at once, as it is written, and saves the visit with it',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.editNote('zone-1', ' 유리 닦음\n'),
        expect: () => [
          loaded(shown: withNote('zone-1', ' 유리 닦음\n'), isSavingNote: true),
          loaded(shown: withNote('zone-1', ' 유리 닦음\n')),
        ],
        verify: (_) => verify(() => visits.save(withNote('zone-1', ' 유리 닦음\n'))).called(1),
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'saves an emptied note',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.editNote('zone-2', ''),
        expect: () => [
          loaded(shown: withNote('zone-2', ''), isSavingNote: true),
          loaded(shown: withNote('zone-2', '')),
        ],
        verify: (_) => verify(() => visits.save(withNote('zone-2', ''))).called(1),
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'saves nothing for the note that the zone already has',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.editNote('zone-2', '왁스'),
        expect: () => isEmpty,
        verify: (_) => verifyNever(() => visits.save(any())),
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'keeps the note on the screen and reports the failure when storage does not take it',
        setUp: () => when(() => visits.save(any())).thenThrow(failure),
        build: build,
        seed: loaded,
        act: (cubit) => cubit.editNote('zone-1', '유리'),
        expect: () => [
          loaded(shown: withNote('zone-1', '유리'), isSavingNote: true),
          loaded(shown: withNote('zone-1', '유리'), isStored: false),
        ],
        errors: () => [failure],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'keeps telling that the notes are not stored while storage takes no edit',
        setUp: () => when(() => visits.save(any())).thenThrow(failure),
        build: build,
        seed: loaded,
        act: (cubit) async {
          await cubit.editNote('zone-1', '유');
          await cubit.editNote('zone-1', '유리');
        },
        expect: () => [
          loaded(shown: withNote('zone-1', '유'), isSavingNote: true),
          loaded(shown: withNote('zone-1', '유'), isStored: false),
          loaded(shown: withNote('zone-1', '유리'), isStored: false, isSavingNote: true),
          loaded(shown: withNote('zone-1', '유리'), isStored: false),
        ],
        errors: () => [failure, failure],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'sends the whole note again with the next edit, and ends the failure when storage takes it',
        build: build,
        seed: () => loaded(shown: withNote('zone-1', '유리'), isStored: false),
        act: (cubit) => cubit.editNote('zone-1', '유리 닦음'),
        expect: () => [
          loaded(shown: withNote('zone-1', '유리 닦음'), isStored: false, isSavingNote: true),
          loaded(shown: withNote('zone-1', '유리 닦음')),
        ],
        verify: (_) => verify(() => visits.save(withNote('zone-1', '유리 닦음'))).called(1),
      );

      test('reports the failure of the newest save although an older save succeeded', () async {
        final saves = holdSaves();
        final cubit = build();
        await cubit.load();

        final edits = [cubit.editNote('zone-1', '유'), cubit.editNote('zone-1', '유리')];
        await pumpEventQueue();
        saves.first.complete();
        await pumpEventQueue();
        expect(cubit.state, loaded(shown: withNote('zone-1', '유리'), isSavingNote: true));
        saves.last.completeError(failure);
        await Future.wait(edits);

        expect(cubit.state, loaded(shown: withNote('zone-1', '유리'), isStored: false));
      });

      test('keeps the failure of an older save until the newest save succeeds', () async {
        final saves = holdSaves();
        final cubit = build();
        await cubit.load();

        final edits = [cubit.editNote('zone-1', '유'), cubit.editNote('zone-1', '유리')];
        await pumpEventQueue();
        saves.first.completeError(failure);
        await pumpEventQueue();
        // The newer save is still on its way, so the person cannot leave yet.
        expect(cubit.state, loaded(shown: withNote('zone-1', '유리'), isStored: false, isSavingNote: true));
        saves.last.complete();
        await Future.wait(edits);

        expect(cubit.state, loaded(shown: withNote('zone-1', '유리')));
      });

      test('does not take the notes as stored from an older save while a newer save is on its way', () async {
        final saves = holdSaves();
        final cubit = build()..emit(loaded(shown: withNote('zone-1', '유'), isStored: false));

        final edits = [cubit.editNote('zone-1', '유리'), cubit.editNote('zone-1', '유리 닦음')];
        saves.first.complete();
        await pumpEventQueue();
        // Storage holds the first edit, and the second is not answered, so the notice of unsaved notes stays.
        expect(cubit.state, loaded(shown: withNote('zone-1', '유리 닦음'), isStored: false, isSavingNote: true));

        saves.last.complete();
        await Future.wait(edits);

        expect(cubit.state, loaded(shown: withNote('zone-1', '유리 닦음')));
      });

      for (final status in [
        VisitCaptureStatus.loading,
        VisitCaptureStatus.loadFailed,
        VisitCaptureStatus.capturing,
      ]) {
        blocTest<VisitCaptureCubit, VisitCaptureState>(
          'does nothing in the ${status.name} status',
          build: build,
          seed: () => loaded(status: status),
          act: (cubit) => cubit.editNote('zone-1', '유리'),
          expect: () => isEmpty,
          verify: (_) => verifyNever(() => visits.save(any())),
        );
      }

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'does nothing while the visit is not loaded, and for a zone that the visit does not hold',
        build: build,
        act: (cubit) async {
          await cubit.editNote('zone-1', '유리');
          await cubit.load();
          await cubit.editNote('zone-9', '유리');
        },
        expect: () => [loaded()],
        verify: (_) => verifyNever(() => visits.save(any())),
      );

      for (final (description, answerSave) in <(String, void Function(Completer<void>))>[
        ('storage answers', (answer) => answer.complete()),
        ('storage fails', (answer) => answer.completeError(failure)),
      ]) {
        test('emits nothing more when the cubit closes before $description', () async {
          final saves = holdSaves();
          final cubit = build();
          await cubit.load();

          final edit = cubit.editNote('zone-1', '유리');
          await pumpEventQueue();
          await cubit.close();
          answerSave(saves.single);
          await edit;

          expect(cubit.state, loaded(shown: withNote('zone-1', '유리'), isSavingNote: true));
        });
      }
    });

    group('saveAgain', () {
      final noted = withNote('zone-1', '유리');

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'sends the visit with its notes to storage again, and tells that the notes are stored',
        build: build,
        seed: () => loaded(shown: noted, isStored: false),
        act: (cubit) => cubit.saveAgain(),
        expect: () => [
          loaded(shown: noted, isStored: false, isSavingNote: true),
          loaded(shown: noted),
        ],
        verify: (_) => verify(() => visits.save(noted)).called(1),
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'keeps telling that the notes are not stored when storage fails again',
        setUp: () => when(() => visits.save(any())).thenThrow(failure),
        build: build,
        seed: () => loaded(shown: noted, isStored: false),
        act: (cubit) => cubit.saveAgain(),
        expect: () => [
          loaded(shown: noted, isStored: false, isSavingNote: true),
          loaded(shown: noted, isStored: false),
        ],
        errors: () => [failure],
      );

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'does nothing while storage holds the notes',
        build: build,
        seed: loaded,
        act: (cubit) => cubit.saveAgain(),
        expect: () => isEmpty,
        verify: (_) => verifyNever(() => visits.save(any())),
      );

      for (final status in [
        VisitCaptureStatus.loading,
        VisitCaptureStatus.loadFailed,
        VisitCaptureStatus.capturing,
      ]) {
        blocTest<VisitCaptureCubit, VisitCaptureState>(
          'does nothing in the ${status.name} status',
          build: build,
          seed: () => loaded(status: status, shown: noted, isStored: false),
          act: (cubit) => cubit.saveAgain(),
          expect: () => isEmpty,
          verify: (_) => verifyNever(() => visits.save(any())),
        );
      }

      blocTest<VisitCaptureCubit, VisitCaptureState>(
        'does nothing while the visit is not loaded',
        build: build,
        act: (cubit) => cubit.saveAgain(),
        expect: () => isEmpty,
        verify: (_) => verifyNever(() => visits.save(any())),
      );
    });

    group('a capture after a note that is on its way to storage', () {
      test('opens the camera only after storage answered for the note', () async {
        photoCapture.results.add(null);
        final saves = holdSaves();
        final cubit = build();
        await cubit.load();

        final edit = cubit.editNote('zone-1', '유리');
        final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
        await pumpEventQueue();
        expect(cubit.state.status, VisitCaptureStatus.capturing);
        expect(photoCapture.calls, 0);

        saves.single.complete();
        await Future.wait([edit, capture]);

        expect(photoCapture.calls, 1);
        expect(cubit.state, loaded(shown: withNote('zone-1', '유리')));
      });

      test('says that the visit is not saved when storage refused the note and the person closes the camera', () async {
        photoCapture.results.add(null);
        final saves = holdSaves();
        final cubit = build();
        await cubit.load();

        final edit = cubit.editNote('zone-1', '유리');
        final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
        await pumpEventQueue();
        saves.single.completeError(failure);
        await Future.wait([edit, capture]);

        expect(cubit.state, loaded(shown: withNote('zone-1', '유리'), isStored: false));
      });

      for (final (description, result, status) in <(String, Object, VisitCaptureStatus)>[
        ('the camera fails', const PhotoCaptureException(), VisitCaptureStatus.captureFailed),
        (
          'the person did not allow the camera',
          const PhotoCaptureException(isAccessDenied: true),
          VisitCaptureStatus.captureDenied,
        ),
      ]) {
        test('still tells that the note is not stored when storage refused the note and $description', () async {
          photoCapture.results.add(result);
          final saves = holdSaves();
          final cubit = build();
          await cubit.load();

          final edit = cubit.editNote('zone-1', '유리');
          final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
          await pumpEventQueue();
          saves.single.completeError(failure);
          await Future.wait([edit, capture]);

          expect(cubit.state, loaded(status: status, shown: withNote('zone-1', '유리'), isStored: false));
        });
      }

      test('still tells that the note is not stored when storage refused the note and then the photo', () async {
        photoCapture.results.addAll([picked, null]);
        when(() => visits.save(any())).thenThrow(failure);
        final noted = withNote('zone-1', '유리');
        final cubit = build();
        await cubit.load();

        await cubit.editNote('zone-1', '유리');
        await cubit.capturePhoto('zone-1', PhotoSlot.before);
        expect(cubit.state, loaded(status: VisitCaptureStatus.saveFailed, shown: noted, isStored: false));
        expect(photoStore.deleted, [newPhoto]);

        // The closed camera of a later capture changes nothing, and the note is still not stored.
        await cubit.capturePhoto('zone-1', PhotoSlot.before);

        expect(cubit.state, loaded(shown: noted, isStored: false));
      });

      test('saves the note together with the photo when storage refused the note alone', () async {
        photoCapture.results.add(picked);
        final saves = holdSaves();
        final noted = withNote('zone-1', '유리');
        final cubit = build();
        await cubit.load();

        final edit = cubit.editNote('zone-1', '유리');
        final capture = cubit.capturePhoto('zone-1', PhotoSlot.before);
        await pumpEventQueue();
        saves.first.completeError(failure);
        await pumpEventQueue();
        saves.last.complete();
        await Future.wait([edit, capture]);

        final withBoth = noted.withRecord(noted.recordFor('zone-1')!.withPhoto(PhotoSlot.before, newPhoto));
        expect(cubit.state, loaded(shown: withBoth));
        verify(() => visits.save(withBoth)).called(1);
      });
    });
  });
}
