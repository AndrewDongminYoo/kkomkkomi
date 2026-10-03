import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../../helpers/helpers.dart';

/// Keeps the errors that the cubits report.
class _ErrorObserver extends BlocObserver {
  final errors = <Object>[];

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(bloc, error, stackTrace);
  }
}

/// A share sheet that records what the backend held at the moment that it opened.
class _RecordingLinkShare implements LinkShare {
  new(this._publisher);

  final FakePublisher _publisher;
  final shared = <Uri>[];

  /// The calls of the backend before each share.
  final callsBeforeShare = <List<String>>[];

  @override
  Future<void> shareLink(Uri link) async {
    callsBeforeShare.add([..._publisher.calls]);
    shared.add(link);
  }
}

void main() {
  const visitId = 'visit-1';
  final client = Client(id: 'client-1', name: '행복빌딩', createdAt: DateTime.utc(2026, 9));
  final visit = Visit(
    id: visitId,
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 1),
    zoneRecords: [
      ZoneRecord(
        zoneId: 'zone-1',
        zoneName: '로비',
        beforePhoto: PhotoRef('photos/visit-1/lobby-before.jpg'),
        afterPhoto: PhotoRef('photos/visit-1/lobby-after.jpg'),
        note: '바닥 왁스',
      ),
    ],
  );

  late FakePublishRepository publishing;
  late Repositories repositories;
  late FakePublisher publisher;
  late FakePhotoStore photoStore;
  late FakeNetworkMonitor network;
  late _RecordingLinkShare linkShare;
  late PublishQueue queue;
  late _ErrorObserver observer;
  late BlocObserver previousObserver;

  setUp(() {
    publishing = FakePublishRepository();
    repositories = Repositories(
      clients: FakeClientRepository(clients: [client]),
      visits: FakeVisitRepository(visits: [visit]),
      companyProfile: FakeCompanyProfileRepository(profile: CompanyProfile(name: '깔끔클린')),
      publishing: publishing,
      openCaptures: FakeOpenCaptureRepository(),
      localData: FakeLocalDataRepository(),
    );
    publisher = FakePublisher();
    photoStore = FakePhotoStore();
    network = FakeNetworkMonitor();
    linkShare = _RecordingLinkShare(publisher);
    queue = publishQueueOf(repositories, publisher: publisher, photoStore: photoStore, networkMonitor: network);
    previousObserver = Bloc.observer;
    observer = _ErrorObserver();
    Bloc.observer = observer;
  });

  tearDown(() async {
    Bloc.observer = previousObserver;
    await queue.dispose();
  });

  ReportLinkCubit build({LinkShare? share, String id = visitId}) =>
      ReportLinkCubit(visitId: id, visits: repositories.visits, publishQueue: queue, linkShare: share ?? linkShare);

  /// The only page that the store holds.
  ClientPage onlyPage() => publishing.pagesById.values.single;

  /// Waits until the cubit reaches a state that [matches].
  Future<void> until(ReportLinkCubit cubit, bool Function(ReportLinkState state) matches) async {
    if (matches(cubit.state)) return;
    await cubit.stream.firstWhere(matches);
  }

  group('ReportLinkCubit', () {
    test('old intent retains the first-share notice and only shares the requested visit under a fresh ID', () async {
      final old = ClientPage(
        id: 'old',
        clientId: 'client-1',
        createdAt: visit.createdAt,
        serverDeleteRequestedAt: visit.createdAt,
      );
      publishing.pagesById[old.id] = old;
      final historical = PublishJob(
        id: 'history',
        kind: PublishJobKind.publish,
        pageId: old.id,
        visitId: visitId,
        createdAt: visit.createdAt,
      ).succeed();
      publishing.jobs[historical.id] = historical;
      final cubit = build();
      await cubit.load();
      expect(cubit.state.isFirstShare, isTrue);
      await cubit.share();
      await until(cubit, (state) => state.status == ReportLinkStatus.ready);
      final fresh = publishing.pagesById.values.singleWhere((page) => page.isOpen);
      expect(fresh.id, isNot(old.id));
      expect(publisher.reports.keys, ['${fresh.id}/$visitId']);
      expect(publishing.jobs[historical.id], historical);
      expect(linkShare.shared.single.path, contains(fresh.id));
      await cubit.close();
    });

    test('intent between page read and enqueue rejects the share, then a new explicit share uses a fresh ID', () async {
      final cubit = build();
      await cubit.load();
      final gate = publishing.beforeEnqueueGate = Completer<void>();
      final sharing = cubit.share();
      await pumpEventQueue();
      final old = onlyPage();
      await publishing.beginPageServerDeletion(old.id, visit.createdAt);
      gate.complete();
      await sharing;
      expect(cubit.state.status, ReportLinkStatus.failed);
      expect(linkShare.shared, isEmpty);
      expect(observer.errors.single, isA<StateError>());
      publishing.beforeEnqueueGate = null;
      await cubit.load();
      expect(cubit.state.isFirstShare, isTrue);
      await cubit.share();
      await until(cubit, (state) => state.status == ReportLinkStatus.ready);
      expect(publishing.pagesById.values.singleWhere((page) => page.isOpen).id, isNot(old.id));
      expect(linkShare.shared, hasLength(1));
      await cubit.close();
    });

    group('load', () {
      test('offers no link in a flavor without a backend', () async {
        publisher.isAvailable = false;
        final cubit = build();

        await cubit.load();

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.unavailable));
        expect(cubit.state.canShare, isFalse);
        await cubit.close();
      });

      test('counts the share as the first one while the client has no page', () async {
        final cubit = build();

        await cubit.load();

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.ready, isFirstShare: true));
        expect(cubit.state.canShare, isTrue);
        await cubit.close();
      });

      test('does not count the share as the first one when the client has an open page', () async {
        await publishing.openPageOf(
          client.id,
          create: () => ClientPage(id: 'page-1', clientId: client.id, createdAt: DateTime.utc(2026, 10)),
        );
        final cubit = build();

        await cubit.load();

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.ready));
        await cubit.close();
      });

      test('counts the share as the first one when the visit is not in storage', () async {
        final cubit = build(id: 'visit-unknown');

        await cubit.load();

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.ready, isFirstShare: true));
        await cubit.close();
      });

      test('counts the share as the first one and reports the error when storage fails', () async {
        final failure = Exception('storage failed');
        publishing.failure = failure;
        final cubit = build();

        await cubit.load();

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.ready, isFirstShare: true));
        expect(observer.errors, [failure]);
        await cubit.close();
      });
    });

    group('share', () {
      test('publishes the visit and opens the share sheet with the link of its report after the report', () async {
        final cubit = build();
        await cubit.load();
        final states = <ReportLinkState>[];
        final subscription = cubit.stream.listen(states.add);

        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        final page = onlyPage();
        final record = visit.zoneRecords.single;
        String objectOf(PhotoSlot slot) => photoObjectPath(
          pageId: page.id,
          visitId: visitId,
          zoneId: record.zoneId,
          slot: slot,
          photo: record.photoIn(slot)!,
        );
        expect(linkShare.shared, [Uri.parse('https://kkomkkomi.web.app/r/${page.id}/$visitId')]);
        // The page, the photos, and the report reached the backend before the share sheet opened.
        expect(linkShare.callsBeforeShare.single, [
          'writePage ${page.id}',
          'uploadPhoto ${objectOf(PhotoSlot.before)}',
          'uploadPhoto ${objectOf(PhotoSlot.after)}',
          'writeReport ${page.id}/$visitId',
        ]);
        expect(states, [
          const ReportLinkState(status: ReportLinkStatus.publishing, isFirstShare: true),
          const ReportLinkState(status: ReportLinkStatus.publishing),
          const ReportLinkState(status: ReportLinkStatus.ready),
        ]);
        await subscription.cancel();
        await cubit.close();
      });

      test('does nothing in a flavor without a backend', () async {
        publisher.isAvailable = false;
        final cubit = build();
        await cubit.load();

        await cubit.share();

        expect(cubit.state.status, ReportLinkStatus.unavailable);
        expect(publishing.jobs, isEmpty);
        expect(linkShare.shared, isEmpty);
        await cubit.close();
      });

      test('does nothing while a share runs', () async {
        final gate = Completer<void>();
        publisher.gates['writeReport'] = gate;
        final cubit = build();
        await cubit.load();

        await cubit.share();
        await cubit.share();
        gate.complete();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(publishing.jobs, hasLength(1));
        expect(linkShare.shared, hasLength(1));
        await cubit.close();
      });

      test('shows the reason of a job that the backend refused, and shares nothing', () async {
        publisher.failures['writeReport'] = [const PublishException(PublishErrorKind.refused, 'denied')];
        final cubit = build();
        await cubit.load();

        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.failed);

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.failed, failure: PublishFailure.refused));
        expect(cubit.state.canShare, isTrue);
        expect(linkShare.shared, isEmpty);
        await cubit.close();
      });

      test('shows the reason of a job whose photo does not read', () async {
        photoStore.readFailure = Exception('no file');
        final cubit = build();
        await cubit.load();

        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.failed);

        expect(cubit.state.failure, PublishFailure.photoMissing);
        await cubit.close();
      });

      test('waits for a retry, and a second share runs the job again at once and opens the share sheet', () async {
        publisher.failures['writePage'] = [const PublishException(PublishErrorKind.transient, 'offline')];
        final cubit = build();
        await cubit.load();

        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.waitingForRetry);
        expect(cubit.state.canShare, isTrue);
        expect(linkShare.shared, isEmpty);

        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(publishing.jobs, hasLength(1));
        expect(linkShare.shared, [Uri.parse('https://kkomkkomi.web.app/r/${onlyPage().id}/$visitId')]);
        await cubit.close();
      });

      test('follows the job that the queue runs before the request returns', () async {
        await queue.start();
        final gate = Completer<void>();
        publishing.enqueueGate = gate;
        final cubit = build();
        await cubit.load();

        unawaited(cubit.share());
        await pumpEventQueue();
        // The network returns while the request waits, and the queue runs the stored job to its end.
        network.restore();
        await pumpEventQueue();
        expect(publisher.calls.last, startsWith('writeReport'));
        expect(cubit.state.status, ReportLinkStatus.publishing);

        gate.complete();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(linkShare.shared, hasLength(1));
        await cubit.close();
      });

      test('ignores the end of an earlier run of the same job', () async {
        await queue.start();
        final reportGate = Completer<void>();
        publisher.gates['writeReport'] = reportGate;
        await queue.publishVisit(visitId);
        await pumpEventQueue();
        final enqueueGate = Completer<void>();
        publishing.enqueueGate = enqueueGate;
        final cubit = build();
        await cubit.load();

        unawaited(cubit.share());
        await pumpEventQueue();
        // The earlier run ends while the request waits, and its update belongs to the generation before the request.
        reportGate.complete();
        await pumpEventQueue();
        expect(cubit.state.status, ReportLinkStatus.publishing);
        expect(linkShare.shared, isEmpty);

        enqueueGate.complete();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(linkShare.shared, hasLength(1));
        await cubit.close();
      });

      test('follows only the generation that the request made, also when an earlier run ends first', () async {
        await queue.start();
        final pageGate = Completer<void>();
        publisher
          ..gates['writePage'] = pageGate
          ..failures['writePage'] = [const PublishException(PublishErrorKind.transient, 'offline')];
        final earlier = await queue.publishVisit(visitId);
        await pumpEventQueue();
        final enqueueGate = Completer<void>();
        publishing.beforeEnqueueGate = enqueueGate;
        final cubit = build();
        await cubit.load();
        final states = <ReportLinkState>[];
        final subscription = cubit.stream.listen(states.add);

        unawaited(cubit.share());
        await pumpEventQueue();
        // The earlier run fails before the request restarts the job, and its update names the job of the request in
        // the generation before it.
        pageGate.complete();
        await pumpEventQueue();
        expect(publishing.jobs[earlier.id]!.nextAttemptAt, isNotNull);

        enqueueGate.complete();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(states.map((state) => state.status), isNot(contains(ReportLinkStatus.waitingForRetry)));
        expect(linkShare.shared, hasLength(1));
        await subscription.cancel();
        await cubit.close();
      });

      test('opens no share sheet when the screen may not open one, and the next share publishes again', () async {
        final cubit = build();
        await cubit.load();

        await cubit.share(mayOpenShareSheet: () => false);
        await until(cubit, (state) => state.status == ReportLinkStatus.published);
        expect(cubit.state.canShare, isTrue);
        expect(linkShare.shared, isEmpty);

        await cubit.share(mayOpenShareSheet: () => true);
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(linkShare.shared, hasLength(1));
        expect(publisher.calls.where((call) => call.startsWith('writeReport')), hasLength(2));
        await cubit.close();
      });

      test('fails and reports the error when the visit is not in storage', () async {
        final cubit = build(id: 'visit-unknown');
        await cubit.load();

        await cubit.share();

        expect(cubit.state, const ReportLinkState(status: ReportLinkStatus.failed, isFirstShare: true));
        expect(observer.errors.single, isA<ArgumentError>());
        expect(linkShare.shared, isEmpty);
        await cubit.close();
      });

      test('reports a share sheet that did not open, and a later share opens it', () async {
        final share = FakeLinkShare()..failure = const ReportShareException();
        final cubit = build(share: share);
        await cubit.load();

        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.shareFailed);
        expect(cubit.state.canShare, isTrue);
        expect(observer.errors.single, isA<ReportShareException>());

        share.failure = null;
        await cubit.share();
        await until(cubit, (state) => state.status == ReportLinkStatus.ready);

        expect(share.shared, hasLength(1));
        await cubit.close();
      });

      test('opens no share sheet after the screen closed', () async {
        final gate = Completer<void>();
        publisher.gates['writeReport'] = gate;
        final cubit = build();
        await cubit.load();

        await cubit.share();
        await cubit.close();
        gate.complete();
        await pumpEventQueue();

        expect(publisher.reports, hasLength(1));
        expect(linkShare.shared, isEmpty);
      });
    });

    test('a state names its status, whether the share is the first one, and the reason of a stop', () {
      const state = ReportLinkState(
        status: ReportLinkStatus.failed,
        isFirstShare: true,
        failure: PublishFailure.refused,
      );

      expect(state.toString(), 'ReportLinkState(failed, true, refused)');
      expect(
        state.hashCode,
        const ReportLinkState(
          status: ReportLinkStatus.failed,
          isFirstShare: true,
          failure: PublishFailure.refused,
        ).hashCode,
      );
      expect(state, isNot(const ReportLinkState(status: ReportLinkStatus.failed, isFirstShare: true)));
    });
  });
}
