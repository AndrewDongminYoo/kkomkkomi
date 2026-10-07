import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/adapters/camera_driver.dart';
import 'package:material_ui/material_ui.dart';

class _Platform extends CameraPlatform {
  List<CameraDescription> cameras = const [
    CameraDescription(name: 'front', lensDirection: CameraLensDirection.front, sensorOrientation: 90),
    CameraDescription(name: 'back', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
  ];
  Object? failure;
  Object? captureFailure;
  Object? initializationFailure;
  CameraDescription? selected;
  bool? audio;
  int disposals = 0;
  final errors = StreamController<CameraErrorEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (failure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
    return cameras;
  }

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? resolution, {
    bool enableAudio = false,
  }) async {
    selected = description;
    audio = enableAudio;
    return 1;
  }

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    if (initializationFailure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => Stream.value(
    CameraInitializedEvent(cameraId, 640, 480, ExposureMode.auto, false, FocusMode.auto, false),
  );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.blue);

  @override
  Future<XFile> takePicture(int cameraId) async {
    if (captureFailure case final error?) Error.throwWithStackTrace(error, StackTrace.current);
    return XFile('/cache/raw.jpg');
  }

  @override
  Future<void> dispose(int cameraId) async => disposals++;
}

void main() {
  late CameraPlatform previous;
  late _Platform platform;
  setUp(() {
    previous = CameraPlatform.instance;
    platform = _Platform();
    CameraPlatform.instance = platform;
  });
  tearDown(() async {
    platform.errors.add(const CameraErrorEvent(1, 'test finished'));
    await platform.errors.close();
    CameraPlatform.instance = previous;
  });

  testWidgets('opens the first rear camera without audio and returns a still path', (tester) async {
    final driver = CameraDriver();
    await driver.initialize();
    expect(platform.selected!.name, 'back');
    expect(platform.audio, isFalse);
    await tester.pumpWidget(MaterialApp(home: driver.preview()));
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(await driver.takePicture(), '/cache/raw.jpg');
    await tester.pumpWidget(const SizedBox());
    await driver.dispose();
    await driver.dispose();
    expect(platform.disposals, 1);
  });

  test('refuses a device with only a front camera', () async {
    platform.cameras = [platform.cameras.first];
    final driver = CameraDriver();
    await expectLater(driver.initialize(), throwsA(isA<PhotoCaptureException>()));
    expect(platform.selected, isNull);
    await driver.dispose();
    expect(platform.disposals, 0);
  });

  for (final code in [
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'unavailable',
  ]) {
    test('maps initialization permission or hardware error $code', () async {
      platform.failure = CameraException(code, 'failure');
      final driver = CameraDriver();
      await expectLater(
        driver.initialize(),
        throwsA(
          isA<PhotoCaptureException>().having(
            (e) => e.isAccessDenied,
            'access denied',
            code != 'unavailable',
          ),
        ),
      );
      await driver.dispose();
    });
  }

  test('maps native permission failure after controller creation and disposes that controller', () async {
    platform.initializationFailure = PlatformException(code: 'CameraAccessDenied');
    final driver = CameraDriver();
    await expectLater(
      driver.initialize(),
      throwsA(isA<PhotoCaptureException>().having((e) => e.isAccessDenied, 'access denied', isTrue)),
    );
    await driver.dispose();
    expect(platform.selected!.name, 'back');
    expect(platform.audio, isFalse);
    expect(platform.disposals, 1);
  });

  test('maps a platform capture failure and still closes the controller', () async {
    final driver = CameraDriver();
    await driver.initialize();
    platform.captureFailure = PlatformException(code: 'capture-failed');
    await expectLater(driver.takePicture(), throwsA(isA<PhotoCaptureException>()));
    await driver.dispose();
    expect(platform.disposals, 1);
  });
}
