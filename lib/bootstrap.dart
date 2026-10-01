import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/persistence/persistence.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

class AppBlocObserver extends BlocObserver {
  const new();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

/// Opens the database, then runs the app that [builder] makes from the repositories, [identity], and the publish
/// queue.
///
/// While the database does not open, the app shows a [StartupFailureApp], and its retry control opens the database
/// again.
///
/// [identity] is asked for the user ID once, which starts the sign-in of a flavor that has one. The app does not
/// wait for the answer, and it opens also when [identity] fails.
///
/// When the database is open, a [PublishQueue] with [publisher] starts and runs the publish jobs that an earlier
/// launch left. It is the one queue of the app, and [builder] gets it for the screens: a second queue on the same
/// database would run the same job at the same time. [networkMonitor] and [photoStore] replace the adapters of the
/// device in a test.
Future<void> bootstrap(
  FutureOr<Widget> Function(Repositories repositories, Identity identity, PublishQueue publishQueue) builder, {
  required Identity identity,
  required Publisher publisher,
  Future<Repositories> Function() openRepositories = openDeviceRepositories,
  NetworkMonitor networkMonitor = const ConnectivityNetworkMonitor(),
  PhotoStore photoStore = const DocumentsPhotoStore(),
}) async {
  // The database plugin uses a platform channel before `runApp` creates the binding.
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  // Add cross-flavor configuration here

  // A sign-in needs the network, and a field network can keep it waiting, so the first screen does not wait for it.
  unawaited(_startIdentity(identity));

  final repositories = await _openUntilSuccess(openRepositories);
  final publishQueue = PublishQueue(
    repository: repositories.publishing,
    clients: repositories.clients,
    visits: repositories.visits,
    companyProfile: repositories.companyProfile,
    photoStore: photoStore,
    publisher: publisher,
    identity: identity,
    networkMonitor: networkMonitor,
    idGenerator: const RandomIdGenerator(),
    clock: const SystemClock(),
  );
  unawaited(_startPublishing(publishQueue));

  runApp(await builder(repositories, identity, publishQueue));
}

Future<void> _startPublishing(PublishQueue queue) async {
  try {
    await queue.start();
  } on Object catch (error, stackTrace) {
    // The queue logs the failures of its jobs itself. A failure here must not close the app either.
    log('The publish queue did not start: $error', stackTrace: stackTrace);
  }
}

Future<void> _startIdentity(Identity identity) async {
  try {
    await identity.currentUserId();
  } on Object catch (error, stackTrace) {
    // The port says that the call does not throw. An adapter that breaks that rule must not close the app, and a
    // plugin can fail with an Error, so the clause catches every object.
    log('Identity did not start: $error', stackTrace: stackTrace);
  }
}

Future<Repositories> _openUntilSuccess(Future<Repositories> Function() openRepositories) async {
  while (true) {
    try {
      return await openRepositories();
    } on Object catch (error, stackTrace) {
      // An unsupported platform fails with an Error and a broken file fails with an Exception, and both must reach
      // the failure screen, so the clause catches every object.
      log('The database did not open: $error', stackTrace: stackTrace);
      final retry = Completer<void>();
      runApp(
        StartupFailureApp(
          onRetry: () {
            // A second press while the database opens again changes nothing.
            if (!retry.isCompleted) retry.complete();
          },
        ),
      );
      await retry.future;
    }
  }
}
