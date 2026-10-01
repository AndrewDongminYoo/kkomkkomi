import 'dart:typed_data';

/// Gives the font file that a report prints its texts with, so that tests never read the asset bundle.
abstract interface class ReportFont {
  /// The bytes of a TrueType font that has the Korean glyphs.
  Future<ByteData> load();
}
