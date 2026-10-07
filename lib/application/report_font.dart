// 🎯 Dart imports:
import 'dart:typed_data';

/// Gives the font files that a report prints its texts with, so that tests never read the asset bundle.
abstract interface class ReportFont {
  /// The bytes of a TrueType font that has the Korean glyphs, in the regular weight.
  Future<ByteData> load();

  /// The bytes of the bold weight of the same font, with the same glyphs as [load].
  Future<ByteData> loadBold();
}
