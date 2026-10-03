import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/app/app.dart';
import 'package:material_ui/material_ui.dart';

/// The contrast ratio of WCAG 2.2 between [a] and [b].
double contrastRatio(Color a, Color b) {
  final (lighter, darker) = a.computeLuminance() >= b.computeLuminance() ? (a, b) : (b, a);
  return (lighter.computeLuminance() + 0.05) / (darker.computeLuminance() + 0.05);
}

void main() {
  group('appTheme', () {
    final theme = appTheme();
    final colors = theme.colorScheme;

    test('is a light Material 3 theme', () {
      expect(theme.useMaterial3, isTrue);
      expect(colors.brightness, Brightness.light);
    });

    test('takes the tokens of the landing page for the roles that match one', () {
      expect(colors.primary, const Color(0xFF0F7F7A));
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
      expect(colors.surface, const Color(0xFFFAF7F1));
      expect(colors.onSurface, const Color(0xFF16243B));
      expect(colors.onSurfaceVariant, const Color(0xFF4B5870));
      expect(colors.outline, const Color(0xFF7F899C));
      expect(colors.outlineVariant, const Color(0xFFE6E0D4));
      expect(colors.error, const Color(0xFFB4342C));
      expect(colors.onError, const Color(0xFFFFFFFF));
    });

    test('puts the app bar on the surface color with the ink of the text', () {
      expect(theme.appBarTheme.backgroundColor, colors.surface);
      expect(theme.appBarTheme.foregroundColor, colors.onSurface);
    });

    test('gives the buttons and the dialogs the radius of the landing page', () {
      const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)));
      for (final style in [
        theme.filledButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
      ]) {
        expect(style?.shape?.resolve({}), shape);
      }
      expect(theme.dialogTheme.shape, shape);
      expect(theme.datePickerTheme.shape, shape);
    });

    test('puts the dialogs and the date picker on a white sheet', () {
      expect(theme.dialogTheme.backgroundColor, const Color(0xFFFFFFFF));
      expect(theme.datePickerTheme.backgroundColor, const Color(0xFFFFFFFF));
    });

    test('sets the size and the weight of the text styles that the screens use, and no font', () {
      final styles = {
        'headlineSmall': (theme.textTheme.headlineSmall, 22.0, FontWeight.w700),
        'titleLarge': (theme.textTheme.titleLarge, 20.0, FontWeight.w700),
        'titleMedium': (theme.textTheme.titleMedium, 16.0, FontWeight.w600),
        'titleSmall': (theme.textTheme.titleSmall, 14.0, FontWeight.w600),
        'bodyLarge': (theme.textTheme.bodyLarge, 16.0, FontWeight.w400),
        'bodyMedium': (theme.textTheme.bodyMedium, 14.0, FontWeight.w400),
        'bodySmall': (theme.textTheme.bodySmall, 12.0, FontWeight.w400),
        'labelLarge': (theme.textTheme.labelLarge, 14.0, FontWeight.w600),
      };
      final platformFont = ThemeData().textTheme.bodyMedium?.fontFamily;
      for (final MapEntry(key: name, value: (style, size, weight)) in styles.entries) {
        expect(style?.fontSize, size, reason: name);
        expect(style?.fontWeight, weight, reason: name);
        expect(style?.fontFamily, platformFont, reason: name);
      }
    });

    test('gives each pair of colors that carries text a contrast of at least 4.5:1', () {
      final pairs = {
        'onPrimary on primary': (colors.onPrimary, colors.primary),
        'onSurface on surface': (colors.onSurface, colors.surface),
        'onSurfaceVariant on surface': (colors.onSurfaceVariant, colors.surface),
        'primary on surface': (colors.primary, colors.surface),
        'onError on error': (colors.onError, colors.error),
        'error on surface': (colors.error, colors.surface),
        'onSurface on surfaceContainerHighest (info notice)': (colors.onSurface, colors.surfaceContainerHighest),
        'onErrorContainer on errorContainer (error notice)': (colors.onErrorContainer, colors.errorContainer),
        'onSurface on the dialog color': (colors.onSurface, theme.dialogTheme.backgroundColor!),
        'primary on the dialog color': (colors.primary, theme.dialogTheme.backgroundColor!),
        'primary on the date picker color': (colors.primary, theme.datePickerTheme.backgroundColor!),
      };
      for (final MapEntry(key: name, value: (text, fill)) in pairs.entries) {
        expect(contrastRatio(text, fill), greaterThanOrEqualTo(4.5), reason: name);
      }
    });
  });

  group('contrastRatio', () {
    test('gives 21 for black on white and 1 for one color on itself, in either order', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(contrastRatio(black, white), moreOrLessEquals(21));
      expect(contrastRatio(white, black), moreOrLessEquals(21));
      expect(contrastRatio(white, white), 1);
    });
  });
}
