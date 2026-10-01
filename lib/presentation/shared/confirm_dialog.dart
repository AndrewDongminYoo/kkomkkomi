import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/dialog_layout.dart';
import 'package:material_ui/material_ui.dart';

/// Asks [title] with [message] under it, and completes with true when the person presses the [confirmLabel] button.
///
/// It completes with false when the person closes the dialog in another way.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      insetPadding: dialogInsetPadding,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.l10n.dialogCancelButton)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}
