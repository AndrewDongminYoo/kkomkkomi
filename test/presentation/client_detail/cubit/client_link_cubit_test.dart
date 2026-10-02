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

void main() {
  const clientId = 'client-1';
  final client = Client(id: clientId, name: '행복빌딩', createdAt: DateTime.utc(2026, 9));
  final visit = Visit(
    id: 'visit-1',
    clientId: clientId,
    visitDate: VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 1),
    zoneRecords: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비', note: '바닥 왁스')],
  );
  const refused = PublishException(PublishErrorKind.refused, 'The rules refused the write');

  late FakePublishRepository publishing;
  late FakePublisher publisher;
  late PublishQueue queue;
  late _ErrorObserver observer;
  late BlocObserver previousObserver;

  setUp(() {
    publishing = FakePublishRepository();
    publisher = FakePublisher();
    queue = publishQueueOf(
      Repositories(
        clients: FakeClientRepository(clients: [client]),
        visits: FakeVisitRepository(visits: [visit]),
        companyProfile: FakeCompanyProfileRepository(profile: CompanyProfile(name: '깔끔클린')),
        publishing: publishing,
        openCaptures: FakeOpenCaptureRepository(),
        localData: FakeLocalDataRepository(),
      ),
      publisher: publisher,
    );
    previousObserver = Bloc.observer;
    observer = _ErrorObserver();
    Bloc.observer = observer;
  });

  tearDown(() async {
    Bloc.observer = previousObserver;
    await queue.dispose();
  });

  ClientLinkCubit build() => ClientLinkCubit(clientId: clientId, publishQueue: queue);

  /// Publishes the visit, which gives the client its open link, and waits for the job.
  Future<void> publish() async {
    await queue.publishVisit(visit.id);
    await pumpEventQueue();
  }

  /// A cubit that loaded the link of a client whose visit is published.
  Future<ClientLinkCubit> loadedWithOpenLink() async {
    await publish();
    final cubit = build();
    await cubit.load();
    expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, hasOpenLink: true));
    return cubit;
  }

  group('ClientLinkCubit', () {
    group('load', () {
      test('shows nothing about links in a flavor without a backend', () async {
        publisher.isAvailable = false;
        publishing.failure = Exception('not read');
        final cubit = build();

        await cubit.load();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.unavailable));
        expect(cubit.state.takesAction, isFalse);
        expect(observer.errors, isEmpty);
        await cubit.close();
      });

      test('says that the client has no link before its first publish', () async {
        final cubit = build();

        await cubit.load();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready));
        expect(cubit.state.takesAction, isTrue);
        await cubit.close();
      });

      test('says that the client has an open link after a publish', () async {
        final cubit = await loadedWithOpenLink();
        await cubit.close();
      });

      test('fails when storage does not answer, and reads the link again on retry', () async {
        publishing.failure = Exception('storage failed');
        final cubit = build();

        await cubit.load();
        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.loadFailed));
        expect(cubit.state.takesAction, isFalse);
        expect(observer.errors, [publishing.failure]);

        publishing.failure = null;
        final states = <ClientLinkState>[];
        final subscription = cubit.stream.listen(states.add);
        await cubit.load();
        await pumpEventQueue();

        expect(states, [const ClientLinkState(), const ClientLinkState(status: ClientLinkStatus.ready)]);
        await subscription.cancel();
        await cubit.close();
      });

      test('shows the link that a publish gives the client while the screen is open', () async {
        final cubit = build();
        await cubit.load();

        await publish();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, hasOpenLink: true));
        await cubit.close();
      });

      test('shows no older data from a read that a later read overtook', () async {
        final cubit = build();
        final gate = publishing.pagesGate = Completer<void>();
        // The first read finds no open link, and then waits for the pages.
        final first = cubit.load();
        await pumpEventQueue();
        expect(publishing.pagesGate, isNull);

        await publish();
        await cubit.load();
        const later = ClientLinkState(status: ClientLinkStatus.ready, hasOpenLink: true);
        expect(cubit.state, later);

        gate.complete();
        await first;
        expect(cubit.state, later);
        await cubit.close();
      });
    });

    group('closeLink', () {
      test('says that the link is closing until its revoke job is done on the backend, and then closed', () async {
        final cubit = await loadedWithOpenLink();
        final gate = publisher.gates['revokePage'] = Completer<void>();
        final states = <ClientLinkState>[];
        final subscription = cubit.stream.listen(states.add);

        await cubit.closeLink();
        await pumpEventQueue();

        expect(states, [
          const ClientLinkState(status: ClientLinkStatus.requesting, hasOpenLink: true),
          const ClientLinkState(status: ClientLinkStatus.ready, isClosing: true),
        ]);
        expect(publisher.calls.last, startsWith('revokePage'));

        gate.complete();
        await pumpEventQueue();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, hasClosedLink: true));
        expect(publishing.pagesById.values.single.isRevoked, isTrue);
        await subscription.cancel();
        await cubit.close();
      });

      test('keeps the link closing while its revoke job waits to run again', () async {
        final cubit = await loadedWithOpenLink();
        publisher.failures['revokePage'] = [Exception('offline')];

        await cubit.closeLink();
        await pumpEventQueue();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, isClosing: true));
        final job = publishing.jobs.values.singleWhere((job) => job.kind == PublishJobKind.revoke);
        expect((job.status, job.attempts), (PublishJobStatus.pending, 1));
        await cubit.close();
      });

      test('says that the link did not close when its revoke job stops', () async {
        final cubit = await loadedWithOpenLink();
        publisher.failures['revokePage'] = [refused];

        await cubit.closeLink();
        await pumpEventQueue();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, hasFailedClose: true));
        await cubit.close();
      });

      test('says that the deletion of all data did not finish, and not that the close failed, when the deletion '
          'stopped the revoke job', () async {
        final cubit = await loadedWithOpenLink();
        publisher.failures['revokePage'] = [Exception('offline')];
        await cubit.closeLink();
        await pumpEventQueue();
        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, isClosing: true));

        // The deletion stops the pending revoke job and deletes the page, and a later step of it fails, so the rows
        // stay on the phone.
        await queue.hold();
        await queue.deletePublished();
        queue.release();
        await cubit.load();

        final job = publishing.jobs.values.singleWhere((job) => job.kind == PublishJobKind.revoke);
        expect((job.status, job.failure), (PublishJobStatus.failed, PublishFailure.deletion));
        expect(publisher.calls.last, startsWith('deletePage'));
        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, hasUnfinishedDeletion: true));
        await cubit.close();
      });

      test('says both when one close failed and the deletion of all data stopped another', () async {
        final cubit = await loadedWithOpenLink();
        publisher.failures['revokePage'] = [refused];
        await cubit.makeNewLink();
        await pumpEventQueue();
        publisher.failures['revokePage'] = [Exception('offline')];
        await cubit.closeLink();
        await pumpEventQueue();

        await queue.hold();
        await queue.deletePublished();
        queue.release();
        await cubit.load();

        expect(
          cubit.state,
          const ClientLinkState(status: ClientLinkStatus.ready, hasFailedClose: true, hasUnfinishedDeletion: true),
        );
        await cubit.close();
      });

      test('keeps the open link and reports the failure when storage does not take the close', () async {
        final cubit = await loadedWithOpenLink();
        publishing.revokeFailure = Exception('storage failed');

        await cubit.closeLink();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.requestFailed, hasOpenLink: true));
        expect(cubit.state.takesAction, isTrue);
        expect(observer.errors, [publishing.revokeFailure]);
        expect(publisher.calls.where((call) => call.startsWith('revokePage')), isEmpty);
        await cubit.close();
      });

      test('says that the link is closing when storage took the close and the read after it fails', () async {
        final cubit = await loadedWithOpenLink();
        final gate = publishing.revokeGate = Completer<void>();
        final closing = cubit.closeLink();
        await pumpEventQueue();
        publishing.failure = Exception('storage failed');
        gate.complete();

        await closing;
        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, isClosing: true));
        expect(observer.errors, [publishing.failure]);

        // The revoke job ends, and the read after it fails too, so the state keeps what it showed.
        await pumpEventQueue();
        expect(
          publishing.jobs.values.singleWhere((job) => job.kind == PublishJobKind.revoke).status,
          PublishJobStatus.done,
        );
        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, isClosing: true));
        expect(observer.errors, [publishing.failure, publishing.failure]);
        await cubit.close();
      });

      test('says that no link is open, and not that one is closing, when a revoke came first and the read after the '
          'close fails', () async {
        final cubit = await loadedWithOpenLink();
        final gate = publishing.revokeGate = Completer<void>();
        final closing = cubit.closeLink();
        await pumpEventQueue();
        // Another revoke closes the page while this one is on its way to storage, so this close takes no revoke job.
        final page = publishing.pagesById.values.single;
        publishing.pagesById[page.id] = page.revoke(DateTime.utc(2026, 10, 2));
        publishing.failure = Exception('storage failed');
        gate.complete();

        await closing;

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready));
        expect(publishing.jobs.values.where((job) => job.kind == PublishJobKind.revoke), isEmpty);
        expect(observer.errors, [publishing.failure]);
        await cubit.close();
      });

      test('does nothing while the client has no open link, and while a request is on its way', () async {
        final cubit = build();
        await cubit.load();

        await cubit.closeLink();
        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready));

        await publish();
        final gate = publishing.revokeGate = Completer<void>();
        final closing = cubit.closeLink();
        expect(cubit.state.status, ClientLinkStatus.requesting);
        expect(cubit.state.takesAction, isFalse);
        await cubit.makeNewLink();
        gate.complete();
        await closing;
        await pumpEventQueue();

        expect(publishing.jobs.values.where((job) => job.kind == PublishJobKind.revoke), hasLength(1));
        expect(publishing.pagesById.values.where((page) => !page.isRevoked), isEmpty);
        await cubit.close();
      });
    });

    test('a state names its status and what became of the links, and keeps them in a copy', () {
      const state = ClientLinkState(
        status: ClientLinkStatus.ready,
        hasOpenLink: true,
        isClosing: true,
        hasFailedClose: true,
        hasUnfinishedDeletion: true,
        hasClosedLink: true,
      );

      expect(
        state.toString(),
        'ClientLinkState(ready, open: true, closing: true, failed: true, deletion unfinished: true, closed: true)',
      );
      expect(state.hashCode, state.copyWith().hashCode);
      expect(state.copyWith(), state);
      expect(state.copyWith(isClosing: false), isNot(state));
      expect(state.copyWith(hasOpenLink: false).hasFailedClose, isTrue);
      expect(state.copyWith(hasOpenLink: false).hasUnfinishedDeletion, isTrue);
      expect(const ClientLinkState(hasUnfinishedDeletion: true), isNot(const ClientLinkState()));
    });

    group('makeNewLink', () {
      test('keeps an open link and says that the old link is closing until its revoke job is done', () async {
        final cubit = await loadedWithOpenLink();
        final old = publishing.pagesById.values.single;
        final gate = publisher.gates['revokePage'] = Completer<void>();

        await cubit.makeNewLink();
        await pumpEventQueue();

        expect(cubit.state, const ClientLinkState(status: ClientLinkStatus.ready, hasOpenLink: true, isClosing: true));

        gate.complete();
        await pumpEventQueue();

        expect(
          cubit.state,
          const ClientLinkState(status: ClientLinkStatus.ready, hasOpenLink: true, hasClosedLink: true),
        );
        final replacement = publishing.pagesById.values.singleWhere((page) => !page.isRevoked);
        expect(replacement.id, isNot(old.id));
        expect(publisher.reports.keys, contains('${replacement.id}/${visit.id}'));
        await cubit.close();
      });
    });
  });
}
