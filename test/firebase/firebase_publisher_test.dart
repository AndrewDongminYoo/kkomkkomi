// 🎯 Dart imports:
import 'dart:async';
import 'dart:typed_data';

// 📦 Package imports:
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/firebase/firebase.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {
  late _MemoryTransaction transaction;
  void Function()? beforeTransaction;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    beforeTransaction?.call();
    return handler(transaction);
  }
}

// This snapshot is a test fixture, not a Firestore implementation.
// ignore: subtype_of_sealed_class
class _DataSnapshot<T> extends Fake implements DocumentSnapshot<T> {
  new(this.value);
  final T? value;
  @override
  T? data() => value;
}

class _MemoryTransaction extends Fake implements Transaction {
  new(this.values);
  final Map<String, Map<String, dynamic>> values;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> ref) async =>
      _DataSnapshot<T>(values[ref.path] as T?);
  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    // Record calls on the same references as the older direct-write tests.
    unawaited((ref as DocumentReference<Map<String, dynamic>>).set(data as Map<String, dynamic>));
    values[ref.path] = Map<String, dynamic>.from(data);
    return this;
  }

  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    values[ref.path] = {...values[ref.path]!, ...data.cast<String, dynamic>()};
    unawaited(ref.set(values[ref.path]));
    return this;
  }
}

// `DocumentReference` is sealed for implementations of Firestore, and a mock that records the writes of the adapter
// is no implementation.
// ignore: subtype_of_sealed_class
class _MockDocument extends Mock implements DocumentReference<Map<String, dynamic>>;

class _MockStorage extends Mock implements FirebaseStorage;

class _MockReference extends Mock implements Reference;

class _MockSnapshot extends Mock implements TaskSnapshot;

/// An upload that ends as [_result] ends. `await` reads a task through `then`.
class _FakeUploadTask extends Fake implements UploadTask {
  new(this._result);

  final Future<TaskSnapshot> _result;

  /// Whether `cancel` was called.
  bool cancelled = false;

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot) onValue, {Function? onError}) =>
      _result.then(onValue, onError: onError);

  @override
  Future<bool> cancel() async {
    cancelled = true;
    return true;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(SettableMetadata());
  });

  late _MockFirestore firestore;
  late _MockStorage storage;
  late Map<String, _MockDocument> documents;
  late FirebasePublisher publisher;

  final page = PublishedPage(
    ownerUid: 'owner-1',
    companyName: '꼼꼬미 청소',
    clientName: '한빛 상가',
    createdAt: DateTime.utc(2026, 10, 2, 9),
  );

  setUp(() {
    firestore = _MockFirestore();
    storage = _MockStorage();
    documents = {};
    firestore.transaction = _MemoryTransaction({
      'clientPages/page-1': {'ownerUid': 'owner-1'},
      'clientPages/p': {'ownerUid': 'owner-1'},
      'publishingGrants/owner-1': {
        'enabled': true,
        'pages': 0,
        'reports': 0,
        'photos': 0,
        'bytes': 0,
        'reservations': <String, dynamic>{},
      },
    });
    when(() => firestore.doc(any())).thenAnswer((invocation) {
      final path = invocation.positionalArguments.single as String;
      final document = documents.putIfAbsent(path, _MockDocument.new);
      when(() => document.path).thenReturn(path);
      when(document.delete).thenAnswer((_) async {});
      when(() => document.set(any())).thenAnswer((_) async {});
      return document;
    });
    publisher = FirebasePublisher(firestore: firestore, storage: storage, wait: () async {});
  });

  Map<String, dynamic> written(String path) =>
      verify(() => documents[path]!.set(captureAny())).captured.single as Map<String, dynamic>;

  group('FirebasePublisher', () {
    test('publishes gallery source only for an existing gallery photo', () async {
      await publisher.writeReport(
        pageId: 'page-1',
        visitId: 'visit-1',
        report: PublishedReport(
          visitDate: VisitDate(2026, 10, 1),
          publishedAt: DateTime.utc(2026),
          zones: [
            const PublishedZone(
              name: 'Lobby',
              note: '',
              beforePhoto: 'b.jpg',
              afterPhoto: 'a.jpg',
              beforePhotoSource: PhotoSource.gallery,
              afterPhotoSource: PhotoSource.gallery,
            ),
            const PublishedZone(
              name: 'Empty',
              note: '',
              beforePhoto: null,
              afterPhoto: null,
              beforePhotoSource: PhotoSource.gallery,
              afterPhotoSource: PhotoSource.gallery,
            ),
          ],
        ),
      );
      final zones = written('clientPages/page-1/reports/visit-1')['zones'] as List<Object?>;
      expect(zones.first, containsPair('beforePhotoSource', 'gallery'));
      expect(zones.first, containsPair('afterPhotoSource', 'gallery'));
      expect(zones.last, isNot(contains('beforePhotoSource')));
      expect(zones.last, isNot(contains('afterPhotoSource')));
    });
    test('new pages are charged once and uncertain identical retries survive approval withdrawal', () async {
      firestore.transaction.values.remove('clientPages/page-1');
      await publisher.writePage('page-1', page);
      final account = firestore.transaction.values['publishingGrants/owner-1']!;
      expect(account['pages'], 1);
      account['enabled'] = false;
      await publisher.writePage('page-1', page);
      expect(account['pages'], 1);
      await expectLater(publisher.writePage('another', page), throwsA(isA<PublishException>()));
    });

    test('report transactions write exactly seven bounded chunks and charge only new reports', () async {
      final report = PublishedReport(
        visitDate: VisitDate(2026, 10, 1),
        publishedAt: DateTime.utc(2026),
        zones: List.generate(
          20,
          (index) => PublishedZone(name: '$index', note: '', beforePhoto: null, afterPhoto: null),
        ),
      );
      await publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report);
      final values = firestore.transaction.values;
      expect(values['publishingGrants/owner-1']!['reports'], 1);
      for (var index = 0; index < 7; index++) {
        final chunk = values['clientPages/page-1/reportValidation/visit-1/chunks/$index']!['zones'] as List;
        expect(chunk.length, index == 6 ? 2 : 3);
        expect((chunk.first as Map)['name'], '${index * 3}');
      }
      values['publishingGrants/owner-1']!['enabled'] = false;
      await publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report);
      expect(values['publishingGrants/owner-1']!['reports'], 1);
      values['clientPages/page-1']!['blockedAt'] = Timestamp.now();
      await expectLater(
        publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report),
        throwsA(isA<PublishException>()),
      );
    });

    test('interrupted drafts remain private and reuse their slot when sharing resumes', () async {
      final report = PublishedReport(
        visitDate: VisitDate(2026, 10, 1),
        publishedAt: DateTime.utc(2026),
        zones: List.generate(
          20,
          (index) => PublishedZone(name: '$index', note: '', beforePhoto: null, afterPhoto: null),
        ),
      );
      var calls = 0;
      final values = firestore.transaction.values;
      firestore.beforeTransaction = () {
        if (++calls == 4) values['publishingGrants/owner-1']!['enabled'] = false;
      };
      await expectLater(
        publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.refused)),
      );
      expect(values['clientPages/page-1/reports/visit-1'], isNull);
      expect(values['clientPages/page-1/reportValidation/visit-1/chunks/1'], isNotNull);
      expect(values['publishingGrants/owner-1']!['reports'], 1);
      values['publishingGrants/owner-1']!['enabled'] = true;
      firestore.beforeTransaction = null;
      await publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report);
      expect(values['clientPages/page-1/reports/visit-1'], isNotNull);
      expect(values['publishingGrants/owner-1']!['reports'], 1);
    });

    test('a concurrent draft mismatch fails transiently before the public report changes', () async {
      final report = PublishedReport(
        visitDate: VisitDate(2026, 10, 1),
        publishedAt: DateTime.utc(2026),
        zones: [const PublishedZone(name: 'Lobby', note: '', beforePhoto: null, afterPhoto: null)],
      );
      var calls = 0;
      final values = firestore.transaction.values;
      firestore.beforeTransaction = () {
        if (++calls == 9) values['clientPages/page-1/reportValidation/visit-1/chunks/0']!['zones'] = <Object?>[];
      };
      await expectLater(
        publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.transient)),
      );
      expect(values['clientPages/page-1/reports/visit-1'], isNull);
    });

    test('a page closed during private staging stops before publication', () async {
      final report = PublishedReport(visitDate: VisitDate(2026, 10, 1), publishedAt: DateTime.utc(2026), zones: []);
      var calls = 0;
      firestore.beforeTransaction = () {
        if (++calls == 2) firestore.transaction.values['clientPages/page-1']!['revokedAt'] = Timestamp.now();
      };
      await expectLater(
        publisher.writeReport(pageId: 'page-1', visitId: 'visit-1', report: report),
        throwsA(isA<PublishException>()),
      );
      expect(firestore.transaction.values['clientPages/page-1/reports/visit-1'], isNull);
    });

    test('updating a legacy public report reserves a slot without charging its inventoried report twice', () async {
      final values = firestore.transaction.values;
      values['clientPages/page-1/reports/visit-1'] = {'old': true};
      values['publishingGrants/owner-1']!['reports'] = 1;
      await publisher.writeReport(
        pageId: 'page-1',
        visitId: 'visit-1',
        report: PublishedReport(visitDate: VisitDate(2026, 10, 1), publishedAt: DateTime.utc(2026), zones: []),
      );
      expect(values['publishingGrants/owner-1']!['reports'], 1);
    });

    test('missing grants refuse publication and admitted withdrawn accounts can close an absent page', () async {
      firestore.transaction.values.remove('publishingGrants/owner-1');
      await expectLater(publisher.writePage('new', page), throwsA(isA<PublishException>()));
      firestore.transaction.values['publishingGrants/owner-1'] = {
        'enabled': false,
        'pages': 0,
        'reports': 0,
        'photos': 0,
        'bytes': 0,
      };
      await publisher.revokePage('new', page, revokedAt: DateTime.utc(2026));
      expect(written('clientPages/new')['revokedAt'], Timestamp.fromDate(DateTime.utc(2026)));
      expect(firestore.transaction.values['publishingGrants/owner-1']!['type'], 'revoke');
    });

    test('the production cooldown is used when a changed resource is charged', () async {
      publisher = FirebasePublisher(firestore: firestore, storage: storage);
      await publisher.writePage('new', page);
      expect(firestore.transaction.values['publishingGrants/owner-1']!['pages'], 1);
    });

    test('identical photo bytes succeed without a reservation or approval and differing bytes fail', () async {
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.getData(any())).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
      firestore.transaction.values.clear();
      await publisher.uploadPhoto(
        'clientPages/p/v/a.jpg',
        Uint8List.fromList([1, 2, 3]),
        cancel: Completer<void>().future,
      );
      verifyNever(() => reference.putData(any(), any()));
      await expectLater(
        publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List.fromList([1, 2, 4]), cancel: Completer<void>().future),
        throwsA(isA<PublishException>()),
      );
      await expectLater(
        publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List(4), cancel: Completer<void>().future),
        throwsA(isA<PublishException>()),
      );
    });

    test('photo reservations are immutable and deletion releases only active allowance', () async {
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.getData(any()))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      when(() => reference.putData(any(), any())).thenAnswer((_) => _FakeUploadTask(Future.value(_MockSnapshot())));
      when(reference.delete).thenAnswer((_) async {});
      final cancel = Completer<void>().future;
      await publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List(3), cancel: cancel);
      final account = firestore.transaction.values['publishingGrants/owner-1']!;
      expect(account['photos'], 1);
      await publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List(3), cancel: cancel);
      expect(firestore.transaction.values['publishingGrants/owner-1']!['photos'], 1);
      await expectLater(
        publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List(4), cancel: cancel),
        throwsA(isA<PublishException>()),
      );
      await publisher.deletePhoto('clientPages/p/v/a.jpg');
      final cleaned = firestore.transaction.values['publishingGrants/owner-1']!;
      expect(cleaned['reservations'], isEmpty);
      expect(cleaned['photos'], 1);
      expect(cleaned['bytes'], 3);
      await publisher.deletePhoto('clientPages/p/v/a.jpg');
      firestore.transaction.values.remove('publishingGrants/owner-1');
      await publisher.deletePhoto('clientPages/p/v/a.jpg');
      firestore.transaction.values.remove('clientPages/p');
      await publisher.deletePhoto('clientPages/p/v/a.jpg');
      await expectLater(
        publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List(3), cancel: cancel),
        throwsA(isA<PublishException>()),
      );
      await expectLater(publisher.deletePhoto('bad'), throwsA(isA<PublishException>()));
    });

    test('cancellation during admission prevents a later PUT', () async {
      final wait = Completer<void>();
      publisher = FirebasePublisher(firestore: firestore, storage: storage, wait: () => wait.future);
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.getData(any()))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      final cancel = Completer<void>();
      final upload = publisher.uploadPhoto('clientPages/p/v/a.jpg', Uint8List(3), cancel: cancel.future);
      await pumpEventQueue();
      cancel.complete();
      await pumpEventQueue();
      final expectation = expectLater(upload, throwsA(isA<PublishException>()));
      wait.complete();
      await expectation;
      verifyNever(() => reference.putData(any(), any()));
    });

    test('is available', () {
      expect(publisher.isAvailable, isTrue);
    });

    test('writes a page with the fields that firestore.rules expects', () async {
      firestore.transaction.values.remove('clientPages/page-1');
      await publisher.writePage('page-1', page);

      expect(written('clientPages/page-1'), {
        'ownerUid': 'owner-1',
        'companyName': '꼼꼬미 청소',
        'clientName': '한빛 상가',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 2, 9)),
      });
    });

    test('writes a page as revoked at the time that it is given, so that a repeated write changes nothing', () async {
      await publisher.revokePage('page-1', page, revokedAt: DateTime.utc(2026, 10, 3, 8));

      final data = written('clientPages/page-1');
      expect(data.keys, ['ownerUid', 'revokedAt']);
      expect(data['ownerUid'], 'owner-1');
      expect(data['revokedAt'], Timestamp.fromDate(DateTime.utc(2026, 10, 3, 8)));
    });

    test('writes a report under its page, with the paths of its photos and the time that it is given', () async {
      await publisher.writeReport(
        pageId: 'page-1',
        visitId: 'visit-1',
        report: PublishedReport(
          visitDate: VisitDate(2026, 10, 2),
          publishedAt: DateTime.utc(2026, 10, 2, 9, 30),
          zones: const [PublishedZone(name: '입구', note: '바닥', beforePhoto: 'a.jpg', afterPhoto: null)],
        ),
      );

      final data = written('clientPages/page-1/reports/visit-1');
      // A report with the footer has no `unbranded` key, as before the key existed.
      expect(data.keys, ['visitDate', 'publishedAt', 'zones']);
      expect(data['visitDate'], '2026-10-02');
      expect(data['publishedAt'], Timestamp.fromDate(DateTime.utc(2026, 10, 2, 9, 30)));
      expect(data['zones'], [
        {'name': '입구', 'note': '바닥', 'beforePhoto': 'a.jpg', 'afterPhoto': null},
      ]);
    });

    test('writes the status and the reason of a zone only for an exception', () async {
      await publisher.writeReport(
        pageId: 'page-1',
        visitId: 'visit-1',
        report: PublishedReport(
          visitDate: VisitDate(2026, 10, 2),
          publishedAt: DateTime.utc(2026, 10, 2, 9, 30),
          zones: const [
            PublishedZone(name: '입구', note: '', beforePhoto: 'a.jpg', afterPhoto: 'b.jpg'),
            PublishedZone(
              name: '탕비실',
              note: '',
              beforePhoto: 'c.jpg',
              afterPhoto: null,
              status: ZoneStatus.partlyDone,
              reason: '전자레인지 안쪽은 다음 방문에',
            ),
            PublishedZone(
              name: '창고',
              note: '',
              beforePhoto: null,
              afterPhoto: null,
              status: ZoneStatus.notDone,
            ),
          ],
        ),
      );

      final zones = written('clientPages/page-1/reports/visit-1')['zones'] as List<Object?>;
      // A done zone has the keys that a zone of an earlier version has, which the report page reads as done.
      expect((zones[0]! as Map<String, Object?>).keys, ['name', 'note', 'beforePhoto', 'afterPhoto']);
      expect(zones[1], {
        'name': '탕비실',
        'note': '',
        'beforePhoto': 'c.jpg',
        'afterPhoto': null,
        'status': 'partlyDone',
        'reason': '전자레인지 안쪽은 다음 방문에',
      });
      expect(zones[2], {
        'name': '창고',
        'note': '',
        'beforePhoto': null,
        'afterPhoto': null,
        'status': 'notDone',
        'reason': '',
      });
    });

    test('writes unbranded: true into a report without the footer', () async {
      await publisher.writeReport(
        pageId: 'page-1',
        visitId: 'visit-1',
        report: PublishedReport(
          visitDate: VisitDate(2026, 10, 2),
          publishedAt: DateTime.utc(2026, 10, 2, 9, 30),
          zones: const [],
          unbranded: true,
        ),
      );

      final data = written('clientPages/page-1/reports/visit-1');
      expect(data.keys, ['visitDate', 'publishedAt', 'zones', 'unbranded']);
      expect(data['unbranded'], isTrue);
    });

    test('uploads a photo as a JPEG to its path', () async {
      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.getData(any()))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      when(() => reference.putData(any(), any())).thenAnswer((_) => _FakeUploadTask(Future.value(_MockSnapshot())));

      await publisher.uploadPhoto('clientPages/p/v/z-before.jpg', bytes, cancel: Completer<void>().future);

      verify(() => storage.ref('clientPages/p/v/z-before.jpg')).called(1);
      final captured = verify(() => reference.putData(captureAny(), captureAny())).captured;
      expect(captured.first, bytes);
      expect((captured.last as SettableMetadata).contentType, 'image/jpeg');
    });

    test('cancels the upload task when the queue asks, and ends as the task ends', () async {
      final reference = _MockReference();
      final result = Completer<TaskSnapshot>();
      final task = _FakeUploadTask(result.future);
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.getData(any()))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      when(() => reference.putData(any(), any())).thenAnswer((_) => task);
      final cancel = Completer<void>();

      final upload = publisher.uploadPhoto('clientPages/p/v/z-before.jpg', Uint8List(3), cancel: cancel.future);
      await pumpEventQueue();
      expect(task.cancelled, isFalse);

      cancel.complete();
      await pumpEventQueue();
      expect(task.cancelled, isTrue);

      result.completeError(FirebaseException(plugin: 'firebase_storage', code: 'canceled'));
      await expectLater(
        upload,
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.transient)),
      );
    });

    test('deletes a photo, and an object that does not exist is no failure', () async {
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.getData(any()))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      when(reference.delete).thenAnswer((_) async {});

      await publisher.deletePhoto('clientPages/p/v/a.jpg');
      verify(reference.delete).called(1);

      when(reference.delete).thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      await expectLater(publisher.deletePhoto('clientPages/p/v/a.jpg'), completes);

      when(reference.delete).thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'));
      await expectLater(
        publisher.deletePhoto('clientPages/p/v/a.jpg'),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.refused)),
      );
    });

    test('deletes a report and a page by their paths', () async {
      final report = documents['clientPages/page-1/reports/visit-1'] = _MockDocument();
      final pageDocument = documents['clientPages/page-1'] = _MockDocument();

      when(report.delete).thenAnswer((_) async {});
      when(pageDocument.delete).thenAnswer((_) async {});

      await publisher.deleteReport(pageId: 'page-1', visitId: 'visit-1');
      verify(report.delete).called(1);
      verify(documents['clientPages/page-1/reportValidation/visit-1']!.delete).called(1);
      for (var index = 0; index < 7; index++) {
        verify(documents['clientPages/page-1/reportValidation/visit-1/chunks/$index']!.delete).called(1);
      }
      verifyNever(pageDocument.delete);

      await publisher.deletePage('page-1');
      verify(pageDocument.delete).called(1);
    });

    test('turns a refused delete of a report or a page into a failure that a retry cannot fix', () async {
      final document = _MockDocument();
      when(() => firestore.doc(any())).thenReturn(document);
      when(document.delete).thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      final refused = throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.refused));

      await expectLater(publisher.deleteReport(pageId: 'page-1', visitId: 'visit-1'), refused);
      await expectLater(publisher.deletePage('page-1'), refused);
    });

    test('turns a failure of Firebase into a publish exception that says whether a retry can fix it', () async {
      final document = _MockDocument();
      when(() => firestore.doc(any())).thenReturn(document);

      when(() => document.path).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'denied'),
      );
      await expectLater(
        publisher.writePage('page-1', page),
        throwsA(
          isA<PublishException>()
              .having((error) => error.kind, 'kind', PublishErrorKind.refused)
              .having((error) => error.message, 'message', 'cloud_firestore/permission-denied: denied'),
        ),
      );

      when(() => document.path).thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      await expectLater(
        publisher.writePage('page-1', page),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.transient)),
      );
    });

    test('lets a failure that is not of Firebase through, for the queue to retry', () async {
      final document = _MockDocument();
      when(() => firestore.doc(any())).thenReturn(document);
      when(() => document.path).thenThrow(StateError('no app'));

      await expectLater(publisher.writePage('page-1', page), throwsStateError);
    });
  });

  group('publishErrorKindOf', () {
    PublishErrorKind kindOf(String code) => publishErrorKindOf(FirebaseException(plugin: 'p', code: code));

    test('names a refusal of the rules and a broken request as failures that a retry cannot fix', () {
      for (final code in [
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
      ]) {
        expect(kindOf(code), PublishErrorKind.refused, reason: code);
      }
    });

    test('names a missing network, a timeout, and an unknown failure as failures that a retry can fix', () {
      for (final code in [
        'unavailable',
        'deadline-exceeded',
        'retry-limit-exceeded',
        'unauthenticated',
        'resource-exhausted',
        'aborted',
        'internal',
        'unknown',
      ]) {
        expect(kindOf(code), PublishErrorKind.transient, reason: code);
      }
    });
  });
}
