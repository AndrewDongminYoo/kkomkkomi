import 'package:kkomkkomi/application/application.dart';
import 'package:mocktail/mocktail.dart';

import 'fakes.dart';

class MockClientRepository extends Mock implements ClientRepository;

class MockVisitRepository extends Mock implements VisitRepository;

class MockCompanyProfileRepository extends Mock implements CompanyProfileRepository;

class MockPublishRepository extends Mock implements PublishRepository;

/// Repositories that are mocks, for a widget test that never reaches the database.
///
/// The client repository answers with no active client, which is all that the home screen reads, and the publish
/// repository answers with no pending job, which is all that the publish queue reads when `bootstrap` starts it.
/// The store of the open capture is an empty fake, so the start of the app finds no lost photo.
Repositories mockRepositories() {
  final clients = MockClientRepository();
  when(clients.activeClients).thenAnswer((_) async => []);
  final publishing = MockPublishRepository();
  when(publishing.clearRetryDelays).thenAnswer((_) async {});
  when(publishing.pendingJobs).thenAnswer((_) async => []);
  return Repositories(
    clients: clients,
    visits: MockVisitRepository(),
    companyProfile: MockCompanyProfileRepository(),
    publishing: publishing,
    openCaptures: FakeOpenCaptureRepository(),
    localData: FakeLocalDataRepository(),
  );
}
