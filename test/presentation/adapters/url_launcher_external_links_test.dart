import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final link = Uri.parse('https://kkomkkomi.web.app/privacy/');

  group('UrlLauncherExternalLinks', () {
    test('gives the launcher the link and answers what it answers', () async {
      final launched = <Uri>[];
      for (final answer in [true, false]) {
        final ExternalLinks links = UrlLauncherExternalLinks(
          launch: (uri) async {
            launched.add(uri);
            return answer;
          },
        );

        expect(await links.open(link), answer);
      }
      expect(launched, [link, link]);
    });

    for (final (kind, failure) in <(String, Object)>[
      ('an exception', PlatformException(code: 'ACTIVITY_NOT_FOUND')),
      ('an error', StateError('no plugin')),
    ]) {
      test('answers false when the launcher throws $kind', () async {
        final links = UrlLauncherExternalLinks(
          launch: (_) async => Error.throwWithStackTrace(failure, StackTrace.current),
        );

        expect(await links.open(link), isFalse);
      });
    }

    test('opens the link outside the app through url_launcher, without asking canLaunchUrl first', () async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(await const UrlLauncherExternalLinks().open(link), isTrue);
      expect(calls.single.method, 'launch');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['url'], '$link');
      // `LaunchMode.externalApplication` is the one mode that opens a web link in neither a web view nor Safari.
      expect(arguments['useWebView'], isFalse);
      expect(arguments['useSafariVC'], isFalse);
    });
  });
}
