import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('PhotoRef', () {
    test('keeps a path relative to the documents directory', () {
      expect(PhotoRef('photos/visit-1/zone-1-before.jpg').path, 'photos/visit-1/zone-1-before.jpg');
    });

    test('refuses an empty path', () {
      expect(() => PhotoRef(''), throwsArgumentError);
    });

    test('refuses an absolute path', () {
      expect(() => PhotoRef('/var/mobile/Documents/photos/a.jpg'), throwsArgumentError);
      expect(() => PhotoRef(r'\photos\a.jpg'), throwsArgumentError);
      expect(() => PhotoRef(r'C:\Users\photos\a.jpg'), throwsArgumentError);
      expect(() => PhotoRef('c:/photos/a.jpg'), throwsArgumentError);
    });

    test('refuses a path that leaves the documents directory', () {
      expect(() => PhotoRef('../photos/a.jpg'), throwsArgumentError);
      expect(() => PhotoRef('photos/../../a.jpg'), throwsArgumentError);
      expect(() => PhotoRef(r'photos\..\a.jpg'), throwsArgumentError);
    });

    test('accepts a file name that only contains two dots', () {
      expect(PhotoRef('photos/a..jpg').path, 'photos/a..jpg');
    });

    test('is equal to a reference with the same path', () {
      expect(PhotoRef('photos/a.jpg'), PhotoRef('photos/a.jpg'));
      expect(PhotoRef('photos/a.jpg').hashCode, PhotoRef('photos/a.jpg').hashCode);
      expect(PhotoRef('photos/a.jpg'), isNot(PhotoRef('photos/b.jpg')));
    });
  });
}
