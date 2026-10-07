import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/adapters/random_id_generator.dart';
import 'package:path_provider/path_provider.dart';

/// Preserves the whole visible camera image while applying the existing photo bounds and metadata policy.
Uint8List normalizeCameraJpeg(Uint8List bytes) {
  final decoded = image.decodeJpg(withoutLocation(bytes));
  if (decoded == null) throw const FormatException('The camera JPEG could not be decoded');
  var oriented = image.bakeOrientation(decoded);
  if (oriented.width > 1600 || oriented.height > 1600) {
    oriented = oriented.width >= oriented.height
        ? image.copyResize(oriented, width: 1600)
        : image.copyResize(oriented, height: 1600);
  }
  return withoutLocation(image.encodeJpg(oriented, quality: 80));
}

abstract interface class CameraPhotoFiles {
  Future<String> normalize(String sourcePath);
  Future<void> discard(String path);
}

final class TemporaryCameraPhotoFiles implements CameraPhotoFiles {
  const new({this._temporaryDirectory = getTemporaryDirectory, this._idGenerator = const RandomIdGenerator()});
  final Future<Directory> Function() _temporaryDirectory;
  final IdGenerator _idGenerator;

  @override
  Future<String> normalize(String sourcePath) async {
    String? output;
    try {
      final bytes = normalizeCameraJpeg(await File(sourcePath).readAsBytes());
      final root = await _temporaryDirectory();
      output = '${root.path}/kkomkkomi-camera/${_idGenerator.newId()}.jpg';
      final target = File(output);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes);
      return output;
    } on Object {
      if (output != null) await discard(output);
      rethrow;
    } finally {
      // This is called only for a fresh file owned by this camera operation, never a saved report photo.
      await discard(sourcePath);
    }
  }

  @override
  Future<void> discard(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // An unused cache file is harmless; cleanup must not replace the capture/save outcome.
      return;
    }
  }
}
