import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';

void main() {
  group('PhotoCaptureException', () {
    test('names no denied access and no cause unless it is given them', () {
      const exception = PhotoCaptureException();

      expect(exception.isAccessDenied, isFalse);
      expect(exception.cause, isNull);
    });

    test('shows whether access was denied and what the camera reported, for the log', () {
      expect(
        const PhotoCaptureException(isAccessDenied: true, cause: 'no camera').toString(),
        'PhotoCaptureException(isAccessDenied: true, cause: no camera)',
      );
    });
  });
}
