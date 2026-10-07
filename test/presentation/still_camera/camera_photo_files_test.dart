import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/still_camera/camera_photo_files.dart';
import 'package:pdf/pdf.dart';

import '../../helpers/helpers.dart';

void main() {
  group('normalizeCameraJpeg', () {
    for (final size in [(2000, 1000), (1000, 2000)]) {
      test('limits the whole ${size.$1} x ${size.$2} image to a 1600 pixel edge', () {
        final original = image.encodeJpg(image.Image(width: size.$1, height: size.$2));
        final bytes = normalizeCameraJpeg(original);
        final decoded = image.decodeJpg(bytes)!;
        expect((decoded.width, decoded.height), size.$1 > size.$2 ? (1600, 800) : (800, 1600));
      });
    }

    test('keeps a small image at its size and applies JPEG quality 80', () {
      final original = image.encodeJpg(image.Image(width: 40, height: 20));
      final bytes = normalizeCameraJpeg(original);
      final decoded = image.decodeJpg(bytes)!;
      expect((decoded.width, decoded.height), (40, 20));
      final table = List.generate(
        bytes.length - 1,
        (i) => i,
      ).firstWhere((i) => bytes[i] == 0xff && bytes[i + 1] == 0xdb);
      // Quality 80 scales the first luminance quantization coefficient (16) to 6.
      expect(bytes[table + 5], 6);
    });

    test('bakes the visible orientation and removes location and descriptive metadata', () {
      final original = gpsPhotoBytes();
      final raw = PdfJpegInfo(original);
      final bytes = normalizeCameraJpeg(original);
      final decoded = image.decodeJpg(bytes)!;
      expect((decoded.width, decoded.height), (raw.height, raw.width));
      expect(holdsMetadataText(bytes), isFalse);
      expect(bytes, withoutLocation(bytes));
      expect(PdfJpegInfo(bytes).orientation, PdfImageOrientation.topLeft);
    });

    for (final bytes in [
      Uint8List.fromList([1, 2, 3]),
      image.encodePng(image.Image(width: 2, height: 2)),
    ]) {
      test('refuses malformed or non-JPEG camera output ${bytes.length}', () {
        expect(() => normalizeCameraJpeg(bytes), throwsFormatException);
      });
    }
  });

  group('TemporaryCameraPhotoFiles', () {
    late Directory root;
    late TemporaryCameraPhotoFiles files;
    setUp(() {
      root = Directory.systemTemp.createTempSync('camera-photo-files');
      files = TemporaryCameraPhotoFiles(temporaryDirectory: () async => root, idGenerator: SequenceIdGenerator());
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('writes a distinct normalized temporary file and removes the owned camera source', () async {
      final raw = File('${root.path}/raw.jpg')..writeAsBytesSync(gpsPhotoBytes());
      final path = await files.normalize(raw.path);
      expect(path, isNot(raw.path));
      expect(File(path).existsSync(), isTrue);
      expect(raw.existsSync(), isFalse);
      expect(holdsMetadataText(await File(path).readAsBytes()), isFalse);
      await files.discard(path);
      await files.discard(path);
      expect(File(path).existsSync(), isFalse);
    });

    test('removes failed camera input without creating a normalized output', () async {
      final raw = File('${root.path}/bad.jpg')..writeAsBytesSync([1, 2, 3]);
      await expectLater(files.normalize(raw.path), throwsFormatException);
      expect(raw.existsSync(), isFalse);
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('preserves a write failure and removes its owned source when the output cannot be written', () async {
      final raw = File('${root.path}/raw.jpg')..writeAsBytesSync(gpsPhotoBytes());
      // A file where the output directory belongs makes recursive creation fail after choosing the output path.
      File('${root.path}/kkomkkomi-camera').writeAsStringSync('occupied');
      await expectLater(files.normalize(raw.path), throwsA(isA<FileSystemException>()));
      expect(raw.existsSync(), isFalse);
      expect(File('${root.path}/kkomkkomi-camera').readAsStringSync(), 'occupied');
    });

    test('reports a missing source as a file error', () async {
      await expectLater(files.normalize('${root.path}/missing.jpg'), throwsA(isA<FileSystemException>()));
    });
  });
}
