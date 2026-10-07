// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/presentation.dart';

/// The path of the photo file that [image] shows.
String photoPathOf(Image image) => ((image.image as ResizeImage).imageProvider as FileImage).file.path;

extension PhotoFinders on WidgetTester {
  /// The paths of the photo files that the thumbnails under [of] show, in the order of the tree.
  List<String> photoPathsIn(Finder of) => [
    for (final thumbnail in widgetList<PhotoThumbnail>(find.descendant(of: of, matching: find.byType(PhotoThumbnail))))
      thumbnail.path,
  ];
}
