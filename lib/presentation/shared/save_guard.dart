// 📦 Package imports:
import 'package:material_ui/material_ui.dart';

/// Keeps [child] on the screen and away from touches while a change is on its way to storage.
///
/// While [isSaving] is true, [child] takes no touch, and the route of [child] does not close on a back press or a
/// tap outside a dialog. The answer of storage then finds the screen as the change left it: the route is still the
/// top route, nothing new is open over it, and a failure has a screen to show itself on.
class SaveGuard extends StatelessWidget {
  const new({required this.isSaving, required this.child, super.key});

  final bool isSaving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isSaving,
      child: AbsorbPointer(absorbing: isSaving, child: child),
    );
  }
}
