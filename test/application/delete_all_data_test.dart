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
          Visit(
            id: 'visit-1',
            clientId: 'client-1',
            visitDate: VisitDate(2026, 10, 1),
            createdAt: DateTime.utc(2026, 10),
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
    localData.onErase = () => steps
      ..addAll(publisher.calls)
      ..add('deleteAccount x${identity.deletions}')
      ..add('eraseAll')
      ..add('deleteAll x${photoStore.deletionsOfAll}');
  });

  tearDown(() => queue.dispose());

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
      expect(publisher.pages.keys, ['page-1']);
      expect(publisher.reports.keys, ['page-1/visit-1']);

      await deletion();

      expect(publisher.pages, isEmpty);
      expect(publisher.reports, isEmpty);
      expect(localData.erasures, 1);
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
      expect((await publishing.jobsOfPage('page-1')).singleWhere((stored) => stored.id == job.id).attempts, 0);

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
