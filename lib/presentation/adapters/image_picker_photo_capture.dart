// 🐦 Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:image_picker/image_picker.dart';

// 🌎 Project imports:
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

  @override
  Future<String?> selectGalleryPhoto() async {
    try {
      final photo = await (_picker ?? ImagePicker()).pickImage(
        source: ImageSource.gallery,
        maxWidth: maxEdge,
        maxHeight: maxEdge,
        imageQuality: quality,
        requestFullMetadata: false,
      );
      return photo?.path;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PhotoCaptureException(cause: error), stackTrace);
    }
  }

  /// True on Android only.
  ///
  /// Only Android opens the camera as another app, so only Android can end the app while the camera is open, and
  /// the picker answers `retrieveLostData` only there: on another platform it throws an `UnimplementedError`.
  @override
  bool get keepsLostPhotos => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Reads the lost answer through `retrieveLostData` of the picker, which a new capture clears.
  ///
  /// The method gives null without asking the picker where [keepsLostPhotos] is false. The picker makes the lost
  /// photo smaller with the size limit and the quality of the capture that lost it, as it does for [takePhoto].
  @override
  Future<String?> retrieveLostPhoto() async {
    if (!keepsLostPhotos) return null;
    final LostDataResponse response;
    try {
      response = await (_picker ?? ImagePicker()).retrieveLostData();
    } on Object catch (error, stackTrace) {
      // The picker fails with a `PlatformException` when the app has no activity, and the clause catches every object
      // for the same reason as the one of `takePhoto`.
      Error.throwWithStackTrace(PhotoCaptureException(cause: error), stackTrace);
    }
    // A lost failure would have an exception and no file, and the capture ended without a photo then, as after a
    // cancel. `image_picker_android` 0.8.13+23 gives an empty response for a lost failure as well.
    return response.file?.path;
  }
}
