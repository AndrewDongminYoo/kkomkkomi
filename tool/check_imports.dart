// Checks import order and group comments; --fix applies the same policy.
// Blank lines belong to `dart format`: import_sorter removes the separator
// that the formatter requires between package and relative imports.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
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
  final changes = <File, String>{};
  for (final name in ['lib', 'test']) {
    final directory = Directory(p.join(root.path, name));
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(recursive: true, followLinks: false).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final relative = p.relative(file.path, from: root.path).split(p.separator).join('/');
      if (ignored.any((pattern) => pattern.hasMatch('/$relative'))) continue;
      final source = file.readAsStringSync();
      final directives = <String, String>{};
      final sortedLines = sortImports(
        _directiveLines(source, relative, directives),
        pubspec['name'] as String,
        config?['emojis'] as bool? ?? false,
        false,
        !(config?['comments'] as bool? ?? true),
      ).sortedFile;
      final restored = const LineSplitter().convert(sortedLines).map((line) => directives[line] ?? line).join('\n');
      final sorted = restored.endsWith('\n') ? restored : '$restored\n';
      if (_withoutBlankLines(source) != _withoutBlankLines(sorted)) {
        problems.add(relative);
        if (fix) changes[file] = sorted;
      }
    }
  }
  for (final change in changes.entries) {
    change.key.writeAsStringSync(change.value);
  }
  return problems..sort();
}

List<String> _directiveLines(String source, String file, Map<String, String> directives) {
  final unit = parseString(content: source, path: file).unit;
  _checkNamespaceOrder(unit.directives.whereType<ExportDirective>(), file, 'exports');
  for (final directive in unit.directives) {
    final docImports = directive.documentationComment?.docImports;
    if (docImports != null) {
      _checkNamespaceOrder(docImports.map((item) => item.import), file, 'documentation imports');
    }
  }
  final lines = <String>[];
  var offset = 0;
  final library = unit.directives.whereType<LibraryDirective>().firstOrNull;
  if (library != null) {
    lines.add(_opaqueKey(source, directives, source.substring(0, library.end)));
    offset = library.end;
    if (source.startsWith('\r\n', offset)) {
      offset += 2;
    } else if (source.startsWith('\n', offset)) {
      offset++;
    }
  }
  for (final directive in unit.directives.whereType<ImportDirective>()) {
    final prefix = const LineSplitter().convert(source.substring(offset, directive.offset));
    final fileIgnore = RegExp(r'^\s*//\s*ignore_for_file:');
    final preambleEnd = offset == 0 ? prefix.indexWhere(fileIgnore.hasMatch) : -1;
    final hasUnsupportedTrivia = prefix.indexed.any((entry) {
      final (index, line) = entry;
      final isFilePreamble =
          index <= preambleEnd && line.trimLeft().startsWith('//') && !RegExp(r'^\s*//\s*ignore:').hasMatch(line);
      return line.trim().isNotEmpty && !_importGroupHeaders.contains(line) && !isFilePreamble;
    });
    if (hasUnsupportedTrivia) {
      throw FormatException('Cannot preserve import-leading trivia in $file');
    }
    if (preambleEnd >= 0) {
      final preamble = prefix.take(preambleEnd + 1).join('\n');
      prefix.replaceRange(0, preambleEnd + 1, [_opaqueKey(source, directives, preamble)]);
    }
    final newline = source.indexOf('\n', directive.end);
    final remainder = source.substring(directive.end, newline < 0 ? source.length : newline);
    final uri = directive.uri.stringValue;
    if (uri == null || directive.metadata.isNotEmpty || remainder.trim().isNotEmpty) {
      throw FormatException('Cannot preserve import-line trivia in $file');
    }
    // Sort by the primary URI, keeping the complete directive as an opaque block.
    // Generated keys cannot collide with code or text already in the file.
    final index = directives.length.toString().padLeft(8, '0');
    var suffix = 0;
    late String key;
    do {
      key = 'import ${jsonEncode(uri)} as _sort_import_${index}_${suffix++};';
    } while (source.contains(key));
    directives[key] = source.substring(directive.offset, directive.end);
    lines
      ..addAll(prefix)
      ..add(key);
    offset = directive.end;
  }
  lines.add(_opaqueKey(source, directives, source.substring(offset)));
  return lines;
}

// The upstream sorter must only inspect real imports, never body text or docs.
String _opaqueKey(String source, Map<String, String> blocks, String text) {
  var suffix = 0;
  late String key;
  do {
    key = '// _sort_text_${blocks.length}_${suffix++}';
  } while (source.contains(key));
  blocks[key] = text;
  return key;
}

// Keep the namespace ordering from directives_ordering without rewriting it.
void _checkNamespaceOrder(Iterable<NamespaceDirective> directives, String file, String kind) {
  var seenNonDart = false;
  var seenRelative = false;
  final previous = <int, String>{};
  for (final directive in directives) {
    final uri = directive.uri.stringValue;
    if (uri == null) continue;
    final isDart = uri.startsWith('dart:');
    final isPackage = uri.startsWith('package:');
    final isRelative = !uri.contains(':');
    if ((isDart && seenNonDart) || (isPackage && seenRelative)) {
      throw FormatException('Unsorted $kind in $file; order them before applying import fixes');
    }
    seenNonDart |= !isDart;
    seenRelative |= isRelative;
    final group = isDart ? 0 : (isPackage ? 1 : (isRelative ? 2 : 3));
    final prior = previous[group];
    if (group < 3 && prior != null && _compareDirectiveUris(prior, uri) > 0) {
      throw FormatException('Unsorted $kind in $file; order them before applying import fixes');
    }
    previous[group] = uri;
  }
}

int _compareDirectiveUris(String a, String b) {
  if (a.startsWith('package:') && b.startsWith('package:')) {
    final slashA = a.indexOf('/');
    final slashB = b.indexOf('/');
    if (slashA >= 0 && slashB >= 0) {
      final packageOrder = a.substring(0, slashA).compareTo(b.substring(0, slashB));
      if (packageOrder != 0) return packageOrder;
      return a.substring(slashA + 1).compareTo(b.substring(slashB + 1));
    }
  }
  return a.compareTo(b);
}

const _importGroupHeaders = {
  '// Dart imports:',
  '// Flutter imports:',
  '// Package imports:',
  '// Project imports:',
  '// 🎯 Dart imports:',
  '// 🐦 Flutter imports:',
  '// 📱 Flutter imports:',
  '// 📦 Package imports:',
  '// 🌎 Project imports:',
};

String _withoutBlankLines(String source) =>
    const LineSplitter().convert(source).where((line) => line.trim().isNotEmpty).join('\n');
