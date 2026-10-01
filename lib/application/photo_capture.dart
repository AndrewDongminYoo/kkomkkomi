/// Takes a photo with the camera of the device, so that tests never open a camera.
abstract interface class PhotoCapture {
  /// The path of the file that holds the new photo, or null when the person closed the camera without a photo.
  ///
  /// The file is temporary, so the caller copies it before the app closes.
  /// Throws a [PhotoCaptureException] when the camera gave no photo for another reason.
  Future<String?> takePhoto();
}

/// The camera gave no photo, and the person did not close it.
final class PhotoCaptureException implements Exception {
  const new({this.isAccessDenied = false, this.cause});

  /// Whether the person did not allow the app to use the camera.
  final bool isAccessDenied;

  /// What the camera reported, for the log.
  final Object? cause;

  @override
  String toString() => 'PhotoCaptureException(isAccessDenied: $isAccessDenied, cause: $cause)';
}
