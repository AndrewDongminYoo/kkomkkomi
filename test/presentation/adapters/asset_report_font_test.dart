import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/gen/assets.gen.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

/// An asset bundle that holds one asset.
class _OneAssetBundle extends CachingAssetBundle {
  new(this.key, this.data);

  final String key;
  final ByteData data;

  @override
  Future<ByteData> load(String key) async => key == this.key ? data : throw Exception('Unable to load asset: "$key".');
}

void main() {
  group('AssetReportFont', () {
    test('reads the font from the bundle that it is given', () async {
      final data = ByteData.sublistView(Uint8List.fromList([1, 2, 3]));

      final font = await AssetReportFont(bundle: _OneAssetBundle(Assets.fonts.notoSansKRRegular, data)).load();

      expect(font, same(data));
    });

    test('fails when the bundle does not hold the font', () async {
      final bundle = _OneAssetBundle('assets/fonts/other.ttf', ByteData(0));

      await expectLater(AssetReportFont(bundle: bundle).load(), throwsException);
    });

    test('reads the font file of the source tree from the assets of the app', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final font = await const AssetReportFont().load();

      // The asset bundle of a test holds what `pubspec.yaml` lists, so this fails when the list loses the font.
      final file = File(Assets.fonts.notoSansKRRegular).readAsBytesSync();
      expect(font.lengthInBytes, file.length);
      expect(font.buffer.asUint8List(font.offsetInBytes, 4), file.sublist(0, 4));
    });

    test('reads the bold font from the bundle that it is given', () async {
      final data = ByteData.sublistView(Uint8List.fromList([4, 5, 6]));

      final font = await AssetReportFont(bundle: _OneAssetBundle(Assets.fonts.notoSansKRBold, data)).loadBold();

      expect(font, same(data));
    });

    test('reads the bold font file of the source tree from the assets of the app', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final font = await const AssetReportFont().loadBold();

      // The asset bundle of a test holds what `pubspec.yaml` lists, so this fails when the list loses the font.
      final file = File(Assets.fonts.notoSansKRBold).readAsBytesSync();
      expect(font.lengthInBytes, file.length);
      expect(font.buffer.asUint8List(font.offsetInBytes, 4), file.sublist(0, 4));
    });

    test('the assets of the app hold the license of the font', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final license = await rootBundle.loadString(Assets.fonts.ofl);

      expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    });
  });
}
