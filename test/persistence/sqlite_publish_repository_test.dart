import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  late Database database;
  late SqlitePublishRepository repository;

  ClientPage page(String id, {String clientId = 'client-1', DateTime? revokedAt}) => ClientPage(
    id: id,
    clientId: clientId,
    createdAt: DateTime.utc(2026, 10, 1, 9, 30, 15, 123, 456),
    revokedAt: revokedAt,
  );

  PublishJob job(
    String id, {
    String pageId = 'page-1',
    String? visitId = 'visit-1',
    PublishJobKind kind = PublishJobKind.publish,
    int minute = 0,
  }) => PublishJob(
    id: id,
    kind: kind,
    pageId: pageId,
    visitId: visitId,
    createdAt: DateTime.utc(2026, 10, 1, 10, minute),
  );

  setUp(() async {
    database = await openMemoryDatabase();
    repository = SqlitePublishRepository(database);
    final clients = SqliteClientRepository(database);
    for (final id in ['client-1', 'client-2']) {
      await clients.save(
        Client(id: id, name: '한빛 사무실', createdAt: DateTime.utc(2026, 9)),
        zones: ClientZones(
          clientId: id,
          zones: [Zone(id: 'zone-$id', clientId: id, name: '로비', position: 0)],
        ),
      );
    }
    final visits = SqliteVisitRepository(database);
    for (final id in ['visit-1', 'visit-2']) {
      await visits.save(
        Visit(id: id, clientId: 'client-1', visitDate: VisitDate(2026, 10, 1), createdAt: DateTime.utc(2026, 10)),
      );
    }
  });

  tearDown(() => database.close());

  group('openPageOf', () {
    test('stores the page that create makes when the client has no open page, and returns it later', () async {
      var creates = 0;
      ClientPage create() {
        creates++;
        return page('page-1');
      }

      expect(await repository.openPageOf('client-1', create: create), page('page-1'));
      expect(await repository.openPageOf('client-1', create: create), page('page-1'));
      expect(await repository.openPageOf('client-1'), page('page-1'));
      expect(creates, 1);
      expect(await repository.pageById('page-1'), page('page-1'));
    });

    test('gives null and stores nothing for a client without an open page when create is not given', () async {
      expect(await repository.openPageOf('client-1'), isNull);
      expect(await database.query('client_pages'), isEmpty);
    });

    test('gives no page of another client and no revoked page', () async {
      await repository.openPageOf('client-2', create: () => page('page-2', clientId: 'client-2'));
      await repository.openPageOf('client-1', create: () => page('page-1'));
      await repository.revoke(page('page-1'), at: DateTime.utc(2026, 10, 2), revokeJob: job('revoke-1', visitId: null));

      expect(await repository.openPageOf('client-1'), isNull);
      expect(await repository.openPageOf('client-2'), page('page-2', clientId: 'client-2'));
    });
  });

  test('pageById gives null for an unknown page', () async {
    expect(await repository.pageById('page-9'), isNull);
  });

  group('jobs', () {
    setUp(() async {
      await repository.openPageOf('client-1', create: () => page('page-1'));
    });

    test('enqueue stores a job, and pendingJobs and jobsOfPage read it back as it was stored', () async {
      final stored = await repository.enqueue(job('job-1'));

      expect(stored, job('job-1'));
      expect(await repository.pendingJobs(), [job('job-1')]);
      expect(await repository.jobsOfPage('page-1'), [job('job-1')]);
      expect(await repository.jobsOfPage('page-9'), isEmpty);
    });

    test('enqueue adds nothing for a pending job of the same visit and page, and restarts that job', () async {
      await repository.enqueue(job('job-1'));
      final failedRun = job('job-1').retryAt(DateTime.utc(2026, 10, 1, 11));
      await repository.saveJob(failedRun);

      final stored = await repository.enqueue(job('job-2', minute: 5));

      expect(stored, job('job-1'));
      expect(await repository.pendingJobs(), [job('job-1')]);
    });

    test('enqueue adds a job for another visit, and for a visit whose earlier job is no longer pending', () async {
      await repository.enqueue(job('job-1'));
      await repository.saveJob(job('job-1').succeed());

      await repository.enqueue(job('job-2', minute: 1));
      await repository.enqueue(job('job-3', visitId: 'visit-2', minute: 2));

      expect(await repository.pendingJobs(), [job('job-2', minute: 1), job('job-3', visitId: 'visit-2', minute: 2)]);
    });

    test('saveJob stores each field of a job, and pendingJobs leaves out a job that is no longer pending', () async {
      await repository.enqueue(job('job-1'));
      await repository.enqueue(job('job-2', visitId: 'visit-2', minute: 1));
      final retried = job('job-1').retryAt(DateTime.utc(2026, 10, 1, 10, 0, 5));
      final failed = job('job-2', visitId: 'visit-2', minute: 1).fail(PublishFailure.photoMissing);

      await repository.saveJob(retried);
      await repository.saveJob(failed);

      expect(await repository.pendingJobs(), [retried]);
      expect(await repository.jobsOfPage('page-1'), [retried, failed]);
    });

    test('pendingJobs gives the oldest job first', () async {
      await repository.enqueue(job('job-b', visitId: 'visit-2', minute: 3));
      await repository.enqueue(job('job-a', minute: 1));

      expect((await repository.pendingJobs()).map((job) => job.id), ['job-a', 'job-b']);
    });

    test('clearRetryDelays clears the delay of each pending job and of no other job', () async {
      await repository.enqueue(job('job-1'));
      await repository.enqueue(job('job-2', visitId: 'visit-2', minute: 1));
      final later = DateTime.utc(2026, 10, 1, 12);
      await repository.saveJob(job('job-1').retryAt(later));
      final failed = job('job-2', visitId: 'visit-2', minute: 1).retryAt(later).fail(PublishFailure.refused);
      await repository.saveJob(failed);

      await repository.clearRetryDelays();

      final cleared = (await repository.pendingJobs()).single;
      expect(cleared.nextAttemptAt, isNull);
      expect(cleared.attempts, 1);
      expect((await repository.jobsOfPage('page-1')).last, failed);
    });
  });

  group('revoke', () {
    setUp(() async {
      await repository.openPageOf('client-1', create: () => page('page-1'));
    });

    test('revokes the page, stops its pending publish jobs, and adds the revoke job', () async {
      await repository.enqueue(job('job-1'));
      await repository.enqueue(job('job-2', visitId: 'visit-2', minute: 1));
      await repository.saveJob(job('job-2', visitId: 'visit-2', minute: 1).succeed());
      final at = DateTime.utc(2026, 10, 2);
      final revokeJob = job('revoke-1', kind: PublishJobKind.revoke, visitId: null, minute: 2);

      expect(await repository.revoke(page('page-1'), at: at, revokeJob: revokeJob), isTrue);

      expect(await repository.pageById('page-1'), page('page-1', revokedAt: at));
      expect(await repository.jobsOfPage('page-1'), [
        job('job-1').fail(PublishFailure.revoked),
        job('job-2', visitId: 'visit-2', minute: 1).succeed(),
        revokeJob,
      ]);
      expect(await repository.pendingJobs(), [revokeJob]);
    });

    test('stores the replacement as the open page and republishes each visit with a pending or done job', () async {
      await repository.enqueue(job('job-a', minute: 1));
      await repository.saveJob(job('job-a', minute: 1).succeed());
      await repository.enqueue(job('job-b', visitId: 'visit-2', minute: 2));
      await repository.saveJob(job('job-b', visitId: 'visit-2', minute: 2).fail(PublishFailure.refused));
      await repository.enqueue(job('job-c', minute: 3));
      final replacement = page('page-2');

      final revoked = await repository.revoke(
        page('page-1'),
        at: DateTime.utc(2026, 10, 2),
        revokeJob: job('revoke-1', kind: PublishJobKind.revoke, visitId: null, minute: 4),
        replacement: replacement,
        republish: (visitId) => job('again-$visitId', pageId: 'page-2', visitId: visitId, minute: 5),
      );

      expect(revoked, isTrue);
      expect(await repository.openPageOf('client-1'), replacement);
      expect(await repository.jobsOfPage('page-2'), [job('again-visit-1', pageId: 'page-2', minute: 5)]);
    });

    test('stores the replacement and adds no job when it is given no republish', () async {
      await repository.enqueue(job('job-a'));

      await repository.revoke(
        page('page-1'),
        at: DateTime.utc(2026, 10, 2),
        revokeJob: job('revoke-1', kind: PublishJobKind.revoke, visitId: null, minute: 4),
        replacement: page('page-2'),
      );

      expect(await repository.openPageOf('client-1'), page('page-2'));
      expect(await repository.jobsOfPage('page-2'), isEmpty);
    });

    test('changes nothing and gives false for a page that is no longer open', () async {
      final first = DateTime.utc(2026, 10, 2);
      await repository.revoke(
        page('page-1'),
        at: first,
        revokeJob: job('revoke-1', kind: PublishJobKind.revoke),
      );

      final again = await repository.revoke(
        page('page-1'),
        at: DateTime.utc(2026, 10, 3),
        revokeJob: job('revoke-2', kind: PublishJobKind.revoke, visitId: null, minute: 1),
        replacement: page('page-3'),
      );

      expect(again, isFalse);
      expect(await repository.pageById('page-1'), page('page-1', revokedAt: first));
      expect(await repository.pageById('page-3'), isNull);
      expect((await repository.jobsOfPage('page-1')).map((job) => job.id), ['revoke-1']);
    });

    test('changes nothing when a step fails', () async {
      await repository.enqueue(job('job-1'));

      await expectLater(
        repository.revoke(
          page('page-1'),
          at: DateTime.utc(2026, 10, 2),
          revokeJob: job('revoke-1', kind: PublishJobKind.revoke, visitId: null),
          // A page for a client that does not exist breaks a foreign key.
          replacement: page('page-2', clientId: 'client-9'),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await repository.openPageOf('client-1'), page('page-1'));
      expect(await repository.pendingJobs(), [job('job-1')]);
    });
  });

  group('uploaded photos', () {
    setUp(() async {
      await repository.openPageOf('client-1', create: () => page('page-1'));
      await repository.openPageOf('client-2', create: () => page('page-2', clientId: 'client-2'));
    });

    test('records which photo file reached which object of which page', () async {
      await repository.saveUploadedPhoto(pageId: 'page-1', objectPath: 'b.jpg', photoPath: 'photos/v/1.jpg');
      await repository.saveUploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg', photoPath: 'photos/v/2.jpg');
      await repository.saveUploadedPhoto(pageId: 'page-2', objectPath: 'a.jpg', photoPath: 'photos/v/3.jpg');

      expect(await repository.uploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg'), 'photos/v/2.jpg');
      expect(await repository.uploadedPhoto(pageId: 'page-2', objectPath: 'a.jpg'), 'photos/v/3.jpg');
      expect(await repository.uploadedPhoto(pageId: 'page-1', objectPath: 'c.jpg'), isNull);
      expect(await repository.uploadedObjects('page-1'), ['a.jpg', 'b.jpg']);
    });

    test('keeps the newest photo file of an object', () async {
      await repository.saveUploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg', photoPath: 'photos/v/1.jpg');
      await repository.saveUploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg', photoPath: 'photos/v/2.jpg');

      expect(await repository.uploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg'), 'photos/v/2.jpg');
      expect(await repository.uploadedObjects('page-1'), ['a.jpg']);
    });

    test('forgets an object that was deleted', () async {
      await repository.saveUploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg', photoPath: 'photos/v/1.jpg');
      await repository.saveUploadedPhoto(pageId: 'page-2', objectPath: 'a.jpg', photoPath: 'photos/v/1.jpg');

      await repository.removeUploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg');

      expect(await repository.uploadedPhoto(pageId: 'page-1', objectPath: 'a.jpg'), isNull);
      expect(await repository.uploadedObjects('page-1'), isEmpty);
      expect(await repository.uploadedObjects('page-2'), ['a.jpg']);
    });
  });
}
