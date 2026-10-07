import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/cubit/still_camera_cubit.dart';

import '../../../helpers/fake_still_camera.dart';

class _Clock implements Clock {
  DateTime time = DateTime.utc(2026, 10, 7, 9, 12, 30, 123, 456);
  int calls = 0;
  @override
  DateTime now() {
    calls++;
    return time;
  }
}

void main() {
  late List<FakeStillCameraDriver> drivers;
  late FakeCameraPhotoFiles files;
  late _Clock clock;
  late StillCameraCubit cubit;
  setUp(() {
    drivers = [];
    files = FakeCameraPhotoFiles();
    clock = _Clock();
    cubit = StillCameraCubit(
      driverFactory: () {
        final driver = FakeStillCameraDriver();
        drivers.add(driver);
        return driver;
      },
      files: files,
      clock: clock,
    );
  });
  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  test('does not touch hardware before start and accepts only ready captures', () async {
    await cubit.capture();
    expect(drivers, isEmpty);
    expect(clock.calls, 0);
    await cubit.start();
    await cubit.start();
    expect(drivers, hasLength(1));
    expect(cubit.state.status, StillCameraStatus.ready);
  });

  test('starting in the background waits for resume without opening hardware', () async {
    cubit.setForeground(foreground: false);
    await cubit.start();
    expect(drivers, isEmpty);
    expect(cubit.state.status, StillCameraStatus.suspended);
    cubit.setForeground(foreground: true);
    await pumpEventQueue();
    expect(drivers.single.initializations, 1);
    expect(cubit.state.status, StillCameraStatus.ready);
    expect(clock.calls, 0);
  });

  test('lifecycle disposal failure terminates without starting a replacement controller', () async {
    await cubit.start();
    drivers.single.closingFailure = StateError('controller release failed');
    cubit.setForeground(foreground: false);
    cubit.setForeground(foreground: true);
    await pumpEventQueue();
    expect(drivers, hasLength(1));
    expect(cubit.state.status, StillCameraStatus.complete);
    expect(cubit.state.failure, isA<PhotoCaptureException>());
    expect(cubit.state.photo, isNull);
  });

  test('resume while a shutter is pending rejects its old result before accepting a fresh request time', () async {
    await cubit.start();
    final old = drivers.single;
    old.picture = Completer<String>();
    final capturing = cubit.capture();
    cubit.setForeground(foreground: false);
    cubit.setForeground(foreground: true);
    await pumpEventQueue();
    expect(drivers, hasLength(2));
    expect(cubit.state.status, StillCameraStatus.loading);
    await cubit.capture();
    expect(drivers.last.captures, 0);
    old.picture!.complete('/cache/obsolete.jpg');
    await capturing;
    expect(files.discarded, ['/cache/obsolete.jpg']);
    expect(cubit.state.status, StillCameraStatus.ready);
    clock.time = clock.time.add(const Duration(minutes: 1));
    await cubit.capture();
    expect(cubit.state.photo!.capturedAt, clock.time);
    expect(clock.calls, 2);
  });

  test('observes request time once before dispatch, not delayed completion time', () async {
    await cubit.start();
    final atRequest = clock.time;
    drivers.single.picture = Completer<String>();
    drivers.single.onCapture = () => expect(clock.calls, 1);
    final capture = cubit.capture();
    expect(cubit.state.status, StillCameraStatus.capturing);
    await cubit.capture();
    expect(drivers.single.captures, 1);
    clock.time = atRequest.add(const Duration(minutes: 10));
    drivers.single.picture!.complete('/cache/raw.jpg');
    await capture;
    expect(cubit.state.photo!.capturedAt, atRequest);
    expect(cubit.state.photo!.capturedAt.isUtc, isTrue);
    expect(cubit.state.photo!.path, '/cache/normalized.jpg');
    expect(drivers.single.disposals, 1);
    expect(files.discarded, isEmpty);
  });

  test('cancelling an initialized camera returns no photo and releases exactly once', () async {
    await cubit.start();
    await cubit.cancel();
    await cubit.cancel();
    expect(cubit.state.status, StillCameraStatus.complete);
    expect(cubit.state.photo, isNull);
    expect(cubit.state.failure, isNull);
    expect(drivers.single.disposals, 1);
    cubit.setForeground(foreground: true);
    await pumpEventQueue();
    expect(drivers, hasLength(1));
  });

  test('stops exposing a live preview while a successful capture closes its controller', () async {
    await cubit.start();
    drivers.single.closing = Completer<void>();
    final capturing = cubit.capture();
    await pumpEventQueue();
    expect(cubit.state.status, StillCameraStatus.loading);
    drivers.single.closing!.complete();
    await capturing;
    expect(cubit.state.photo, isNotNull);
  });

  test('closing failure discards the new file and returns a failure instead of a saved photo', () async {
    await cubit.start();
    drivers.single.closingFailure = StateError('closing failed');
    await cubit.capture();
    expect(cubit.state.photo, isNull);
    expect(cubit.state.failure, isA<PhotoCaptureException>());
    expect(files.discarded, ['/cache/normalized.jpg']);
  });

  test('cancellation ignores a late capture file and discards only that file', () async {
    await cubit.start();
    drivers.single.picture = Completer<String>();
    final capturing = cubit.capture();
    await cubit.cancel();
    drivers.single.picture!.complete('/cache/late.jpg');
    await capturing;
    expect(cubit.state.photo, isNull);
    expect(files.normalized, isEmpty);
    expect(files.discarded, ['/cache/late.jpg']);
  });

  test('foreground loss during normalization discards the obsolete normalized file', () async {
    await cubit.start();
    files.normalization = Completer<String>();
    final capturing = cubit.capture();
    await pumpEventQueue();
    cubit.setForeground(foreground: false);
    await pumpEventQueue();
    files.normalization!.complete('/cache/obsolete.jpg');
    await capturing;
    expect(cubit.state.status, StillCameraStatus.suspended);
    expect(cubit.state.photo, isNull);
    expect(files.discarded, ['/cache/obsolete.jpg']);
    cubit.setForeground(foreground: true);
    await pumpEventQueue();
    expect(cubit.state.status, StillCameraStatus.ready);
    expect(drivers, hasLength(2));
  });

  test('first permission grant can suspend/resume before initialization answers', () async {
    await cubit.close();
    final first = FakeStillCameraDriver()..initialization = Completer<void>();
    final second = FakeStillCameraDriver();
    final pending = [first, second];
    cubit = StillCameraCubit(driverFactory: () => pending.removeAt(0), files: files, clock: clock);
    final starting = cubit.start();
    await pumpEventQueue();
    cubit.setForeground(foreground: false);
    cubit.setForeground(foreground: true);
    first.initialization!.complete();
    await starting;
    await pumpEventQueue();
    expect(first.disposals, 1);
    expect(second.initializations, 1);
    expect(cubit.state.status, StillCameraStatus.ready);
  });

  test('permission denial during inactive/resumed initialization never starts an automatic retry', () async {
    await cubit.close();
    final first = FakeStillCameraDriver()
      ..initialization = Completer<void>()
      ..initializationFailure = const PhotoCaptureException(isAccessDenied: true);
    final second = FakeStillCameraDriver();
    final pending = [first, second];
    cubit = StillCameraCubit(driverFactory: () => pending.removeAt(0), files: files, clock: clock);
    final starting = cubit.start();
    await pumpEventQueue();
    cubit.setForeground(foreground: false);
    cubit.setForeground(foreground: true);
    first.initialization!.complete();
    await starting;
    await pumpEventQueue();
    expect(second.initializations, 0);
    expect(cubit.state.status, StillCameraStatus.complete);
    expect(cubit.state.failure!.isAccessDenied, isTrue);
  });

  for (final initializationFails in [false, true]) {
    test(
      'obsolete initialization (failure: $initializationFails) with failed disposal never overlaps a new controller',
      () async {
        await cubit.close();
        final first = FakeStillCameraDriver()
          ..initialization = Completer<void>()
          ..closingFailure = StateError('old controller could not close')
          ..initializationFailure = initializationFails ? StateError('initialization failed') : null;
        final second = FakeStillCameraDriver();
        final pending = [first, second];
        cubit = StillCameraCubit(driverFactory: () => pending.removeAt(0), files: files, clock: clock);
        final starting = cubit.start();
        await pumpEventQueue();
        cubit.setForeground(foreground: false);
        cubit.setForeground(foreground: true);
        first.initialization!.complete();
        await starting;
        await pumpEventQueue();
        expect(second.initializations, 0);
        expect(cubit.state.status, StillCameraStatus.complete);
        expect(cubit.state.failure, isA<PhotoCaptureException>());
      },
    );
  }

  test('cancel during initialization never makes the late controller ready', () async {
    await cubit.close();
    final driver = FakeStillCameraDriver()..initialization = Completer<void>();
    cubit = StillCameraCubit(driverFactory: () => driver, files: files, clock: clock);
    final starting = cubit.start();
    await pumpEventQueue();
    final cancelling = cubit.cancel();
    driver.initialization!.complete();
    await Future.wait([starting, cancelling]);
    expect(cubit.state.status, StillCameraStatus.complete);
    expect(driver.disposals, 1);
    expect(clock.calls, 0);
  });

  test('resume waits for prior disposal and never replays the shutter', () async {
    await cubit.start();
    drivers.single.closing = Completer<void>();
    cubit.setForeground(foreground: false);
    await pumpEventQueue();
    cubit.setForeground(foreground: true);
    await pumpEventQueue();
    expect(drivers, hasLength(1));
    drivers.single.closing!.complete();
    await pumpEventQueue();
    expect(drivers, hasLength(2));
    expect(drivers.every((d) => d.captures == 0), isTrue);
    expect(cubit.state.status, StillCameraStatus.ready);
  });

  test('permission denial reaches a typed terminal failure', () async {
    await cubit.close();
    final driver = FakeStillCameraDriver()..initializationFailure = const PhotoCaptureException(isAccessDenied: true);
    cubit = StillCameraCubit(driverFactory: () => driver, files: files, clock: clock);
    await cubit.start();
    expect(cubit.state.failure!.isAccessDenied, isTrue);
    expect(cubit.state.photo, isNull);
    expect(driver.disposals, 1);
  });

  for (final stage in ['capture', 'normalization']) {
    test('$stage failure supplies no observation', () async {
      await cubit.start();
      if (stage == 'capture') {
        drivers.single.pictureFailure = StateError('camera failed');
      } else {
        files.failure = const FormatException('bad camera photo');
      }
      await cubit.capture();
      expect(cubit.state.photo, isNull);
      expect(cubit.state.failure, isA<PhotoCaptureException>());
      expect(cubit.state.status, StillCameraStatus.complete);
    });
  }

  test('closing a pending capture ignores its late answer without emissions', () async {
    await cubit.start();
    drivers.single.picture = Completer<String>();
    final capturing = cubit.capture();
    await cubit.close();
    drivers.single.picture!.complete('/cache/after-close.jpg');
    await capturing;
    expect(files.discarded, ['/cache/after-close.jpg']);
    expect(drivers.single.disposals, 1);
  });
}
