import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';

extension NameEntryMessage on NameEntry {
  /// The text that tells a person why the name is not saved, or null when the entry names no problem.
  String? message(AppLocalizations l10n) => switch (this) {
    NameEntry.empty => l10n.nameEmptyError,
    NameEntry.duplicate => l10n.zoneDuplicateNameError,
    NameEntry.limitReached => l10n.clientLimitReachedError,
    NameEntry.failed => l10n.saveFailedMessage,
    NameEntry.editing || NameEntry.saving || NameEntry.saved => null,
  };
}
