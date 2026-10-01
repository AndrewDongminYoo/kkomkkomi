import 'package:kkomkkomi/application/application.dart';
import 'package:mocktail/mocktail.dart';

class MockClientRepository extends Mock implements ClientRepository;

class MockVisitRepository extends Mock implements VisitRepository;

class MockCompanyProfileRepository extends Mock implements CompanyProfileRepository;

/// Repositories that are mocks, for a widget test that never reaches the database.
Repositories mockRepositories() => Repositories(
  clients: MockClientRepository(),
  visits: MockVisitRepository(),
  companyProfile: MockCompanyProfileRepository(),
);
