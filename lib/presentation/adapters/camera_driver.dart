// 📦 Package imports:
import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/still_camera_driver.dart';

final class CameraDriver implements StillCameraDriver {
  CameraController? _controller;
  static const _denied = {'CameraAccessDenied', 'CameraAccessDeniedWithoutPrompt', 'CameraAccessRestricted'};

  @override
  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      final rear = cameras.where((camera) => camera.lensDirection == CameraLensDirection.back).firstOrNull;
      if (rear == null) throw const PhotoCaptureException();
      final controller = CameraController(rear, ResolutionPreset.high, enableAudio: false);
      _controller = controller;
      await controller.initialize();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_failure(error), stackTrace);
    }
  }

  @override
  Widget preview() => CameraPreview(_controller!);

  @override
  Future<String> takePicture() async {
    try {
      return (await _controller!.takePicture()).path;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_failure(error), stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  PhotoCaptureException _failure(Object error) => error is PhotoCaptureException
      ? error
      : PhotoCaptureException(isAccessDenied: error is CameraException && _denied.contains(error.code), cause: error);
}
