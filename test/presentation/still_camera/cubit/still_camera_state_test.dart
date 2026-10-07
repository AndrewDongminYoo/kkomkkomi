// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/cubit/still_camera_cubit.dart';

void main() {
  final photo = ObservedCameraPhoto(path: '/cache/photo.jpg', capturedAt: DateTime.utc(2026, 10, 7));
  const failure = PhotoCaptureException();

  test('copyWith preserves every field when arguments are omitted', () {
    for (final state in [
      const StillCameraState(),
      StillCameraState(status: StillCameraStatus.complete, photo: photo),
      const StillCameraState(status: StillCameraStatus.complete, failure: failure),
    ]) {
      expect(state.copyWith(), state);
    }
  });

  test('copyWith treats explicit null arguments as keeping the existing values', () {
    for (final state in [
      StillCameraState(status: StillCameraStatus.complete, photo: photo),
      const StillCameraState(status: StillCameraStatus.complete, failure: failure),
    ]) {
      // Explicit null arguments intentionally exercise the documented retention contract.
      // ignore: avoid_redundant_argument_values
      expect(state.copyWith(status: null, photo: null, failure: null), state);
    }
  });

  test('copyWith changes only the status when photo and failure are omitted', () {
    for (final state in [
      StillCameraState(status: StillCameraStatus.complete, photo: photo),
      const StillCameraState(status: StillCameraStatus.complete, failure: failure),
    ]) {
      final changed = state.copyWith(status: StillCameraStatus.suspended);
      expect(changed.status, StillCameraStatus.suspended);
      expect(changed.photo, same(state.photo));
      expect(changed.failure, same(state.failure));
      expect(state.status, StillCameraStatus.complete);
    }
  });

  test('copyWith replaces the photo without changing the source state or other fields', () {
    final replacement = ObservedCameraPhoto(path: '/cache/replacement.jpg', capturedAt: DateTime.utc(2026, 10, 8));
    final state = StillCameraState(status: StillCameraStatus.complete, photo: photo);
    final changed = state.copyWith(photo: replacement);
    expect(changed.photo, same(replacement));
    expect(changed.status, StillCameraStatus.complete);
    expect(changed.failure, isNull);
    expect(state.photo, same(photo));
  });

  test('copyWith replaces the failure without changing the source state or other fields', () {
    const replacement = PhotoCaptureException(isAccessDenied: true);
    const state = StillCameraState(status: StillCameraStatus.complete, failure: failure);
    final changed = state.copyWith(failure: replacement);
    expect(changed.failure, same(replacement));
    expect(changed.status, StillCameraStatus.complete);
    expect(changed.photo, isNull);
    expect(state.failure, same(failure));
  });

  test('state identity includes status, successful observation and failure', () {
    final complete = StillCameraState(status: StillCameraStatus.complete, photo: photo);
    final same = StillCameraState(status: StillCameraStatus.complete, photo: photo);
    final states = {
      complete,
      same,
      const StillCameraState(),
      const StillCameraState(status: StillCameraStatus.complete, failure: failure),
    };
    expect(states, hasLength(3));
    expect(complete, same);
    expect(complete == Object(), isFalse);
  });
}
