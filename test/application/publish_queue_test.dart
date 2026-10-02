import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/helpers.dart';
import '../persistence/support.dart';

/// A clock that a test moves.
class _Clock implements Clock {
  new(this.time);

  DateTime time;

  @override
  DateTime now() => time;
}

/// A timer that fires only when a test calls [fire].
class _Timer implements Timer {
  new(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

/// The stored jobs of the app, with a read of the pending jobs that waits while [gate] is set.
class _GatedRepository implements PublishRepository {
  new(this._inner);

  final PublishRepository _inner;

  /// The next read of the pending jobs waits for this completer, and clears it.
  Completer<void>? gate;

  @override
  Future<List<PublishJob>> pendingJobs() async {
    final waiting = gate;
    gate = null;
    await waiting?.future;
    return await _inner.pendingJobs();
  }

  @override
  Future<ClientPage?> openPageOf(String clientId, {ClientPage Function()? create}) =>
      _inner.openPageOf(clientId, create: create);

  @override
  Future<ClientPage?> pageById(String id) => _inner.pageById(id);

  @override
  Future<List<ClientPage>> pages() => _inner.pages();

  @override
  Future<PublishJob> enqueue(PublishJob job) => _inner.enqueue(job);

  @override
  Future<bool> revoke(
    ClientPage page, {
    required DateTime at,
    required PublishJob revokeJob,
    ClientPage? replacement,
    PublishJob Function(String visitId)? republish,
  }) => _inner.revoke(page, at: at, revokeJob: revokeJob, replacement: replacement, republish: republish);

  /// The next save of a job waits for this completer, and clears it.
  Completer<void>? saveGate;

  @override
  Future<bool> saveJob(PublishJob job) async {
    final waiting = saveGate;
    saveGate = null;
    await waiting?.future;
    return await _inner.saveJob(job);
  }

  @override
  Future<void> recordUploadIntent({required String pageId, required String objectPath, required String photoPath}) =>
      _inner.recordUploadIntent(pageId: pageId, objectPath: objectPath, photoPath: photoPath);

  @override
  Future<List<PublishJob>> jobsOfPage(String pageId) => _inner.jobsOfPage(pageId);

  @override
  Future<void> stopPendingJobs(PublishFailure reason) => _inner.stopPendingJobs(reason);

  @override
  Future<void> clearRetryDelays() => _inner.clearRetryDelays();

  @override
  Future<String?> uploadedPhoto({required String pageId, required String objectPath}) =>
      _inner.uploadedPhoto(pageId: pageId, objectPath: objectPath);

  @override
  Future<void> saveUploadedPhoto({required String pageId, required String objectPath, required String photoPath}) =>
      _inner.saveUploadedPhoto(pageId: pageId, objectPath: objectPath, photoPath: photoPath);

  @override
  Future<List<String>> uploadedObjects(String pageId) => _inner.uploadedObjects(pageId);

  @override
  Future<void> removeUploadedPhoto({required String pageId, required String objectPath}) =>
      _inner.removeUploadedPhoto(pageId: pageId, objectPath: objectPath);

  @override
  Future<void> forgetArrivedUploads() => _inner.forgetArrivedUploads();
}

const _transient = PublishException(PublishErrorKind.transient, 'unavailable');
const _refused = PublishException(PublishErrorKind.refused, 'permission-denied');

void main() {
  final start = DateTime.utc(2026, 10, 2, 9);
  final beforePhoto = PhotoRef('photos/visit-1/before.jpg');
  final afterPhoto = PhotoRef('photos/visit-1/after.jpg');
  final visit1 = Visit(
    id: 'visit-1',
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 2),
    createdAt: start,
    zoneRecords: [
      ZoneRecord(zoneId: 'zone-1', zoneName: '입구', beforePhoto: beforePhoto, afterPhoto: afterPhoto, note: ' 바닥 \n'),
      ZoneRecord(zoneId: 'zone-2', zoneName: '복도'),
      ZoneRecord(zoneId: 'zone-3', zoneName: '창고', note: '정리함'),
    ],
  );
  final visit2 = Visit(
    id: 'visit-2',
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 3),
    createdAt: start,
    zoneRecords: [
      ZoneRecord(zoneId: 'zone-1', zoneName: '입구', beforePhoto: PhotoRef('photos/visit-2/before.jpg')),
    ],
  );

  late Database database;
  late Repositories repositories;
  late FakePublisher publisher;
  late FakePhotoStore photoStore;
  late FakeIdentity identity;
  late FakeNetworkMonitor network;
  late _Clock clock;
  late List<_Timer> timers;
  late List<PublishQueue> queues;

  PublishQueue newQueue({PublishRepository? repository, Duration stepTimeout = PublishQueue.defaultStepTimeout}) {
    final queue = PublishQueue(
      repository: repository ?? repositories.publishing,
      clients: repositories.clients,
      visits: repositories.visits,
      companyProfile: repositories.companyProfile,
      photoStore: photoStore,
      publisher: publisher,
      identity: identity,
      networkMonitor: network,
      idGenerator: SequenceIdGenerator(),
      clock: clock,
      random: Random(7),
      startTimer: (delay, callback) {
        final timer = _Timer(delay, callback);
        timers.add(timer);
        return timer;
      },
      stepTimeout: stepTimeout,
    );
    queues.add(queue);
    return queue;
  }

  /// Lets the queue finish what it runs now.
  Future<void> settle() => pumpEventQueue(times: 200);

  /// Waits until [condition] holds, for a step that ends on a real timer, and then lets the queue finish.
  Future<void> waitUntil(Future<bool> Function() condition) async {
    for (var wait = 0; wait < 5000 && !await condition(); wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await settle();
  }

  List<_Timer> activeTimers() => timers.where((timer) => timer.isActive).toList();

  /// The stored state of [job].
  Future<PublishJob> jobOf(PublishJob job) async =>
      (await repositories.publishing.jobsOfPage(job.pageId)).singleWhere((stored) => stored.id == job.id);

  /// Whether [job] failed once, which a test waits for after a step did not answer in time.
  Future<bool> failedOnce(PublishJob job) async => (await jobOf(job)).attempts == 1;

  setUp(() async {
    database = await openMemoryDatabase();
    repositories = sqliteRepositories(database);
    await repositories.clients.save(
      Client(id: 'client-1', name: '한빛 상가', createdAt: DateTime.utc(2026, 9)),
      zones: ClientZones(
        clientId: 'client-1',
        zones: [
          Zone(id: 'zone-1', clientId: 'client-1', name: '입구', position: 0),
          Zone(id: 'zone-2', clientId: 'client-1', name: '복도', position: 1),
          Zone(id: 'zone-3', clientId: 'client-1', name: '창고', position: 2),
        ],
      ),
    );
    await repositories.visits.save(visit1);
    await repositories.visits.save(visit2);
    await repositories.companyProfile.save(CompanyProfile(name: '꼼꼬미 청소'));
    publisher = FakePublisher();
    photoStore = FakePhotoStore();
    identity = FakeIdentity(userId: 'owner-1');
    network = FakeNetworkMonitor();
    clock = _Clock(start);
    timers = [];
    queues = [];
  });

  tearDown(() async {
    for (final queue in queues) {
      await queue.dispose();
    }
    await database.close();
  });

  group('retryDelay', () {
    test('starts at five seconds, doubles with each failure, and stops growing at fifteen minutes', () {
      expect(
        [for (var failures = 1; failures <= 9; failures++) PublishQueue.retryDelay(failures)],
        [
          const Duration(seconds: 5),
          const Duration(seconds: 10),
          const Duration(seconds: 20),
          const Duration(seconds: 40),
          const Duration(seconds: 80),
          const Duration(seconds: 160),
          const Duration(seconds: 320),
          const Duration(seconds: 640),
          const Duration(minutes: 15),
        ],
      );
      expect(PublishQueue.retryDelay(1000), const Duration(minutes: 15));
    });
  });

  group('photoObjectPath', () {
    test('depends only on the page, the visit, the zone, the slot, and the name of the photo file', () {
      expect(
        photoObjectPath(
          pageId: 'page-1',
          visitId: 'visit-1',
          zoneId: 'zone-1',
          slot: PhotoSlot.after,
          photo: PhotoRef('photos/visit-1/3f9a.jpg'),
        ),
        'clientPages/page-1/visit-1/zone-1-after-3f9a.jpg',
      );
    });

    test('gives a retake of a slot, which is a new photo file, another object', () {
      String path(String file) => photoObjectPath(
        pageId: 'page-1',
        visitId: 'visit-1',
        zoneId: 'zone-1',
        slot: PhotoSlot.before,
        photo: PhotoRef('photos/visit-1/$file'),
      );

      expect(path('first.jpg'), isNot(path('second.jpg')));
      expect(path('first.jpeg'), path('first.jpg'));
      expect(path('first'), 'clientPages/page-1/visit-1/zone-1-before-first.jpg');
    });
  });

  group('isAvailable', () {
    test('says whether the publisher of the flavor has a backend', () {
      final queue = newQueue();
      expect(queue.isAvailable, isTrue);

      publisher.isAvailable = false;
      expect(queue.isAvailable, isFalse);
    });
  });

  group('hasOpenPage', () {
    test('is false before the first publish of a client, true after it, and false after a revoke', () async {
      final queue = newQueue();
      expect(await queue.hasOpenPage('client-1'), isFalse);

      await queue.publishVisit(visit1.id);
      await settle();
      expect(await queue.hasOpenPage('client-1'), isTrue);

      await queue.revokeClientPage('client-1');
      expect(await queue.hasOpenPage('client-1'), isFalse);
    });
  });

  group('publishVisit', () {
    test('writes the page, uploads the photos, and then writes the report, and the job is done', () async {
      final queue = newQueue();
      final updates = <PublishJob>[];
      queue.updates.listen(updates.add);

      final job = await queue.publishVisit('visit-1');
      await settle();

      final page = (await repositories.publishing.openPageOf('client-1'))!;
      expect(job.pageId, page.id);
      expect(job.visitId, 'visit-1');
      expect(page.createdAt, start);
      final before = 'clientPages/${page.id}/visit-1/zone-1-before-before.jpg';
      final after = 'clientPages/${page.id}/visit-1/zone-1-after-after.jpg';
      expect(publisher.calls, [
        'writePage ${page.id}',
        'uploadPhoto $before',
        'uploadPhoto $after',
        'writeReport ${page.id}/visit-1',
      ]);
      expect(
        publisher.pages[page.id],
        PublishedPage(ownerUid: 'owner-1', companyName: '꼼꼬미 청소', clientName: '한빛 상가', createdAt: start),
      );
      // The fixture holds an Exif and an IPTC segment, which the queue removes before the upload.
      expect(publisher.objects[before], withoutLocation(fixturePhotoBytes()));
      expect(photoStore.readPhotos, [beforePhoto, afterPhoto]);
      // The zone without a photo and without a note is left out, and a note is published without the space around it.
      expect(
        publisher.reports['${page.id}/visit-1'],
        PublishedReport(
          visitDate: VisitDate(2026, 10, 2),
          publishedAt: start,
          zones: [
            PublishedZone(name: '입구', note: '바닥', beforePhoto: before, afterPhoto: after),
            const PublishedZone(name: '창고', note: '정리함', beforePhoto: null, afterPhoto: null),
          ],
        ),
      );
      expect(await jobOf(job), job.succeed());
      expect(updates, [job.succeed()]);
      expect(activeTimers(), isEmpty);
    });

    test('gives the client one page of 128 random bits and publishes each visit under it', () async {
      final queue = newQueue();

      final first = await queue.publishVisit('visit-1');
      final second = await queue.publishVisit('visit-2');
      await settle();

      expect(first.pageId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second.pageId, first.pageId);
      expect(publisher.reports.keys, ['${first.pageId}/visit-1', '${first.pageId}/visit-2']);
    });

    test('publishes a company name of null when no company profile is saved', () async {
      await database.delete('company_profile');
      final queue = newQueue();

      final job = await queue.publishVisit('visit-1');
      await settle();

      expect(publisher.pages[job.pageId]?.companyName, isNull);
    });

    test('adds no second job for a visit whose job is pending, and gives that job', () async {
      publisher.gate = Completer<void>();
      final queue = newQueue();

      final first = await queue.publishVisit('visit-2');
      final second = await queue.publishVisit('visit-2');
      publisher.gate!.complete();
      await settle();

      expect(second.id, first.id);
      expect(await repositories.publishing.jobsOfPage(first.pageId), [second.succeed()]);
    });

    test('runs a job that is added while the run on its way reads the jobs for the last time', () async {
      final repository = _GatedRepository(repositories.publishing);
      final queue = newQueue(repository: repository);
      publisher.gate = Completer<void>();
      final first = await queue.publishVisit('visit-1');
      await settle();

      // The first job ends, and the run reads the jobs again to schedule its next run. The second job comes while
      // that read is on its way.
      final lastRead = repository.gate = Completer<void>();
      publisher.gate!.complete();
      await settle();
      final second = await queue.publishVisit('visit-2');
      lastRead.complete();
      await settle();

      expect((await jobOf(first)).status, PublishJobStatus.done);
      expect((await jobOf(second)).status, PublishJobStatus.done);
      expect(activeTimers(), isEmpty);
    });

    test('runs a job again when its visit is published again while the job runs', () async {
      publisher.gate = Completer<void>();
      final queue = newQueue();
      final first = await queue.publishVisit('visit-2');
      await settle();

      final changed = visit2.withRecord(visit2.zoneRecords.single.withNote('유리 닦음'));
      await repositories.visits.save(changed);
      final second = await queue.publishVisit('visit-2');
      publisher.gate!.complete();
      await settle();

      expect(second.id, first.id);
      expect(publisher.calls.where((call) => call.startsWith('writeReport')), hasLength(2));
      expect(publisher.reports['${first.pageId}/visit-2']?.zones.single.note, '유리 닦음');
      expect((await jobOf(first)).status, PublishJobStatus.done);
    });

    test('runs a job again when its visit is published again after its steps and before its result is saved', () async {
      final repository = _GatedRepository(repositories.publishing);
      final queue = newQueue(repository: repository);
      final saving = repository.saveGate = Completer<void>();
      final first = await queue.publishVisit('visit-2');
      await settle();
      expect(publisher.calls.last, 'writeReport ${first.pageId}/visit-2');

      final changed = visit2.withRecord(visit2.zoneRecords.single.withNote('유리 닦음'));
      await repositories.visits.save(changed);
      final second = await queue.publishVisit('visit-2');
      saving.complete();
      await settle();

      expect(second.id, first.id);
      expect(second.generation, first.generation + 1);
      expect(publisher.reports['${first.pageId}/visit-2']?.zones.single.note, '유리 닦음');
      expect((await jobOf(first)).status, PublishJobStatus.done);
    });

    test('throws an ArgumentError for a visit that does not exist', () async {
      await expectLater(newQueue().publishVisit('visit-9'), throwsArgumentError);
    });
  });

  group('a step that fails for a reason that a retry can fix', () {
    for (final (step, failedCalls, retriedCalls) in [
      ('writePage', 1, ['writePage', 'uploadPhoto', 'writeReport']),
      ('uploadPhoto', 2, ['writePage', 'uploadPhoto', 'writeReport']),
      ('writeReport', 3, ['writePage', 'writeReport']),
    ]) {
      test('$step: the job runs again after the delay, and the photos that reached the backend are not uploaded '
          'again', () async {
        publisher.failures[step] = [_transient];
        final queue = newQueue();
        final updates = <PublishJob>[];
        queue.updates.listen(updates.add);

        final job = await queue.publishVisit('visit-2');
        await settle();

        final retried = job.retryAt(start.add(const Duration(seconds: 5)));
        expect(await jobOf(job), retried);
        expect(publisher.calls, hasLength(failedCalls));
        expect(activeTimers().single.delay, const Duration(seconds: 5));

        publisher.calls.clear();
        clock.time = start.add(const Duration(seconds: 5));
        activeTimers().single.fire();
        await settle();

        expect(publisher.calls.map((call) => call.split(' ').first), retriedCalls);
        expect(await jobOf(job), retried.succeed());
        expect(updates, [retried, retried.succeed()]);
        expect(activeTimers(), isEmpty);
      });
    }

    test('the delay grows with each failure, and the job keeps the count of its failures', () async {
      publisher.failures['writePage'] = [_transient, _transient, _transient];
      final queue = newQueue();

      final job = await queue.publishVisit('visit-2');
      await settle();
      final delays = <Duration>[];
      for (var run = 0; run < 3; run++) {
        final timer = activeTimers().single;
        delays.add(timer.delay);
        clock.time = clock.time.add(timer.delay);
        timer.fire();
        await settle();
      }

      expect(delays, const [Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 20)]);
      expect((await jobOf(job)).status, PublishJobStatus.done);
      expect((await jobOf(job)).attempts, 3);
    });

    test('a job waits for its delay while the queue runs another job', () async {
      publisher.failures['writePage'] = [_transient];
      final queue = newQueue();
      final failed = await queue.publishVisit('visit-2');
      await settle();
      publisher.calls.clear();

      clock.time = start.add(const Duration(seconds: 2));
      final other = await queue.publishVisit('visit-1');
      await settle();

      expect(publisher.calls.where((call) => call.startsWith('writeReport')), ['writeReport ${other.pageId}/visit-1']);
      expect((await jobOf(failed)).status, PublishJobStatus.pending);
      expect(activeTimers().single.delay, const Duration(seconds: 3));
    });

    test('no signed-in user: the job runs again, and no step reaches the backend', () async {
      identity.userId = null;
      final queue = newQueue();

      final job = await queue.publishVisit('visit-2');
      await settle();

      expect(publisher.calls, isEmpty);
      expect(await jobOf(job), job.retryAt(start.add(const Duration(seconds: 5))));
    });

    test('a step that does not answer in time: the job runs again', () async {
      publisher.gate = Completer<void>();
      final queue = newQueue(stepTimeout: const Duration(milliseconds: 10));

      final job = await queue.publishVisit('visit-2');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();

      expect(publisher.calls, ['writePage ${job.pageId}']);
      expect((await jobOf(job)).status, PublishJobStatus.pending);
      expect((await jobOf(job)).attempts, 1);
      publisher.gate!.complete();
    });

    test('an upload that arrives after the queue cancelled it counts as arrived, and the job goes on', () async {
      // The wait after the cancel is long, so that the upload ends inside it on a busy machine too.
      final queue = newQueue(stepTimeout: const Duration(seconds: 1));
      publisher.cancelEndsUploads = false;
      final upload = publisher.gates['uploadPhoto'] = Completer<void>();

      final job = await queue.publishVisit('visit-2');
      final object = 'clientPages/${job.pageId}/visit-2/zone-1-before-before.jpg';
      await waitUntil(() async => publisher.calls.contains('cancelUpload $object'));
      upload.complete();
      await settle();

      expect(publisher.calls, [
        'writePage ${job.pageId}',
        'uploadPhoto $object',
        'cancelUpload $object',
        'writeReport ${job.pageId}/visit-2',
      ]);
      expect(await jobOf(job), job.succeed());
      expect(
        await repositories.publishing.uploadedPhoto(pageId: job.pageId, objectPath: object),
        'photos/visit-2/before.jpg',
      );
    });

    test('a retry does not start an upload of an object while an earlier upload of it is on its way', () async {
      final queue = newQueue(stepTimeout: const Duration(milliseconds: 10));
      publisher.cancelEndsUploads = false;
      final upload = publisher.gates['uploadPhoto'] = Completer<void>();
      final job = await queue.publishVisit('visit-2');
      await waitUntil(() => failedOnce(job));
      final object = 'clientPages/${job.pageId}/visit-2/zone-1-before-before.jpg';
      publisher.calls.clear();

      clock.time = start.add(const Duration(seconds: 5));
      activeTimers().single.fire();
      await settle();

      expect(publisher.calls, ['writePage ${job.pageId}']);
      expect((await jobOf(job)).attempts, 2);

      upload.complete();
      await settle();
      publisher.calls.clear();
      clock.time = start.add(const Duration(seconds: 15));
      activeTimers().single.fire();
      await settle();

      expect(publisher.calls, ['writePage ${job.pageId}', 'uploadPhoto $object', 'writeReport ${job.pageId}/visit-2']);
      expect((await jobOf(job)).status, PublishJobStatus.done);
    });
  });

  group('a step that fails for a reason that a retry cannot fix', () {
    for (final (step, calls) in [('writePage', 1), ('uploadPhoto', 2), ('writeReport', 3)]) {
      test('$step: the job stops and keeps the refusal as its reason', () async {
        publisher.failures[step] = [_refused];
        final queue = newQueue();
        final updates = <PublishJob>[];
        queue.updates.listen(updates.add);

        final job = await queue.publishVisit('visit-2');
        await settle();

        expect(publisher.calls, hasLength(calls));
        expect(await jobOf(job), job.fail(PublishFailure.refused));
        expect(updates, [job.fail(PublishFailure.refused)]);
        expect(activeTimers(), isEmpty);
      });
    }

    for (final (name, PublishFailure reason, void Function() setUpFailure) in [
      (
        'a photo file that does not read',
        PublishFailure.photoMissing,
        () => photoStore.readFailure = Exception('gone'),
      ),
      (
        'a photo file that is no JPEG',
        PublishFailure.photoNotJpeg,
        () => photoStore.contents[PhotoRef('photos/visit-2/before.jpg')] = Uint8List.fromList([0x89, 0x50, 0x4e]),
      ),
      (
        'a photo file that is a truncated JPEG',
        PublishFailure.photoNotJpeg,
        () => photoStore.contents[PhotoRef('photos/visit-2/before.jpg')] = File(
          'test/fixtures/photo_truncated.jpg',
        ).readAsBytesSync(),
      ),
      (
        'a photo file that is too large',
        PublishFailure.photoTooLarge,
        () =>
            photoStore.contents[PhotoRef('photos/visit-2/before.jpg')] = Uint8List(maxPhotoBytes + 1)
              ..setAll(0, [0xff, 0xd8, 0xff]),
      ),
    ]) {
      test('$name: the job stops before the upload and keeps the reason', () async {
        setUpFailure();
        final queue = newQueue();

        final job = await queue.publishVisit('visit-2');
        await settle();

        expect(publisher.calls, ['writePage ${job.pageId}']);
        expect(await jobOf(job), job.fail(reason));
      });
    }

    test(
      'a retake publishes the new photo to its own object, and an upload of the old photo cannot replace it',
      () async {
        final queue = newQueue();
        final first = await queue.publishVisit('visit-2');
        await settle();
        final oldObject = 'clientPages/${first.pageId}/visit-2/zone-1-before-before.jpg';
        expect(publisher.objects.keys, [oldObject]);

        final retaken = PhotoRef('photos/visit-2/retaken.jpg');
        // A JPEG without metadata, which the queue uploads as it is.
        final retakenBytes = File('test/fixtures/photo_no_exif.jpg').readAsBytesSync();
        photoStore.contents[retaken] = retakenBytes;
        await repositories.visits.save(
          visit2.withRecord(visit2.zoneRecords.single.withPhoto(PhotoSlot.before, retaken)),
        );
        publisher.calls.clear();
        await queue.publishVisit('visit-2');
        await settle();

        final newObject = 'clientPages/${first.pageId}/visit-2/zone-1-before-retaken.jpg';
        expect(publisher.calls, [
          'writePage ${first.pageId}',
          'uploadPhoto $newObject',
          'writeReport ${first.pageId}/visit-2',
          // The report no longer names the old object, so it is deleted after the report.
          'deletePhoto $oldObject',
        ]);
        expect(publisher.reports['${first.pageId}/visit-2']?.zones.single.beforePhoto, newObject);
        expect(publisher.objects, {newObject: retakenBytes});
        expect(await repositories.publishing.uploadedObjects(first.pageId), [newObject]);
      },
    );

    test('an old object whose upload is still on its way is deleted after that upload ends', () async {
      final queue = newQueue(stepTimeout: const Duration(milliseconds: 10));
      publisher.cancelEndsUploads = false;
      final oldUpload = publisher.gates['uploadPhoto'] = Completer<void>();
      final job = await queue.publishVisit('visit-2');
      await waitUntil(() => failedOnce(job));
      final oldObject = 'clientPages/${job.pageId}/visit-2/zone-1-before-before.jpg';
      expect(publisher.calls.last, 'cancelUpload $oldObject');

      // Only the upload of the old photo waits.
      publisher.gates.remove('uploadPhoto');
      final retaken = PhotoRef('photos/visit-2/retaken.jpg');
      await repositories.visits.save(
        visit2.withRecord(visit2.zoneRecords.single.withPhoto(PhotoSlot.before, retaken)),
      );
      publisher.calls.clear();
      await queue.publishVisit('visit-2');
      await settle();

      final newObject = 'clientPages/${job.pageId}/visit-2/zone-1-before-retaken.jpg';
      expect(publisher.calls, [
        'writePage ${job.pageId}',
        'uploadPhoto $newObject',
        'writeReport ${job.pageId}/visit-2',
      ]);
      expect(await repositories.publishing.uploadedObjects(job.pageId), containsAll([oldObject, newObject]));
      expect((await jobOf(job)).status, PublishJobStatus.pending);

      oldUpload.complete();
      await settle();
      publisher.calls.clear();
      clock.time = start.add(const Duration(minutes: 1));
      activeTimers().single.fire();
      await settle();

      expect(publisher.calls, [
        'writePage ${job.pageId}',
        'writeReport ${job.pageId}/visit-2',
        'deletePhoto $oldObject',
      ]);
      expect(publisher.objects.keys, [newObject]);
      expect(await repositories.publishing.uploadedObjects(job.pageId), [newObject]);
      expect((await jobOf(job)).status, PublishJobStatus.done);
    });

    test('an old object that a delete did not remove is deleted at the next run, after the report', () async {
      final queue = newQueue();
      final first = await queue.publishVisit('visit-2');
      await settle();
      final retaken = PhotoRef('photos/visit-2/retaken.jpg');
      await repositories.visits.save(
        visit2.withRecord(visit2.zoneRecords.single.withPhoto(PhotoSlot.before, retaken)),
      );
      publisher.failures['deletePhoto'] = [_transient];
      final requested = start.add(const Duration(minutes: 1));
      clock.time = requested;

      final second = await queue.publishVisit('visit-2');
      await settle();
      expect((await jobOf(second)).status, PublishJobStatus.pending);
      publisher.calls.clear();
      clock.time = requested.add(const Duration(seconds: 5));
      activeTimers().single.fire();
      await settle();

      // The report written again by the retry keeps the time of the publish request, not the time of the retry.
      expect(publisher.reports['${first.pageId}/visit-2']?.publishedAt, requested);

      expect(publisher.calls, [
        'writePage ${first.pageId}',
        'writeReport ${first.pageId}/visit-2',
        'deletePhoto clientPages/${first.pageId}/visit-2/zone-1-before-before.jpg',
      ]);
      expect((await jobOf(second)).status, PublishJobStatus.done);
    });

    test('a photo file that a retake deleted while the job ran: the job runs again with the new photo', () async {
      publisher.gate = Completer<void>();
      final queue = newQueue();
      final job = await queue.publishVisit('visit-2');
      await settle();

      // The run read the visit before the retake, which deletes the file of the photo that it replaces.
      final retaken = PhotoRef('photos/visit-2/retaken.jpg');
      await repositories.visits.save(
        visit2.withRecord(visit2.zoneRecords.single.withPhoto(PhotoSlot.before, retaken)),
      );
      photoStore.readFailure = Exception('gone');
      publisher.gate!.complete();
      await settle();
      expect((await jobOf(job)).status, PublishJobStatus.pending);

      photoStore.readFailure = null;
      clock.time = start.add(const Duration(seconds: 5));
      activeTimers().single.fire();
      await settle();

      expect(photoStore.readPhotos.last, retaken);
      expect((await jobOf(job)).status, PublishJobStatus.done);
    });

    test('a photo that holds a location: the upload holds the photo without it', () async {
      final withGps = gpsPhotoBytes();
      expect(holdsMetadataText(withGps), isTrue);
      photoStore.contents[PhotoRef('photos/visit-2/before.jpg')] = withGps;
      final queue = newQueue();

      final job = await queue.publishVisit('visit-2');
      await settle();

      expect((await jobOf(job)).status, PublishJobStatus.done);
      final uploaded = publisher.objects.values.single;
      expect(holdsMetadataText(uploaded), isFalse);
      expect(uploaded, withoutLocation(withGps));
    });

    test('a photo of exactly the size limit is uploaded', () async {
      final photo = jpegOfLength(maxPhotoBytes);
      expect(photo.length, maxPhotoBytes);
      photoStore.contents[PhotoRef('photos/visit-2/before.jpg')] = photo;
      final queue = newQueue();

      final job = await queue.publishVisit('visit-2');
      await settle();

      expect((await jobOf(job)).status, PublishJobStatus.done);
    });

    test('a flavor without a backend: the job stops as unavailable, and nothing reaches a backend', () async {
      publisher.isAvailable = false;
      final queue = newQueue();

      final job = await queue.publishVisit('visit-2');
      await settle();

      expect(publisher.calls, isEmpty);
      expect(identity.calls, 0);
      expect(await jobOf(job), job.fail(PublishFailure.unavailable));
    });
  });

  group('start', () {
    test('runs at once the jobs that an earlier queue left, also a job inside its delay', () async {
      publisher.failures['writePage'] = [_transient];
      final first = newQueue();
      final waiting = await first.publishVisit('visit-2');
      await settle();
      await first.dispose();
      expect((await jobOf(waiting)).nextAttemptAt, isNotNull);

      final second = newQueue();
      await second.start();
      await settle();

      expect((await jobOf(waiting)).status, PublishJobStatus.done);
    });

    test('runs again from its first step a job that stopped in the middle, without the photos that arrived', () async {
      final first = newQueue();
      publisher.gate = Completer<void>();
      final stopped = await first.publishVisit('visit-1');
      // The page and the two photos reach the backend, and the process ends while the report is on its way.
      for (var call = 0; call < 3; call++) {
        await settle();
        final gate = publisher.gate!;
        publisher.gate = Completer<void>();
        gate.complete();
      }
      await settle();
      expect(publisher.calls.last, 'writeReport ${stopped.pageId}/visit-1');
      await first.dispose();
      expect((await jobOf(stopped)).status, PublishJobStatus.pending);

      publisher = FakePublisher();
      final second = newQueue();
      await second.start();
      await settle();

      expect(publisher.calls, ['writePage ${stopped.pageId}', 'writeReport ${stopped.pageId}/visit-1']);
      expect((await jobOf(stopped)).status, PublishJobStatus.done);
    });

    test('runs the pending jobs at once when the network returns', () async {
      publisher.failures['writePage'] = [_transient];
      final queue = newQueue();
      await queue.start();
      final job = await queue.publishVisit('visit-2');
      await settle();
      expect((await jobOf(job)).status, PublishJobStatus.pending);

      network.restore();
      await settle();

      expect((await jobOf(job)).status, PublishJobStatus.done);
      expect(activeTimers(), isEmpty);
    });

    test('listens to the network once, also when it is called twice', () async {
      final queue = newQueue();

      await queue.start();
      await queue.start();
      await queue.dispose();

      expect(network.hasListener, isFalse);
    });

    test('keeps the queue running when local storage fails', () async {
      final repository = MockPublishRepository();
      when(repository.clearRetryDelays).thenThrow(Exception('disk full'));
      when(repository.pendingJobs).thenThrow(Exception('disk full'));
      final queue = newQueue(repository: repository);

      await expectLater(queue.start(), completes);
      when(repository.pendingJobs).thenAnswer((_) async => []);
      network.restore();
      await settle();

      // The first read failed, and the network event made a new run read the jobs again.
      verify(repository.pendingJobs).called(3);
    });

    test('keeps listening when the network state fails', () async {
      publisher.failures['writePage'] = [_transient];
      final queue = newQueue();
      await queue.start();
      final job = await queue.publishVisit('visit-2');
      await settle();

      network.fail(Exception('no plugin'));
      network.restore();
      await settle();

      expect((await jobOf(job)).status, PublishJobStatus.done);
    });
  });

  group('dispose', () {
    test('runs no job after it, also a job that the run on its way had read', () async {
      final queue = newQueue();
      publisher.gate = Completer<void>();
      final first = await queue.publishVisit('visit-1');
      final second = await queue.publishVisit('visit-2');
      await settle();

      await queue.dispose();
      publisher.gate!.complete();
      await settle();

      expect(publisher.calls.where((call) => call.startsWith('writeReport')), ['writeReport ${first.pageId}/visit-1']);
      expect((await jobOf(second)).status, PublishJobStatus.pending);
      expect(activeTimers(), isEmpty);
    });
  });

  group('revokeClientPage', () {
    test('marks the page as revoked on the backend and deletes the photos that the app uploaded', () async {
      final queue = newQueue();
      final published = await queue.publishVisit('visit-1');
      await settle();
      publisher.calls.clear();
      clock.time = start.add(const Duration(hours: 1));

      final revoked = await queue.revokeClientPage('client-1');
      await settle();

      final pageId = published.pageId;
      expect(revoked?.id, pageId);
      expect(revoked?.revokedAt, clock.time);
      expect(await repositories.publishing.pageById(pageId), revoked);
      expect(await repositories.publishing.openPageOf('client-1'), isNull);
      expect(publisher.calls, [
        'revokePage $pageId',
        'deletePhoto clientPages/$pageId/visit-1/zone-1-after-after.jpg',
        'deletePhoto clientPages/$pageId/visit-1/zone-1-before-before.jpg',
      ]);
      expect(
        publisher.revokedPages[pageId],
        PublishedPage(ownerUid: 'owner-1', companyName: '꼼꼬미 청소', clientName: '한빛 상가', createdAt: start),
      );
      expect(publisher.objects, isEmpty);
      expect(await repositories.publishing.uploadedObjects(pageId), isEmpty);
      final jobs = await repositories.publishing.jobsOfPage(pageId);
      expect(jobs.last.kind, PublishJobKind.revoke);
      expect(jobs.last.status, PublishJobStatus.done);
    });

    test('a delete that fails runs again and deletes only the photos that are left', () async {
      final queue = newQueue();
      final published = await queue.publishVisit('visit-1');
      await settle();
      publisher
        ..calls.clear()
        ..failures['deletePhoto'] = [null, Exception('offline')];

      final revokedAt = start.add(const Duration(minutes: 1));
      clock.time = revokedAt;
      await queue.revokeClientPage('client-1');
      await settle();
      publisher.calls.clear();
      clock.time = revokedAt.add(const Duration(seconds: 5));
      activeTimers().single.fire();
      await settle();

      final pageId = published.pageId;
      expect(publisher.calls, [
        'revokePage $pageId',
        'deletePhoto clientPages/$pageId/visit-1/zone-1-before-before.jpg',
      ]);
      // The revoke written again by the retry keeps the time of the revoke, not the time of the retry.
      expect(publisher.revokedAt[pageId], revokedAt);
      expect(await repositories.publishing.uploadedObjects(pageId), isEmpty);
    });

    test(
      'fails a step only after its cancelled upload ended, so a revoke after it finds no upload on its way',
      () async {
        final queue = newQueue(stepTimeout: const Duration(milliseconds: 10));
        final upload = publisher.gates['uploadPhoto'] = Completer<void>();
        final job = await queue.publishVisit('visit-2');
        await waitUntil(() => failedOnce(job));
        expect((await jobOf(job)).attempts, 1);
        final lateObject = 'clientPages/${job.pageId}/visit-2/zone-1-before-before.jpg';
        // The step counts as failed only after the cancelled upload ended.
        expect(publisher.calls, ['writePage ${job.pageId}', 'uploadPhoto $lateObject', 'cancelUpload $lateObject']);
        expect(await repositories.publishing.uploadedObjects(job.pageId), [lateObject]);
        expect(await repositories.publishing.uploadedPhoto(pageId: job.pageId, objectPath: lateObject), isNull);

        await queue.revokeClientPage('client-1');
        await settle();
        expect(publisher.calls, contains('deletePhoto $lateObject'));
        expect(await repositories.publishing.uploadedObjects(job.pageId), isEmpty);

        // Without the cancel, the upload would finish now, after the revoke deleted its path (issue 13).
        upload.complete();
        await settle();

        expect(publisher.objects, isEmpty);
      },
    );

    test('keeps the record of an upload that a cancel did not end, and deletes its object after it ends', () async {
      final queue = newQueue(stepTimeout: const Duration(milliseconds: 10));
      publisher.cancelEndsUploads = false;
      final upload = publisher.gates['uploadPhoto'] = Completer<void>();
      final job = await queue.publishVisit('visit-2');
      await waitUntil(() => failedOnce(job));
      final lateObject = 'clientPages/${job.pageId}/visit-2/zone-1-before-before.jpg';
      expect(publisher.calls.last, 'cancelUpload $lateObject');
      expect((await jobOf(job)).attempts, 1);

      final revokedAt = clock.time;
      await queue.revokeClientPage('client-1');
      await settle();

      // The upload is still on its way, so the revoke deletes nothing yet and runs again.
      expect(publisher.calls.where((call) => call.startsWith('deletePhoto')), isEmpty);
      expect(await repositories.publishing.uploadedObjects(job.pageId), [lateObject]);
      final revoke = (await repositories.publishing.jobsOfPage(job.pageId)).last;
      expect(revoke.kind, PublishJobKind.revoke);
      expect(revoke.status, PublishJobStatus.pending);

      upload.complete();
      await settle();
      expect(publisher.objects.keys, [lateObject]);
      clock.time = revokedAt.add(const Duration(seconds: 5));
      activeTimers().single.fire();
      await settle();

      expect(publisher.calls.last, 'deletePhoto $lateObject');
      expect(publisher.objects, isEmpty);
      expect(await repositories.publishing.uploadedObjects(job.pageId), isEmpty);
      expect((await repositories.publishing.jobsOfPage(job.pageId)).last.status, PublishJobStatus.done);
    });

    test('stops the pending publish jobs of the page', () async {
      identity.userId = null;
      final queue = newQueue();
      final waiting = await queue.publishVisit('visit-2');
      await settle();

      await queue.revokeClientPage('client-1');

      expect((await jobOf(waiting)).failure, PublishFailure.revoked);
    });

    test('stops a publish job that a run had read before the page was revoked', () async {
      final queue = newQueue();
      publisher.gate = Completer<void>();
      await queue.publishVisit('visit-1');
      final second = await queue.publishVisit('visit-2');
      await settle();

      await queue.revokeClientPage('client-1');
      publisher.gate!.complete();
      await settle();

      expect(publisher.reports.keys.where((key) => key.endsWith('visit-2')), isEmpty);
      expect((await jobOf(second)).failure, PublishFailure.revoked);
    });

    for (final (outcome, Object? failure) in [
      ('ends', null),
      ('fails for a reason that a retry can fix', _transient),
    ]) {
      test('keeps a job revoked that the page revoke stopped while a step of it ran and then $outcome', () async {
        final queue = newQueue();
        final updates = <PublishJob>[];
        queue.updates.listen(updates.add);
        publisher
          ..gate = Completer<void>()
          ..failures['writePage'] = [failure];
        final running = await queue.publishVisit('visit-2');
        await settle();
        expect(publisher.calls, ['writePage ${running.pageId}']);

        await queue.revokeClientPage('client-1');
        publisher.gate!.complete();
        await settle();

        expect(await jobOf(running), running.fail(PublishFailure.revoked));
        expect(updates.where((update) => update.id == running.id), isEmpty);
        // The revoke job runs after the stopped run, so the page is revoked on the backend after the run's last write.
        expect(
          publisher.calls.indexOf('revokePage ${running.pageId}'),
          greaterThan(publisher.calls.lastIndexOf('writePage ${running.pageId}')),
        );
        expect(publisher.revokedPages.keys, [running.pageId]);
      });
    }

    test('revokes a page once when two revokes come at one time', () async {
      final queue = newQueue();
      await queue.publishVisit('visit-1');
      await settle();

      final results = await Future.wait([queue.revokeClientPage('client-1'), queue.revokeClientPage('client-1')]);

      expect(results.whereType<ClientPage>(), hasLength(1));
      final jobs = await repositories.publishing.jobsOfPage(results.whereType<ClientPage>().single.id);
      expect(jobs.where((job) => job.kind == PublishJobKind.revoke), hasLength(1));
    });

    test('gives null and adds no job for a client without an open page', () async {
      final queue = newQueue();

      expect(await queue.revokeClientPage('client-1'), isNull);
      expect(await repositories.publishing.pendingJobs(), isEmpty);
    });
  });

  group('reissueClientPage', () {
    test('revokes the old page and publishes again under a new page each visit that was published', () async {
      final queue = newQueue();
      final published = await queue.publishVisit('visit-1');
      await settle();
      publisher.failures['writePage'] = [_refused];
      final refused = await queue.publishVisit('visit-2');
      await settle();
      expect((await jobOf(refused)).failure, PublishFailure.refused);

      final replacement = await queue.reissueClientPage('client-1');
      await settle();

      expect(replacement.id, isNot(published.pageId));
      expect(replacement.id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(await repositories.publishing.openPageOf('client-1'), replacement);
      expect((await repositories.publishing.pageById(published.pageId))?.isRevoked, isTrue);
      expect(publisher.revokedPages.keys, [published.pageId]);
      expect(publisher.reports.keys, ['${published.pageId}/visit-1', '${replacement.id}/visit-1']);
      final jobs = await repositories.publishing.jobsOfPage(replacement.id);
      expect(jobs.map((job) => (job.visitId, job.status)), [('visit-1', PublishJobStatus.done)]);
    });

    test('gives the client one new page when two reissues come at one time', () async {
      final queue = newQueue();
      final published = await queue.publishVisit('visit-1');
      await settle();

      final pages = await Future.wait([queue.reissueClientPage('client-1'), queue.reissueClientPage('client-1')]);
      await settle();

      expect(pages.first, pages.last);
      expect(await repositories.publishing.openPageOf('client-1'), pages.first);
      expect(await repositories.publishing.jobsOfPage(pages.first.id), hasLength(1));
      final revokes = (await repositories.publishing.jobsOfPage(published.pageId)).where(
        (job) => job.kind == PublishJobKind.revoke,
      );
      expect(revokes, hasLength(1));
    });

    test('gives a client without an open page a new page and adds no job', () async {
      final queue = newQueue();

      final page = await queue.reissueClientPage('client-1');

      expect(await repositories.publishing.openPageOf('client-1'), page);
      expect(await repositories.publishing.pendingJobs(), isEmpty);
    });
  });

  group('hold', () {
    test('starts no job at a request or when the network returns, and release runs the jobs', () async {
      final queue = newQueue();
      await queue.start();

      await queue.hold();
      final job = await queue.publishVisit('visit-2');
      network.restore();
      await settle();

      expect(queue.isHeld, isTrue);
      expect(publisher.calls, isEmpty);
      expect((await jobOf(job)).status, PublishJobStatus.pending);

      queue.release();
      await settle();

      expect(queue.isHeld, isFalse);
      expect((await jobOf(job)).status, PublishJobStatus.done);
    });

    test('waits for the job that runs now, and no other job of the same run starts after it', () async {
      // Two jobs that an earlier queue left, so that the first run reads both before the hold.
      publisher.failures['writePage'] = [_transient, _transient];
      final earlier = newQueue();
      final first = await earlier.publishVisit('visit-1');
      final second = await earlier.publishVisit('visit-2');
      await settle();
      await earlier.dispose();
      expect((await repositories.publishing.pendingJobs()).map((job) => job.id), [first.id, second.id]);
      publisher.calls.clear();
      final queue = newQueue();
      publisher.gate = Completer<void>();
      unawaited(queue.start());
      await settle();
      expect(publisher.calls, ['writePage ${first.pageId}']);

      var held = false;
      unawaited(queue.hold().then((_) => held = true));
      await settle();
      expect(held, isFalse);

      publisher.gate!.complete();
      await settle();

      expect(held, isTrue);
      expect((await jobOf(first)).status, PublishJobStatus.done);
      expect((await jobOf(second)).status, PublishJobStatus.pending);
      expect(publisher.calls.where((call) => call.startsWith('writeReport')), ['writeReport ${first.pageId}/visit-1']);
    });

    test('stops the retry timer, and a job inside its delay waits for the release', () async {
      publisher.failures['writePage'] = [_transient];
      final queue = newQueue();
      final job = await queue.publishVisit('visit-2');
      await settle();
      expect(activeTimers(), hasLength(1));

      await queue.hold();

      expect(activeTimers(), isEmpty);
      queue.release();
      await settle();
      expect((await jobOf(job)).status, PublishJobStatus.pending);
      expect(activeTimers(), hasLength(1));
    });

    test('a release of a queue that is not held runs nothing', () async {
      final queue = newQueue();

      queue.release();
      await settle();

      expect(queue.isHeld, isFalse);
      expect(publisher.calls, isEmpty);
    });
  });

  group('deletePublished', () {
    test('throws a StateError while the queue is not held', () async {
      final queue = newQueue();

      await expectLater(queue.deletePublished(), throwsStateError);
      expect(publisher.calls, isEmpty);
    });

    test(
      'deletes the objects of every page, then the reports of every visit that a job published, then the pages',
      () async {
        final queue = newQueue();
        final revoked = await queue.publishVisit('visit-1');
        await settle();
        await queue.revokeClientPage('client-1');
        await settle();
        final open = await queue.publishVisit('visit-1');
        await settle();
        // A job that stopped is still a job of the page, and a report that it wrote before it stopped stays.
        publisher.failures['writeReport'] = [_refused];
        final stopped = await queue.publishVisit('visit-2');
        await settle();
        expect((await jobOf(stopped)).status, PublishJobStatus.failed);
        final objects = await repositories.publishing.uploadedObjects(open.pageId);
        expect(objects, hasLength(3));
        publisher.calls.clear();

        await queue.hold();
        await queue.deletePublished();

        expect(publisher.calls, [
          for (final object in objects) 'deletePhoto $object',
          'deleteReport ${revoked.pageId}/visit-1',
          'deleteReport ${open.pageId}/visit-1',
          'deleteReport ${open.pageId}/visit-2',
          'deletePage ${revoked.pageId}',
          'deletePage ${open.pageId}',
        ]);
        expect(publisher.objects, isEmpty);
        expect(publisher.reports, isEmpty);
        expect(publisher.pages, isEmpty);
        expect(publisher.revokedPages, isEmpty);
        expect(await repositories.publishing.uploadedObjects(open.pageId), isEmpty);
        // The local pages and jobs stay until the caller erases the local data.
        expect(await repositories.publishing.pages(), hasLength(2));
        expect(await repositories.publishing.jobsOfPage(open.pageId), hasLength(2));
      },
    );

    test('does nothing, and asks for no user, when the app made no page', () async {
      final queue = newQueue();
      await queue.hold();

      await queue.deletePublished();

      expect(publisher.calls, isEmpty);
      expect(identity.calls, 0);
    });

    test('fails before any delete when no user is signed in', () async {
      final queue = newQueue();
      await queue.publishVisit('visit-2');
      await settle();
      publisher.calls.clear();
      identity.userId = null;
      await queue.hold();

      await expectLater(
        queue.deletePublished(),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.transient)),
      );
      expect(publisher.calls, isEmpty);
    });

    test('stops at a failed delete, and a second call deletes what is left', () async {
      final queue = newQueue();
      final job = await queue.publishVisit('visit-2');
      await settle();
      final object = (await repositories.publishing.uploadedObjects(job.pageId)).single;
      publisher.calls.clear();
      publisher.failures['deleteReport'] = [_transient];
      await queue.hold();

      await expectLater(queue.deletePublished(), throwsA(_transient));
      expect(publisher.calls, ['deletePhoto $object', 'deleteReport ${job.pageId}/visit-2']);
      expect(publisher.pages.keys, [job.pageId]);

      publisher.calls.clear();
      await queue.deletePublished();

      expect(publisher.calls, ['deleteReport ${job.pageId}/visit-2', 'deletePage ${job.pageId}']);
      expect(publisher.pages, isEmpty);
    });

    test('stops every waiting job before its first delete, and a new queue on the store runs none of them', () async {
      // A revoke of the first page and a publish under the new page, both waiting, as a deletion can find them.
      final queue = newQueue();
      await queue.publishVisit('visit-1');
      await settle();
      await queue.hold();
      final revoked = (await queue.revokeClientPage('client-1'))!;
      final revoke = (await repositories.publishing.jobsOfPage(revoked.id)).last;
      final waiting = await queue.publishVisit('visit-2');
      expect(waiting.pageId, isNot(revoked.id));
      expect(await repositories.publishing.pendingJobs(), [revoke, waiting]);
      publisher.calls.clear();
      publisher.failures['deletePage'] = [_transient];

      await expectLater(queue.deletePublished(), throwsA(_transient));

      for (final job in [revoke, waiting]) {
        expect((await jobOf(job)).status, PublishJobStatus.failed);
        expect((await jobOf(job)).failure, PublishFailure.deletion);
      }
      publisher.calls.clear();
      final restarted = newQueue();
      await restarted.start();
      await settle();
      expect(publisher.calls, isEmpty);
    });

    test('fails before any delete while an upload that a cancel did not end is on its way', () async {
      final queue = newQueue(stepTimeout: const Duration(milliseconds: 10));
      publisher.cancelEndsUploads = false;
      final upload = publisher.gates['uploadPhoto'] = Completer<void>();
      final job = await queue.publishVisit('visit-2');
      await waitUntil(() => failedOnce(job));
      final lateObject = 'clientPages/${job.pageId}/visit-2/zone-1-before-before.jpg';
      publisher.calls.clear();
      await queue.hold();

      await expectLater(
        queue.deletePublished(),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.transient)),
      );
      expect(publisher.calls, isEmpty);

      upload.complete();
      await settle();
      expect(publisher.objects.keys, [lateObject]);
      await queue.deletePublished();

      expect(publisher.calls.first, 'deletePhoto $lateObject');
      expect(publisher.objects, isEmpty);
      expect(publisher.pages, isEmpty);
    });
  });
}

/// A well-formed JPEG of [length] bytes: the fixture without metadata, filled up with comments.
Uint8List jpegOfLength(int length) {
  final clean = File('test/fixtures/photo_no_exif.jpg').readAsBytesSync();
  final filler = <int>[];
  var missing = length - clean.length;
  while (missing > 0) {
    // A segment is at least 4 and at most 65537 bytes long, so no rest below 4 bytes may stay.
    var size = min(missing, 0xffff + 2);
    if (missing - size case final rest when rest > 0 && rest < 4) size -= 4;
    filler.addAll([0xff, 0xfe, (size - 2) >> 8, (size - 2) & 0xff, ...List.filled(size - 4, 0x20)]);
    missing -= size;
  }
  return Uint8List.fromList([...clean.sublist(0, 2), ...filler, ...clean.sublist(2)]);
}
