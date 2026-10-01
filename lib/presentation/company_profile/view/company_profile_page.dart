import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/company_profile/cubit/company_profile_cubit.dart';
import 'package:kkomkkomi/presentation/shared/load_failure.dart';
import 'package:kkomkkomi/presentation/shared/name_entry.dart';
import 'package:kkomkkomi/presentation/shared/name_field.dart';
import 'package:kkomkkomi/presentation/shared/save_guard.dart';
import 'package:material_ui/material_ui.dart';

/// The screen that edits the company name, which the report prints.
class CompanyProfilePage extends StatelessWidget {
  const new({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const CompanyProfilePage());

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = CompanyProfileCubit(companyProfile: context.read<CompanyProfileRepository>());
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
      listenWhen: (previous, current) => previous.entry != NameEntry.saved && current.entry == NameEntry.saved,
      listener: (context, _) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.companyProfileSavedMessage))),
      // A person who leaves while the name is on its way would not see that storage did not take it.
      builder: (context, state) => SaveGuard(
        isSaving: state.entry == NameEntry.saving,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.companyProfileTitle)),
          body: SafeArea(
            child: switch (state.status) {
              CompanyProfileStatus.loading => const Center(child: CircularProgressIndicator()),
              CompanyProfileStatus.loadFailed => LoadFailure(
                message: l10n.companyProfileLoadFailedMessage,
                onRetry: () => unawaited(context.read<CompanyProfileCubit>().load()),
              ),
              CompanyProfileStatus.ready => _CompanyProfileForm(initialName: state.name, entry: state.entry),
            },
          ),
        ),
      ),
    );
  }
}

class _CompanyProfileForm extends StatefulWidget {
  const new({required this.initialName, required this.entry});

  /// The name that the field holds when the form opens. A later value does not replace what the person typed.
  final String initialName;
  final NameEntry entry;

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
    final isSaving = widget.entry == NameEntry.saving;
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
          FilledButton(onPressed: isSaving ? null : save, child: Text(l10n.nameSaveButton)),
        ],
      ),
    );
  }
}
