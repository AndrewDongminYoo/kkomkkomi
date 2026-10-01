import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/firebase/firebase.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestore extends Mock implements FirebaseFirestore;

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

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot) onValue, {Function? onError}) =>
      _result.then(onValue, onError: onError);
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
    when(() => firestore.doc(any())).thenAnswer((invocation) {
      final document = documents.putIfAbsent(invocation.positionalArguments.single as String, _MockDocument.new);
      when(() => document.set(any())).thenAnswer((_) async {});
      return document;
    });
    publisher = FirebasePublisher(firestore: firestore, storage: storage);
  });

  Map<String, dynamic> written(String path) =>
      verify(() => documents[path]!.set(captureAny())).captured.single as Map<String, dynamic>;

  group('FirebasePublisher', () {
    test('is available', () {
      expect(publisher.isAvailable, isTrue);
    });

    test('writes a page with the fields that firestore.rules expects', () async {
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
      expect(data.keys, ['ownerUid', 'companyName', 'clientName', 'createdAt', 'revokedAt']);
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
      expect(data['visitDate'], '2026-10-02');
      expect(data['publishedAt'], Timestamp.fromDate(DateTime.utc(2026, 10, 2, 9, 30)));
      expect(data['zones'], [
        {'name': '입구', 'note': '바닥', 'beforePhoto': 'a.jpg', 'afterPhoto': null},
      ]);
    });

    test('uploads a photo as a JPEG to its path', () async {
      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(() => reference.putData(any(), any())).thenAnswer((_) => _FakeUploadTask(Future.value(_MockSnapshot())));

      await publisher.uploadPhoto('clientPages/p/v/z-before.jpg', bytes);

      verify(() => storage.ref('clientPages/p/v/z-before.jpg')).called(1);
      final captured = verify(() => reference.putData(captureAny(), captureAny())).captured;
      expect(captured.first, bytes);
      expect((captured.last as SettableMetadata).contentType, 'image/jpeg');
    });

    test('deletes a photo, and an object that does not exist is no failure', () async {
      final reference = _MockReference();
      when(() => storage.ref(any())).thenReturn(reference);
      when(reference.delete).thenAnswer((_) async {});

      await publisher.deletePhoto('a.jpg');
      verify(reference.delete).called(1);

      when(reference.delete).thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'));
      await expectLater(publisher.deletePhoto('a.jpg'), completes);

      when(reference.delete).thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'));
      await expectLater(
        publisher.deletePhoto('a.jpg'),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.refused)),
      );
    });

    test('turns a failure of Firebase into a publish exception that says whether a retry can fix it', () async {
      final document = _MockDocument();
      when(() => firestore.doc(any())).thenReturn(document);

      when(() => document.set(any())).thenThrow(
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

      when(() => document.set(any())).thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      await expectLater(
        publisher.writePage('page-1', page),
        throwsA(isA<PublishException>().having((error) => error.kind, 'kind', PublishErrorKind.transient)),
      );
    });

    test('lets a failure that is not of Firebase through, for the queue to retry', () async {
      final document = _MockDocument();
      when(() => firestore.doc(any())).thenReturn(document);
      when(() => document.set(any())).thenThrow(StateError('no app'));

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
