import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

import '../helpers/helpers.dart';

void main() {
  const object = 'clientPages/page-1/visit-1/zone-1-before-photo-1.jpg';
  const transient = PublishException(PublishErrorKind.transient, 'unavailable');

  late FakePublishRepository publishing;
  late FakeLocalDataRepository localData;
  late FakePublisher publisher;
  late FakeIdentity identity;
  late FakePhotoStore photoStore;
  late PublishQueue queue;

  /// Each step in the order in which it ran.
  late List<String> steps;

  DeleteAllData deleteAllData({Duration stepTimeout = PublishQueue.defaultStepTimeout}) => DeleteAllData(
    publishQueue: queue,
    identity: identity,
    localData: localData,
    photoStore: photoStore,
    stepTimeout: stepTimeout,
  );

  Matcher failsAt(DeletionStep step) => throwsA(isA<DeletionFailure>().having((failure) => failure.step, 'step', step));

  setUp(() async {
    publishing = FakePublishRepository();
    localData = FakeLocalDataRepository();
    publisher = FakePublisher();
    identity = FakeIdentity(userId: 'owner-1');
    photoStore = FakePhotoStore();
    steps = [];
    final repositories = Repositories(
      clients: FakeClientRepository(
        clients: [Client(id: 'client-1', name: '한빛 상가', createdAt: DateTime.utc(2026, 9))],
      ),
      visits: FakeVisitRepository(
        visits: [
          // The photo of the uploaded object below, so that a share of the visit again names that object.
          Visit(
            id: 'visit-1',
            clientId: 'client-1',
            visitDate: VisitDate(2026, 10, 1),
            createdAt: DateTime.utc(2026, 10),
            zoneRecords: [
              ZoneRecord(zoneId: 'zone-1', zoneName: '입구', beforePhoto: PhotoRef('photos/visit-1/photo-1.jpg')),
            ],
          ),
        ],
      ),
      companyProfile: FakeCompanyProfileRepository(),
      publishing: publishing,
      openCaptures: FakeOpenCaptureRepository(),
      localData: localData,
    );
    queue = publishQueueOf(repositories, publisher: publisher, identity: identity, photoStore: photoStore);
    // One page with one published visit and one uploaded photo, as a publish leaves them.
    publishing.pagesById['page-1'] = ClientPage(id: 'page-1', clientId: 'client-1', createdAt: DateTime.utc(2026, 10));
    await publishing.enqueue(
      PublishJob(
        id: 'job-1',
        kind: PublishJobKind.publish,
        pageId: 'page-1',
        visitId: 'visit-1',
        createdAt: DateTime.utc(2026, 10),
        status: PublishJobStatus.done,
      ),
    );
    await publishing.saveUploadedPhoto(pageId: 'page-1', objectPath: object, photoPath: 'photos/visit-1/photo-1.jpg');
    publisher.objects[object] = fixturePhotoBytes();
    localData.onErase = () {
      steps
        ..addAll(publisher.calls)
        ..add('deleteAccount x${identity.deletions}')
        ..add('eraseAll')
        ..add('deleteAll x${photoStore.deletionsOfAll}');
      if (localData.failure == null) {
        publishing.pagesById.clear();
        publishing.jobs.clear();
      }
    };
  });

  tearDown(() => queue.dispose());

  group('durable page deletion', () {
    test('intent exists before deletePage and confirmation follows acknowledgement', () async {
      await queue.hold();
      final gate = publisher.gates['deletePage'] = Completer<void>();
      final running = queue.deletePublished();
      await pumpEventQueue();
      try {
        expect(publishing.pagesById['page-1']!.serverDeleteRequestedAt, isNotNull);
        expect(publishing.pagesById['page-1']!.serverDeletedAt, isNull);
      } finally {
        gate.complete();
        await running;
      }
      expect(publishing.pagesById['page-1']!.serverDeletedAt, isNotNull);
    });

    for (final device in [false, true]) {
      test('confirmation remains when ${device ? 'database transaction' : 'account'} deletion fails', () async {
        if (device) {
          localData.failure = Exception('disk');
        } else {
          identity.deleteFailures.add(Exception('account'));
        }
        await expectLater(deleteAllData()(), failsAt(device ? DeletionStep.deviceData : DeletionStep.account));
        final stored = publishing.pagesById['page-1']!;
        expect(stored.serverDeleteRequestedAt, isNotNull);
        expect(stored.serverDeletedAt, isNotNull);
        expect(stored.isOpen, isFalse);
      });
    }

    test('intent failure sends no page delete and stops later stages', () async {
      publishing.beginDeletionFailure = Exception('intent transaction');
      await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));
      expect(publisher.calls, isNot(contains('deletePage page-1')));
      expect(identity.deletions, 0);
      expect(localData.erasures, 0);
      expect(publishing.pagesById['page-1']!.serverDeleteRequestedAt, isNull);
    });

    test('confirmation failure retains intent and explicit retry preserves its first time', () async {
      publishing.markDeletedFailure = StateError('confirmation transaction');
      final deletion = deleteAllData();
      await expectLater(deletion(), failsAt(DeletionStep.publishedData));
      final requestedAt = publishing.pagesById['page-1']!.serverDeleteRequestedAt;
      expect(requestedAt, isNotNull);
      expect(publishing.pagesById['page-1']!.serverDeletedAt, isNull);
      expect(identity.deletions, 0);
      expect(localData.erasures, 0);
      publishing.markDeletedFailure = null;
      identity.deleteFailures.add(Exception('keep rows'));
      await expectLater(deletion(), failsAt(DeletionStep.account));
      expect(publishing.pagesById['page-1']!.serverDeleteRequestedAt, requestedAt);
      expect(publishing.pagesById['page-1']!.serverDeletedAt, isNotNull);
    });

    test('remote refusal keeps unresolved intent', () async {
      publisher.failures['deletePage'] = [const PublishException(PublishErrorKind.refused, 'refused')];
      await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));
      expect(publishing.pagesById['page-1']!.isServerDeletionPending, isTrue);
      expect(queue.isHeld, isFalse);
    });

    for (final method in ['deletePhoto', 'deleteReport']) {
      test('early $method failure does not add a page intent', () async {
        publisher.failures[method] = [transient];
        await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));
        expect(publishing.pagesById['page-1']!.isOpen, isTrue);
        expect(publishing.pagesById['page-1']!.serverDeleteRequestedAt, isNull);
      });
    }

    for (final phase in ['intent', 'remote', 'confirmation']) {
      for (final fails in [false, true]) {
        test('timeout during $phase retains the combined future until late ${fails ? 'failure' : 'success'}', () async {
          final gate = Completer<void>();
          switch (phase) {
            case 'intent':
              publishing.beginDeletionGate = gate;
            case 'remote':
              publisher.gates['deletePage'] = gate;
              if (fails) publisher.failures['deletePage'] = [transient];
            case 'confirmation':
              publishing.markDeletedGate = gate;
          }
          await expectLater(
            deleteAllData(stepTimeout: const Duration(milliseconds: 10))(),
            failsAt(DeletionStep.publishedData),
          );
          expect(queue.isHeld, isTrue);
          if (fails && phase != 'remote') {
            gate.completeError(Exception('late SQLite failure'));
          } else {
            gate.complete();
          }
          await pumpEventQueue();
          final stored = publishing.pagesById['page-1']!;
          expect(stored.serverDeletedAt != null, !fails);
          expect(stored.serverDeleteRequestedAt != null, !fails || phase != 'intent');
          expect(identity.deletions, 0);
          expect(localData.erasures, 0);
          expect(queue.isHeld, isFalse);
        });
      }
    }

    test('late remote success stays held through delayed confirmation persistence', () async {
      final remote = publisher.gates['deletePage'] = Completer<void>();
      final marker = publishing.markDeletedGate = Completer<void>();
      await expectLater(
        deleteAllData(stepTimeout: const Duration(milliseconds: 10))(),
        failsAt(DeletionStep.publishedData),
      );
      remote.complete();
      await pumpEventQueue();
      expect(queue.isHeld, isTrue);
      expect(publishing.pagesById['page-1']!.serverDeletedAt, isNull);
      marker.complete();
      await pumpEventQueue();
      expect(publishing.pagesById['page-1']!.serverDeletedAt, isNotNull);
      expect(queue.isHeld, isFalse);
      expect(identity.deletions, 0);
    });

    test('disposal lets a pending delete finish durable confirmation', () async {
      await queue.hold();
      final gate = publisher.gates['deletePage'] = Completer<void>();
      final running = queue.deletePublished();
      await pumpEventQueue();
      await queue.dispose();
      gate.complete();
      await running;
      expect(publishing.pagesById['page-1']!.serverDeletedAt, isNotNull);
    });

    test('device failure after photo-file cleanup begins can have no database rows', () async {
      photoStore.deleteAllFailure = const FileSystemFailure();
      await expectLater(deleteAllData()(), failsAt(DeletionStep.deviceData));
      expect(publishing.pagesById, isEmpty);
      expect(publishing.jobs, isEmpty);
    });
  });

  group('quarantine request races', () {
    test('rejects a share that read the page before intent committed', () async {
      await queue.hold();
      final gate = publishing.beforeEnqueueGate = Completer<void>();
      final request = queue.publishVisit('visit-1');
      await pumpEventQueue();
      final rejected = expectLater(request, throwsStateError);
      await publishing.beginPageServerDeletion('page-1', DateTime.utc(2026, 10, 3));
      gate.complete();
      await rejected;
      expect(publisher.calls, isEmpty);
      expect(await publishing.pendingJobs(), isEmpty);
    });

    test('a delayed revoke cannot add work after intent committed', () async {
      await queue.hold();
      final gate = publishing.revokeGate = Completer<void>();
      final request = queue.revokeClientPage('client-1');
      await pumpEventQueue();
      await publishing.beginPageServerDeletion('page-1', DateTime.utc(2026, 10, 3));
      gate.complete();
      expect(await request, isNull);
      expect(publishing.jobs.values.where((job) => job.kind == PublishJobKind.revoke), isEmpty);
      expect(publisher.calls, isEmpty);
    });

    test('a delayed reissue never republishes historical visits from an intent page', () async {
      await queue.hold();
      final gate = publishing.revokeGate = Completer<void>();
      final request = queue.reissueClientPage('client-1');
      await pumpEventQueue();
      await publishing.beginPageServerDeletion('page-1', DateTime.utc(2026, 10, 3));
      gate.complete();
      final fresh = await request;
      expect(fresh.id, isNot('page-1'));
      expect(fresh.isOpen, isTrue);
      expect(publishing.jobs.values, hasLength(1));
      expect(publisher.calls, isEmpty);
    });
  });

  group('DeleteAllData', () {
    test('deletes the photos, the reports, the pages, the account, and then the data on the device', () async {
      await deleteAllData()();

      expect(steps, [
        'deletePhoto $object',
        'deleteReport page-1/visit-1',
        'deletePage page-1',
        'deleteAccount x1',
        'eraseAll',
        'deleteAll x0',
      ]);
      expect(localData.erasures, 1);
      expect(photoStore.deletionsOfAll, 1);
      expect(publisher.objects, isEmpty);
      expect(queue.isHeld, isFalse);
    });

    test('in a flavor without a backend, deletes only the data on the device', () async {
      publisher.isAvailable = false;

      await deleteAllData()();

      expect(publisher.calls, isEmpty);
      expect(identity.deletions, 0);
      expect(identity.calls, 0);
      expect(localData.erasures, 1);
      expect(photoStore.deletionsOfAll, 1);
    });

    test('stops before the account and the device when the published data does not delete', () async {
      publisher.failures['deletePage'] = [transient];
      final deletion = deleteAllData();

      await expectLater(deletion(), failsAt(DeletionStep.publishedData));

      expect(identity.deletions, 0);
      expect(localData.erasures, 0);
      expect(photoStore.deletionsOfAll, 0);
      expect(queue.isHeld, isFalse);

      publisher.calls.clear();
      await deletion();

      expect(publisher.calls, ['deleteReport page-1/visit-1', 'deletePage page-1']);
      expect(identity.deletions, 1);
      expect(localData.erasures, 1);
      expect(queue.isHeld, isFalse);
    });

    test('stops before the device when no user is signed in, and stops no job', () async {
      final waiting = await publishing.enqueue(
        PublishJob(
          id: 'job-2',
          kind: PublishJobKind.publish,
          pageId: 'page-1',
          visitId: 'visit-1',
          createdAt: DateTime.utc(2026, 10, 2),
        ),
      );
      identity.userId = null;

      await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));

      expect(publisher.calls, isEmpty);
      expect(localData.erasures, 0);
      // No delete left for the backend, so the job that waits to publish still waits.
      expect(publishing.jobs[waiting.id]!.status, PublishJobStatus.pending);
      expect(queue.isHeld, isFalse);
    });

    test('stops every waiting job before the first delete, so that no job publishes again after a restart', () async {
      final publish = await publishing.enqueue(
        PublishJob(
          id: 'job-2',
          kind: PublishJobKind.publish,
          pageId: 'page-1',
          visitId: 'visit-1',
          createdAt: DateTime.utc(2026, 10, 2),
        ),
      );
      final revoke = await publishing.enqueue(
        PublishJob(id: 'job-3', kind: PublishJobKind.revoke, pageId: 'page-1', createdAt: DateTime.utc(2026, 10, 2)),
      );
      publisher.failures['deletePhoto'] = [transient];

      await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));

      for (final job in [publish, revoke]) {
        expect(publishing.jobs[job.id]!.status, PublishJobStatus.failed);
        expect(publishing.jobs[job.id]!.failure, PublishFailure.deletion);
      }
      expect(queue.isHeld, isFalse);

      // A new start of the app makes a new queue over the same store, which finds no job to run.
      publisher.calls.clear();
      final restarted = publishQueueOf(
        Repositories(
          clients: FakeClientRepository(),
          visits: FakeVisitRepository(),
          companyProfile: FakeCompanyProfileRepository(),
          publishing: publishing,
          openCaptures: FakeOpenCaptureRepository(),
          localData: localData,
        ),
        publisher: publisher,
        identity: FakeIdentity(userId: 'owner-2'),
      );
      addTearDown(restarted.dispose);
      await restarted.start();
      await pumpEventQueue();

      expect(publisher.calls, isEmpty);
    });

    test('stops before the device when the account does not delete, and a retry runs every step again', () async {
      identity.deleteFailures.add(Exception('network-request-failed'));
      final deletion = deleteAllData();

      await expectLater(deletion(), failsAt(DeletionStep.account));

      expect(publisher.pages, isEmpty);
      expect(localData.erasures, 0);
      expect(photoStore.deletionsOfAll, 0);

      publisher.calls.clear();
      await deletion();

      // The deletes of what is gone change nothing, and the object, whose record went with its delete, is not asked.
      expect(publisher.calls, ['deleteReport page-1/visit-1', 'deletePage page-1']);
      expect(identity.deletions, 2);
      expect(localData.erasures, 1);
      expect(photoStore.deletionsOfAll, 1);
    });

    test('a retry deletes what a share published again after a failed deletion', () async {
      identity.deleteFailures.add(Exception('network-request-failed'));
      final deletion = deleteAllData();
      await expectLater(deletion(), failsAt(DeletionStep.account));
      expect(publisher.pages, isEmpty);

      // The person shares the visit again, which publishes its page and its report again.
      final job = await queue.publishVisit('visit-1');
      await pumpEventQueue();
      expect(publishing.jobs[job.id]!.status, PublishJobStatus.done);
      expect(job.pageId, isNot('page-1'));
      expect(publisher.pages.keys, [job.pageId]);
      expect(publisher.reports.keys, ['${job.pageId}/visit-1']);

      await deletion();

      expect(publisher.pages, isEmpty);
      expect(publisher.reports, isEmpty);
      expect(localData.erasures, 1);
    });

    group('the record that an upload arrived', () {
      test('is forgotten before any delete, so a failed attempt leaves every object to upload again', () async {
        identity.userId = null;

        await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));

        expect(publisher.calls, isEmpty);
        expect(await publishing.uploadedPhoto(pageId: 'page-1', objectPath: object), isNull);
        // The record stays as an intent, so a cleanup or a revoke still knows the object.
        expect(await publishing.uploadedObjects('page-1'), [object]);
      });

      test('a share after a Storage delete whose record did not go uploads the photo again', () async {
        publishing.removeFailure = Exception('disk I/O error');

        await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));
        expect(publisher.objects, isEmpty);
        expect(queue.isHeld, isFalse);

        publishing.removeFailure = null;
        publisher.calls.clear();
        await queue.publishVisit('visit-1');
        await pumpEventQueue();

        expect(publisher.calls, contains('uploadPhoto $object'));
        expect(publisher.objects.keys, [object]);
      });

      test('a share after a late Storage delete whose record did not go uploads the photo again', () async {
        final gate = publisher.gates['deletePhoto'] = Completer<void>();
        publishing.removeFailure = Exception('disk I/O error');
        await expectLater(
          deleteAllData(stepTimeout: const Duration(milliseconds: 10))(),
          failsAt(DeletionStep.publishedData),
        );

        gate.complete();
        await pumpEventQueue();
        expect(queue.isHeld, isFalse);

        publishing.removeFailure = null;
        publisher.calls.clear();
        await queue.publishVisit('visit-1');
        await pumpEventQueue();

        expect(publisher.calls, contains('uploadPhoto $object'));
        expect(publisher.objects.keys, [object]);
      });
    });

    group('a backend delete that does not answer in time', () {
      const timeout = Duration(milliseconds: 10);

      test('keeps the queue held, and a reshare after a late Storage delete uploads the photo again', () async {
        final gate = publisher.gates['deletePhoto'] = Completer<void>();
        final deletion = deleteAllData(stepTimeout: timeout);

        await expectLater(deletion(), failsAt(DeletionStep.publishedData));
        expect(queue.isHeld, isTrue);

        // The person shares the visit again while the delete of its photo is still on its way.
        publisher.calls.clear();
        final job = await queue.publishVisit('visit-1');
        await pumpEventQueue();
        expect(publisher.calls, isEmpty);

        gate.complete();
        await pumpEventQueue();

        // The late delete removed the object and its record, so the share uploads the photo again.
        expect(queue.isHeld, isFalse);
        expect(publishing.jobs[job.id]!.status, PublishJobStatus.done);
        expect(publisher.calls, containsAllInOrder(['writePage page-1', 'uploadPhoto $object']));
        expect(publisher.objects.keys, [object]);
        expect(await publishing.uploadedPhoto(pageId: 'page-1', objectPath: object), 'photos/visit-1/photo-1.jpg');
      });

      test('a late Storage delete that fails keeps the object and its record, and lets the queue run', () async {
        final gate = publisher.gates['deletePhoto'] = Completer<void>();
        publisher.failures['deletePhoto'] = [transient];
        final deletion = deleteAllData(stepTimeout: timeout);
        await expectLater(deletion(), failsAt(DeletionStep.publishedData));

        gate.complete();
        await pumpEventQueue();

        expect(queue.isHeld, isFalse);
        expect(publisher.objects.keys, [object]);
        expect(await publishing.uploadedObjects('page-1'), [object]);
      });

      test('a next try while a Storage delete is on its way starts no second delete of it', () async {
        final gate = publisher.gates['deletePhoto'] = Completer<void>();
        final deletion = deleteAllData(stepTimeout: timeout);
        await expectLater(deletion(), failsAt(DeletionStep.publishedData));

        await expectLater(deletion(), failsAt(DeletionStep.publishedData));
        expect(publisher.calls.where((call) => call.startsWith('deletePhoto')), hasLength(1));
        expect(queue.isHeld, isTrue);

        publisher.gates.remove('deletePhoto');
        final third = deletion();
        gate.complete();
        await third;
        // The third try waited for the late delete, and then deleted the recorded object again, which is gone: a
        // delete of what is gone changes nothing.
        expect(publisher.calls.where((call) => call.startsWith('deletePhoto')), hasLength(2));
        expect(publisher.objects, isEmpty);
        expect(localData.erasures, 1);
        expect(queue.isHeld, isFalse);
      });

      test('keeps the queue held until a late report delete ends too', () async {
        final gate = publisher.gates['deleteReport'] = Completer<void>();
        final deletion = deleteAllData(stepTimeout: timeout);

        await expectLater(deletion(), failsAt(DeletionStep.publishedData));
        expect(queue.isHeld, isTrue);

        gate.complete();
        await pumpEventQueue();
        expect(queue.isHeld, isFalse);
      });
    });

    group('an account deletion that does not answer in time', () {
      const timeout = Duration(milliseconds: 10);

      test('stops at the account, and no reshare publishes under the old user while it runs', () async {
        final gate = identity.deleteGate = Completer<void>();
        final deletion = deleteAllData(stepTimeout: timeout);

        await expectLater(deletion(), failsAt(DeletionStep.account));
        expect(localData.erasures, 0);
        expect(queue.isHeld, isTrue);

        // The person shares the visit again while the delete of the account is still on its way.
        publisher.calls.clear();
        final asked = identity.calls;
        final job = await queue.publishVisit('visit-1');
        await pumpEventQueue();
        expect(publisher.calls, isEmpty);
        expect(identity.calls, asked);
        expect(publishing.jobs[job.id]!.attempts, 0);

        gate.complete();
        await pumpEventQueue();
        // The account is gone, so nothing may publish under a new account before the device is erased.
        expect(queue.isHeld, isTrue);
        expect(publisher.calls, isEmpty);
      });

      test('a next try that finds the delete settled with success goes on with the device only', () async {
        final gate = identity.deleteGate = Completer<void>();
        final deletion = deleteAllData(stepTimeout: timeout);
        await expectLater(deletion(), failsAt(DeletionStep.account));
        gate.complete();
        await pumpEventQueue();
        publisher.calls.clear();
        final asked = identity.calls;

        await deletion();

        expect(publisher.calls, isEmpty);
        expect(identity.calls, asked);
        expect(identity.deletions, 1);
        expect(localData.erasures, 1);
        expect(photoStore.deletionsOfAll, 1);
        expect(queue.isHeld, isFalse);
      });

      test('a next try while the delete is still on its way starts no second delete and names the account', () async {
        final gate = identity.deleteGate = Completer<void>();
        final deletion = deleteAllData(stepTimeout: timeout);
        await expectLater(deletion(), failsAt(DeletionStep.account));

        await expectLater(deletion(), failsAt(DeletionStep.account));

        expect(identity.deletions, 1);
        expect(localData.erasures, 0);
        expect(queue.isHeld, isTrue);

        // The second try waits for the delete, and goes on when it ends inside the wait.
        final third = deletion();
        gate.complete();
        await third;
        expect(identity.deletions, 1);
        expect(localData.erasures, 1);
        expect(queue.isHeld, isFalse);
      });

      test('a delete that settles with a failure keeps the account and lets the queue run again', () async {
        final gate = identity.deleteGate = Completer<void>();
        identity.deleteFailures.add(Exception('network-request-failed'));
        final deletion = deleteAllData(stepTimeout: timeout);
        await expectLater(deletion(), failsAt(DeletionStep.account));
        expect(queue.isHeld, isTrue);

        gate.complete();
        await pumpEventQueue();

        expect(queue.isHeld, isFalse);
        identity.deleteGate = null;
        await deletion();
        expect(identity.deletions, 2);
        expect(localData.erasures, 1);
      });
    });

    test('names the device when the database does not erase, and a retry with a new account completes', () async {
      localData.failure = Exception('disk I/O error');
      final deletion = deleteAllData();

      await expectLater(deletion(), failsAt(DeletionStep.deviceData));
      expect(photoStore.deletionsOfAll, 0);

      localData.failure = null;
      publisher.calls.clear();
      // The account is gone, so the retry signs in with a new one, which may delete what is gone and is deleted too.
      identity.userId = 'owner-2';
      await deletion();

      expect(publisher.calls, ['deleteReport page-1/visit-1', 'deletePage page-1']);
      expect(identity.deletions, 2);
      expect(localData.erasures, 1);
      expect(photoStore.deletionsOfAll, 1);
    });

    test('names the device when the photo files do not delete', () async {
      photoStore.deleteAllFailure = const FileSystemFailure();
      final deletion = deleteAllData();

      await expectLater(deletion(), failsAt(DeletionStep.deviceData));
      expect(localData.erasures, 1);

      photoStore.deleteAllFailure = null;
      identity.userId = 'owner-2';
      await deletion();

      expect(localData.erasures, 2);
      expect(photoStore.deletionsOfAll, 1);
    });

    test('a failure names its step and its cause in the log', () {
      expect(
        const DeletionFailure(DeletionStep.account, 'network-request-failed').toString(),
        'DeletionFailure(account, network-request-failed)',
      );
    });

    test('names the step of a failure that is an error and not an exception', () async {
      publisher.failures['deletePhoto'] = [StateError('no plugin')];

      await expectLater(deleteAllData()(), failsAt(DeletionStep.publishedData));
    });

    test('runs no publish job from the first step until the deletion ends', () async {
      final deletion = deleteAllData();
      publisher.gates['deletePage'] = Completer<void>();
      final running = deletion();
      await pumpEventQueue();
      final asked = identity.calls;

      // A job asks for the user before its first step, so a job that ran would ask once more.
      final job = await queue.publishVisit('visit-1');
      await pumpEventQueue();
      expect(identity.calls, asked);
      expect((await publishing.jobsOfPage(job.pageId)).singleWhere((stored) => stored.id == job.id).attempts, 0);

      publisher.gates.remove('deletePage')!.complete();
      await running;
      expect(queue.isHeld, isFalse);
    });
  });
}

/// A failure of the file system that a test gives to the fake photo store.
final class FileSystemFailure implements Exception {
  const new();
}
