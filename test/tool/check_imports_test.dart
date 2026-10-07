// 🎯 Dart imports:
import 'dart:io';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import '../../tool/check_imports.dart';

void main() {
  late Directory root;

  void write(String name, String content) {
    File('${root.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('check_imports_test');
    write(
      'pubspec.yaml',
      'name: kkomkkomi\nimport_sorter:\n  emojis: true\n  ignored_files:\n    - "^/lib/generated/"\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('accepts the formatter separator between project and relative imports', () {
    write(
      'test/example.dart',
      "// 🌎 Project imports:\nimport 'package:kkomkkomi/app/app.dart';\n\nimport '../helper.dart';\n",
    );
    expect(importProblems(root), isEmpty);
  });

  test('reports unsorted imports without changing the input', () {
    const source = "import 'package:z/z.dart';\nimport 'dart:io';\n";
    write('lib/example.dart', source);
    expect(importProblems(root), ['lib/example.dart']);
    expect(File('${root.path}/lib/example.dart').readAsStringSync(), source);
  });

  test('requires group headers even when import order is correct', () {
    write('lib/example.dart', "import 'dart:io';\n");
    expect(importProblems(root), ['lib/example.dart']);
  });

  test('fixes only eligible sources and then passes the read-only check', () {
    const original = "import 'package:z/z.dart';\nimport 'dart:io';\n";
    write('lib/example.dart', original);
    write('test/example.dart', original);
    write('lib/generated/example.dart', original);
    write('bin/lib/example.dart', original);
    expect(importProblems(root, fix: true), ['lib/example.dart', 'test/example.dart']);
    expect(
      File('${root.path}/lib/example.dart').readAsStringSync().trimRight(),
      "// 🎯 Dart imports:\nimport 'dart:io';\n\n// 📦 Package imports:\nimport 'package:z/z.dart';",
    );
    expect(File('${root.path}/lib/generated/example.dart').readAsStringSync(), original);
    expect(File('${root.path}/bin/lib/example.dart').readAsStringSync(), original);
    expect(importProblems(root), isEmpty);
    expect(importProblems(root, fix: true), isEmpty);
  });

  test('excludes configured generated files and paths outside lib and test', () {
    for (final name in ['lib/generated/example.dart', 'bin/lib/example.dart', 'tests/test/example.dart']) {
      write(name, "import 'package:z/z.dart';\nimport 'dart:io';\n");
    }
    expect(importProblems(root), isEmpty);
  });

  test('uses production exclusions for both checking and fixing', () {
    write('pubspec.yaml', File('pubspec.yaml').readAsStringSync());
    const source = "import 'package:z/z.dart';\nimport 'dart:io';\n";
    const excluded = [
      'lib/gen/assets.gen.dart',
      'lib/l10n/gen/app_localizations.dart',
      'lib/firebase_options.dart',
      'lib/presentation/shared/keep_all_text.dart',
    ];
    for (final name in excluded) {
      write(name, source);
    }
    expect(importProblems(root), isEmpty);
    expect(importProblems(root, fix: true), isEmpty);
    for (final name in excluded) {
      expect(File('${root.path}/$name').readAsStringSync(), source);
    }
  });
}
