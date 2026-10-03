import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
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
    final theme = Theme.of(context);
    final helper = this.helper;
    final error = entry.message(context.l10n);
    // The label and the field are one node for a screen reader, which then reads the label as the name of the
    // field.
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeepAllText(label, style: theme.textTheme.labelLarge),
          TextField(
            controller: controller,
            autofocus: autofocus,
            // The field keeps the name that is on its way to storage, so that the answer of storage is about the
            // name on the screen.
            readOnly: entry == NameEntry.saving,
            textInputAction: TextInputAction.done,
            // The messages are widgets and not the strings of the decoration, which Flutter shows as a Text of its
            // own, so that Korean text breaks between words. A widget takes neither the line limit of the decoration
            // nor, for the helper, its style: the error gets the error style from the decoration, and the helper
            // style is the Material 3 default, because the theme sets no input decoration theme.
            decoration: InputDecoration(
              helper: helper == null
                  ? null
                  : KeepAllText(
                      helper,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                      maxLines: _messageMaxLines,
                    ),
              error: error == null
                  ? null
                  : KeepAllText(error, overflow: TextOverflow.ellipsis, maxLines: _messageMaxLines),
            ),
            onSubmitted: (_) => onSubmitted(),
          ),
        ],
      ),
    );
  }
}
