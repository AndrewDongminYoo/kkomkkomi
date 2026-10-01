import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/helpers.dart';

void main() {
  const path = '/documents/photos/visit-1/photo-1.jpg';

  group('PhotoThumbnail', () {
    testWidgets('shows the file of the path, cut to fill its box and decoded at the thumbnail width', (tester) async {
      await tester.pumpApp(const PhotoThumbnail(path: path));

      final image = tester.widget<Image>(find.byType(Image));
      expect(photoPathOf(image), path);
      expect(image.fit, BoxFit.cover);
      expect((image.image as ResizeImage).width, 600);
      expect((image.image as ResizeImage).height, isNull);
    });

    testWidgets('shows the whole photo when it is told to', (tester) async {
      await tester.pumpApp(const PhotoThumbnail(path: path, fit: BoxFit.contain));

      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    });

    testWidgets('is not in the semantics tree without a label', (tester) async {
      await tester.pumpApp(const PhotoThumbnail(path: path));

      expect(tester.widget<Image>(find.byType(Image)).excludeFromSemantics, isTrue);
    });

    testWidgets('gives a screen reader the label that it is given', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(const PhotoThumbnail(path: path, semanticLabel: 'Before photo'));

      expect(find.bySemanticsLabel('Before photo'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows an icon in place of a file that does not load', (tester) async {
      await tester.pumpApp(const PhotoThumbnail(path: '/no-such-directory/photo.jpg'));
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

      // The file is read outside the fake clock of the test, so the test waits in real time until the read fails.
      for (var attempt = 0; attempt < 200 && find.byIcon(Icons.broken_image_outlined).evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
