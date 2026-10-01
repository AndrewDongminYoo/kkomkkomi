import 'package:kkomkkomi/application/client_repository.dart';
import 'package:kkomkkomi/application/company_profile_repository.dart';
import 'package:kkomkkomi/application/visit_repository.dart';

/// The repositories that `bootstrap` builds and passes to the app.
final class Repositories {
  const new({required this.clients, required this.visits, required this.companyProfile});

  final ClientRepository clients;
  final VisitRepository visits;
  final CompanyProfileRepository companyProfile;
}
