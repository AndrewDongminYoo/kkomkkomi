import 'package:kkomkkomi/application/client_repository.dart';
import 'package:kkomkkomi/application/company_profile_repository.dart';
import 'package:kkomkkomi/application/open_capture.dart';
import 'package:kkomkkomi/application/publish_repository.dart';
import 'package:kkomkkomi/application/visit_repository.dart';

/// The repositories that `bootstrap` builds and passes to the app.
final class Repositories {
  const new({
    required this.clients,
    required this.visits,
    required this.companyProfile,
    required this.publishing,
    required this.openCaptures,
  });

  final ClientRepository clients;
  final VisitRepository visits;
  final CompanyProfileRepository companyProfile;

  /// The client pages and the publish jobs, which the publish queue reads.
  final PublishRepository publishing;

  /// The capture that has the camera open, which the visit screen writes and the start of the app reads.
  final OpenCaptureRepository openCaptures;
}
