// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/shared/notice.dart';

extension Styles on WidgetTester {
  /// The color that fills the one `FilledButton` that shows [label], as the button paints it.
  Color? filledButtonColor(String label) => widget<Material>(
    find.descendant(of: find.widgetWithText(FilledButton, label), matching: find.byType(Material)),
  ).color;

  /// The tone of the one [Notice] that shows [text], or null when no notice holds the text.
  NoticeTone? noticeToneOf(String text) {
    final notice = find.ancestor(of: find.text(text), matching: find.byType(Notice));
    if (notice.evaluate().isEmpty) return null;
    return widget<Notice>(notice).tone;
  }
}
