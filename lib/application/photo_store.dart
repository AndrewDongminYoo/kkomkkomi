import 'dart:typed_data';

import 'package:kkomkkomi/domain/domain.dart';

/// Keeps the photo files of the visits under the application documents directory.
abstract interface class PhotoStore {
  /// Copies the JPEG file at [sourcePath] into `photos/<visitId>/` without its location, through `withoutLocation`,
  /// and returns the path of the copy.
  ///
  /// The path is relative to the application documents directory. The name of the copy is [photoId] with the
  /// extension of [sourcePath], so a copy never replaces a file that another photo identifier named. Throws a
  /// [FormatException] when the file is not a well-formed JPEG file.
  Future<PhotoRef> save({required String sourcePath, required String visitId, required String photoId});

  /// Deletes the file of [photo]. A file that does not exist is no failure.
  Future<void> delete(PhotoRef photo);

  /// The bytes of the file of [photo]. Throws an exception when the file does not exist.
  Future<Uint8List> read(PhotoRef photo);

  /// The absolute path of the directory that the path of every [PhotoRef] is relative to.
  ///
  /// The path can change between launches of the app, so it must not be stored.
  Future<String> directoryPath();
}
