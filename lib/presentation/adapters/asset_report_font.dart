import 'package:flutter/services.dart';
import 'package:kkomkkomi/application/application.dart';

/// Reads the font of the report from the assets of the app.
final class AssetReportFont implements ReportFont {
  /// The `bundle` argument replaces the asset bundle of the app in a test.
  const new({this._bundle});

  /// The asset key of the font file, which `pubspec.yaml` lists with its license file.
  static const assetKey = 'assets/fonts/NotoSansKR-Regular.ttf';

  final AssetBundle? _bundle;

  @override
  Future<ByteData> load() => (_bundle ?? rootBundle).load(assetKey);
}
