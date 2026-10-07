// Checks import order and group comments; --fix applies the same policy.
// Blank lines belong to `dart format`: import_sorter removes the separator
// that the formatter requires between package and relative imports.
import 'dart:convert';
import 'dart:io';

import 'package:import_sorter/sort.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  final fix = arguments.contains('--fix');
  final problems = importProblems(Directory.current, fix: fix);
  for (final file in problems) {
    if (fix) {
      stdout.writeln('Sorted imports: $file');
    } else {
      stderr.writeln('Unsorted imports: $file');
    }
  }
  if (!fix && problems.isNotEmpty) exitCode = 1;
}

/// Finds sources whose import order or group comments differ from the sorter.
/// The separate Dart formatting gate checks whitespace.
/// With [fix], applies the import changes and returns the changed paths.
List<String> importProblems(Directory root, {bool fix = false}) {
  final pubspec = loadYaml(File(p.join(root.path, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
  final config = pubspec['import_sorter'] as YamlMap?;
  final ignored = (config?['ignored_files'] as YamlList? ?? YamlList()).cast<String>().map(RegExp.new).toList();
  final problems = <String>[];
  for (final name in ['lib', 'test']) {
    final directory = Directory(p.join(root.path, name));
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(recursive: true, followLinks: false).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final relative = p.relative(file.path, from: root.path).split(p.separator).join('/');
      if (ignored.any((pattern) => pattern.hasMatch('/$relative'))) continue;
      final source = file.readAsStringSync();
      final sorted = sortImports(
        const LineSplitter().convert(source),
        pubspec['name'] as String,
        config?['emojis'] as bool? ?? false,
        false,
        !(config?['comments'] as bool? ?? true),
      ).sortedFile;
      if (_withoutBlankLines(source) != _withoutBlankLines(sorted)) {
        problems.add(relative);
        if (fix) file.writeAsStringSync(sorted);
      }
    }
  }
  return problems..sort();
}

String _withoutBlankLines(String source) =>
    const LineSplitter().convert(source).where((line) => line.trim().isNotEmpty).join('\n');
