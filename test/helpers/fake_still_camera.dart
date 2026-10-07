import 'dart:async';

import 'package:kkomkkomi/presentation/still_camera/camera_photo_files.dart';
import 'package:kkomkkomi/presentation/still_camera/still_camera_driver.dart';
import 'package:material_ui/material_ui.dart';

class FakeStillCameraDriver implements StillCameraDriver {
  Completer<void>? initialization;
  Completer<String>? picture;
  Completer<void>? closing;
  Object? initializationFailure;
  Object? pictureFailure;
  Object? closingFailure;
  int initializations = 0;
  int captures = 0;
  int disposals = 0;
  void Function()? onCapture;

  @override
  Future<void> initialize() async {
    initializations++;
    await initialization?.future;
    if (initializationFailure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
  }

  @override
  Widget preview() => const AspectRatio(
    aspectRatio: 3 / 4,
    child: ColoredBox(color: Colors.blue),
  );

  @override
  Future<String> takePicture() async {
    captures++;
    onCapture?.call();
    if (pictureFailure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
    return await picture?.future ?? '/cache/camera.jpg';
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await closing?.future;
    if (closingFailure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
  }
}

class FakeCameraPhotoFiles implements CameraPhotoFiles {
  Completer<String>? normalization;
  Object? failure;
  final normalized = <String>[];
  final discarded = <String>[];

  @override
  Future<String> normalize(String sourcePath) async {
    normalized.add(sourcePath);
    if (failure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
    return await normalization?.future ?? '/cache/normalized.jpg';
  }

  @override
  Future<void> discard(String path) async => discarded.add(path);
}
