// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/gen/assets.gen.dart';

/// Reads the fonts of the report from the assets of the app, which `pubspec.yaml` lists with their license file.
final class AssetReportFont implements ReportFont {
  /// The `bundle` argument replaces the asset bundle of the app in a test.
  const new({this._bundle});

  final AssetBundle? _bundle;

  @override
  Future<ByteData> load() => (_bundle ?? rootBundle).load(Assets.fonts.notoSansKRRegular);

  @override
  Future<ByteData> loadBold() => (_bundle ?? rootBundle).load(Assets.fonts.notoSansKRBold);
}
