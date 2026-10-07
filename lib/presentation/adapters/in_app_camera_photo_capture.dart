import 'package:kkomkkomi/application/application.dart';

final class InAppCameraPhotoCapture implements InAppPhotoCapture {
  new({required this._openCamera, required this._picker});
  final Future<Object?> Function() _openCamera;
  final PhotoCapture _picker;
  bool _isOpen = false;
  @override
  Future<ObservedCameraPhoto?> takeObservedPhoto() async {
    if (_isOpen) throw const PhotoCaptureException();
    _isOpen = true;
    try {
      final result = await _openCamera();
      return switch (result) {
        null => null,
        final ObservedCameraPhoto photo => photo,
        final PhotoCaptureException failure => throw failure,
        _ => throw const PhotoCaptureException(),
      };
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        error is PhotoCaptureException ? error : PhotoCaptureException(cause: error),
        stackTrace,
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  Future<String?> takePhoto() async => (await takeObservedPhoto())?.path;
  @override
  Future<String?> selectGalleryPhoto() => _picker.selectGalleryPhoto();
  @override
  bool get keepsLostPhotos => _picker.keepsLostPhotos;
  @override
  Future<String?> retrieveLostPhoto() => _picker.retrieveLostPhoto();
}
