import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:kkomkkomi/application/application.dart';

/// Writes published reports to Firestore and their photos to Storage, as `firestore.rules` and `storage.rules`
/// expect them.
///
/// The adapter does not start Firebase: the queue asks `FirebaseIdentity` for the user ID before each job, and an ID
/// means that Firebase started. Every decision about the order of the steps and about retries is in the queue.
final class FirebasePublisher implements Publisher {
  /// The `firestore` and `storage` arguments replace Firebase in a test.
  new({this._firestore, this._storage});

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;

  FirebaseFirestore get _database => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _files => _storage ?? FirebaseStorage.instance;

  @override
  bool get isAvailable => true;

  @override
  Future<void> writePage(String pageId, PublishedPage page) =>
      _guard(() => _database.doc('clientPages/$pageId').set(_pageData(page)));

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List bytes, {required Future<void> cancel}) => _guard(() async {
    // The rules refuse an object without this content type.
    final task = _files.ref(objectPath).putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    // A cancelled task ends with the code `canceled`. The end of the task, not the answer of `cancel`, says whether
    // the object arrived, so a failure of `cancel` is ignored.
    cancel.then((_) => task.cancel()).ignore();
    await task;
  });

  @override
  Future<void> writeReport({required String pageId, required String visitId, required PublishedReport report}) =>
      _guard(
        () => _database.doc('clientPages/$pageId/reports/$visitId').set({
          'visitDate': report.visitDate.toString(),
          'publishedAt': Timestamp.fromDate(report.publishedAt),
          'zones': [
            for (final zone in report.zones)
              {
                'name': zone.name,
                'note': zone.note,
                'beforePhoto': zone.beforePhoto,
                'afterPhoto': zone.afterPhoto,
              },
          ],
        }),
      );

  @override
  Future<void> revokePage(String pageId, PublishedPage page, {required DateTime revokedAt}) => _guard(
    () => _database.doc('clientPages/$pageId').set({..._pageData(page), 'revokedAt': Timestamp.fromDate(revokedAt)}),
  );

  @override
  Future<void> deletePhoto(String objectPath) => _guard(() async {
    try {
      await _files.ref(objectPath).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  });

  static Map<String, Object?> _pageData(PublishedPage page) => {
    'ownerUid': page.ownerUid,
    'companyName': page.companyName,
    'clientName': page.clientName,
    'createdAt': Timestamp.fromDate(page.createdAt),
  };

  static Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on FirebaseException catch (error) {
      throw PublishException(publishErrorKindOf(error), '${error.plugin}/${error.code}: ${error.message}');
    }
  }
}

/// The codes of Firestore and Storage failures that a retry cannot fix.
///
/// Every other code, such as `unavailable`, `deadline-exceeded`, `retry-limit-exceeded`, or `unauthenticated` while a
/// token is renewed, can pass with time.
const _refusedCodes = {
  'permission-denied',
  'unauthorized',
  'invalid-argument',
  'failed-precondition',
  'out-of-range',
  'unimplemented',
  'bucket-not-found',
  'project-not-found',
  'no-default-bucket',
  'invalid-url',
};

/// Whether a retry can fix [error], a failure of Firestore or Storage.
PublishErrorKind publishErrorKindOf(FirebaseException error) =>
    _refusedCodes.contains(error.code) ? PublishErrorKind.refused : PublishErrorKind.transient;
