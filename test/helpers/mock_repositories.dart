import 'package:kkomkkomi/application/application.dart';
import 'package:mocktail/mocktail.dart';

class MockClientRepository extends Mock implements ClientRepository;

class MockVisitRepository extends Mock implements VisitRepository;

class MockCompanyProfileRepository extends Mock implements CompanyProfileRepository;

/// Repositories that are mocks, for a widget test that never reaches the database.
///
/// The client repository answers with no active client, which is all that the home screen reads.
Repositories mockRepositories() {
  final clients = MockClientRepository();
  when(clients.activeClients).thenAnswer((_) async => []);
  return Repositories(clients: clients, visits: MockVisitRepository(), companyProfile: MockCompanyProfileRepository());
}
