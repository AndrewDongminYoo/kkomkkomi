import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';

void main() {
  group('reportLinkOf', () {
    test('is the path of the report under the client page on the Hosting site', () {
      expect(
        reportLinkOf(pageId: '0123456789abcdef0123456789abcdef', visitId: 'fedcba9876543210fedcba9876543210'),
        Uri.parse('https://kkomkkomi.web.app/r/0123456789abcdef0123456789abcdef/fedcba9876543210fedcba9876543210'),
      );
    });

    test('encodes each ID as one path segment', () {
      final link = reportLinkOf(pageId: 'a/b', visitId: 'c d');

      expect(link.pathSegments, ['r', 'a/b', 'c d']);
    });
  });
}
