import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/bootstrap.dart';
import 'package:material_ui/material_ui.dart';

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

        await bootstrap((opened) => App(repositories: opened), openRepositories: () async => repositories);
        await tester.pump();

        expect(tester.widget<App>(find.byType(App)).repositories, same(repositories));
        expect(find.byType(StartupFailureApp), findsNothing);
      });
    });

    testWidgets('installs the bloc observer and an error handler that reports without throwing', (tester) async {
      await _keepingGlobals(() async {
        await bootstrap((opened) => App(repositories: opened), openRepositories: () async => mockRepositories());
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
        final failures = <Object>[StateError('databaseFactory not initialized'), Exception('open failed')];
        var attempts = 0;
        var builds = 0;
        Future<Repositories> open() async {
          attempts++;
          if (failures.isNotEmpty) Error.throwWithStackTrace(failures.removeAt(0), StackTrace.current);
          return repositories;
        }

        unawaited(
          bootstrap((opened) {
            builds++;
            return App(repositories: opened);
          }, openRepositories: open),
        );
        await _settle(tester);

        expect(find.byType(StartupFailureApp), findsOneWidget);
        expect(find.text("Can't open your saved records. Try again."), findsOneWidget);
        expect((attempts, builds), (1, 0));

        await tester.tap(find.byType(FilledButton));
        await _settle(tester);

        expect(find.byType(StartupFailureApp), findsOneWidget);
        expect((attempts, builds), (2, 0));

        await tester.tap(find.byType(FilledButton));
        await _settle(tester);

        expect(find.byType(StartupFailureApp), findsNothing);
        expect(tester.widget<App>(find.byType(App)).repositories, same(repositories));
        expect((attempts, builds), (3, 1));
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

        unawaited(bootstrap((opened) => App(repositories: opened), openRepositories: open));
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
