import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/cubit/still_camera_cubit.dart';

void main() {
  test('state identity includes status, successful observation and failure', () {
    final photo = ObservedCameraPhoto(path: '/cache/photo.jpg', capturedAt: DateTime.utc(2026, 10, 7));
    const failure = PhotoCaptureException();
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
