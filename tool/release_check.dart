// The offline checks of `merry run release check`, which `merry run release
// ios` and `merry run release android` run before they build. Each check
// prints one line for each problem that it finds, and the script exits with 1
// when any check finds one.
//
// The metadata lanes, which build nothing, pass `--metadata`, which leaves out
// the check of the RevenueCat keys file.
//
// Run it from the root of the repository.
import 'dart:convert';
import 'dart:io';

/// The longest release notes of a locale that Google Play takes, in Unicode
/// characters, from the `release-cut` skill. Newlines count, because the store
/// does not say that they do not.
const playChangelogLimit = 500;

/// The longest release notes of a locale that App Store Connect takes, in
/// Unicode characters, from the `release-cut` skill. Newlines count too.
const appStoreReleaseNotesLimit = 4000;

/// The store texts of a locale in `fastlane/metadata/android/<locale>/` that
/// the Android `metadata` lane uploads, and the most Unicode characters that
/// Google Play takes for each. Newlines count, as in [playChangelogLimit].
///
/// Source: Play Console Help, "Create and set up your app", the table under
/// "Product details" (https://support.google.com/googleplay/android-developer/answer/9859152,
/// accessed 2026-10-04): "App name ... 30 character limit", "Short description
/// ... 80 character limit", and "Full description ... 4000 character limit".
/// Its note says that the limits apply to full-width and half-width characters
/// alike, so a Korean syllable counts as one character.
const Map<String, int> playListingLimits = {
  'title.txt': 30,
  'short_description.txt': 80,
  'full_description.txt': 4000,
};

/// The store texts of a locale in `fastlane/metadata/ios/<locale>/` that the
/// iOS `metadata` lane uploads, and the most Unicode characters that App Store
/// Connect takes for each. Newlines count, as in [appStoreReleaseNotesLimit].
/// The keywords have a limit in bytes instead: see [appStoreKeywordsByteLimit].
///
/// Sources, accessed 2026-10-04:
/// - name and subtitle: App Store Connect Help, "App information"
///   (https://developer.apple.com/help/app-store-connect/reference/app-information/app-information):
///   the name has "no more than 30 characters", and the subtitle "can't be
///   longer than 30 characters".
/// - description and promotional text: App Store Connect Help, "Platform
///   version information"
///   (https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information):
///   the description is "Limited to 4000 characters", and the promotional text
///   "can't be longer than 170 characters".
const Map<String, int> appStoreTextLimits = {
  'name.txt': 30,
  'subtitle.txt': 30,
  'description.txt': 4000,
  'promotional_text.txt': 170,
  'release_notes.txt': appStoreReleaseNotesLimit,
};

/// The most bytes of the keywords of a locale, in
/// `fastlane/metadata/ios/<locale>/keywords.txt`, that App Store Connect takes.
///
/// Source: App Store Connect Help, "Platform version information"
/// (https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information,
/// accessed 2026-10-04): "You can provide up to 100 bytes of content." The
/// page does not name an encoding, so the check counts the bytes of the file in
/// UTF-8, where a Korean syllable takes 3 bytes. Newlines count too.
const appStoreKeywordsByteLimit = 100;

/// The file that holds the RevenueCat public SDK keys, which the production
/// build scripts of `merry.yaml` read with `--dart-define-from-file`. Git
/// ignores it, so a fresh clone does not have it.
const revenueCatKeysPath = 'config/revenuecat.json';

/// The tracked file that shows the keys of [revenueCatKeysPath], with empty
/// values.
const revenueCatKeysExamplePath = 'config/revenuecat.example.json';

/// The version name and the build number of `version: <name>+<build>` in
/// `pubspec.yaml`, or null when the file has no such line.
({String name, int build})? parsePubspecVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*([^\s+]+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) return null;
  return (name: match.group(1)!, build: int.parse(match.group(2)!));
}

/// The problems that block a release of the repository at [root].
///
/// [gitStatus] is the output of `git status --porcelain` in [root], so any
/// line in it is a change that is not committed. [forBuild] is false for a
/// release that builds nothing, which does not read the RevenueCat keys file.
List<String> releaseProblems({
  required Directory root,
  required String gitStatus,
  bool forBuild = true,
}) {
  final problems = <String>[];

  final changes = gitStatus.split('\n').where((line) => line.trim().isNotEmpty).toList();
  if (changes.isNotEmpty) {
    problems.add(
      'The working tree has ${changes.length} uncommitted change(s); commit or stash them first:\n'
      '${changes.map((line) => '  $line').join('\n')}',
    );
  }

  final pubspec = File('${root.path}/pubspec.yaml');
  final version = pubspec.existsSync() ? parsePubspecVersion(pubspec.readAsStringSync()) : null;
  if (version == null) {
    problems.add(
      'pubspec.yaml has no line of the form "version: <name>+<build>".',
    );
  } else {
    problems
      ..addAll(_changelogProblems(root, version.name))
      ..addAll(_playChangelogProblems(root, version.build));
  }

  problems
    ..addAll(_playListingProblems(root))
    ..addAll(_appStoreTextProblems(root));
  if (forBuild) problems.addAll(_revenueCatKeysProblems(root));
  return problems;
}

/// The names of the `--dart-define` values that [revenueCatKeysPath] must hold,
/// as `String.fromEnvironment` in `lib/billing/` reads them.
const revenueCatKeyNames = ['REVENUECAT_IOS_API_KEY', 'REVENUECAT_ANDROID_API_KEY'];

/// A build without the keys file, or with a file that does not hold each key
/// as a string, stops, so that no build lacks the keys by accident. The file
/// with empty keys passes: it builds an app without subscriptions on purpose.
List<String> _revenueCatKeysProblems(Directory root) {
  final file = File('${root.path}/$revenueCatKeysPath');
  if (!file.existsSync()) {
    const fix = 'or keep them empty for a build without subscriptions.';
    return [
      '$revenueCatKeysPath is missing: copy $revenueCatKeysExamplePath to it and fill in the RevenueCat public SDK keys, $fix',
    ];
  }

  final Object? keys;
  try {
    keys = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return ['$revenueCatKeysPath is not valid JSON: ${error.message}.'];
  }
  if (keys is! Map<String, Object?>) {
    return ['$revenueCatKeysPath does not hold a JSON object; see $revenueCatKeysExamplePath.'];
  }
  const fix = 'keep the value empty for a build without subscriptions.';
  return [
    for (final name in revenueCatKeyNames)
      if (keys[name] is! String) '$revenueCatKeysPath has no string "$name"; see $revenueCatKeysExamplePath, and $fix',
  ];
}

List<String> _changelogProblems(Directory root, String versionName) {
  final changelog = File('${root.path}/CHANGELOG.md');
  if (!changelog.existsSync()) return ['CHANGELOG.md does not exist.'];

  final heading = RegExp(
    '^## \\[${RegExp.escape(versionName)}\\]',
    multiLine: true,
  );
  if (heading.hasMatch(changelog.readAsStringSync())) return const [];
  return [
    'CHANGELOG.md has no entry "## [$versionName]" for the version of pubspec.yaml.',
  ];
}

List<String> _playChangelogProblems(Directory root, int build) {
  final locales = _localeDirectories(
    Directory('${root.path}/fastlane/metadata/android'),
  );
  if (locales.isEmpty) {
    return ['fastlane/metadata/android has no locale directory.'];
  }

  final problems = <String>[];
  for (final locale in locales) {
    final path = 'fastlane/metadata/android/$locale/changelogs/$build.txt';
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      problems.add(
        '$path is missing: Google Play needs release notes for build $build in each locale.',
      );
    } else {
      problems.addAll(_lengthProblems(file, path, playChangelogLimit));
    }
  }
  return problems;
}

List<String> _playListingProblems(Directory root) {
  final problems = <String>[];
  for (final locale in _localeDirectories(
    Directory('${root.path}/fastlane/metadata/android'),
  )) {
    for (final MapEntry(key: name, value: limit) in playListingLimits.entries) {
      final path = 'fastlane/metadata/android/$locale/$name';
      final file = File('${root.path}/$path');
      if (file.existsSync()) problems.addAll(_lengthProblems(file, path, limit));
    }
  }
  return problems;
}

List<String> _appStoreTextProblems(Directory root) {
  final problems = <String>[];
  for (final locale in _localeDirectories(
    Directory('${root.path}/fastlane/metadata/ios'),
  )) {
    for (final MapEntry(key: name, value: limit) in appStoreTextLimits.entries) {
      final path = 'fastlane/metadata/ios/$locale/$name';
      final file = File('${root.path}/$path');
      if (file.existsSync()) problems.addAll(_lengthProblems(file, path, limit));
    }

    final path = 'fastlane/metadata/ios/$locale/keywords.txt';
    final file = File('${root.path}/$path');
    if (file.existsSync()) {
      final bytes = utf8.encode(file.readAsStringSync()).length;
      if (bytes > appStoreKeywordsByteLimit) {
        problems.add(
          '$path has $bytes bytes in UTF-8, newlines included, and the store takes at most $appStoreKeywordsByteLimit.',
        );
      }
    }
  }
  return problems;
}

List<String> _lengthProblems(File file, String path, int limit) {
  final length = file.readAsStringSync().runes.length;
  if (length <= limit) return const [];
  return [
    '$path has $length characters, newlines included, and the store takes at most $limit.',
  ];
}

List<String> _localeDirectories(Directory parent) {
  if (!parent.existsSync()) return const [];
  return [
    for (final entity in parent.listSync())
      if (entity is Directory) entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
  ]..sort();
}

Future<void> main(List<String> arguments) async {
  final root = Directory.current;
  final status = await Process.run('git', [
    'status',
    '--porcelain',
  ], workingDirectory: root.path);
  if (status.exitCode != 0) {
    stderr.writeln('git status failed: ${status.stderr}');
    exitCode = 1;
    return;
  }

  final problems = releaseProblems(
    root: root,
    gitStatus: status.stdout as String,
    forBuild: !arguments.contains('--metadata'),
  );
  if (problems.isEmpty) {
    final version = parsePubspecVersion(
      File('${root.path}/pubspec.yaml').readAsStringSync(),
    )!;
    stdout.writeln(
      'Release check passed for ${version.name}+${version.build}.',
    );
    return;
  }

  stderr.writeln('Release check failed:');
  for (final problem in problems) {
    stderr.writeln('- $problem');
  }
  exitCode = 1;
}
