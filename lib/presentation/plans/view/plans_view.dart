import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/plans/cubit/plans_cubit.dart';
import 'package:kkomkkomi/presentation/plans/view/plan_name.dart';
import 'package:kkomkkomi/presentation/shared/corner_radius.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/shared/notice.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:material_ui/material_ui.dart';

/// The standard end user license agreement of Apple, which is the terms of use of the subscriptions (operator,
/// 2026-10-05).
final Uri termsOfUseUrl = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');

/// The privacy policy in the language of [locale]: Korean at `/privacy/`, and English at `/privacy/en/` otherwise.
Uri privacyPolicyUrlFor(Locale locale) =>
    Uri.parse('$reportSiteOrigin/privacy/${locale.languageCode == 'ko' ? '' : 'en/'}');

class PlansView extends StatefulWidget {
  const new({super.key});

  @override
  State<PlansView> createState() => _PlansViewState();
}

class _PlansViewState extends State<PlansView> {
  /// Reads the plan and the offers again each time that the app comes back to the foreground, because the person can
  /// change the subscription outside the app, for example in the subscription management of the store.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(context.read<PlansCubit>().refresh()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<PlansCubit, PlansState>(
      // A person who leaves while the store sheet is open would not see what became of the purchase.
      builder: (context, state) => SaveGuard(
        isSaving: state.isBusy,
        child: Scaffold(
          appBar: AppBar(title: KeepAllText(l10n.plansTitle)),
          body: SafeArea(
            child: switch (state.status) {
              PlansStatus.loading => const Center(child: CircularProgressIndicator()),
              PlansStatus.ready => _Plans(state: state),
            },
          ),
        ),
      ),
    );
  }
}

class _Plans extends StatelessWidget {
  const new({required this.state});

  final PlansState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cubit = context.read<PlansCubit>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeepAllText(l10n.plansCurrentLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          KeepAllText(state.plan.nameIn(l10n), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          _PlanContents(plan: state.plan),
          if (state.isBusy) ...[const SizedBox(height: 16), const LinearProgressIndicator()],
          if (state.notice case final notice?) ...[const SizedBox(height: 16), _ActionNotice(notice: notice)],
          const SizedBox(height: 24),
          if (!state.sellsPlans)
            Notice(children: [KeepAllText(l10n.plansUnavailableMessage)])
          else ...[
            ..._offers(context),
            const SizedBox(height: 8),
            KeepAllText(l10n.plansArchivedNote, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => unawaited(cubit.restore()),
              child: KeepAllText(l10n.plansRestoreButton),
            ),
            if (state.managementUrl != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => unawaited(cubit.openManagement()),
                child: KeepAllText(l10n.plansManageButton),
              ),
            ],
            const SizedBox(height: 16),
            KeepAllText(l10n.plansRenewalNote, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => unawaited(cubit.open(termsOfUseUrl)),
                child: KeepAllText(l10n.plansTermsLink),
              ),
              TextButton(
                onPressed: () => unawaited(cubit.open(privacyPolicyUrlFor(Localizations.localeOf(context)))),
                child: KeepAllText(l10n.plansPrivacyLink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The offers of each paid plan, or a load, or a failure with a retry control.
  List<Widget> _offers(BuildContext context) {
    final l10n = context.l10n;
    return switch (state.offersStatus) {
      OffersStatus.loading => [const Center(child: CircularProgressIndicator())],
      OffersStatus.failed => [
        Notice(
          tone: NoticeTone.error,
          children: [
            KeepAllText(l10n.plansOffersFailedMessage),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => unawaited(context.read<PlansCubit>().retry()),
                child: KeepAllText(l10n.loadRetryButton),
              ),
            ),
          ],
        ),
      ],
      OffersStatus.loaded => [
        for (final plan in [Plan.basic, Plan.pro])
          if (state.offers.where((offer) => offer.plan == plan).toList() case final offers when offers.isNotEmpty) ...[
            _PlanCard(plan: plan, offers: offers, state: state),
            const SizedBox(height: 12),
          ],
      ],
    };
  }
}

/// What [plan] holds: its client limit and whether its reports carry the footer text.
class _PlanContents extends StatelessWidget {
  const new({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAllText(switch (plan.clientLimit) {
          final limit? => l10n.planClientLimit(limit),
          null => l10n.planNoClientLimit,
        }),
        const SizedBox(height: 4),
        KeepAllText(
          plan.showsFooter ? l10n.planFooterShown(l10n.reportFooter) : l10n.planFooterHidden(l10n.reportFooter),
        ),
      ],
    );
  }
}

/// A paid plan with its contents and one control for each period that the store sells.
class _PlanCard extends StatelessWidget {
  const new({required this.plan, required this.offers, required this.state});

  final Plan plan;
  final List<PlanOffer> offers;
  final PlansState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeepAllText(plan.nameIn(l10n), style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _PlanContents(plan: plan),
            for (final offer in offers) ...[
              const SizedBox(height: 12),
              if (state.isInUse(offer))
                OutlinedButton(
                  onPressed: null,
                  child: KeepAllText(switch (offer.period) {
                    BillingPeriod.monthly => l10n.plansMonthlyInUse(offer.price),
                    BillingPeriod.annual => l10n.plansAnnualInUse(offer.price),
                  }),
                )
              else
                FilledButton(
                  onPressed: () => unawaited(context.read<PlansCubit>().purchase(offer)),
                  child: KeepAllText(switch (offer.period) {
                    BillingPeriod.monthly => l10n.plansSubscribeMonthlyButton(offer.price),
                    BillingPeriod.annual => l10n.plansSubscribeAnnualButton(offer.price),
                  }),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The outcome of the last action, in the tone of a failure or of a fact.
class _ActionNotice extends StatelessWidget {
  const new({required this.notice});

  final PlansNotice notice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (tone, message) = switch (notice) {
      PlansNotice.purchasePending => (NoticeTone.info, l10n.plansPurchasePendingMessage),
      PlansNotice.purchaseFailed => (NoticeTone.error, l10n.plansPurchaseFailedMessage),
      PlansNotice.restored => (NoticeTone.info, l10n.plansRestoredMessage),
      PlansNotice.nothingFound => (NoticeTone.info, l10n.plansNothingFoundMessage),
      PlansNotice.restoreFailed => (NoticeTone.error, l10n.plansRestoreFailedMessage),
      PlansNotice.linkFailed => (NoticeTone.error, l10n.plansLinkFailedMessage),
    };
    return Notice(tone: tone, children: [KeepAllText(message)]);
  }
}
