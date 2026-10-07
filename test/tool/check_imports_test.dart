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

  test('rejects unsorted multiline conditional imports without writing', () {
    const source =
        "// 📦 Package imports:\nimport 'package:z/z.dart';\n"
        "import 'package:alpha/alpha.dart'\n    if (dart.library.io) 'package:alpha/io.dart';\n";
    write('lib/example.dart', source);
    expect(importProblems(root), ['lib/example.dart']);
    expect(File('${root.path}/lib/example.dart').readAsStringSync(), source);
  });

  test('accepts correctly grouped multiline conditional imports', () {
    write(
      'lib/example.dart',
      "// 📦 Package imports:\nimport 'package:alpha/alpha.dart'\n"
          "    if (dart.library.io) 'package:alpha/io.dart';\nimport 'package:z/z.dart';\n",
    );
    expect(importProblems(root), isEmpty);
  });

  test('fixes conditional import order while preserving its URI, alias, and comment', () {
    write(
      'lib/example.dart',
      "// 📦 Package imports:\nimport 'package:z/z.dart';\n"
          "import 'package:alpha/alpha.dart'\n    // Keep the platform fallback.\n"
          "    if (dart.library.io) 'package:alpha/io.dart' as platform;\n",
    );
    expect(importProblems(root, fix: true), ['lib/example.dart']);
    expect(
      File('${root.path}/lib/example.dart').readAsStringSync().trimRight(),
      "// 📦 Package imports:\nimport 'package:alpha/alpha.dart'\n"
      '    // Keep the platform fallback.\n'
      "    if (dart.library.io) 'package:alpha/io.dart' as platform;\nimport 'package:z/z.dart';",
    );
    expect(importProblems(root), isEmpty);
  });

  test('refuses import-line lint comments before writing any source', () {
    const source = "import 'dart:io'; // ignore: unnecessary_import\n";
    const other = "import 'package:z/z.dart';\nimport 'dart:io';\n";
    write('lib/other.dart', other);
    write('lib/example.dart', source);
    expect(() => importProblems(root, fix: true), throwsFormatException);
    expect(File('${root.path}/lib/example.dart').readAsStringSync(), source);
    expect(File('${root.path}/lib/other.dart').readAsStringSync(), other);
  });

  test('groups a conditional import by its primary URI', () {
    write(
      'lib/example.dart',
      "// 📦 Package imports:\nimport 'package:alpha/alpha.dart'\n"
          "    if (dart.library.io) 'package:kkomkkomi/platform.dart';\n\n"
          "// 🌎 Project imports:\nimport 'package:kkomkkomi/app/app.dart';\n",
    );
    expect(importProblems(root), isEmpty);
  });

  test('refuses leading lint comments between imports before writing any source', () {
    const source = "import 'package:z/z.dart';\n// ignore: unnecessary_import\nimport 'package:alpha/alpha.dart';\n";
    const other = "import 'package:z/z.dart';\nimport 'dart:io';\n";
    write('lib/other.dart', other);
    write('lib/example.dart', source);
    expect(() => importProblems(root, fix: true), throwsFormatException);
    expect(File('${root.path}/lib/example.dart').readAsStringSync(), source);
    expect(File('${root.path}/lib/other.dart').readAsStringSync(), other);
  });

  test('refuses a lint comment before the first import without moving it', () {
    const source = "// ignore: unnecessary_import\nimport 'dart:io';\n";
    write('lib/example.dart', source);
    expect(() => importProblems(root, fix: true), throwsFormatException);
    expect(File('${root.path}/lib/example.dart').readAsStringSync(), source);
  });

  test('refuses an ambiguous rationale before the first import without writing any source', () {
    const source = "// Rationale for z.\nimport 'package:z/z.dart';\nimport 'package:alpha/alpha.dart';\n";
    const other = "import 'package:z/z.dart';\nimport 'dart:io';\n";
    write('lib/other.dart', other);
    write('lib/example.dart', source);
    expect(() => importProblems(root, fix: true), throwsFormatException);
    expect(File('${root.path}/lib/example.dart').readAsStringSync(), source);
    expect(File('${root.path}/lib/other.dart').readAsStringSync(), other);
  });

  test('preserves the existing file-level lint preamble when reordering imports', () {
    const preamble =
        '// Every field of this class is final.\n'
        '// The domain annotation is not available here.\n'
        '// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes\n\n';
    write(
      'lib/example.dart',
      "$preamble// 📦 Package imports:\nimport 'package:z/z.dart';\nimport 'package:alpha/alpha.dart';\n",
    );
    expect(importProblems(root, fix: true), ['lib/example.dart']);
    expect(
      File('${root.path}/lib/example.dart').readAsStringSync().trimRight(),
      "$preamble// 📦 Package imports:\nimport 'package:alpha/alpha.dart';\nimport 'package:z/z.dart';",
    );
    expect(importProblems(root), isEmpty);
  });
}
