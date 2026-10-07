// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc/bloc.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/camera_photo_files.dart';
import 'package:kkomkkomi/presentation/still_camera/still_camera_driver.dart';

part 'still_camera_state.dart';

class StillCameraCubit extends Cubit<StillCameraState> {
  new({required this._driverFactory, required this._files, required this._clock}) : super(const StillCameraState());
  final StillCameraDriver Function() _driverFactory;
  final CameraPhotoFiles _files;
  final Clock _clock;
  StillCameraDriver? _driver;
  Future<void> _resources = Future.value();
  bool _started = false;
  bool _foreground = true;
  bool _terminal = false;
  bool _driverReady = false;
  bool _capturePending = false;
  int _generation = 0;

  /// The preview is requested only while the state says the current driver is ready.
  // Read-only access to the initialized preview resource; session mutations remain void commands.
  // ignore: prefer_void_public_cubit_methods
  StillCameraDriver get driver => _driver!;

  Future<void> start() {
    if (_started || _terminal) return _resources;
    _started = true;
    if (!_foreground) {
      _show(const StillCameraState(status: StillCameraStatus.suspended));
      return _resources;
    }
    return _enqueue(() => _initialize(_generation));
  }

  void setForeground({required bool foreground}) {
    if (_terminal || foreground == _foreground) return;
    _foreground = foreground;
    final generation = ++_generation;
    if (!_started) return;
    _show(StillCameraState(status: foreground ? StillCameraStatus.loading : StillCameraStatus.suspended));
    unawaited(
      _enqueue(() async {
        final error = await _release();
        if (error != null && !_terminal) {
          _completeFailure(error);
        } else if (foreground) {
          await _initialize(generation);
        }
      }),
    );
  }

  Future<void> _initialize(int generation) async {
    if (!_current(generation) || !_foreground) return;
    try {
      final driver = _driverFactory();
      _driver = driver;
      await driver.initialize();
      if (!_current(generation)) {
        final error = await _release();
        if (error != null && !_terminal) _completeFailure(error);
        return;
      }
      _driverReady = true;
      _showReady();
    } on Object catch (error) {
      final closingError = await _release();
      if (!_terminal) {
        final failure = _failure(error);
        // A prompt can change generations before denial; obsolete hardware errors belong to the old session.
        if (_current(generation) || failure.isAccessDenied) {
          _completeFailure(failure);
        } else if (closingError != null) {
          _completeFailure(closingError);
        }
      }
    }
  }

  void _completeFailure(Object error) {
    _terminal = true;
    ++_generation;
    _show(StillCameraState(status: StillCameraStatus.complete, failure: _failure(error)));
  }

  Future<void> capture() async {
    if (state.status != StillCameraStatus.ready || _capturePending || _terminal) return;
    final driver = _driver!;
    final generation = _generation;
    _capturePending = true;
    _show(const StillCameraState(status: StillCameraStatus.capturing));
    try {
      // Observe the accepted shutter request, with no await before dispatch. Its completion time is not evidence.
      final time = _clock.now().toUtc();
      final raw = await driver.takePicture();
      if (!_current(generation)) {
        await _files.discard(raw);
        return;
      }
      final normalized = await _files.normalize(raw);
      if (!_current(generation)) {
        await _files.discard(normalized);
        return;
      }
      await _finish(
        photo: ObservedCameraPhoto(path: normalized, capturedAt: time),
      );
    } on Object catch (error) {
      if (_current(generation)) await _finish(failure: _failure(error));
    } finally {
      _capturePending = false;
      _showReady();
    }
  }

  Future<void> cancel() async {
    if (_terminal) return;
    _terminal = true;
    ++_generation;
    _show(const StillCameraState());
    await _enqueue(() async {
      await _release();
    });
    _show(const StillCameraState(status: StillCameraStatus.complete));
  }

  Future<void> _finish({ObservedCameraPhoto? photo, PhotoCaptureException? failure}) async {
    _terminal = true;
    ++_generation;
    _show(const StillCameraState());
    Object? closingError;
    await _enqueue(() async {
      closingError = await _release();
    });
    if (closingError != null) {
      if (photo != null) await _files.discard(photo.path);
      _show(StillCameraState(status: StillCameraStatus.complete, failure: failure ?? _failure(closingError!)));
    } else {
      _show(StillCameraState(status: StillCameraStatus.complete, photo: photo, failure: failure));
    }
  }

  Future<Object?> _release() async {
    final driver = _driver;
    _driver = null;
    _driverReady = false;
    try {
      await driver?.dispose();
      return null;
    } on Object catch (error) {
      return error;
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _resources.then((_) => operation());
    _resources = next;
    return next;
  }

  bool _current(int generation) => !_terminal && !isClosed && generation == _generation;

  void _showReady() {
    if (!_terminal && _foreground && _driverReady) {
      _show(StillCameraState(status: _capturePending ? StillCameraStatus.loading : StillCameraStatus.ready));
    }
  }

  void _show(StillCameraState next) {
    if (!isClosed) emit(next);
  }

  PhotoCaptureException _failure(Object error) =>
      error is PhotoCaptureException ? error : PhotoCaptureException(cause: error);

  @override
  Future<void> close() async {
    _terminal = true;
    ++_generation;
    await _enqueue(() async {
      await _release();
    });
    await super.close();
  }
}
