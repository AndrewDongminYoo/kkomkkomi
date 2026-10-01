import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

void main() {
  late Directory root;
  late Directory documents;

  /// Makes a file that stands for a photo of the picker, with [name] and three bytes.
  File pickedFile(String name) => File('${root.path}/picked/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync([1, 2, 3]);

  File stored(String relativePath) => File('${documents.path}/$relativePath');

  DocumentsPhotoStore store() => DocumentsPhotoStore(documentsDirectory: () async => documents);

  setUp(() {
    root = Directory.systemTemp.createTempSync('documents_photo_store_test');
    documents = Directory('${root.path}/documents')..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('DocumentsPhotoStore', () {
    group('save', () {
      test('copies the picked file into photos/<visitId>/ under the documents directory', () async {
        final picked = pickedFile('scaled_camera.jpg');

        final photo = await store().save(sourcePath: picked.path, visitId: 'visit-1', photoId: 'photo-1');

        expect(stored('photos/visit-1/photo-1.jpg').readAsBytesSync(), [1, 2, 3]);
        expect(stored(photo.path).existsSync(), isTrue);
        expect(picked.existsSync(), isTrue);
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
          ..writeAsBytesSync([1]);

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

    group('read', () {
      test('gives the bytes of the file of the photo', () async {
        final photo = await store().save(
          sourcePath: pickedFile('scaled_camera.jpg').path,
          visitId: 'visit-1',
          photoId: 'photo-1',
        );

        expect(await store().read(photo), [1, 2, 3]);
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
