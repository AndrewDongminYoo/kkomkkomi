// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final link = Uri.parse('https://kkomkkomi.web.app/r/page-1/visit-1');

  /// Answers each call of the plugin with [answer], and keeps the calls.
  List<MethodCall> answerWith(Future<Object?> Function() answer) {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return answer();
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    return calls;
  }

  group('SharePlusLinkShare', () {
    test('gives the plugin the link as a URI', () async {
      final calls = answerWith(() async => 'dev.fluttercommunity.plus/share/unavailable');

      await const SharePlusLinkShare().shareLink(link);

      expect(calls.single.method, 'share');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['uri'], '$link');
      expect(arguments.containsKey('text'), isFalse);
    });

    test('counts a share sheet that the person closed as a share', () async {
      answerWith(() async => '');

      await expectLater(const SharePlusLinkShare().shareLink(link), completes);
    });

    test('fails with the exception of the plugin as the cause', () async {
      final cause = PlatformException(code: 'share_failed');
      answerWith(() async => throw cause);

      await expectLater(
        const SharePlusLinkShare().shareLink(link),
        throwsA(isA<ReportShareException>().having((exception) => exception.cause, 'cause', isA<PlatformException>())),
      );
    });
  });
}
