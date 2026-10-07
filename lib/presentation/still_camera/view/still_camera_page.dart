// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';
import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';
import 'package:kkomkkomi/presentation/still_camera/camera_photo_files.dart';
import 'package:kkomkkomi/presentation/still_camera/cubit/still_camera_cubit.dart';
import 'package:kkomkkomi/presentation/still_camera/still_camera_driver.dart';

class StillCameraPage extends StatelessWidget {
  const new({required this.driverFactory, required this.files, required this.clock, super.key});
  final StillCameraDriver Function() driverFactory;
  final CameraPhotoFiles files;
  final Clock clock;
  static Route<Object> route({
    required StillCameraDriver Function() driverFactory,
    required CameraPhotoFiles files,
    required Clock clock,
  }) => MaterialPageRoute<Object>(
    builder: (_) => StillCameraPage(driverFactory: driverFactory, files: files, clock: clock),
  );
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = StillCameraCubit(driverFactory: driverFactory, files: files, clock: clock);
      unawaited(cubit.start());
      return cubit;
    },
    // A visit notice must not move onto this route and cover its shutter control.
    child: const ScaffoldMessenger(child: StillCameraView()),
  );
}

class StillCameraView extends StatefulWidget {
  const new({super.key});
  @override
  State<StillCameraView> createState() => _StillCameraViewState();
}

class _StillCameraViewState extends State<StillCameraView> {
  late final AppLifecycleListener _lifecycle;
  @override
  void initState() {
    super.initState();
    final cubit = context.read<StillCameraCubit>();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null) cubit.setForeground(foreground: lifecycle == AppLifecycleState.resumed);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => cubit.setForeground(foreground: state == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<StillCameraCubit, StillCameraState>(
    listenWhen: (_, current) => current.status == StillCameraStatus.complete,
    listener: (context, state) => Navigator.of(context).pop(state.failure ?? state.photo),
    child: BlocBuilder<StillCameraCubit, StillCameraState>(
      builder: (context, state) {
        final cubit = context.read<StillCameraCubit>();
        final l10n = context.l10n;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(cubit.cancel());
          },
          child: Scaffold(
            appBar: AppBar(
              title: KeepAllText(l10n.cameraTitle),
              leading: IconButton(
                tooltip: l10n.cameraClose,
                icon: const Icon(Icons.close),
                onPressed: () => unawaited(cubit.cancel()),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: switch (state.status) {
                        StillCameraStatus.ready || StillCameraStatus.capturing => cubit.driver.preview(),
                        _ => const CircularProgressIndicator(),
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: state.status == StillCameraStatus.ready ? () => unawaited(cubit.capture()) : null,
                      icon: const Icon(Icons.camera_alt),
                      label: KeepAllText(l10n.cameraShutter),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
