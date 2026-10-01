import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/client_detail/cubit/client_detail_cubit.dart';
import 'package:kkomkkomi/presentation/shared/confirm_dialog.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:kkomkkomi/presentation/visit_capture/visit_capture.dart';
import 'package:material_ui/material_ui.dart';

/// The largest text scale inside the date picker of a visit.
///
/// The header of the `material_ui` date picker has a fixed height, and above this scale its text overflows on a
/// screen 320 pixels wide.
const _datePickerMaxTextScale = 2.0;

/// The screen of one client: its name, its zone list, its past visits, and the control that starts a visit.
class ClientDetailPage extends StatelessWidget {
  const new({required this.clientId, super.key});

  final String clientId;

  static Route<void> route({required String clientId}) =>
      MaterialPageRoute<void>(builder: (_) => ClientDetailPage(clientId: clientId));

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = ClientDetailCubit(
          clientId: clientId,
          clients: context.read<ClientRepository>(),
          visits: context.read<VisitRepository>(),
          idGenerator: context.read<IdGenerator>(),
          startVisit: StartVisit(
            clients: context.read<ClientRepository>(),
            visits: context.read<VisitRepository>(),
            idGenerator: context.read<IdGenerator>(),
            clock: context.read<Clock>(),
          ),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const ClientDetailView(),
    );
  }
}

class ClientDetailView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<ClientDetailCubit, ClientDetailState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        if (state.status == ClientDetailStatus.archived) Navigator.of(context).pop();
        if (state.startedVisitId case final visitId? when state.status == ClientDetailStatus.visitStarted) {
          Navigator.of(context).push(VisitCapturePage.route(visitId: visitId));
        }
        if (state.status == ClientDetailStatus.saveFailed) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l10n.saveFailedMessage)));
        }
      },
      builder: (context, state) {
        final client = state.client;
        // The archived status closes the top route and a started visit opens over it, so the screen must still be
        // that route when storage answers.
        return SaveGuard(
          isSaving: state.status == ClientDetailStatus.saving,
          child: Scaffold(
            appBar: AppBar(
              title: client == null ? null : Text(client.name),
              actions: [if (client != null) _ClientMenu(client: client)],
            ),
            body: SafeArea(
              child: switch (state.status) {
                ClientDetailStatus.loading => const Center(child: CircularProgressIndicator()),
                ClientDetailStatus.loadFailed => LoadFailure(
                  message: l10n.clientDetailLoadFailedMessage,
                  onRetry: () => unawaited(context.read<ClientDetailCubit>().load()),
                ),
                ClientDetailStatus.ready ||
                ClientDetailStatus.saving ||
                ClientDetailStatus.saveFailed ||
                ClientDetailStatus.archived ||
                ClientDetailStatus.visitStarted => _ClientContent(zones: state.activeZones, visits: state.visits),
              },
            ),
          ),
        );
      },
    );
  }
}

enum _ClientAction { rename, archive }

class _ClientMenu extends StatelessWidget {
  const new({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<_ClientAction>(
      onSelected: (action) => switch (action) {
        _ClientAction.rename => _showRenameDialog(context),
        _ClientAction.archive => unawaited(_confirmArchive(context)),
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: _ClientAction.rename, child: Text(l10n.clientDetailRenameAction)),
        PopupMenuItem(value: _ClientAction.archive, child: Text(l10n.clientDetailArchiveAction)),
      ],
    );
  }

  void _showRenameDialog(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ClientDetailCubit>()..startNameEntry();
    unawaited(
      showNameDialog<ClientDetailCubit, ClientDetailState>(
        context: context,
        cubit: cubit,
        entryOf: (state) => state.entry,
        title: l10n.clientRenameDialogTitle,
        fieldLabel: l10n.clientNameFieldLabel,
        submitLabel: l10n.nameSaveButton,
        initialName: client.name,
        onSubmit: cubit.renameClient,
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<ClientDetailCubit>();
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.clientArchiveDialogTitle,
      message: l10n.clientArchiveDialogMessage,
      confirmLabel: l10n.clientDetailArchiveAction,
    );
    if (confirmed) await cubit.archive();
  }
}

/// The body of the screen: one list that scrolls the start control, the zones, and the past visits together.
///
/// The zones are the items of the list, so that a person can drag one past the edge of the screen, and the rest
/// stands in the header and the footer of the list.
class _ClientContent extends StatelessWidget {
  const new({required this.zones, required this.visits});

  final List<Zone> zones;
  final List<Visit> visits;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 24),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            // A visit keeps the zones that it started with, so a client without zones has no visit to start.
            child: FilledButton(
              onPressed: zones.isEmpty ? null : () => unawaited(_pickDateAndStartVisit(context)),
              child: Text(l10n.clientDetailStartVisitButton),
            ),
          ),
          _SectionTitle(l10n.zoneSectionTitle),
          if (zones.isEmpty) _SectionMessage(l10n.zoneEmptyMessage),
        ],
      ),
      itemCount: zones.length,
      itemBuilder: (context, index) => _ZoneTile(key: ValueKey(zones[index].id), zone: zones[index], index: index),
      onReorderItem: (from, to) => unawaited(context.read<ClientDetailCubit>().moveZone(from, to)),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => _showAddZoneDialog(context),
              icon: const Icon(Icons.add),
              label: Text(l10n.zoneAddButton),
            ),
          ),
          _SectionTitle(l10n.visitSectionTitle),
          if (visits.isEmpty) _SectionMessage(l10n.visitEmptyMessage),
          for (final visit in visits)
            ListTile(
              title: Text(
                l10n.visitDateLabel(DateTime(visit.visitDate.year, visit.visitDate.month, visit.visitDate.day)),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(VisitCapturePage.route(visitId: visit.id)),
            ),
        ],
      ),
    );
  }

  /// Asks for the visit date, which is today unless the person picks an earlier day, and starts the visit.
  ///
  /// A visit records a cleaning that took place, so the picker offers no day after today.
  Future<void> _pickDateAndStartVisit(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<ClientDetailCubit>();
    final today = DateUtils.dateOnly(context.read<Clock>().now().toLocal());
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: l10n.visitDatePickerHelp,
      cancelText: l10n.dialogCancelButton,
      confirmText: l10n.clientDetailStartVisitButton,
      builder: (context, child) =>
          MediaQuery.withClampedTextScaling(maxScaleFactor: _datePickerMaxTextScale, child: child!),
    );
    if (picked != null) await cubit.startVisit(VisitDate.fromDateTime(picked));
  }

  void _showAddZoneDialog(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ClientDetailCubit>()..startNameEntry();
    unawaited(
      showNameDialog<ClientDetailCubit, ClientDetailState>(
        context: context,
        cubit: cubit,
        entryOf: (state) => state.entry,
        title: l10n.zoneAddDialogTitle,
        fieldLabel: l10n.zoneNameFieldLabel,
        submitLabel: l10n.nameAddButton,
        onSubmit: cubit.addZone,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(text));
  }
}

class _ZoneTile extends StatelessWidget {
  const new({required this.zone, required this.index, super.key});

  final Zone zone;

  /// The index of [zone] among the listed zones, which the drag handle passes to the list.
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      horizontalTitleGap: 4,
      // The handle has no tooltip and no label. The long press of a tooltip takes the pointer from the drag when a
      // person rests a finger on the handle before the move, and a screen reader moves the zone with the actions
      // that the list gives each row, not with the handle.
      leading: ReorderableDragStartListener(
        index: index,
        child: const SizedBox.square(dimension: 48, child: Icon(Icons.drag_handle)),
      ),
      title: Text(zone.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.zoneRenameTooltip(zone.name),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showRenameDialog(context),
          ),
          IconButton(
            tooltip: l10n.zoneRemoveTooltip(zone.name),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_confirmRemove(context)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ClientDetailCubit>()..startNameEntry();
    unawaited(
      showNameDialog<ClientDetailCubit, ClientDetailState>(
        context: context,
        cubit: cubit,
        entryOf: (state) => state.entry,
        title: l10n.zoneRenameDialogTitle,
        fieldLabel: l10n.zoneNameFieldLabel,
        submitLabel: l10n.nameSaveButton,
        initialName: zone.name,
        onSubmit: (name) => unawaited(cubit.renameZone(zone.id, name)),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<ClientDetailCubit>();
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.zoneRemoveDialogTitle(zone.name),
      message: l10n.zoneRemoveDialogMessage,
      confirmLabel: l10n.zoneRemoveConfirmButton,
    );
    if (confirmed) await cubit.removeZone(zone.id);
  }
}
