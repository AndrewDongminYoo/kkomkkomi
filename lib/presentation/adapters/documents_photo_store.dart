// 🎯 Dart imports:
import 'dart:io';
import 'dart:typed_data';

// 📦 Package imports:
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Keeps the photo files under the application documents directory, which `path_provider` finds.
final class DocumentsPhotoStore implements PhotoStore {
  /// The `documentsDirectory` argument replaces the directory of the platform in a test.
  const new({this._documentsDirectory = getApplicationDocumentsDirectory});

  static final _separator = RegExp(r'[/\\]');

  final Future<Directory> Function() _documentsDirectory;

  @override
  Future<PhotoRef> save({required String sourcePath, required String visitId, required String photoId}) async {
    // The stored path has `/` on every platform, so that it names the same file wherever it is read.

    // The location goes before the photo reaches the directory, so the file, the PDF, and an upload never hold it
    // (issue 20). A PNG becomes JPEG; unsupported or malformed input fails before anything is written.
    final original = await File(sourcePath).readAsBytes();
    final Uint8List bytes;
    final String extension;
    if (original.length >= 8 &&
        original[0] == 0x89 &&
        original[1] == 0x50 &&
        original[2] == 0x4e &&
        original[3] == 0x47) {
      final decoded = image.decodePng(original);
      if (decoded == null) throw const FormatException('The selected PNG could not be decoded');
      var oriented = image.bakeOrientation(decoded);
      if (oriented.width > 1600 || oriented.height > 1600) {
        oriented = oriented.width >= oriented.height
            ? image.copyResize(oriented, width: 1600)
            : image.copyResize(oriented, height: 1600);
      }
      final background = image.Image(width: oriented.width, height: oriented.height);
      image.fill(background, color: image.ColorRgb8(255, 255, 255));
      image.compositeImage(background, oriented);
      bytes = withoutLocation(image.encodeJpg(background, quality: 80));
      extension = '.jpg';
    } else {
      bytes = withoutLocation(original);
      extension = _extensionOf(sourcePath);
    }
    final photo = PhotoRef('photos/$visitId/$photoId$extension');
    final target = await _fileOf(photo);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
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
  Future<void> deleteAll() async {
    try {
      await Directory('${await directoryPath()}/photos').delete(recursive: true);
    } on PathNotFoundException {
      // No photo was ever kept, or an earlier call deleted them.
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
