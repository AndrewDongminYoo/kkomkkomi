// 📦 Package imports:
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/app/view/app_theme.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';

/// The app that `bootstrap` shows while the database does not open: a message and a retry control.
class StartupFailureApp extends StatelessWidget {
  const new({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme(),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = context.l10n;
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeepAllText(l10n.startupFailureMessage, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: onRetry, child: KeepAllText(l10n.startupFailureRetryButton)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
