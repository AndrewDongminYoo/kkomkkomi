import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
      picker: FakePhotoCapture(),
    );
    expect(await adapter.takeObservedPhoto(), same(observation));
    expect(await adapter.takePhoto(), '/camera.jpg');
    expect(opened, 2);
  });

  test('returns no observation on cancellation', () async {
    final adapter = InAppCameraPhotoCapture(openCamera: () async => null, picker: FakePhotoCapture());
    expect(await adapter.takeObservedPhoto(), isNull);
    expect(await adapter.takePhoto(), isNull);
  });

  test('preserves typed permission failures returned by the route', () async {
    const denied = PhotoCaptureException(isAccessDenied: true);
    final adapter = InAppCameraPhotoCapture(openCamera: () async => denied, picker: FakePhotoCapture());
    await expectLater(adapter.takeObservedPhoto(), throwsA(same(denied)));
  });

  test('wraps a route-launch failure and refuses an unexpected result', () async {
    final failed = InAppCameraPhotoCapture(
      openCamera: () async => throw StateError('no navigator'),
      picker: FakePhotoCapture(),
    );
    await expectLater(failed.takeObservedPhoto(), throwsA(isA<PhotoCaptureException>()));
    final unexpected = InAppCameraPhotoCapture(
      openCamera: () async => 'not an observation',
      picker: FakePhotoCapture(),
    );
    await expectLater(unexpected.takeObservedPhoto(), throwsA(isA<PhotoCaptureException>()));
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
    );
    expect(await adapter.selectGalleryPhoto(), '/gallery.jpg');
    expect(adapter.keepsLostPhotos, isTrue);
    expect(await adapter.retrieveLostPhoto(), '/recovered.jpg');
    picker.keepsLostPhotos = false;
    expect(adapter.keepsLostPhotos, isFalse);
    expect(opened, 0);
  });
}
