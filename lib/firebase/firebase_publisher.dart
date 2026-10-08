// 🎯 Dart imports:
import 'dart:async';
import 'dart:typed_data';

// 📦 Package imports:
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';

/// Writes published reports to Firestore and their photos to Storage, as `firestore.rules` and `storage.rules`
/// expect them.
///
/// The adapter does not start Firebase: the queue asks `FirebaseIdentity` for the user ID before each job, and an ID
/// means that Firebase started. Every decision about the order of the steps and about retries is in the queue.
final class FirebasePublisher implements Publisher {
  /// The `firestore` and `storage` arguments replace Firebase in a test.
  new({this._firestore, this._storage, Future<void> Function()? wait}) : _wait = wait ?? _cooldown;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final Future<void> Function() _wait;

  static Future<void> _cooldown() => Future<void>.delayed(const Duration(seconds: 1));

  FirebaseFirestore get _database => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _files => _storage ?? FirebaseStorage.instance;

  @override
  bool get isAvailable => true;

  @override
  Future<void> writePage(String pageId, PublishedPage page) =>
      _guard(() => _write(pageId: pageId, ownerUid: page.ownerUid, data: _pageData(page)));

  @override
  Future<void> uploadPhoto(String objectPath, Uint8List bytes, {required Future<void> cancel}) => _guard(() async {
    var cancelled = false;
    UploadTask? task;
    cancel.then((_) {
      cancelled = true;
      task?.cancel().ignore();
    }).ignore();
    void checkCancel() {
      if (cancelled) throw const PublishException(PublishErrorKind.transient, 'Upload cancelled');
    }

    checkCancel();
    final reference = _files.ref(objectPath);
    Future<bool> arrived() async {
      try {
        final prior = await reference.getData(5 * 1024 * 1024);
        if (!_same(prior, bytes)) {
          throw const PublishException(PublishErrorKind.refused, 'Photo path already contains different bytes');
        }
        return true;
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
        return false;
      }
    }

    if (await arrived()) return;
    checkCancel();
    await _reservation(objectPath, bytes: bytes.length);
    checkCancel();
    task = reference.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    try {
      await task;
    } on FirebaseException catch (error) {
      // Another uncertain upload may have committed after the read. Only identical bytes are a successful retry.
      if (error.code != 'unauthorized' || !await arrived()) rethrow;
    }
  });

  @override
  Future<void> writeReport({
    required String pageId,
    required String visitId,
    required PublishedReport report,
  }) => _guard(
    () => _publishReport(
      pageId: pageId,
      visitId: visitId,
      data: {
        'visitDate': report.visitDate.toString(),
        'publishedAt': Timestamp.fromDate(report.publishedAt),
        'zones': [
          for (final zone in report.zones)
            {
              'name': zone.name,
              'note': zone.note,
              'beforePhoto': zone.beforePhoto,
              'afterPhoto': zone.afterPhoto,
              if (zone.beforePhoto != null && zone.beforePhotoSource == PhotoSource.gallery)
                'beforePhotoSource': 'gallery',
              if (zone.afterPhoto != null && zone.afterPhotoSource == PhotoSource.gallery)
                'afterPhotoSource': 'gallery',
              // A done zone leaves both keys out, so it has the shape of a zone that an earlier version published,
              // and the report page reads a missing status as done.
              if (zone.status != ZoneStatus.done) ...{'status': zone.status.name, 'reason': zone.reason},
            },
        ],
        // The rules take only the value true, and only from a paid writer, so a report with the footer leaves the
        // key out.
        if (report.unbranded) 'unbranded': true,
      },
    ),
  );

  @override
  Future<void> revokePage(String pageId, PublishedPage page, {required DateTime revokedAt}) => _guard(
    () => _write(
      pageId: pageId,
      ownerUid: page.ownerUid,
      data: {..._pageData(page), 'revokedAt': Timestamp.fromDate(revokedAt)},
      revoke: true,
    ),
  );

  @override
  Future<void> deletePhoto(String objectPath) => _guard(() async {
    await _reservation(objectPath, remove: true);
    try {
      await _files.ref(objectPath).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  });

  @override
  Future<void> deleteReport({required String pageId, required String visitId}) => _guard(() async {
    for (var index = 0; index < 7; index++) {
      await _database.doc('clientPages/$pageId/reportValidation/$visitId/chunks/$index').delete();
    }
    await _database.doc('clientPages/$pageId/reportValidation/$visitId').delete();
    await _database.doc('clientPages/$pageId/reports/$visitId').delete();
  });

  @override
  Future<void> deletePage(String pageId) => _guard(() => _database.doc('clientPages/$pageId').delete());

  Future<void> _publishReport({
    required String pageId,
    required String visitId,
    required Map<String, Object?> data,
  }) async {
    final draftPath = 'clientPages/$pageId/reportValidation/$visitId';
    final needed = await _database.runTransaction((transaction) async {
      final parent = (await transaction.get(_database.doc('clientPages/$pageId'))).data();
      if (parent?['blockedAt'] != null || parent?['revokedAt'] != null) {
        throw const PublishException(PublishErrorKind.refused, 'Page is closed');
      }
      final prior = (await transaction.get(_database.doc('clientPages/$pageId/reports/$visitId'))).data();
      if (_same(prior, data)) return false;
      final account = _database.doc('publishingGrants/${parent?['ownerUid']}');
      final access = (await transaction.get(account)).data();
      _approved(access);
      final draft = _database.doc(draftPath);
      if ((await transaction.get(draft)).data() == null) {
        await _wait();
        transaction.update(
          account,
          _charge(access!, type: 'reserveReport', pageId: pageId, visitId: visitId, reports: prior == null ? 1 : 0),
        );
        transaction.set(draft, {'createdAt': FieldValue.serverTimestamp()});
      }
      return true;
    });
    if (!needed) return;
    final zones = data['zones']! as List<Object?>;
    for (var index = 0; index < 7; index++) {
      final chunkData = {'zones': zones.skip(index * 3).take(3).toList()};
      await _database.runTransaction((transaction) async {
        final parent = (await transaction.get(_database.doc('clientPages/$pageId'))).data();
        if (parent?['blockedAt'] != null || parent?['revokedAt'] != null) {
          throw const PublishException(PublishErrorKind.refused, 'Page is closed');
        }
        final chunk = _database.doc('$draftPath/chunks/$index');
        if (_same((await transaction.get(chunk)).data(), chunkData)) return;
        final account = _database.doc('publishingGrants/${parent?['ownerUid']}');
        final access = (await transaction.get(account)).data();
        _approved(access);
        transaction.set(chunk, chunkData);
      });
    }
    await _write(pageId: pageId, visitId: visitId, data: data);
  }

  // The account and target are read in one transaction. Rules bind its one charge to the resource it writes.
  Future<void> _write({
    required String pageId,
    required Map<String, Object?> data,
    String? ownerUid,
    String? visitId,
    bool revoke = false,
  }) => _database.runTransaction((transaction) async {
    final parent = _database.doc('clientPages/$pageId');
    final parentData = (await transaction.get(parent)).data();
    final target = visitId == null ? parent : _database.doc('clientPages/$pageId/reports/$visitId');
    final prior = visitId == null ? parentData : (await transaction.get(target)).data();
    if (revoke && parentData != null) {
      transaction.update(parent, {'revokedAt': data['revokedAt']});
      return;
    }
    if (parentData?['blockedAt'] != null || (visitId != null && parentData?['revokedAt'] != null)) {
      throw const PublishException(PublishErrorKind.refused, 'Page is closed');
    }
    if (_same(prior, data)) return;
    final uid = ownerUid ?? parentData?['ownerUid'];
    final account = _database.doc('publishingGrants/$uid');
    final access = (await transaction.get(account)).data();
    if (revoke && access != null) {
      // A previously admitted account can close a not-yet-written page after approval is withdrawn.
    } else {
      _approved(access);
    }
    final kind = revoke
        ? 'revoke'
        : visitId == null
        ? 'page'
        : 'report';
    if (visitId != null) {
      // Pin each staged version. A concurrent draft cannot publish a mixture of its chunks and this report.
      await transaction.get(_database.doc('clientPages/$pageId/reportValidation/$visitId'));
      final staged = <Object?>[];
      for (var index = 0; index < 7; index++) {
        final chunk = await transaction.get(
          _database.doc('clientPages/$pageId/reportValidation/$visitId/chunks/$index'),
        );
        staged.addAll(chunk.data()?['zones'] as List? ?? []);
      }
      if (!_same(staged, data['zones'])) {
        throw const PublishException(PublishErrorKind.transient, 'Report draft changed while publishing');
      }
    }
    await _wait(); // After reading the server timestamp, allow its cooldown without trusting the device clock.
    transaction.update(
      account,
      _charge(
        access!,
        type: kind,
        pageId: pageId,
        visitId: visitId ?? '',
        pages: visitId == null && prior == null ? 1 : 0,
      ),
    );
    transaction.set(target, data);
  });

  Future<void> _reservation(String objectPath, {int bytes = 0, bool remove = false}) async {
    final parts = objectPath.split('/');
    if (parts.length != 4 || parts.first != 'clientPages') {
      throw const PublishException(PublishErrorKind.refused, 'Invalid photo path');
    }
    final pageId = parts[1];
    final key = parts.skip(1).join('/');
    await _database.runTransaction((transaction) async {
      final parent = (await transaction.get(_database.doc('clientPages/$pageId'))).data();
      if (parent == null) {
        if (remove) return;
        throw const PublishException(PublishErrorKind.refused, 'Page does not exist');
      }
      final account = _database.doc('publishingGrants/${parent['ownerUid']}');
      final access = (await transaction.get(account)).data();
      if (remove && access == null) return;
      if (!remove) _approved(access);
      final reservations = Map<String, dynamic>.from(access!['reservations'] as Map);
      final prior = reservations[key];
      if (remove) {
        if (prior == null) return;
        reservations.remove(key);
      } else {
        if (prior != null) {
          if (prior != bytes) throw const PublishException(PublishErrorKind.refused, 'Photo reservation cannot grow');
          return;
        }
        reservations[key] = bytes;
        await _wait();
      }
      transaction.update(account, {
        ..._charge(
          access,
          type: remove ? 'removePhoto' : 'photo',
          pageId: pageId,
          visitId: parts[2],
          fileName: parts[3],
          photos: remove ? 0 : 1,
          bytes: remove ? 0 : bytes,
        ),
        'reservations': reservations,
      });
    });
  }

  static void _approved(Map<String, dynamic>? access) {
    if (access?['enabled'] != true) {
      throw const PublishException(PublishErrorKind.refused, 'Publishing needs operator approval');
    }
  }

  static Map<String, Object?> _charge(
    Map<String, dynamic> access, {
    required String type,
    required String pageId,
    String visitId = '',
    String fileName = '',
    int pages = 0,
    int reports = 0,
    int photos = 0,
    int bytes = 0,
  }) => {
    'pages': (access['pages'] as int) + pages,
    'reports': (access['reports'] as int) + reports,
    'photos': (access['photos'] as int) + photos,
    'bytes': (access['bytes'] as int) + bytes,
    'type': type,
    'pageId': pageId,
    'visitId': visitId,
    'fileName': fileName,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static bool _same(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every((key) => right.containsKey(key) && _same(left[key], right[key]));
    }
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index++) {
        if (!_same(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

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
