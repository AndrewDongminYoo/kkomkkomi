import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/view/still_camera_page.dart';
import 'package:material_ui/material_ui.dart';

import '../../../helpers/fake_still_camera.dart';
import '../../../helpers/helpers.dart';

void main() {
  late FakeStillCameraDriver driver;
  late FakeCameraPhotoFiles files;
  Object? result;
  final time = DateTime.utc(2026, 10, 7, 9, 12);
  setUp(() {
    driver = FakeStillCameraDriver();
    files = FakeCameraPhotoFiles();
    result = null;
  });

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                StillCameraPage.route(
                  driverFactory: () => driver,
                  files: files,
                  clock: FixedClock(time),
                ),
              );
            },
            child: const Text('Open camera'),
          ),
        ),
      ),
      locale: locale,
    );
    await tester.tap(find.text('Open camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('shows the ready preview and returns an observed still after one press', (tester) async {
    await open(tester);
    expect(find.text('Camera'), findsOneWidget);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(result, isA<ObservedCameraPhoto>());
    expect((result! as ObservedCameraPhoto).capturedAt, time);
    expect(driver.captures, 1);
    expect(driver.disposals, 1);
    expect(find.text('Open camera'), findsOneWidget);
  });

  testWidgets('keeps shutter disabled during initialization and permits close', (tester) async {
    driver.initialization = Completer<void>();
    await open(tester);
    await tester.tap(find.text('Take photo'));
    expect(driver.captures, 0);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    driver.initialization!.complete();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(driver.disposals, 1);
  });

  testWidgets('system back cancels a pending capture and ignores its later file', (tester) async {
    await open(tester);
    driver.picture = Completer<String>();
    await tester.tap(find.text('Take photo'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    driver.picture!.complete('/cache/late.jpg');
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(files.discarded, ['/cache/late.jpg']);
    expect(driver.disposals, 1);
  });

  testWidgets('returns camera permission failure for the existing visit notice', (tester) async {
    driver.initializationFailure = const PhotoCaptureException(isAccessDenied: true);
    await open(tester);
    await tester.pumpAndSettle();
    expect(result, isA<PhotoCaptureException>().having((e) => e.isAccessDenied, 'access denied', isTrue));
  });

  for (final locale in [const Locale('en'), const Locale('ko')]) {
    testWidgets('keeps controls readable at largest text in ${locale.languageCode}', (tester) async {
      tester.useNarrowScreenWithLargestText();
      await open(tester, locale: locale);
      tester.expectWholeText(locale.languageCode == 'ko' ? '촬영' : 'Take photo');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip(locale.languageCode == 'ko' ? '닫기' : 'Close'));
      await tester.pumpAndSettle();
    });
  }
}
