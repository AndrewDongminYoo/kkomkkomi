import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/company_profile/cubit/company_profile_cubit.dart';
import 'package:kkomkkomi/presentation/plans/plans.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';
import 'package:kkomkkomi/presentation/shared/name_field.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:material_ui/material_ui.dart';

/// The screen that edits the company name, which the report prints, that opens the plans, and that deletes all data.
class CompanyProfilePage extends StatelessWidget {
  const new({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const CompanyProfilePage());

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = CompanyProfileCubit(
          companyProfile: context.read<CompanyProfileRepository>(),
          deleteAllData: context.read<DeleteAllData>(),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const CompanyProfileView(),
    );
  }
}

class CompanyProfileView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<CompanyProfileCubit, CompanyProfileState>(
      listenWhen: (previous, current) =>
          (previous.entry != NameEntry.saved && current.entry == NameEntry.saved) ||
          (previous.deletion != DataDeletion.deleted && current.deletion == DataDeletion.deleted),
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        if (state.deletion == DataDeletion.deleted) {
          // The app is as at its first launch, so it goes back to the client list, which is empty now.
          Navigator.of(context).popUntil((route) => route.isFirst);
          messenger.showSnackBar(SnackBar(content: KeepAllText(l10n.dataDeletedMessage)));
        } else {
          messenger.showSnackBar(SnackBar(content: KeepAllText(l10n.companyProfileSavedMessage)));
        }
      },
      // A person who leaves while the name is on its way would not see that storage did not take it, and one who
      // leaves while a deletion is on its way would not see which step failed.
      builder: (context, state) => SaveGuard(
        isSaving: state.entry == NameEntry.saving || state.deletion == DataDeletion.deleting,
        child: Scaffold(
          appBar: AppBar(title: KeepAllText(l10n.companyProfileTitle)),
          body: SafeArea(
            child: switch (state.status) {
              CompanyProfileStatus.loading => const Center(child: CircularProgressIndicator()),
              CompanyProfileStatus.loadFailed => LoadFailure(
                message: l10n.companyProfileLoadFailedMessage,
                onRetry: () => unawaited(context.read<CompanyProfileCubit>().load()),
              ),
              CompanyProfileStatus.ready => _CompanyProfileForm(
                initialName: state.name,
                entry: state.entry,
                deletion: state.deletion,
                deletionFailure: state.deletionFailure,
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _CompanyProfileForm extends StatefulWidget {
  const new({
    required this.initialName,
    required this.entry,
    required this.deletion,
    required this.deletionFailure,
  });

  /// The name that the field holds when the form opens. A later value does not replace what the person typed.
  final String initialName;
  final NameEntry entry;
  final DataDeletion deletion;
  final DeletionStep? deletionFailure;

  @override
  State<_CompanyProfileForm> createState() => _CompanyProfileFormState();
}

class _CompanyProfileFormState extends State<_CompanyProfileForm> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The keyboard can still submit while the screen takes no touch, so a deletion also stops the save here.
    final isSaving = widget.entry == NameEntry.saving || widget.deletion != DataDeletion.idle;
    void save() {
      if (!isSaving) unawaited(context.read<CompanyProfileCubit>().save(_controller.text));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NameField(
            controller: _controller,
            label: l10n.companyNameFieldLabel,
            helper: l10n.companyNameHelper,
            entry: widget.entry,
            onSubmitted: save,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: isSaving ? null : save, child: KeepAllText(l10n.nameSaveButton)),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const _PlanEntry(),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          _DataDeletion(deletion: widget.deletion, failure: widget.deletionFailure),
        ],
      ),
    );
  }
}

/// The plan of the company, which follows what the store reports, and the control that opens the plans.
class _PlanEntry extends StatefulWidget {
  const new();

  @override
  State<_PlanEntry> createState() => _PlanEntryState();
}

class _PlanEntryState extends State<_PlanEntry> {
  late final Entitlements _entitlements = context.read<Entitlements>();
  late final StreamSubscription<Plan> _changes;

  /// The plan that the store gave, or null while it is on its way.
  Plan? _plan;

  @override
  void initState() {
    super.initState();
    _changes = _entitlements.planChanges.listen(_show);
    // A plan that the store reported while the read was on its way is newer than the answer of the read.
    unawaited(
      _entitlements.currentPlan().then((plan) {
        if (_plan == null) _show(plan);
      }),
    );
  }

  void _show(Plan plan) {
    if (mounted) setState(() => _plan = plan);
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAllText(l10n.companyProfilePlanTitle, style: Theme.of(context).textTheme.titleMedium),
        if (_plan case final plan?) ...[
          const SizedBox(height: 8),
          KeepAllText(l10n.companyProfilePlanMessage(plan.nameIn(l10n))),
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(PlansPage.route()),
          child: KeepAllText(l10n.companyProfilePlansButton),
        ),
      ],
    );
  }
}

/// The control that deletes all data, with what it deletes, its progress, and the step at which it stopped.
class _DataDeletion extends StatelessWidget {
  const new({required this.deletion, required this.failure});

  final DataDeletion deletion;
  final DeletionStep? failure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDeleting = deletion == DataDeletion.deleting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAllText(l10n.dataDeletionTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        KeepAllText(l10n.dataDeletionDescription),
        const SizedBox(height: 16),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: isDeleting ? null : () => unawaited(_confirmAndDelete(context)),
          child: KeepAllText(l10n.dataDeletionButton),
        ),
        if (isDeleting) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          KeepAllText(l10n.dataDeletingMessage),
        ] else if (failure case final failure?) ...[
          const SizedBox(height: 16),
          Notice(
            tone: NoticeTone.error,
            children: [
              KeepAllText(switch (failure) {
                DeletionStep.publishedData => l10n.dataDeletionPublishedFailedMessage,
                DeletionStep.account => l10n.dataDeletionAccountFailedMessage,
                DeletionStep.deviceData => l10n.dataDeletionDeviceFailedMessage,
              }),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<CompanyProfileCubit>();
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.dataDeletionDialogTitle,
      message: l10n.dataDeletionDialogMessage,
      confirmLabel: l10n.dataDeletionConfirmButton,
      isDestructive: true,
    );
    if (confirmed) await cubit.deleteAllData();
  }
}
