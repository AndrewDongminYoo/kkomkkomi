import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/export/export.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:pdf/pdf.dart';

import '../../../helpers/helpers.dart';

/// Keeps the errors that the cubits report.
class _ErrorObserver extends BlocObserver {
  final errors = <Object>[];

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(bloc, error, stackTrace);
  }
}

void main() {
  const visitId = 'visit-1';
  final labels = ReportLabels(
    title: '청소 완료 보고서',
    clientHeading: '거래처',
    visitDateHeading: '방문일',
    visitDate: '2026년 10월 1일',
    beforePhoto: '청소 전',
    afterPhoto: '청소 후',
    notPhotographed: '촬영하지 않음',
    partlyDone: '일부 완료',
    notDone: '못 함',
    summaryOf: (done, total) => '$total곳 중 $done곳 완료',
    note: '메모',
    footer: '꼼꼬미로 만든 보고서',
  );
  final client = Client(id: 'client-1', name: '행복빌딩', createdAt: DateTime.utc(2026, 9));
  final lobbyBefore = PhotoRef('photos/visit-1/lobby-before.jpg');
  final lobbyAfter = PhotoRef('photos/visit-1/lobby-after.jpg');
  final hallBefore = PhotoRef('photos/visit-1/hall-before.jpg');
  final lobby = ZoneRecord(
    zoneId: 'zone-1',
    zoneName: '로비',
    beforePhoto: lobbyBefore,
    afterPhoto: lobbyAfter,
    note: '바닥 왁스',
  );
  final hall = ZoneRecord(zoneId: 'zone-2', zoneName: '복도', beforePhoto: hallBefore);
  final pantry = ZoneRecord(zoneId: 'zone-3', zoneName: '탕비실');
  final visit = Visit(
    id: visitId,
    clientId: 'client-1',
    visitDate: VisitDate(2026, 10, 1),
    createdAt: DateTime.utc(2026, 10, 1, 1),
    zoneRecords: [lobby, hall, pantry],
  );
  final failure = Exception('storage failed');

  late FakeVisitRepository visits;
  late FakeClientRepository clients;
  late FakeCompanyProfileRepository companyProfile;
  late FakePhotoStore photoStore;
  late FakeReportShare reportShare;
  late ReportFont reportFont;
  late FakeIdentity identity;

  VisitReportCubit build() => VisitReportCubit(
    visitId: visitId,
    visits: visits,
    clients: clients,
    companyProfile: companyProfile,
    photoStore: photoStore,
    reportFont: reportFont,
    reportShare: reportShare,
    identity: identity,
  );

  ReportDocument documentOf(Visit visit, {String? companyName = '깔끔클린'}) => ReportDocument.fromVisit(
    visit: visit,
    client: client,
    companyProfile: companyName == null ? null : CompanyProfile(name: companyName),
  );

  VisitReportState loaded({
    VisitReportStatus status = VisitReportStatus.ready,
    Visit? of,
    String? companyName = '깔끔클린',
    List<ZoneRecord>? zonesLackingPhoto,
    bool showsFooterText = true,
  }) => VisitReportState(
    status: status,
    document: documentOf(of ?? visit, companyName: companyName),
    zonesLackingPhoto: zonesLackingPhoto ?? [hall, pantry],
    photoDirectory: FakePhotoStore.directory,
    showsFooterText: showsFooterText,
  );

  /// Gives the errors that the cubits report from now until the test ends.
  List<Object> observeErrors() {
    final observer = _ErrorObserver();
    final previous = Bloc.observer;
    Bloc.observer = observer;
    addTearDown(() => Bloc.observer = previous);
    return observer.errors;
  }

  setUp(() {
    visits = FakeVisitRepository(visits: [visit]);
    clients = FakeClientRepository(clients: [client]);
    companyProfile = FakeCompanyProfileRepository(profile: CompanyProfile(name: '깔끔클린'));
    photoStore = FakePhotoStore();
    reportShare = FakeReportShare();
    reportFont = const FileReportFont();
    identity = FakeIdentity();
  });

  group('VisitReportState', () {
    test('can share only while the report holds a zone and no share or load is on its way', () {
      for (final status in VisitReportStatus.values) {
        expect(
          loaded(status: status).canShare,
          status == VisitReportStatus.ready || status == VisitReportStatus.shareFailed,
          reason: '$status',
        );
      }
      expect(
        loaded(
          of: Visit.start(
            id: visitId,
            zones: ClientZones(clientId: 'client-1'),
            visitDate: visit.visitDate,
            createdAt: visit.createdAt,
          ),
        ).canShare,
        isFalse,
      );
      expect(const VisitReportState(status: VisitReportStatus.ready).canShare, isFalse);
    });

    test('gives the absolute path of a photo file under the photo directory', () {
      expect(loaded().pathOf(lobbyBefore), '/documents/photos/visit-1/lobby-before.jpg');
    });

    test('is equal to a state with the same fields', () {
      expect(loaded(), loaded());
      expect(loaded().hashCode, loaded().hashCode);
    });

    test('copyWith replaces the status and keeps the rest', () {
      expect(loaded().copyWith(status: VisitReportStatus.sharing), loaded(status: VisitReportStatus.sharing));
      expect(loaded(status: VisitReportStatus.shareFailed).copyWith(), loaded(status: VisitReportStatus.shareFailed));
      expect(
        loaded(showsFooterText: false).copyWith(status: VisitReportStatus.sharing),
        loaded(status: VisitReportStatus.sharing, showsFooterText: false),
      );
      expect(
        loaded(status: VisitReportStatus.sharing).copyWith(showsFooterText: false),
        loaded(status: VisitReportStatus.sharing, showsFooterText: false),
      );
    });

    test('differs from a state with another field value', () {
      expect(loaded(), isNot(loaded(status: VisitReportStatus.sharing)));
      expect(loaded(), isNot(loaded(companyName: null)));
      expect(loaded(), isNot(loaded(zonesLackingPhoto: [hall])));
      expect(loaded(), isNot(loaded(showsFooterText: false)));
      expect(
        loaded(),
        isNot(
          VisitReportState(
            status: VisitReportStatus.ready,
            document: documentOf(visit),
            zonesLackingPhoto: [hall, pantry],
            photoDirectory: '/other',
          ),
        ),
      );
    });
  });

  group('VisitReportCubit', () {
    test('starts in the loading status without a report', () {
      expect(build().state, const VisitReportState());
    });

    group('load', () {
      blocTest<VisitReportCubit, VisitReportState>(
        'builds the report of the visit, and lists the zones that lack a photo in visit order',
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [loaded()],
        verify: (cubit) {
          expect(cubit.state.document!.zones.map((zone) => zone.name), ['로비', '복도']);
          expect(cubit.state.document!.companyName, '깔끔클린');
        },
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'leaves a zone that is not done out of the zones that lack a photo, and keeps a partly done one',
        setUp: () {
          final storage = ZoneRecord(zoneId: 'zone-4', zoneName: '창고', status: ZoneStatus.notDone, reason: '잠김');
          final kitchen = ZoneRecord(zoneId: 'zone-5', zoneName: '주방', status: ZoneStatus.partlyDone);
          visits = FakeVisitRepository(
            visits: [
              Visit(
                id: visitId,
                clientId: 'client-1',
                visitDate: VisitDate(2026, 10, 1),
                createdAt: DateTime.utc(2026, 10, 1, 1),
                zoneRecords: [lobby, hall, storage, kitchen],
              ),
            ],
          );
        },
        build: build,
        act: (cubit) => cubit.load(),
        verify: (cubit) {
          expect(cubit.state.zonesLackingPhoto.map((record) => record.zoneName), ['복도', '주방']);
          expect(cubit.state.document!.zones.map((zone) => zone.name), ['로비', '복도', '창고', '주방']);
        },
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'builds a report without a company name when no company profile is saved',
        setUp: () => companyProfile.profile = null,
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [loaded(companyName: null)],
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'builds the report without the footer text for a user whose token holds a paid entitlement',
        setUp: () => identity.paid = true,
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [loaded(showsFooterText: false)],
      );

      test('asks for the paid entitlement once, also when it loads again', () async {
        identity.paid = true;
        final cubit = build();

        await cubit.load();
        await cubit.load();

        expect(identity.paidChecks, 1);
        expect(cubit.state, loaded(showsFooterText: false));
        await cubit.close();
      });

      test('shows the report with the footer text before the check of the paid entitlement answers, and leaves the '
          'text out when the check answers true', () async {
        identity
          ..paid = true
          ..paidGate = Completer<void>();
        final cubit = build();
        final states = <VisitReportState>[];
        final subscription = cubit.stream.listen(states.add);

        await cubit.load();
        expect(cubit.state, loaded());
        identity.paidGate!.complete();
        await Future<void>.delayed(Duration.zero);

        expect(states, [loaded(), loaded(showsFooterText: false)]);
        await subscription.cancel();
        await cubit.close();
      });

      test(
        'keeps the footer text when the check of the paid entitlement answers false after the report shows',
        () async {
          identity.paidGate = Completer<void>();
          final cubit = build();
          final states = <VisitReportState>[];
          final subscription = cubit.stream.listen(states.add);

          await cubit.load();
          identity.paidGate!.complete();
          await Future<void>.delayed(Duration.zero);

          expect(states, [loaded()]);
          await subscription.cancel();
          await cubit.close();
        },
      );

      test(
        'leaves the footer text out when the report loads again after a check that answered true without a report',
        () async {
          identity
            ..paid = true
            ..paidGate = Completer<void>();
          visits = FakeVisitRepository();
          final cubit = build();

          await cubit.load();
          expect(cubit.state, const VisitReportState(status: VisitReportStatus.loadFailed));
          identity.paidGate!.complete();
          await Future<void>.delayed(Duration.zero);
          expect(cubit.state, const VisitReportState(status: VisitReportStatus.loadFailed));

          await visits.save(visit);
          await cubit.load();
          expect(cubit.state, loaded(showsFooterText: false));
          expect(identity.paidChecks, 1);
          await cubit.close();
        },
      );

      test('emits nothing when the cubit closes before the check of the paid entitlement answers', () async {
        identity
          ..paid = true
          ..paidGate = Completer<void>();
        final cubit = build();
        await cubit.load();
        await cubit.close();

        identity.paidGate!.complete();
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state, loaded());
      });

      blocTest<VisitReportCubit, VisitReportState>(
        'fails for a visit that storage does not have',
        setUp: () => visits = FakeVisitRepository(),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const VisitReportState(status: VisitReportStatus.loadFailed)],
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails for a client that storage does not have',
        setUp: () => clients = FakeClientRepository(),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const VisitReportState(status: VisitReportStatus.loadFailed)],
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails and reports the error when storage fails',
        setUp: () => companyProfile.failure = failure,
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const VisitReportState(status: VisitReportStatus.loadFailed)],
        errors: () => [failure],
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'shows the loading status again before a second load, and reads what storage holds then',
        build: build,
        act: (cubit) async {
          await cubit.load();
          companyProfile.profile = CompanyProfile(name: '새 이름');
          await cubit.load();
        },
        expect: () => [loaded(), const VisitReportState(), loaded(companyName: '새 이름')],
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'loads again after a failed load',
        setUp: () => companyProfile.failure = failure,
        build: build,
        act: (cubit) async {
          await cubit.load();
          companyProfile.failure = null;
          await cubit.load();
        },
        expect: () => [
          const VisitReportState(status: VisitReportStatus.loadFailed),
          const VisitReportState(),
          loaded(),
        ],
        errors: () => [failure],
      );

      test('does nothing while a share is on its way', () async {
        final cubit = build();
        await cubit.load();
        reportShare.gate = Completer<void>();
        final share = cubit.share(labels);
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.status, VisitReportStatus.sharing);

        companyProfile.profile = CompanyProfile(name: '새 이름');
        await cubit.load();

        expect(cubit.state, loaded(status: VisitReportStatus.sharing));
        reportShare.gate!.complete();
        await share;
        expect(cubit.state, loaded());
      });

      test('does nothing after the cubit closed, and emits nothing when it closes before storage answers', () async {
        // A second load of a loaded cubit starts with the loading status, which a closed cubit cannot show.
        final closed = build();
        await closed.load();
        await closed.close();
        await expectLater(closed.load(), completes);
        expect(closed.state, loaded());

        final closing = build();
        final load = closing.load();
        await closing.close();
        await expectLater(load, completes);
        expect(closing.state, const VisitReportState());
      });

      test('reports no error when it closes before storage fails', () async {
        final errors = observeErrors();
        companyProfile.failure = failure;
        final cubit = build();
        final load = cubit.load();
        await cubit.close();

        await expectLater(load, completes);
        expect(cubit.state, const VisitReportState());
        expect(errors, isEmpty);
      });
    });

    group('share', () {
      blocTest<VisitReportCubit, VisitReportState>(
        'gives the share sheet a PDF of the report under the file name of the client and the date',
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [loaded(), loaded(status: VisitReportStatus.sharing), loaded()],
        verify: (_) {
          final shared = reportShare.shared.single;
          expect(shared.fileName, '청소 완료 보고서_행복빌딩_2026-10-01.pdf');
          final summary = PdfSummary.read(shared.bytes);
          expect(summary.pages.expand((page) => page.images), hasLength(3));
          expect(
            summary.text,
            stringContainsInOrder(['깔끔클린', '청소 완료 보고서', '행복빌딩', '2026년 10월 1일', '로비', '바닥 왁스', '복도']),
          );
          expect(summary.text, isNot(contains('탕비실')));
          expect(photoStore.readPhotos, [lobbyBefore, lobbyAfter, hallBefore]);
        },
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'prints the footer text and the page number in the PDF of a user without a paid entitlement',
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        verify: (_) => expect(
          PdfSummary.read(reportShare.shared.single.bytes).pages.first.text,
          startsWith('꼼꼬미로 만든 보고서 1 / '),
        ),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'leaves the footer text out of the PDF of a user with a paid entitlement and keeps the page number',
        setUp: () => identity.paid = true,
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [
          loaded(showsFooterText: false),
          loaded(status: VisitReportStatus.sharing, showsFooterText: false),
          loaded(showsFooterText: false),
        ],
        verify: (_) {
          final summary = PdfSummary.read(reportShare.shared.single.bytes);
          expect(summary.pages.first.text, startsWith('1 / '));
          expect(summary.text, isNot(contains('꼼꼬미로 만든 보고서')));
        },
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'shares a report without a company name',
        setUp: () => companyProfile.profile = null,
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [
          loaded(companyName: null),
          loaded(status: VisitReportStatus.sharing, companyName: null),
          loaded(companyName: null),
        ],
        verify: (_) => expect(reportShare.shared, hasLength(1)),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails and reports the error when the share sheet does not open, and shares on the next try',
        setUp: () => reportShare.failure = const ReportShareException(),
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
          reportShare.failure = null;
          await cubit.share(labels);
        },
        expect: () => [
          loaded(),
          loaded(status: VisitReportStatus.sharing),
          loaded(status: VisitReportStatus.shareFailed),
          loaded(status: VisitReportStatus.sharing),
          loaded(),
        ],
        errors: () => [isA<ReportShareException>()],
        verify: (_) => expect(reportShare.shared, hasLength(1)),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails when a photo file does not read, and opens no share sheet',
        setUp: () => photoStore.readFailure = const FileSystemException('The file is gone'),
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [
          loaded(),
          loaded(status: VisitReportStatus.sharing),
          loaded(status: VisitReportStatus.shareFailed),
        ],
        errors: () => [isA<FileSystemException>()],
        verify: (_) => expect(reportShare.shared, isEmpty),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'puts a photo that holds a location into the PDF without it',
        setUp: () {
          expect(holdsMetadataText(gpsPhotoBytes()), isTrue);
          photoStore.contents[lobbyAfter] = gpsPhotoBytes();
        },
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [loaded(), loaded(status: VisitReportStatus.sharing), loaded()],
        verify: (_) => expect(holdsMetadataText(reportShare.shared.single.bytes), isFalse),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails when a photo file is no well-formed JPEG, and opens no share sheet',
        setUp: () => photoStore.contents[lobbyAfter] = Uint8List.fromList([1, 2, 3]),
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [
          loaded(),
          loaded(status: VisitReportStatus.sharing),
          loaded(status: VisitReportStatus.shareFailed),
        ],
        errors: () => [isA<FormatException>()],
        verify: (_) => expect(reportShare.shared, isEmpty),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails when the renderer cannot read a photo that is a well-formed JPEG file, and opens no share sheet',
        // A well-formed JPEG file without a frame header.
        setUp: () => photoStore.contents[lobbyAfter] = Uint8List.fromList([
          0xff, 0xd8, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x12, 0x34, 0xff, 0xd9, //
        ]),
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [
          loaded(),
          loaded(status: VisitReportStatus.sharing),
          loaded(status: VisitReportStatus.shareFailed),
        ],
        errors: () => [isA<PdfException>()],
        verify: (_) => expect(reportShare.shared, isEmpty),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'fails when the font does not load',
        setUp: () => reportFont = const FailingReportFont(),
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        expect: () => [
          loaded(),
          loaded(status: VisitReportStatus.sharing),
          loaded(status: VisitReportStatus.shareFailed),
        ],
        errors: () => [isA<FileSystemException>()],
        verify: (_) => expect(reportShare.shared, isEmpty),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'does nothing before the report is loaded',
        build: build,
        act: (cubit) => cubit.share(labels),
        expect: () => <VisitReportState>[],
        verify: (_) => expect(reportShare.shared, isEmpty),
      );

      blocTest<VisitReportCubit, VisitReportState>(
        'does nothing for a report without a zone',
        setUp: () => visits = FakeVisitRepository(
          visits: [
            Visit(
              id: visitId,
              clientId: 'client-1',
              visitDate: VisitDate(2026, 10, 1),
              createdAt: DateTime.utc(2026, 10, 1, 1),
              zoneRecords: [pantry],
            ),
          ],
        ),
        build: build,
        act: (cubit) async {
          await cubit.load();
          await cubit.share(labels);
        },
        verify: (cubit) {
          expect(cubit.state.status, VisitReportStatus.ready);
          expect(cubit.state.document!.zones, isEmpty);
          expect(cubit.state.zonesLackingPhoto, [pantry]);
          expect(reportShare.shared, isEmpty);
        },
      );

      test('does not start a second share while one is on its way', () async {
        final cubit = build();
        await cubit.load();
        reportShare.gate = Completer<void>();
        final first = cubit.share(labels);
        await Future<void>.delayed(Duration.zero);

        await cubit.share(labels);
        reportShare.gate!.complete();
        await first;

        expect(reportShare.shared, hasLength(1));
        expect(cubit.state, loaded());
      });

      test('emits nothing and reports no error when it closes before the share sheet answers', () async {
        final errors = observeErrors();
        final cubit = build();
        await cubit.load();
        reportShare
          ..gate = Completer<void>()
          ..failure = const ReportShareException();
        final share = cubit.share(labels);
        await Future<void>.delayed(Duration.zero);
        await cubit.close();
        reportShare.gate!.complete();

        await expectLater(share, completes);
        expect(cubit.state, loaded(status: VisitReportStatus.sharing));
        expect(errors, isEmpty);
      });

      test('emits nothing when it closes before a share sheet that opens answers', () async {
        final cubit = build();
        await cubit.load();
        reportShare.gate = Completer<void>();
        final share = cubit.share(labels);
        await Future<void>.delayed(Duration.zero);
        await cubit.close();
        reportShare.gate!.complete();

        await expectLater(share, completes);
        expect(cubit.state, loaded(status: VisitReportStatus.sharing));
      });
    });
  });
}
