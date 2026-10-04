import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/bootstrap.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/helpers.dart';

class _RecordingObserver extends AppBlocObserver {
  final changes = <Change<dynamic>>[];
  final errors = <Object>[];

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    changes.add(change);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    errors.add(error);
  }
}

/// Runs [body] and then puts back the globals that `bootstrap` replaces.
///
/// The test binding fails a test that leaves `FlutterError.onError` changed, so the handler must be back before the
/// test body returns.
Future<void> _keepingGlobals(Future<void> Function() body) async {
  final onError = FlutterError.onError;
  final observer = Bloc.observer;
  try {
    await body();
  } finally {
    FlutterError.onError = onError;
    Bloc.observer = observer;
  }
}

/// Lets `bootstrap` reach its next wait, then draws a frame.
///
/// The test binding runs the microtask queue inside `runApp`. A test body that awaits only fake-async futures keeps
/// running inside that call, so `bootstrap` does not get past the `runApp` call that showed the screen under test.
/// A wait on the real event loop lets that call return. `runApp` outside a test does not run the queue.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {});
  await tester.pump();
}

/// A network monitor that fails when the queue listens to it.
class _BrokenNetworkMonitor implements NetworkMonitor {
  @override
  Stream<void> get restored => throw StateError('no plugin');
}

/// The builder of the entry points.
App _app(
  Repositories repositories,
  Identity identity,
  Entitlements entitlements,
  PublishQueue publishQueue,
  LostCaptureRecovery? recovery,
) => App(
  repositories: repositories,
  identity: identity,
  entitlements: entitlements,
  publishQueue: publishQueue,
  recovery: recovery,
);

void main() {
  group('AppBlocObserver', () {
    test('passes each change and each error of a bloc on', () async {
      final previous = Bloc.observer;
      final observer = _RecordingObserver();
      Bloc.observer = observer;
      addTearDown(() => Bloc.observer = previous);
      final cubit = TestCubit();
      addTearDown(cubit.close);

      cubit
        ..change()
        ..fail();

      expect(observer.changes.single.nextState, 1);
      expect(observer.errors.single, isStateError);
    });
  });

  group('bootstrap', () {
    testWidgets('opens the repositories and runs the app that the builder makes from them', (tester) async {
      await _keepingGlobals(() async {
        final repositories = mockRepositories();

        await bootstrap(
          _app,
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: FakeNetworkMonitor(),
          identity: FakeIdentity(),
          openRepositories: () async => repositories,
        );
        await tester.pump();

        expect(tester.widget<App>(find.byType(App)).repositories, same(repositories));
        expect(find.byType(StartupFailureApp), findsNothing);
      });
    });

    testWidgets('asks the identity for the user ID once and gives the identity to the builder', (tester) async {
      await _keepingGlobals(() async {
        final identity = FakeIdentity(userId: 'user-1');

        await bootstrap(
          _app,
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: FakeNetworkMonitor(),
          identity: identity,
          openRepositories: () async => mockRepositories(),
        );
        await tester.pump();

        expect(identity.calls, 1);
        expect(tester.widget<App>(find.byType(App)).identity, same(identity));
        expect(tester.element(find.byType(ClientListPage)).read<Identity>(), same(identity));
      });
    });

    testWidgets('gives the entitlements to the builder and does not ask them for the plan', (tester) async {
      await _keepingGlobals(() async {
        final entitlements = FakeEntitlements(plan: Plan.pro);
        Entitlements? built;

        await bootstrap(
          (repositories, identity, given, publishQueue, recovery) {
            built = given;
            return _app(repositories, identity, given, publishQueue, recovery);
          },
          identity: FakeIdentity(userId: 'user-1'),
          entitlements: entitlements,
          publisher: const UnavailablePublisher(),
          networkMonitor: FakeNetworkMonitor(),
          openRepositories: () async => mockRepositories(),
        );
        await _settle(tester);

        expect(built, same(entitlements));
        expect(tester.element(find.byType(ClientListPage)).read<Entitlements>(), same(entitlements));
        // A call would configure RevenueCat in the production flavor, and nothing in this build may do that yet.
        expect(entitlements.calls, 0);
      });
    });

    testWidgets('opens the app while the identity is unavailable', (tester) async {
      await _keepingGlobals(() async {
        final identity = FakeIdentity();

        await bootstrap(
          _app,
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: FakeNetworkMonitor(),
          identity: identity,
          openRepositories: () async => mockRepositories(),
        );
        await tester.pump();

        expect(identity.calls, 1);
        expect(find.byType(ClientListPage), findsOneWidget);
      });
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', Exception('sign-in failed')),
      ('an error', StateError('no Firebase app')),
    ]) {
      testWidgets('opens the app when the identity throws $kind', (tester) async {
        await _keepingGlobals(() async {
          final identity = FakeIdentity()..failure = failure;

          await bootstrap(
            _app,
            entitlements: FakeEntitlements(),
            publisher: const UnavailablePublisher(),
            networkMonitor: FakeNetworkMonitor(),
            identity: identity,
            openRepositories: () async => mockRepositories(),
          );
          await _settle(tester);

          expect(identity.calls, 1);
          expect(find.byType(ClientListPage), findsOneWidget);
          // A failure that `bootstrap` did not catch would reach the zone of the test and fail it here.
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('opens the app while the sign-in of the identity is on its way', (tester) async {
      await _keepingGlobals(() async {
        final identity = FakeIdentity()..gate = Completer<void>();

        // A `bootstrap` that waited for the sign-in would never answer, so the test does not wait for it either.
        unawaited(
          bootstrap(
            _app,
            entitlements: FakeEntitlements(),
            publisher: const UnavailablePublisher(),
            networkMonitor: FakeNetworkMonitor(),
            identity: identity,
            openRepositories: () async => mockRepositories(),
          ),
        );
        await _settle(tester);

        expect(identity.calls, 1);
        expect(find.byType(ClientListPage), findsOneWidget);
      });
    });

    testWidgets('starts the publish queue on the opened repositories', (tester) async {
      await _keepingGlobals(() async {
        final repositories = mockRepositories();
        final network = FakeNetworkMonitor();

        await bootstrap(
          _app,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: network,
          openRepositories: () async => repositories,
        );
        await _settle(tester);

        // The queue listens for the return of the network and reads the jobs that an earlier launch left.
        expect(network.hasListener, isTrue);
        verify(repositories.publishing.clearRetryDelays).called(1);
        verify(repositories.publishing.pendingJobs).called(greaterThanOrEqualTo(1));
      });
    });

    testWidgets('gives the builder the one publish queue, with the publisher of the flavor', (tester) async {
      await _keepingGlobals(() async {
        final publishers = [FakePublisher(), FakePublisher()..isAvailable = false];
        final queues = <PublishQueue>[];

        for (final publisher in publishers) {
          await bootstrap(
            (repositories, identity, entitlements, publishQueue, recovery) {
              queues.add(publishQueue);
              return _app(repositories, identity, entitlements, publishQueue, recovery);
            },
            identity: FakeIdentity(),
            entitlements: FakeEntitlements(),
            publisher: publisher,
            networkMonitor: FakeNetworkMonitor(),
            openRepositories: () async => mockRepositories(),
          );
          await _settle(tester);
        }

        expect([for (final queue in queues) queue.isAvailable], [isTrue, isFalse]);
        expect(tester.element(find.byType(ClientListPage)).read<PublishQueue>(), same(queues.last));
      });
    });

    testWidgets('opens the app when the publish queue does not start', (tester) async {
      await _keepingGlobals(() async {
        await bootstrap(
          _app,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: _BrokenNetworkMonitor(),
          openRepositories: () async => mockRepositories(),
        );
        await _settle(tester);

        expect(find.byType(ClientListPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('installs the bloc observer and an error handler that reports without throwing', (tester) async {
      await _keepingGlobals(() async {
        await bootstrap(
          _app,
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: FakeNetworkMonitor(),
          identity: FakeIdentity(),
          openRepositories: () async => mockRepositories(),
        );
        await tester.pump();

        expect(Bloc.observer, isA<AppBlocObserver>());
        expect(
          () => FlutterError.onError!(FlutterErrorDetails(exception: StateError('failed'), stack: StackTrace.current)),
          returnsNormally,
        );
      });
    });

    testWidgets('shows the failure screen while the database does not open, and opens it again on retry', (
      tester,
    ) async {
      await _keepingGlobals(() async {
        final repositories = mockRepositories();
        final identity = FakeIdentity();
        final failures = <Object>[StateError('databaseFactory not initialized'), Exception('open failed')];
        var attempts = 0;
        var builds = 0;
        Future<Repositories> open() async {
          attempts++;
          if (failures.isNotEmpty) Error.throwWithStackTrace(failures.removeAt(0), StackTrace.current);
          return repositories;
        }

        unawaited(
          bootstrap(
            (opened, identity, entitlements, publishQueue, _) {
              builds++;
              return App(
                repositories: opened,
                identity: identity,
                entitlements: entitlements,
                publishQueue: publishQueue,
              );
            },
            identity: identity,
            entitlements: FakeEntitlements(),
            publisher: const UnavailablePublisher(),
            networkMonitor: FakeNetworkMonitor(),
            openRepositories: open,
          ),
        );
        await _settle(tester);

        expect(find.byType(StartupFailureApp), findsOneWidget);
        expect(find.text("Can't open your saved records. Try again."), findsOneWidget);
        expect((attempts, builds), (1, 0));
        // The sign-in does not wait for the database, so it started while the failure screen is up.
        expect(identity.calls, 1);

        await tester.tap(find.byType(FilledButton));
        await _settle(tester);

        expect(find.byType(StartupFailureApp), findsOneWidget);
        expect((attempts, builds), (2, 0));

        await tester.tap(find.byType(FilledButton));
        await _settle(tester);

        expect(find.byType(StartupFailureApp), findsNothing);
        expect(tester.widget<App>(find.byType(App)).repositories, same(repositories));
        expect((attempts, builds), (3, 1));
        // A retry opens the database again and does not ask the identity again.
        expect(identity.calls, 1);
      });
    });

    group('a capture whose answer the app lost', () {
      const lost = OpenCapture(visitId: 'visit-1', zoneId: 'zone-1', slot: PhotoSlot.after);
      final visit = Visit(
        id: 'visit-1',
        clientId: 'client-1',
        visitDate: VisitDate(2026, 10, 2),
        createdAt: DateTime.utc(2026, 10, 2, 1),
        zoneRecords: [ZoneRecord(zoneId: 'zone-1', zoneName: '로비')],
      );

      late FakeVisitRepository visits;
      late FakeOpenCaptureRepository openCaptures;
      late FakePhotoCapture photoCapture;
      late FakePhotoStore photoStore;

      setUp(() {
        visits = FakeVisitRepository(visits: [visit]);
        openCaptures = FakeOpenCaptureRepository(capture: lost);
        photoCapture = FakePhotoCapture()..lostPhoto = '/cache/lost.jpg';
        photoStore = FakePhotoStore();
      });

      Future<void> start() {
        final mocks = mockRepositories();
        return bootstrap(
          _app,
          identity: FakeIdentity(),
          entitlements: FakeEntitlements(),
          publisher: const UnavailablePublisher(),
          networkMonitor: FakeNetworkMonitor(),
          photoCapture: photoCapture,
          photoStore: photoStore,
          openRepositories: () async => Repositories(
            // The visit screen that the recovery opens reads the client of the visit.
            clients: FakeClientRepository(),
            visits: visits,
            companyProfile: mocks.companyProfile,
            publishing: mocks.publishing,
            openCaptures: openCaptures,
            localData: FakeLocalDataRepository(),
          ),
        );
      }

      testWidgets('puts the photo into its slot and gives the builder the recovery, which opens its visit', (
        tester,
      ) async {
        await _keepingGlobals(() async {
          await start();
          await _settle(tester);

          final recovery = tester.widget<App>(find.byType(App)).recovery;
          expect(recovery?.visitId, 'visit-1');
          expect(recovery?.isRecovered, isTrue);
          expect(tester.widget<VisitCapturePage>(find.byType(VisitCapturePage)).recovery, same(recovery));
          // The start of the app names the file with a random identifier.
          final recoveredPhoto = photoStore.sources.keys.single;
          expect(photoStore.sources.values, ['/cache/lost.jpg']);
          expect(
            await visits.visitById('visit-1'),
            visit.withRecord(visit.zoneRecords.single.withPhoto(PhotoSlot.after, recoveredPhoto)),
          );
          expect(openCaptures.capture, isNull);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('gives the builder the failure, which opens its visit, when the photo did not reach the visit', (
        tester,
      ) async {
        await _keepingGlobals(() async {
          final diskFull = Exception('disk full');
          photoStore.saveFailure = diskFull;

          await start();
          await _settle(tester);

          final recovery = tester.widget<App>(find.byType(App)).recovery;
          expect(recovery?.visitId, 'visit-1');
          expect(recovery?.failure, same(diskFull));
          expect(find.byType(VisitCapturePage), findsOneWidget);
          expect(await visits.visitById('visit-1'), visit);
          expect(openCaptures.capture, isNull);
        });
      });

      testWidgets('opens the client list, and keeps the stored capture, when the camera cannot be asked', (
        tester,
      ) async {
        await _keepingGlobals(() async {
          photoCapture.lostPhoto = const PhotoCaptureException(cause: 'no_activity');

          await start();
          await _settle(tester);

          expect(find.byType(ClientListPage), findsOneWidget);
          expect(find.byType(VisitCapturePage), findsNothing);
          expect(tester.widget<App>(find.byType(App)).recovery, isNull);
          expect(openCaptures.capture, lost);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('opens the client list, and removes the stored capture, where the camera keeps no lost photo', (
        tester,
      ) async {
        await _keepingGlobals(() async {
          photoCapture.keepsLostPhotos = false;

          await start();
          await _settle(tester);

          expect(find.byType(ClientListPage), findsOneWidget);
          expect(find.byType(VisitCapturePage), findsNothing);
          expect(photoCapture.lostPhotoCalls, 0);
          expect(openCaptures.capture, isNull);
        });
      });
    });

    testWidgets('opens the database once when the retry control is pressed twice', (tester) async {
      await _keepingGlobals(() async {
        final opening = Completer<Repositories>();
        var attempts = 0;
        Future<Repositories> open() {
          attempts++;
          return attempts == 1 ? Future.error(Exception('open failed')) : opening.future;
        }

        unawaited(
          bootstrap(
            _app,
            entitlements: FakeEntitlements(),
            publisher: const UnavailablePublisher(),
            networkMonitor: FakeNetworkMonitor(),
            identity: FakeIdentity(),
            openRepositories: open,
          ),
        );
        await _settle(tester);
        // The handler that `bootstrap` installed only logs, so a failure inside the retry control would stay unseen.
        final reported = <Object>[];
        FlutterError.onError = (details) => reported.add(details.exception);

        await tester.tap(find.byType(FilledButton));
        await _settle(tester);
        await tester.tap(find.byType(FilledButton));
        await _settle(tester);

        expect(attempts, 2);
        expect(reported, isEmpty);

        opening.complete(mockRepositories());
        await _settle(tester);

        expect(find.byType(App), findsOneWidget);
      });
    });
  });
}
