import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/client_detail/client_detail.dart';
import 'package:kkomkkomi/presentation/client_list/cubit/client_list_cubit.dart';
import 'package:kkomkkomi/presentation/company_profile/company_profile.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/name_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// The home screen: the active clients, a control that adds a client, and the way to the company profile.
class ClientListPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = ClientListCubit(
          clients: context.read<ClientRepository>(),
          idGenerator: context.read<IdGenerator>(),
          clock: context.read<Clock>(),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const ClientListView(),
    );
  }
}

class ClientListView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.clientListTitle),
        actions: [
          IconButton(
            tooltip: l10n.companyProfileTitle,
            icon: const Icon(Icons.business_outlined),
            onPressed: () async {
              final cubit = context.read<ClientListCubit>();
              await Navigator.of(context).push(CompanyProfilePage.route());
              // The profile screen can delete all data, which empties this list.
              await cubit.load();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<ClientListCubit, ClientListState>(
          builder: (context, state) => switch (state.status) {
            ClientListStatus.loading => const Center(child: CircularProgressIndicator()),
            ClientListStatus.loadFailed => LoadFailure(
              message: l10n.clientListLoadFailedMessage,
              onRetry: () => unawaited(context.read<ClientListCubit>().load()),
            ),
            ClientListStatus.ready => _ClientList(clients: state.clients),
          },
        ),
      ),
    );
  }
}

class _ClientList extends StatelessWidget {
  const new({required this.clients});

  final List<Client> clients;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: clients.isEmpty
              ? const _EmptyClientList()
              : ListView.builder(
                  itemCount: clients.length,
                  itemBuilder: (context, index) => _ClientTile(client: clients[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.clientListAddButton),
          ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ClientListCubit>()..startNameEntry();
    unawaited(
      showNameDialog<ClientListCubit, ClientListState>(
        context: context,
        cubit: cubit,
        entryOf: (state) => state.entry,
        title: l10n.clientAddDialogTitle,
        fieldLabel: l10n.clientNameFieldLabel,
        submitLabel: l10n.nameAddButton,
        onSubmit: cubit.addClient,
      ),
    );
  }
}

class _EmptyClientList extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.clientListEmptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.clientListEmptyMessage, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const new({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(client.name),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final cubit = context.read<ClientListCubit>();
        await Navigator.of(context).push(ClientDetailPage.route(clientId: client.id));
        // The client screen can rename or archive the client, and both change this list.
        await cubit.load();
      },
    );
  }
}
