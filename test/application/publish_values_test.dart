import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  final created = DateTime.utc(2026, 10, 2, 9);

  group('ClientPage', () {
    test('keeps its times in UTC and is open until it is revoked', () {
      final page = ClientPage(id: 'page-1', clientId: 'client-1', createdAt: DateTime(2026, 10, 2, 18));

      expect(page.createdAt.isUtc, isTrue);
      expect(page.isRevoked, isFalse);
      final revoked = page.revoke(DateTime(2026, 10, 3, 9));
      expect(revoked.isRevoked, isTrue);
      expect(revoked.revokedAt?.isUtc, isTrue);
      expect((revoked.id, revoked.clientId, revoked.createdAt), (page.id, page.clientId, page.createdAt));
    });

    test('has value equality', () {
      ClientPage page({String id = 'page-1', DateTime? revokedAt}) =>
          ClientPage(id: id, clientId: 'client-1', createdAt: created, revokedAt: revokedAt);

      expect(page(), page());
      expect(page().hashCode, page().hashCode);
      expect(page(), isNot(page(id: 'page-2')));
      expect(page(), isNot(page(revokedAt: created)));
      expect(page().toString(), contains('page-1'));
    });
  });

  group('newPageId', () {
    test('makes 128 random bits as 32 hexadecimal digits', () {
      final ids = {for (var i = 0; i < 100; i++) newPageId(Random(i))};

      expect(pageIdBits, 128);
      expect(ids, hasLength(100));
      expect(ids, everyElement(matches(RegExp(r'^[0-9a-f]{32}$'))));
    });
  });

  group('PublishJob', () {
    final job = PublishJob(
      id: 'job-1',
      kind: PublishJobKind.publish,
      pageId: 'page-1',
      visitId: 'visit-1',
      createdAt: DateTime(2026, 10, 2, 18),
    );

    test('starts pending without a failure and keeps its times in UTC', () {
      expect(job.status, PublishJobStatus.pending);
      expect((job.attempts, job.nextAttemptAt, job.failure), (0, null, null));
      expect(job.createdAt.isUtc, isTrue);
    });

    test('counts each retry and clears the count when it restarts', () {
      final retried = job.retryAt(DateTime(2026, 10, 2, 19)).retryAt(DateTime(2026, 10, 2, 20));

      expect(retried.status, PublishJobStatus.pending);
      expect(retried.attempts, 2);
      expect(retried.nextAttemptAt, DateTime(2026, 10, 2, 20).toUtc());
      expect(retried.restart(), job);
    });

    test('keeps the count of retries when it is done or fails, and clears the delay', () {
      final retried = job.retryAt(created);

      expect(retried.succeed().status, PublishJobStatus.done);
      expect((retried.succeed().attempts, retried.succeed().nextAttemptAt), (1, null));
      final failed = retried.fail(PublishFailure.photoMissing);
      expect(
        (failed.status, failed.failure, failed.attempts, failed.nextAttemptAt),
        (
          PublishJobStatus.failed,
          PublishFailure.photoMissing,
          1,
          null,
        ),
      );
    });

    test('has value equality', () {
      expect(job.retryAt(created), job.retryAt(created));
      expect(job.retryAt(created).hashCode, job.retryAt(created).hashCode);
      expect(job, isNot(job.succeed()));
      expect(job.fail(PublishFailure.refused).toString(), contains('refused'));
    });

    test('limits a photo to the size that storage.rules allows', () {
      expect(maxPhotoBytes, 5 * 1024 * 1024);
    });
  });

  group('published values', () {
    test('a page keeps its time in UTC and has value equality', () {
      PublishedPage page({String? companyName = '꼼꼬미 청소'}) => PublishedPage(
        ownerUid: 'owner-1',
        companyName: companyName,
        clientName: '한빛 상가',
        createdAt: DateTime(2026, 10, 2, 18),
      );

      expect(page().createdAt.isUtc, isTrue);
      expect(page(), page());
      expect(page().hashCode, page().hashCode);
      expect(page(), isNot(page(companyName: null)));
      expect(page().toString(), contains('owner-1'));
    });

    test('a report and its zones have value equality', () {
      PublishedReport report(String note, {DateTime? publishedAt}) => PublishedReport(
        visitDate: VisitDate(2026, 10, 2),
        publishedAt: publishedAt ?? DateTime.utc(2026, 10, 2, 9),
        zones: [PublishedZone(name: '입구', note: note, beforePhoto: 'a.jpg', afterPhoto: null)],
      );

      expect(report('바닥'), report('바닥'));
      expect(report('바닥').hashCode, report('바닥').hashCode);
      expect(report('바닥'), isNot(report('창문')));
      expect(report('바닥'), isNot(report('바닥', publishedAt: DateTime.utc(2026, 10, 2, 10))));
      expect(report('바닥', publishedAt: DateTime(2026, 10, 2, 18)).publishedAt.isUtc, isTrue);
      expect(report('바닥').zones.single.hashCode, report('바닥').zones.single.hashCode);
      expect(report('바닥').toString(), contains('입구'));
      expect(() => report('바닥').zones.add(report('바닥').zones.single), throwsUnsupportedError);
    });

    test('a publish exception says its kind and its message', () {
      expect(
        const PublishException(PublishErrorKind.refused, 'permission-denied').toString(),
        'PublishException(refused, permission-denied)',
      );
    });
  });
}
