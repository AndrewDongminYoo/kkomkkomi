import 'dart:io';

import 'package:material_ui/material_ui.dart';

/// Shows the photo file at [path], cut to fill the box that the parent gives.
///
/// A file that does not load shows an icon in its place, so that a lost file breaks one picture and not the screen.
class PhotoThumbnail extends StatelessWidget {
  const new({required this.path, this.semanticLabel, super.key});

  /// The width in pixels at which the photo is decoded.
  ///
  /// A stored photo has more pixels than a thumbnail shows, and a visit with many zones keeps many photos in memory.
  static const decodeWidth = 600;

  /// The absolute path of the photo file.
  final String path;

  /// What a screen reader says for the photo. Without it, the photo is not in the semantics tree, which suits a
  /// photo inside a control that has its own label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
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
