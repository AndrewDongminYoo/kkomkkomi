// 📦 Package imports:
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';

extension FieldMessages on InputDecoration {
  /// The string of the error that `NameField` gives the decoration as a [KeepAllText], or null without an error.
  String? get errorMessage => (error as KeepAllText?)?.data;
}
