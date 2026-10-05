import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/dialog_layout.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:material_ui/material_ui.dart';

/// Asks [title] with [message] under it, and [details] under the message when given, and completes with true when the
/// person presses the [confirmLabel] button.
///
/// It completes with false when the person closes the dialog in another way. When [isDestructive] is true, the
/// confirm button has the error colors, for an action that deletes data, closes a link, or loses a note.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool isDestructive = false,
  Widget? details,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        scrollable: true,
        insetPadding: dialogInsetPadding,
        title: KeepAllText(title),
        content: details == null
            ? KeepAllText(message)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [KeepAllText(message), const SizedBox(height: 16), details],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: KeepAllText(context.l10n.dialogCancelButton),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: KeepAllText(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
