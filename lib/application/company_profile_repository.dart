// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';

/// Stores the one company profile of the app.
abstract interface class CompanyProfileRepository {
  /// The saved profile, or null when none was saved.
  Future<CompanyProfile?> load();

  Future<void> save(CompanyProfile profile);
}
