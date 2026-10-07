import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:mocktail/mocktail.dart';

class _MockImagePicker extends Mock implements ImagePicker;

void main() {
  late ImagePicker picker;

  When<Future<XFile?>> pickImage() => when(
    () => picker.pickImage(
      source: any(named: 'source'),
      maxWidth: any(named: 'maxWidth'),
      maxHeight: any(named: 'maxHeight'),
      imageQuality: any(named: 'imageQuality'),
    ),
  );

  Future<PhotoCaptureException> failureOf(Object thrown) async {
    pickImage().thenThrow(thrown);
    try {
      await ImagePickerPhotoCapture(picker: picker).takePhoto();
    } on PhotoCaptureException catch (exception) {
      return exception;
    }
    fail('The capture did not fail');
  }

  setUpAll(() => registerFallbackValue(ImageSource.gallery));

  setUp(() => picker = _MockImagePicker());

  group('ImagePickerPhotoCapture', () {
    test('selects a single gallery photo without requesting full metadata', () async {
      when(
        () => picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          requestFullMetadata: false,
        ),
      ).thenAnswer((_) async => XFile('/cache/gallery.png'));
      expect(await ImagePickerPhotoCapture(picker: picker).selectGalleryPhoto(), '/cache/gallery.png');
    });

    test('gallery cancellation gives no photo and a picker failure is reported', () async {
      when(
        () => picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          requestFullMetadata: false,
        ),
      ).thenAnswer((_) async => null);
      final capture = ImagePickerPhotoCapture(picker: picker);
      expect(await capture.selectGalleryPhoto(), isNull);
      when(
        () => picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          requestFullMetadata: false,
        ),
      ).thenThrow(PlatformException(code: 'photo_access_denied'));
      await expectLater(capture.selectGalleryPhoto(), throwsA(isA<PhotoCaptureException>()));
    });
    test('limits each edge of a photo to 1600 pixels and sets the JPEG quality to 80', () {
      expect(ImagePickerPhotoCapture.maxEdge, 1600);
      expect(ImagePickerPhotoCapture.quality, 80);
    });

    test('opens the camera with the size limit and the quality, and gives the path of the photo', () async {
      pickImage().thenAnswer((_) async => XFile('/cache/scaled_photo.jpg'));

      final path = await ImagePickerPhotoCapture(picker: picker).takePhoto();

      expect(path, '/cache/scaled_photo.jpg');
      verify(
        () => picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 80),
      ).called(1);
    });

    test('gives null when the person closes the camera without a photo', () async {
      pickImage().thenAnswer((_) async => null);

      expect(await ImagePickerPhotoCapture(picker: picker).takePhoto(), isNull);
    });

    test('reports a camera that the person did not allow as denied access', () async {
      final denied = PlatformException(code: 'camera_access_denied');

      final exception = await failureOf(denied);

      expect(exception.isAccessDenied, isTrue);
      expect(exception.cause, same(denied));
    });

    test('reports a camera that the phone does not let the person use as denied access', () async {
      // iOS reports this code when a restriction, such as Screen Time, blocks the camera. Another try cannot work.
      final restricted = PlatformException(code: 'camera_access_restricted');

      final exception = await failureOf(restricted);

      expect(exception.isAccessDenied, isTrue);
      expect(exception.cause, same(restricted));
    });

    test('reports another failure of the platform as a failed capture without denied access', () async {
      final noCamera = PlatformException(code: 'no_available_camera');

      final exception = await failureOf(noCamera);

      expect(exception.isAccessDenied, isFalse);
      expect(exception.cause, same(noCamera));
    });

    test('reports the Error of a platform without a camera implementation as a failed capture', () async {
      final unsupported = StateError('This implementation requires a camera delegate');

      final exception = await failureOf(unsupported);

      expect(exception.isAccessDenied, isFalse);
      expect(exception.cause, same(unsupported));
    });

    group('retrieveLostPhoto', () {
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('keeps lost photos on Android', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        expect(ImagePickerPhotoCapture(picker: picker).keepsLostPhotos, isTrue);
      });

      test('gives the file of the lost photo on Android', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        when(picker.retrieveLostData).thenAnswer(
          (_) async => LostDataResponse(file: XFile('/cache/scaled_lost.jpg'), type: RetrieveType.image),
        );

        expect(await ImagePickerPhotoCapture(picker: picker).retrieveLostPhoto(), '/cache/scaled_lost.jpg');
        verify(picker.retrieveLostData).called(1);
      });

      test('gives null on Android when the camera keeps no lost answer, as after a cancel', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        when(picker.retrieveLostData).thenAnswer((_) async => LostDataResponse.empty());

        expect(await ImagePickerPhotoCapture(picker: picker).retrieveLostPhoto(), isNull);
      });

      // `image_picker_android` 0.8.13+23 gives an empty response for a lost failure, so this response does not come
      // from the plugin version in the lock file. The test keeps the adapter safe for one that sends it.
      test('gives null on Android for a response that holds a failure of the camera and no file', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        when(picker.retrieveLostData).thenAnswer(
          (_) async => LostDataResponse(
            exception: PlatformException(code: 'no_available_camera'),
            type: RetrieveType.image,
          ),
        );

        expect(await ImagePickerPhotoCapture(picker: picker).retrieveLostPhoto(), isNull);
      });

      test('reports a picker that cannot be asked as a failed capture', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final noActivity = PlatformException(code: 'no_activity');
        when(picker.retrieveLostData).thenThrow(noActivity);

        await expectLater(
          ImagePickerPhotoCapture(picker: picker).retrieveLostPhoto(),
          throwsA(isA<PhotoCaptureException>().having((exception) => exception.cause, 'cause', same(noActivity))),
        );
      });

      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        test('keeps no lost photo on ${platform.name}, and gives null without asking the picker', () async {
          debugDefaultTargetPlatformOverride = platform;

          expect(ImagePickerPhotoCapture(picker: picker).keepsLostPhotos, isFalse);
          expect(await ImagePickerPhotoCapture(picker: picker).retrieveLostPhoto(), isNull);
          verifyNever(picker.retrieveLostData);
        });
      }
    });
  });
}
