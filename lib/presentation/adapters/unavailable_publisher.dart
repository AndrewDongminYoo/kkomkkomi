import 'dart:typed_data';

import 'package:kkomkkomi/application/application.dart';

/// Reports that publishing is unavailable, for a flavor that does not start Firebase.
///
/// The queue stops each job without a call to this adapter, so a call is a defect of the caller.
final class UnavailablePublisher implements Publisher {
  const new();

  static const _unavailable = PublishException(PublishErrorKind.refused, 'This flavor has no backend');

  @override
  bool get isAvailable => false;

  @override
  Future<void> writePage(String pageId, PublishedPage page) async => throw _unavailable;

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List bytes, {required Future<void> cancel}) async =>
      throw _unavailable;

  @override
  Future<void> writeReport({required String pageId, required String visitId, required PublishedReport report}) async =>
      throw _unavailable;

  @override
  Future<void> revokePage(String pageId, PublishedPage page, {required DateTime revokedAt}) async => throw _unavailable;

  @override
  Future<void> deletePhoto(String objectPath) async => throw _unavailable;

  @override
  Future<void> deleteReport({required String pageId, required String visitId}) async => throw _unavailable;

  @override
  Future<void> deletePage(String pageId) async => throw _unavailable;
}
