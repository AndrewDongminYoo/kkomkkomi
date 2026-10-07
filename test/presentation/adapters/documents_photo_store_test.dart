// 🎯 Dart imports:
import 'dart:io';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../helpers/helpers.dart';

void main() {
  late Directory root;
  late Directory documents;

  /// A JPEG without metadata, which the store keeps as it is.
  final clean = File('test/fixtures/photo_no_exif.jpg').readAsBytesSync();

  /// Makes a file that stands for a photo of the picker, with [name] and the [bytes] of a JPEG.
  File pickedFile(String name, [List<int>? bytes]) => File('${root.path}/picked/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes ?? clean);

  File stored(String relativePath) => File('${documents.path}/$relativePath');

  DocumentsPhotoStore store() => DocumentsPhotoStore(documentsDirectory: () async => documents);

  setUp(() {
    root = Directory.systemTemp.createTempSync('documents_photo_store_test');
    documents = Directory('${root.path}/documents')..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('DocumentsPhotoStore', () {
    group('save', () {
      for (final (width, height) in [(1601, 8), (8, 1601)]) {
        test('limits a converted PNG edge for $width x $height pixels', () async {
          final png = image.Image(width: width, height: height);
          final photo = await store().save(
            sourcePath: pickedFile('big.png', image.encodePng(png)).path,
            visitId: 'visit-1',
            photoId: 'big',
          );
          final decoded = image.decodeJpg(stored(photo.path).readAsBytesSync())!;
          expect(decoded.width, lessThanOrEqualTo(1600));
          expect(decoded.height, lessThanOrEqualTo(1600));
        });
      }
      test('normalizes a transparent PNG to a white-backed JPEG before storing it', () async {
        final png = image.Image(width: 8, height: 6, numChannels: 4);
        final picked = pickedFile('gallery.png', image.encodePng(png));
        final photo = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'png');
        expect(photo.path, 'photos/visit-1/png.jpg');
        final bytes = stored(photo.path).readAsBytesSync();
        final decoded = image.decodeJpg(bytes)!;
        expect((decoded.width, decoded.height), (8, 6));
        expect(decoded.getPixel(0, 0).r, greaterThan(250));
        expect(bytes, withoutLocation(bytes));
      });

      test('refuses a malformed PNG before creating a photo file', () async {
        final picked = pickedFile('bad.png', [0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
        await expectLater(
          store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'bad'),
          throwsFormatException,
        );
        expect(Directory('${documents.path}/photos').existsSync(), isFalse);
      });
      test('copies the picked file into photos/<visitId>/ under the documents directory', () async {
        final picked = pickedFile('scaled_camera.jpg');

        final photo = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1');

        expect(stored('photos/visit-1/photo-1.jpg').readAsBytesSync(), clean);
        expect(stored(photo.path).existsSync(), isTrue);
        expect(picked.existsSync(), isTrue);
      });

      test('keeps the picked photo without its location and its other metadata, and with its orientation', () async {
        final withGps = gpsPhotoBytes();
        expect(holdsMetadataText(withGps), isTrue);

        final photo = await store().save(
          sourcePath: pickedFile('scaled_camera.jpg', withGps).path,
          visitId: 'visit-1',
          photoId: 'photo-1',
        );

        final kept = stored(photo.path).readAsBytesSync();
        expect(holdsMetadataText(kept), isFalse);
        expect(kept, withoutLocation(withGps));
        expect(PdfJpegInfo(kept).orientation, PdfImageOrientation.rightTop);
      });

      test('fails with a FormatException and keeps no file when the picked file is no well-formed JPEG', () async {
        final picked = pickedFile('scaled_camera.jpg', File('test/fixtures/photo_truncated.jpg').readAsBytesSync());

        await expectLater(
          store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1'),
          throwsFormatException,
        );
        expect(Directory('${documents.path}/photos').existsSync(), isFalse);
      });

      test('returns a path that is relative to the documents directory', () async {
        final photo = await store().save(
          sourcePath: pickedFile('scaled_camera.jpg').path,
          visitId: 'visit-1',
          photoId: 'photo-1',
        );

        expect(photo, PhotoRef('photos/visit-1/photo-1.jpg'));
        expect(photo.path, isNot(contains(documents.path)));
        expect(photo.path, isNot(startsWith('/')));
      });

      test('keeps the photos of one visit under different names', () async {
        final picked = pickedFile('scaled_camera.jpg');

        final first = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1');
        final second = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-2');

        expect(first, isNot(second));
        expect(stored(first.path).existsSync(), isTrue);
        expect(stored(second.path).existsSync(), isTrue);
      });

      test('keeps the extension of the picked file, and adds none when the file has none', () async {
        Future<String> pathFor(String name) async =>
            (await store().save(sourcePath: pickedFile(name).path, visitId: 'visit-1', photoId: 'photo-1')).path;

        expect(await pathFor('camera.PNG'), 'photos/visit-1/photo-1.PNG');
        expect(await pathFor('archive.tar.jpeg'), 'photos/visit-1/photo-1.jpeg');
        expect(await pathFor('camera'), 'photos/visit-1/photo-1');
        expect(await pathFor('.hidden'), 'photos/visit-1/photo-1');
      });

      test('reads the extension from the file name and not from a directory name', () async {
        final picked = File('${root.path}/picked.cache/camera')
          ..createSync(recursive: true)
          ..writeAsBytesSync(clean);

        final photo = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1');

        expect(photo.path, 'photos/visit-1/photo-1');
      });

      test('fails with an exception when the picked file is not there', () async {
        await expectLater(
          store().save(sourcePath: '${root.path}/picked/gone.jpg', visitId: 'visit-1', photoId: 'photo-1'),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('delete', () {
      test('deletes the file of the photo and keeps the other photos', () async {
        final picked = pickedFile('scaled_camera.jpg');
        final first = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1');
        final second = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-2');

        await store().delete(first);

        expect(stored(first.path).existsSync(), isFalse);
        expect(stored(second.path).existsSync(), isTrue);
      });

      test('does not fail for a file that is not there', () async {
        await expectLater(store().delete(PhotoRef('photos/visit-1/gone.jpg')), completes);
      });
    });

    group('deleteAll', () {
      test('deletes every photo with the photos directory, and keeps the other files of the documents', () async {
        final picked = pickedFile('scaled_camera.jpg');
        final first = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1');
        final second = await store().save(sourcePath: picked.path, visitId: 'visit-2', photoId: 'photo-2');
        final other = File('${documents.path}/other.txt')..writeAsStringSync('kept');

        await store().deleteAll();

        expect(stored(first.path).existsSync(), isFalse);
        expect(stored(second.path).existsSync(), isFalse);
        expect(Directory('${documents.path}/photos').existsSync(), isFalse);
        expect(other.existsSync(), isTrue);
      });

      test('does not fail when no photo was ever kept', () async {
        await expectLater(store().deleteAll(), completes);
      });

      test('fails when the documents directory cannot be found', () async {
        final store = DocumentsPhotoStore(documentsDirectory: () async => throw const FileSystemException('no path'));

        await expectLater(store.deleteAll(), throwsA(isA<FileSystemException>()));
      });
    });

    group('read', () {
      test('gives the bytes of the file of the photo', () async {
        final photo = await store().save(
          sourcePath: pickedFile('scaled_camera.jpg').path,
          visitId: 'visit-1',
          photoId: 'photo-1',
        );

        expect(await store().read(photo), clean);
      });

      test('fails with an exception for a file that is not there', () async {
        await expectLater(store().read(PhotoRef('photos/visit-1/gone.jpg')), throwsA(isA<FileSystemException>()));
      });
    });

    test('directoryPath gives the documents directory', () async {
      expect(await store().directoryPath(), documents.path);
    });
  });
}
