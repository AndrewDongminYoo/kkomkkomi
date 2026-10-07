import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
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
      // Only the production flavor publishes, and only its build can sell a plan in the store. The flag comes from the
      // publish queue and not from `Entitlements`, which reaches RevenueCat in that flavor.
      child: CompanyProfileView(mentionsStoreSubscription: context.read<PublishQueue>().isAvailable),
    );
  }
}

class CompanyProfileView extends StatelessWidget {
  const new({this.mentionsStoreSubscription = false, super.key});

  /// Whether the confirmation of Delete All Data tells that the deletion does not cancel a subscription of the store,
  /// and how to cancel it. Only a flavor that can sell a plan sets it.
  final bool mentionsStoreSubscription;

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
                initialPhone: state.phone,
                entry: state.entry,
                deletion: state.deletion,
                deletionFailure: state.deletionFailure,
                mentionsStoreSubscription: mentionsStoreSubscription,
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
    required this.initialPhone,
    required this.entry,
    required this.deletion,
    required this.deletionFailure,
    required this.mentionsStoreSubscription,
  });

  /// The name that the field holds when the form opens. A later value does not replace what the person typed.
  final String initialName;
  final String initialPhone;
  final NameEntry entry;
  final DataDeletion deletion;
  final DeletionStep? deletionFailure;
  final bool mentionsStoreSubscription;

  @override
  State<_CompanyProfileForm> createState() => _CompanyProfileFormState();
}

class _CompanyProfileFormState extends State<_CompanyProfileForm> {
  late final _controller = TextEditingController(text: widget.initialName);
  late final _phoneController = TextEditingController(text: widget.initialPhone);

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The keyboard can still submit while the screen takes no touch, so a deletion also stops the save here.
    final isSaving = widget.entry == NameEntry.saving || widget.deletion != DataDeletion.idle;
    void save() {
      if (!isSaving) {
        unawaited(context.read<CompanyProfileCubit>().save(_controller.text, phone: _phoneController.text));
      }
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
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeepAllText(l10n.companyPhoneFieldLabel, style: Theme.of(context).textTheme.labelLarge),
                TextField(
                  key: const Key('company-phone'),
                  controller: _phoneController,
                  readOnly: isSaving,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    helper: KeepAllText(
                      l10n.companyPhoneHelper,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onSubmitted: (_) => save(),
                ),
              ],
            ),
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
          _DataDeletion(
            deletion: widget.deletion,
            failure: widget.deletionFailure,
            mentionsStoreSubscription: widget.mentionsStoreSubscription,
          ),
        ],
      ),
    );
  }
}

/// The control that opens the plans.
///
/// It reads nothing from `Entitlements`: in the production flavor a read reaches RevenueCat with the user ID, and that
/// must happen only when the person opens the plans screen, not when the person opens this screen to delete all data.
class _PlanEntry extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAllText(l10n.companyProfilePlanTitle, style: Theme.of(context).textTheme.titleMedium),
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
  const new({required this.deletion, required this.failure, required this.mentionsStoreSubscription});

  final DataDeletion deletion;
  final DeletionStep? failure;
  final bool mentionsStoreSubscription;

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
    // The app sells plans only through the App Store and Google Play, so another platform has no subscription to name.
    final platform = Theme.of(context).platform;
    final store = platform == TargetPlatform.android || platform == TargetPlatform.iOS ? platform : null;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.dataDeletionDialogTitle,
      message: l10n.dataDeletionDialogMessage,
      confirmLabel: l10n.dataDeletionConfirmButton,
      isDestructive: true,
      details: mentionsStoreSubscription && store != null ? _StoreSubscriptionNotice(store: store) : null,
    );
    if (confirmed) await cubit.deleteAllData();
  }
}

/// The page of Google Play that shows all the subscriptions of the person, as the Play Billing documentation names it.
final Uri _playSubscriptionsUrl = Uri.parse('https://play.google.com/store/account/subscriptions');

/// Tells that Delete All Data does not cancel a subscription of the store, and how to cancel it: a link to the
/// subscriptions of Google Play on Android, and the steps in Settings on iOS, for which no Apple source for a link was
/// found.
class _StoreSubscriptionNotice extends StatefulWidget {
  const new({required this.store});

  /// [TargetPlatform.android] or [TargetPlatform.iOS].
  final TargetPlatform store;

  @override
  State<_StoreSubscriptionNotice> createState() => _StoreSubscriptionNoticeState();
}

class _StoreSubscriptionNoticeState extends State<_StoreSubscriptionNotice> {
  var _openFailed = false;

  Future<void> _openSubscriptions() async {
    final opened = await context.read<ExternalLinks>().open(_playSubscriptionsUrl);
    // The person can close the question while the link opens.
    if (!mounted) return;
    setState(() => _openFailed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Notice(
          children: [
            KeepAllText(l10n.dataDeletionSubscriptionMessage),
            if (widget.store == TargetPlatform.android)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => unawaited(_openSubscriptions()),
                  child: KeepAllText(l10n.dataDeletionSubscriptionLink),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              KeepAllText(l10n.dataDeletionSubscriptionSteps),
            ],
          ],
        ),
        if (_openFailed) ...[
          const SizedBox(height: 8),
          Notice(tone: NoticeTone.error, children: [KeepAllText(l10n.plansLinkFailedMessage)]),
        ],
      ],
    );
  }
}
