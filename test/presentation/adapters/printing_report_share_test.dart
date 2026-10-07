// 🐦 Flutter imports:
import 'package:flutter/services.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  group('PrintingReportShare', () {
    test('gives the plugin the bytes and the file name', () async {
      final calls = <({Uint8List bytes, String filename})>[];
      final share = PrintingReportShare(
        sharePdf: ({required bytes, filename = 'document.pdf'}) async {
          calls.add((bytes: bytes, filename: filename));
          return true;
        },
      );

      await share.sharePdf(bytes: bytes, fileName: '청소 완료 보고서_행복빌딩_2026-10-01.pdf');

      expect(calls.single.bytes, same(bytes));
      expect(calls.single.filename, '청소 완료 보고서_행복빌딩_2026-10-01.pdf');
    });

    test('fails when the plugin answers that nothing was shared', () async {
      final share = PrintingReportShare(sharePdf: ({required bytes, filename = 'document.pdf'}) async => false);

      await expectLater(
        share.sharePdf(bytes: bytes, fileName: 'report.pdf'),
        throwsA(isA<ReportShareException>().having((exception) => exception.cause, 'cause', isNull)),
      );
    });

    test('fails with the exception of the plugin as the cause', () async {
      final cause = PlatformException(code: 'share_failed');
      final share = PrintingReportShare(sharePdf: ({required bytes, filename = 'document.pdf'}) async => throw cause);

      await expectLater(
        share.sharePdf(bytes: bytes, fileName: 'report.pdf'),
        throwsA(isA<ReportShareException>().having((exception) => exception.cause, 'cause', same(cause))),
      );
    });

    test('calls the printing plugin unless it is given another function', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      const channel = MethodChannel('net.nfet.printing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 1;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );

      await const PrintingReportShare().sharePdf(bytes: bytes, fileName: 'report.pdf');

      expect(calls.single.method, 'sharePdf');
      expect((calls.single.arguments as Map<Object?, Object?>)['name'], 'report.pdf');
      expect((calls.single.arguments as Map<Object?, Object?>)['doc'], bytes);
    });
  });

  test('ReportShareException names its cause in its text', () {
    expect('${ReportShareException(cause: StateError('no window'))}', contains('no window'));
  });
}
