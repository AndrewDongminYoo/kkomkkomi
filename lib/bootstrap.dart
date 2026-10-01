import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/persistence/persistence.dart';

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

/// Opens the database, then runs the app that [builder] makes from the repositories.
///
/// While the database does not open, the app shows a [StartupFailureApp], and its retry control opens the database
/// again.
Future<void> bootstrap(
  FutureOr<Widget> Function(Repositories repositories) builder, {
  Future<Repositories> Function() openRepositories = openDeviceRepositories,
}) async {
  // The database plugin uses a platform channel before `runApp` creates the binding.
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  // Add cross-flavor configuration here

  runApp(await builder(await _openUntilSuccess(openRepositories)));
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
