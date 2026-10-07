// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

final class InAppCameraPhotoCapture implements OwnedCameraPhotoCapture {
  new({required this._openCamera, required this._picker, required this._discardPhoto});
  final Future<Object?> Function() _openCamera;
  final PhotoCapture _picker;
  final Future<void> Function(String) _discardPhoto;
  final _ownedPhotos = <String>{};
  bool _isOpen = false;
  @override
  Future<void> discardCameraPhoto(String path) async {
    if (_ownedPhotos.remove(path)) await _discardPhoto(path);
  }

  ObservedCameraPhoto _own(ObservedCameraPhoto photo) {
    _ownedPhotos.add(photo.path);
    return photo;
  }

  @override
  Future<ObservedCameraPhoto?> takeObservedPhoto() async {
    if (_isOpen) throw const PhotoCaptureException();
    _isOpen = true;
    try {
      final result = await _openCamera();
      return switch (result) {
        null => null,
        final ObservedCameraPhoto photo => _own(photo),
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
