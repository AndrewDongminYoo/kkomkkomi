/// Takes a photo with the camera of the device, so that tests never open a camera.
abstract interface class PhotoCapture {
  /// The path of the file that holds the new photo, or null when the person closed the camera without a photo.
  ///
  /// The file is temporary, so the caller copies it before the app closes.
  /// Throws a [PhotoCaptureException] when the camera gave no photo for another reason.
  Future<String?> takePhoto();

  /// Selects one gallery image, or null after cancellation. Its capture time is unknown.
  Future<String?> selectGalleryPhoto();

  /// Whether the camera of this platform can keep the photo of a capture whose answer the app lost.
  ///
  /// The answer is lost when the system ends the app while the camera app is open, which only a platform that opens
  /// the camera as another app does. On another platform [retrieveLostPhoto] never has a photo.
  bool get keepsLostPhotos;

  /// The path of the file that holds the photo of a capture whose answer the app lost, or null when the camera has
  /// no such photo now.
  ///
  /// The camera keeps the lost answer until it is read or the next capture starts. A capture that ended without a
  /// photo, because the person closed the camera or the camera failed, gives null, and so does a platform where
  /// [keepsLostPhotos] is false. The file is temporary, as the file of [takePhoto] is.
  /// Throws a [PhotoCaptureException] when the camera could not be asked for the lost answer.
  Future<String?> retrieveLostPhoto();
}

/// The camera gave no photo, and the person did not close it.
final class PhotoCaptureException implements Exception {
  const new({this.isAccessDenied = false, this.cause});

  /// Whether the app is not allowed to use the camera, so that another try cannot work until the setting changes.
  final bool isAccessDenied;

  /// What the camera reported, for the log.
  final Object? cause;

  @override
  String toString() => 'PhotoCaptureException(isAccessDenied: $isAccessDenied, cause: $cause)';
}

/// Optional capability of a camera preview inside the app.
///
/// The adapter observes the shutter time directly. A picker, a gallery image and a recovered picker result must
/// never implement this capability by using their return time, file time or Exif.
abstract interface class InAppPhotoCapture implements PhotoCapture {
  Future<ObservedCameraPhoto?> takeObservedPhoto();
}

/// An in-app camera that owns its returned temporary files.
///
/// After copying an observed photo (or a failed copy), the caller releases only that camera result. Borrowed picker
/// and saved report files are never passed to this capability.
abstract interface class OwnedCameraPhotoCapture implements InAppPhotoCapture {
  Future<void> discardCameraPhoto(String path);
}

/// A temporary photo and the device-clock time observed by the in-app camera at capture.
final class ObservedCameraPhoto {
  new({required this.path, required DateTime capturedAt}) : capturedAt = capturedAt.toUtc();

  final String path;
  final DateTime capturedAt;
}
