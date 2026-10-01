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
  });
}
