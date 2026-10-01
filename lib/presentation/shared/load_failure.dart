import 'package:kkomkkomi/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// What a screen shows in place of its content when the content did not load: [message] and a retry control.
class LoadFailure extends StatelessWidget {
  const new({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(context.l10n.loadRetryButton)),
          ],
        ),
      ),
    );
  }
}
