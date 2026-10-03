import 'package:kkomkkomi/presentation/shared/corner_radius.dart';
import 'package:material_ui/material_ui.dart';

/// What a [Notice] tells: a fact that the person should know, or a failure.
enum NoticeTone { info, error }

/// A box that sets a message apart from the content around it, in the colors of its [tone].
///
/// The text and the text buttons in [children] take the color of the text of the tone, and an icon at the start tells
/// a failure from a fact without the color.
class Notice extends StatelessWidget {
  const new({required this.children, this.tone = NoticeTone.info, super.key});

  final NoticeTone tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (fill, onFill, icon) = switch (tone) {
      NoticeTone.info => (colors.surfaceContainerHighest, colors.onSurface, Icons.info_outline),
      NoticeTone.error => (colors.errorContainer, colors.onErrorContainer, Icons.error_outline),
    };
    final buttonStyle = TextButton.styleFrom(foregroundColor: onFill).merge(TextButtonTheme.of(context).style);
    return DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(cornerRadius)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: onFill),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: onFill),
                child: TextButtonTheme(
                  data: TextButtonThemeData(style: buttonStyle),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
