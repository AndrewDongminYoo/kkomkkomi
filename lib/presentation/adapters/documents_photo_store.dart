import 'dart:io';
import 'dart:typed_data';

import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the photo files under the application documents directory, which `path_provider` finds.
final class DocumentsPhotoStore implements PhotoStore {
  /// The `documentsDirectory` argument replaces the directory of the platform in a test.
  const new({this._documentsDirectory = getApplicationDocumentsDirectory});

  static final _separator = RegExp(r'[/\\]');

  final Future<Directory> Function() _documentsDirectory;

  @override
  Future<PhotoRef> save({required String sourcePath, required String visitId, required String photoId}) async {
    // The stored path has `/` on every platform, so that it names the same file wherever it is read.
    final photo = PhotoRef('photos/$visitId/$photoId${_extensionOf(sourcePath)}');
    final target = await _fileOf(photo);
    await target.parent.create(recursive: true);
    await File(sourcePath).copy(target.path);
    return photo;
  }

  @override
  Future<void> delete(PhotoRef photo) async {
    try {
      await (await _fileOf(photo)).delete();
    } on PathNotFoundException {
      // The file is gone, which is what the caller wants.
    }
  }

  @override
  Future<Uint8List> read(PhotoRef photo) async => await (await _fileOf(photo)).readAsBytes();

  @override
  Future<String> directoryPath() async => (await _documentsDirectory()).path;

  Future<File> _fileOf(PhotoRef photo) async => File('${await directoryPath()}/${photo.path}');

  /// The extension of the file name in [path] with its dot, or an empty text when the name has none.
  static String _extensionOf(String path) {
    final name = path.split(_separator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot);
  }
}
