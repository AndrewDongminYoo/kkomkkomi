// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import '../helpers/helpers.dart';

/// The one file that may import `url_launcher`: the adapter of the `ExternalLinks` port.
const _linksAdapter = 'lib/presentation/adapters/url_launcher_external_links.dart';

/// Whether [source] names a library of the `url_launcher` package.
bool namesUrlLauncher(String source) => libraryUrisIn(source).any((uri) => uri.startsWith('package:url_launcher/'));

void main() {
  group('namesUrlLauncher', () {
    test('finds an import and an export of the url_launcher package', () {
      expect(namesUrlLauncher("import 'package:url_launcher/url_launcher.dart';"), isTrue);
      expect(namesUrlLauncher('export "package:url_launcher/url_launcher.dart" show launchUrl;'), isTrue);
    });

    test('finds none in a file that names other libraries', () {
      expect(
        namesUrlLauncher("import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';"),
        isFalse,
      );
      expect(namesUrlLauncher('/// Opens the page through `url_launcher`.'), isFalse);
    });
  });

  test('the links adapter is the one file under lib that imports url_launcher', () {
    final importers = [
      for (final file in dartFilesUnder('lib/'))
        if (namesUrlLauncher(file.readAsStringSync())) file.path,
    ];

    expect(importers, [_linksAdapter]);
  });
}
