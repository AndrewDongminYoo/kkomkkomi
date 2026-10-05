import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';

extension PlanName on Plan {
  /// The name of the plan in the language of [l10n].
  String nameIn(AppLocalizations l10n) => switch (this) {
    Plan.free => l10n.planFreeName,
    Plan.basic => l10n.planBasicName,
    Plan.pro => l10n.planProName,
  };
}
