import 'dart:async';
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
  Future<PublishJob> enqueue(PublishJob job) => _inner.enqueue(job);

  @override
  Future<bool> revoke(
    ClientPage page, {
    required DateTime at,
    required PublishJob revokeJob,
    ClientPage? replacement,
    PublishJob Function(String visitId)? republish,
  }) => _inner.revoke(page, at: at, revokeJob: revokeJob, replacement: replacement, republish: republish);

  @override
  Future<void> saveJob(PublishJob job) => _inner.saveJob(job);

  @override
  Future<List<PublishJob>> jobsOfPage(String pageId) => _inner.jobsOfPage(pageId);

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

  List<_Timer> activeTimers() => timers.where((timer) => timer.isActive).toList();

  /// The stored state of [job].
  Future<PublishJob> jobOf(PublishJob job) async =>
      (await repositories.publishing.jobsOfPage(job.pageId)).singleWhere((stored) => stored.id == job.id);

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

  test('photoObjectPath depends only on the page, the visit, the zone, and the slot', () {
    expect(
      photoObjectPath(pageId: 'page-1', visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.after),
      'clientPages/page-1/visit-1/zone-1-after.jpg',
    );
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
      final before = 'clientPages/${page.id}/visit-1/zone-1-before.jpg';
      final after = 'clientPages/${page.id}/visit-1/zone-1-after.jpg';
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
      expect(publisher.objects[before], fixturePhotoBytes());
      expect(photoStore.readPhotos, [beforePhoto, afterPhoto]);
      // The zone without a photo and without a note is left out, and a note is published without the space around it.
      expect(
        publisher.reports['${page.id}/visit-1'],
        PublishedReport(
          visitDate: VisitDate(2026, 10, 2),
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
      expect(await repositories.publishing.jobsOfPage(first.pageId), [first.succeed()]);
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

    test('a photo of exactly the size limit is uploaded', () async {
      final photo = Uint8List(maxPhotoBytes)..setAll(0, [0xff, 0xd8, 0xff]);
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
        'deletePhoto clientPages/$pageId/visit-1/zone-1-after.jpg',
        'deletePhoto clientPages/$pageId/visit-1/zone-1-before.jpg',
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

      await queue.revokeClientPage('client-1');
      await settle();
      publisher.calls.clear();
      clock.time = start.add(const Duration(seconds: 5));
      activeTimers().single.fire();
      await settle();

      final pageId = published.pageId;
      expect(publisher.calls, [
        'revokePage $pageId',
        'deletePhoto clientPages/$pageId/visit-1/zone-1-before.jpg',
      ]);
      expect(await repositories.publishing.uploadedObjects(pageId), isEmpty);
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
}
