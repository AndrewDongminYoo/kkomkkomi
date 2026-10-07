// 📦 Package imports:
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/l10n/gen/app_localizations.dart';

export 'package:kkomkkomi/l10n/gen/app_localizations.dart';

/// The delegates that every `MaterialApp` of the app takes: the app strings and the strings of `material_ui`.
///
/// The generated `AppLocalizations.localizationsDelegates` names the delegates of `flutter_localizations`. Those do
/// not serve the widgets of `material_ui`, which then find no `MaterialLocalizations` under the Korean locale.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
