import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:material_ui/material_ui.dart';

/// The accent of the product, `--teal` of the landing page and the web report.
const _teal = Color(0xFF0F7F7A);

/// The text and marks on the accent, `--on-teal`.
const _onTeal = Color(0xFFFFFFFF);

/// The warm ground of every page, `--bg`.
const _ground = Color(0xFFFAF7F1);

/// The navy of the body text, `--ink`.
const _ink = Color(0xFF16243B);

/// The secondary text, `--ink-2`.
const _ink2 = Color(0xFF4B5870);

/// The border of an input, `--field-edge`, which is 3:1 on the ground.
const _fieldEdge = Color(0xFF7F899C);

/// The rule of the report sheet, `--paper-edge`.
const _paperEdge = Color(0xFFE6E0D4);

/// The error color, `--err`.
const _error = Color(0xFFB4342C);

/// The text on the error color. The web pages have no token for it.
const _onError = Color(0xFFFFFFFF);

/// The theme of the app, in the colors of the launcher icon, the landing page, and the web report.
///
/// The color scheme takes the tokens of `web/index.html` for the roles that match one, and the color generated from
/// the accent for every other role. The app has a light theme only.
ThemeData appTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _teal,
    primary: _teal,
    onPrimary: _onTeal,
    surface: _ground,
    onSurface: _ink,
    onSurfaceVariant: _ink2,
    outline: _fieldEdge,
    outlineVariant: _paperEdge,
    error: _error,
    onError: _onError,
  );
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(cornerRadius)));
  const buttonStyle = ButtonStyle(shape: WidgetStatePropertyAll(shape));
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    // Only sizes and weights, so that the platform keeps its own font: the bundled Noto Sans KR is the font of the PDF.
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarThemeData(backgroundColor: colorScheme.surface, foregroundColor: colorScheme.onSurface),
    filledButtonTheme: const FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: const TextButtonThemeData(style: buttonStyle),
    // A dialog is a white sheet, as the report is on the web. On the generated tint of the default dialog color, the
    // accent of a text button is under 4.5:1.
    dialogTheme: DialogThemeData(shape: shape, backgroundColor: colorScheme.surfaceContainerLowest),
    // Material 3 reads the shape of the date picker from its own theme only, never from the dialog theme.
    datePickerTheme: DatePickerThemeData(shape: shape, backgroundColor: colorScheme.surfaceContainerLowest),
  );
}
