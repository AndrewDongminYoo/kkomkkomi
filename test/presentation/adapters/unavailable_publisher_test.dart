import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  group('UnavailablePublisher', () {
    const Publisher publisher = UnavailablePublisher();
    final page = PublishedPage(ownerUid: 'u', companyName: null, clientName: 'c', createdAt: DateTime.utc(2026));
    final refused = throwsA(
      isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.refused),
    );

    test('says that publishing is unavailable', () {
      expect(publisher.isAvailable, isFalse);
    });

    test('refuses each call', () async {
      await expectLater(publisher.writePage('p', page), refused);
      await expectLater(publisher.uploadPhoto('o', Uint8List(0), cancel: Completer<void>().future), refused);
      await expectLater(
        publisher.writeReport(
          pageId: 'p',
          visitId: 'v',
          report: PublishedReport(visitDate: VisitDate(2026, 10, 2), publishedAt: DateTime.utc(2026), zones: const []),
        ),
        refused,
      );
      await expectLater(publisher.revokePage('p', page, revokedAt: DateTime.utc(2026)), refused);
      await expectLater(publisher.deletePhoto('o'), refused);
    });
  });
}
