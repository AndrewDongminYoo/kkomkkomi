import 'dart:io';

import 'package:material_ui/material_ui.dart';

/// Shows the photo file at [path] in the box that the parent gives, cut to fill it unless [fit] says another way.
///
/// A file that does not load shows an icon in its place, so that a lost file breaks one picture and not the screen.
class PhotoThumbnail extends StatelessWidget {
  const new({required this.path, this.fit = BoxFit.cover, this.semanticLabel, super.key});

  /// The width in pixels at which the photo is decoded.
  ///
  /// A stored photo has more pixels than a thumbnail shows, and a visit with many zones keeps many photos in memory.
  static const decodeWidth = 600;

  /// The absolute path of the photo file.
  final String path;

  /// How the photo takes its box. [BoxFit.cover] cuts the edges of a photo with another ratio than the box, and
  /// [BoxFit.contain] shows the whole photo.
  final BoxFit fit;

  /// What a screen reader says for the photo. Without it, the photo is not in the semantics tree, which suits a
  /// photo inside a control that has its own label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: decodeWidth,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (context, _, _) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}
