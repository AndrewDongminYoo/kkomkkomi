import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kkomkkomi/application/application.dart';

/// Takes a photo with the camera app of the device through `image_picker`.
///
/// The picker makes the photo smaller before it gives the file: each edge is at most [maxEdge] pixels, and the JPEG
/// quality is [quality]. A smaller file is what the report and a later upload on a field network need.
final class ImagePickerPhotoCapture implements PhotoCapture {
  /// The `picker` argument replaces the picker of the platform in a test.
  const new({this._picker});

  /// The most pixels that the width and the height of a photo have.
  static const double maxEdge = 1600;

  /// The JPEG quality of a photo, from 0 to 100.
  static const int quality = 80;

  /// The codes with which the picker reports that the app is not allowed to use the camera: the person did not
  /// allow it, or a restriction of the phone blocks it. Another try cannot work until the setting changes.
  static const _accessDeniedCodes = {'camera_access_denied', 'camera_access_restricted'};

  final ImagePicker? _picker;

  @override
  Future<String?> takePhoto() async {
    try {
      final photo = await (_picker ?? ImagePicker()).pickImage(
        source: ImageSource.camera,
        maxWidth: maxEdge,
        maxHeight: maxEdge,
        imageQuality: quality,
      );
      return photo?.path;
    } on Object catch (error, stackTrace) {
      // The picker fails with a `PlatformException` on a phone and with an `Error` on a platform that has no camera
      // implementation. Both must reach the screen as a failed capture, so the clause catches every object.
      Error.throwWithStackTrace(
        PhotoCaptureException(
          isAccessDenied: error is PlatformException && _accessDeniedCodes.contains(error.code),
          cause: error,
        ),
        stackTrace,
      );
    }
  }
}
