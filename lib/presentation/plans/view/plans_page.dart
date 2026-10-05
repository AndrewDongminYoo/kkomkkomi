import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/presentation/plans/cubit/plans_cubit.dart';
import 'package:kkomkkomi/presentation/plans/view/plans_view.dart';
import 'package:material_ui/material_ui.dart';

/// The screen that shows the plan of the company and sells the paid plans.
class PlansPage extends StatelessWidget {
  const new({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const PlansPage());

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = PlansCubit(entitlements: context.read<Entitlements>(), links: context.read<ExternalLinks>());
        unawaited(cubit.load());
        return cubit;
      },
      child: const PlansView(),
    );
  }
}
