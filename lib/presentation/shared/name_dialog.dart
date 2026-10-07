// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/dialog_layout.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';
import 'package:kkomkkomi/presentation/shared/name_field.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';

/// Shows a [NameDialog] that follows the name entry of [cubit], and closes it when the name is saved.
///
/// [entryOf] reads the entry from a state of [cubit]. The caller sets the entry back to [NameEntry.editing] before
/// the call, so that the dialog does not open with the problem of an earlier name.
Future<void> showNameDialog<C extends StateStreamable<S>, S>({
  required BuildContext context,
  required C cubit,
  required NameEntry Function(S state) entryOf,
  required String title,
  required String fieldLabel,
  required String submitLabel,
  required ValueChanged<String> onSubmit,
  String initialName = '',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocConsumer<C, S>(
      bloc: cubit,
      listenWhen: (previous, current) => entryOf(previous) != NameEntry.saved && entryOf(current) == NameEntry.saved,
      listener: (context, _) => Navigator.of(context).pop(),
      builder: (context, state) => NameDialog(
        title: title,
        fieldLabel: fieldLabel,
        submitLabel: submitLabel,
        initialName: initialName,
        entry: entryOf(state),
        onSubmit: onSubmit,
      ),
    ),
  );
}

/// A dialog with one name field, a button that closes the dialog, and a button that submits the name.
///
/// The dialog shows the problem that [entry] names under the field. While a name is on its way to storage, it takes
/// no second name and it does not close, so that the answer of storage finds the dialog that asked.
class NameDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.fieldLabel,
    required this.submitLabel,
    required this.entry,
    required this.onSubmit,
    this.initialName = '',
    super.key,
  });

  final String title;
  final String fieldLabel;
  final String submitLabel;
  final String initialName;
  final NameEntry entry;
  final ValueChanged<String> onSubmit;

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = widget.entry == NameEntry.saving;
    void submit() {
      if (!isSaving) widget.onSubmit(_controller.text);
    }

    return SaveGuard(
      // The listener of `showNameDialog` closes the top route, so the dialog must still be that route when storage
      // answers.
      isSaving: isSaving,
      child: AlertDialog(
        scrollable: true,
        insetPadding: dialogInsetPadding,
        title: KeepAllText(widget.title),
        content: NameField(
          controller: _controller,
          label: widget.fieldLabel,
          entry: widget.entry,
          autofocus: true,
          onSubmitted: submit,
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.of(context).pop(),
            child: KeepAllText(context.l10n.dialogCancelButton),
          ),
          FilledButton(onPressed: isSaving ? null : submit, child: KeepAllText(widget.submitLabel)),
        ],
      ),
    );
  }
}
