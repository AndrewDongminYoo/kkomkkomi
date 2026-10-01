import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';
import 'package:kkomkkomi/presentation/shared/name_entry_message.dart';
import 'package:material_ui/material_ui.dart';

/// The most lines that a message under a name field takes before it is cut.
const _messageMaxLines = 10;

/// A text field for a name, with its label above it and the problem that [entry] names under it.
///
/// The field takes no edit while [entry] is [NameEntry.saving].
/// The label is a text of its own and not the label of the input decoration, which shows one line and cuts the
/// rest. A text of its own wraps, so a large text size on a narrow screen cuts nothing.
class NameField extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.entry,
    required this.onSubmitted,
    this.helper,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  /// What became of the name that the field last submitted.
  final NameEntry entry;

  /// Called when the person submits the name from the keyboard.
  final VoidCallback onSubmitted;

  /// The text under the field while [entry] names no problem.
  final String? helper;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // The label and the field are one node for a screen reader, which then reads the label as the name of the
    // field.
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          TextField(
            controller: controller,
            autofocus: autofocus,
            // The field keeps the name that is on its way to storage, so that the answer of storage is about the
            // name on the screen.
            readOnly: entry == NameEntry.saving,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              helperText: helper,
              helperMaxLines: _messageMaxLines,
              errorText: entry.message(context.l10n),
              errorMaxLines: _messageMaxLines,
            ),
            onSubmitted: (_) => onSubmitted(),
          ),
        ],
      ),
    );
  }
}
