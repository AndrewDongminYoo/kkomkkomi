import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_check.dart';

void main() {
  late Directory root;

  void write(String path, String content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('release_check_test');
    write('pubspec.yaml', 'name: kkomkkomi\nversion: 1.2.0+7\n');
    write(
      'CHANGELOG.md',
      '# Changelog\n\n## [Unreleased]\n\n## [1.2.0] - 2026-10-04\n\n- A change.\n',
    );
    write('fastlane/metadata/android/en-US/changelogs/7.txt', 'A change.\n');
    write('fastlane/metadata/android/ko-KR/changelogs/7.txt', '바뀐 점.\n');
    write('fastlane/metadata/ios/ko/name.txt', '꼼꼬미\n');
    write(
      revenueCatKeysPath,
      '{"REVENUECAT_IOS_API_KEY": "", "REVENUECAT_ANDROID_API_KEY": ""}\n',
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('parsePubspecVersion', () {
    test('reads the name and the build', () {
      expect(parsePubspecVersion('name: a\nversion: 1.0.0+1\n'), (
        name: '1.0.0',
        build: 1,
      ));
    });

    test('is null without a build number', () {
      expect(parsePubspecVersion('version: 1.0.0\n'), isNull);
    });
  });

  group('releaseProblems', () {
    test('finds nothing in a clean tree with every input in place', () {
      expect(releaseProblems(root: root, gitStatus: ''), isEmpty);
    });

    test('names each uncommitted change', () {
      final problems = releaseProblems(
        root: root,
        gitStatus: ' M pubspec.yaml\n?? notes.txt\n',
      );

      expect(problems, hasLength(1));
      expect(problems.single, contains('2 uncommitted change(s)'));
      expect(problems.single, contains(' M pubspec.yaml'));
      expect(problems.single, contains('?? notes.txt'));
    });

    test('fails when pubspec.yaml has no version with a build number', () {
      write('pubspec.yaml', 'name: kkomkkomi\nversion: 1.2.0\n');

      expect(releaseProblems(root: root, gitStatus: ''), [
        contains('version: <name>+<build>'),
      ]);
    });

    test('fails when pubspec.yaml is missing', () {
      File('${root.path}/pubspec.yaml').deleteSync();

      expect(releaseProblems(root: root, gitStatus: ''), [
        contains('version: <name>+<build>'),
      ]);
    });

    test('fails when CHANGELOG.md has no entry for the version', () {
      write(
        'CHANGELOG.md',
        '# Changelog\n\n## [1.1.0] - 2026-10-01\n\n- An old change.\n',
      );

      expect(releaseProblems(root: root, gitStatus: ''), [
        contains('no entry "## [1.2.0]"'),
      ]);
    });

    test('does not take a longer version for the version', () {
      write(
        'CHANGELOG.md',
        '# Changelog\n\n## [1.2.0.1] - 2026-10-01\n\n## [1.2.01] - 2026-10-01\n',
      );

      expect(releaseProblems(root: root, gitStatus: ''), [
        contains('no entry "## [1.2.0]"'),
      ]);
    });

    test('fails when CHANGELOG.md is missing', () {
      File('${root.path}/CHANGELOG.md').deleteSync();

      expect(releaseProblems(root: root, gitStatus: ''), [
        'CHANGELOG.md does not exist.',
      ]);
    });

    test('fails for each locale without the Play changelog of the build', () {
      File('${root.path}/fastlane/metadata/android/ko-KR/changelogs/7.txt').renameSync(
        '${root.path}/fastlane/metadata/android/ko-KR/changelogs/6.txt',
      );

      expect(releaseProblems(root: root, gitStatus: ''), [
        contains('fastlane/metadata/android/ko-KR/changelogs/7.txt is missing'),
      ]);
    });

    test('fails when no Android locale exists', () {
      Directory('${root.path}/fastlane/metadata/android').deleteSync(recursive: true);

      expect(releaseProblems(root: root, gitStatus: ''), [
        contains('no locale directory'),
      ]);
    });

    test('counts newlines toward the Play limit', () {
      write(
        'fastlane/metadata/android/en-US/changelogs/7.txt',
        '${'a' * (playChangelogLimit - 1)}\n',
      );
      expect(releaseProblems(root: root, gitStatus: ''), isEmpty);

      write(
        'fastlane/metadata/android/en-US/changelogs/7.txt',
        '${'a' * playChangelogLimit}\n',
      );
      expect(releaseProblems(root: root, gitStatus: ''), [
        'fastlane/metadata/android/en-US/changelogs/7.txt has 501 characters, newlines included, and the store takes at most 500.',
      ]);
    });

    test('counts a Korean syllable as one character', () {
      write(
        'fastlane/metadata/android/ko-KR/changelogs/7.txt',
        '가' * playChangelogLimit,
      );

      expect(releaseProblems(root: root, gitStatus: ''), isEmpty);
    });

    test('fails when App Store release notes are over the limit', () {
      write(
        'fastlane/metadata/ios/ko/release_notes.txt',
        '가' * appStoreReleaseNotesLimit,
      );
      expect(releaseProblems(root: root, gitStatus: ''), isEmpty);

      write(
        'fastlane/metadata/ios/ko/release_notes.txt',
        '가' * (appStoreReleaseNotesLimit + 1),
      );
      expect(releaseProblems(root: root, gitStatus: ''), [
        contains(
          'fastlane/metadata/ios/ko/release_notes.txt has 4001 characters',
        ),
      ]);
    });

    // The limits are literal here, so that a wrong limit in the check fails a
    // test.
    for (final (path, limit) in [
      ('fastlane/metadata/android/en-US/title.txt', 30),
      ('fastlane/metadata/android/ko-KR/short_description.txt', 80),
      ('fastlane/metadata/android/en-US/full_description.txt', 4000),
      ('fastlane/metadata/ios/ko/name.txt', 30),
      ('fastlane/metadata/ios/en-US/subtitle.txt', 30),
      ('fastlane/metadata/ios/ko/description.txt', 4000),
      ('fastlane/metadata/ios/en-US/promotional_text.txt', 170),
    ]) {
      test('fails when $path is longer than $limit characters', () {
        write(path, '${'가' * (limit - 1)}\n');
        expect(releaseProblems(root: root, gitStatus: ''), isEmpty);

        write(path, '${'가' * limit}\n');
        expect(releaseProblems(root: root, gitStatus: ''), [
          '$path has ${limit + 1} characters, newlines included, and the store takes at most $limit.',
        ]);
      });
    }

    test('measures App Store keywords in UTF-8 bytes', () {
      const path = 'fastlane/metadata/ios/ko/keywords.txt';
      // 33 syllables of 3 bytes each and a newline make 100 bytes.
      write(path, '${'가' * 33}\n');
      expect(releaseProblems(root: root, gitStatus: ''), isEmpty);

      write(path, '${'가' * 34}\n');
      expect(releaseProblems(root: root, gitStatus: ''), [
        '$path has 103 bytes in UTF-8, newlines included, and the store takes at most 100.',
      ]);
    });

    test('fails when the RevenueCat keys file is missing, and names the example file', () {
      File('${root.path}/$revenueCatKeysPath').deleteSync();

      expect(releaseProblems(root: root, gitStatus: ''), [
        allOf(
          contains('config/revenuecat.json is missing'),
          contains('config/revenuecat.example.json'),
        ),
      ]);
    });

    test('does not read the RevenueCat keys file for a release that builds nothing', () {
      File('${root.path}/$revenueCatKeysPath').deleteSync();

      expect(releaseProblems(root: root, gitStatus: '', forBuild: false), isEmpty);
    });

    test('passes with the RevenueCat keys file that holds empty keys, for a build without subscriptions', () {
      expect(
        File('${root.path}/$revenueCatKeysPath').readAsStringSync(),
        contains('"REVENUECAT_IOS_API_KEY": ""'),
      );
      expect(releaseProblems(root: root, gitStatus: ''), isEmpty);
    });

    test('reports every problem at once', () {
      write('CHANGELOG.md', '# Changelog\n');
      File('${root.path}/fastlane/metadata/android/en-US/changelogs/7.txt').deleteSync();

      expect(releaseProblems(root: root, gitStatus: '?? a\n'), hasLength(3));
    });
  });
}
