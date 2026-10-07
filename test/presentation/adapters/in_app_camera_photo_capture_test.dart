// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/adapters/in_app_camera_photo_capture.dart';

import '../../helpers/helpers.dart';

void main() {
  test('rejects a competing session instead of opening a second camera route', () async {
    final gate = Completer<Object?>();
    var opened = 0;
    final adapter = InAppCameraPhotoCapture(
      openCamera: () {
        opened++;
        return gate.future;
      },
      discardPhoto: (_) async {},
      picker: FakePhotoCapture(),
    );
    final first = adapter.takeObservedPhoto();
    await expectLater(adapter.takeObservedPhoto(), throwsA(isA<PhotoCaptureException>()));
    expect(opened, 1);
    gate.complete(null);
    expect(await first, isNull);
  });
  test('returns the observed route result and uses the same route for path-only capture', () async {
    final observation = ObservedCameraPhoto(path: '/camera.jpg', capturedAt: DateTime.utc(2026, 10, 7));
    var opened = 0;
    final adapter = InAppCameraPhotoCapture(
      openCamera: () async {
        opened++;
        return observation;
      },
      discardPhoto: (_) async {},
      picker: FakePhotoCapture(),
    );
    expect(await adapter.takeObservedPhoto(), same(observation));
    expect(await adapter.takePhoto(), '/camera.jpg');
    expect(opened, 2);
  });

  test('returns no observation on cancellation', () async {
    final adapter = InAppCameraPhotoCapture(
      openCamera: () async => null,
      discardPhoto: (_) async {},
      picker: FakePhotoCapture(),
    );
    expect(await adapter.takeObservedPhoto(), isNull);
    expect(await adapter.takePhoto(), isNull);
  });

  test('preserves typed permission failures returned by the route', () async {
    const denied = PhotoCaptureException(isAccessDenied: true);
    final adapter = InAppCameraPhotoCapture(
      openCamera: () async => denied,
      discardPhoto: (_) async {},
      picker: FakePhotoCapture(),
    );
    await expectLater(adapter.takeObservedPhoto(), throwsA(same(denied)));
  });

  test('wraps a route-launch failure and refuses an unexpected result', () async {
    final failed = InAppCameraPhotoCapture(
      openCamera: () async => throw StateError('no navigator'),
      discardPhoto: (_) async {},
      picker: FakePhotoCapture(),
    );
    await expectLater(failed.takeObservedPhoto(), throwsA(isA<PhotoCaptureException>()));
    final unexpected = InAppCameraPhotoCapture(
      openCamera: () async => 'not an observation',
      discardPhoto: (_) async {},
      picker: FakePhotoCapture(),
    );
    await expectLater(unexpected.takeObservedPhoto(), throwsA(isA<PhotoCaptureException>()));
  });

  test('discards an accepted camera result once and never a borrowed or saved photo', () async {
    final removed = <String>[];
    final observation = ObservedCameraPhoto(path: '/cache/owned.jpg', capturedAt: DateTime.utc(2026, 10, 7));
    final adapter = InAppCameraPhotoCapture(
      openCamera: () async => observation,
      picker: FakePhotoCapture(),
      discardPhoto: (path) async => removed.add(path),
    );
    await adapter.takeObservedPhoto();
    await adapter.discardCameraPhoto('/documents/report.jpg');
    await adapter.discardCameraPhoto(observation.path);
    await adapter.discardCameraPhoto(observation.path);
    expect(removed, [observation.path]);
  });

  test('delegates gallery selection and lost-result recovery without opening the in-app camera', () async {
    final picker = FakePhotoCapture()
      ..results.add('/gallery.jpg')
      ..lostPhoto = '/recovered.jpg';
    var opened = 0;
    final adapter = InAppCameraPhotoCapture(
      openCamera: () async {
        opened++;
        return null;
      },
      picker: picker,
      discardPhoto: (_) async {},
    );
    expect(await adapter.selectGalleryPhoto(), '/gallery.jpg');
    expect(adapter.keepsLostPhotos, isTrue);
    expect(await adapter.retrieveLostPhoto(), '/recovered.jpg');
    picker.keepsLostPhotos = false;
    expect(adapter.keepsLostPhotos, isFalse);
    expect(opened, 0);
  });
}
