// The function relies on the grapheme cluster rules of `characters`, a direct dependency, and not on the export of
// Flutter that makes the library visible here too.
// 📦 Package imports:
// ignore: unnecessary_import
import 'package:characters/characters.dart';
import 'package:material_ui/material_ui.dart';

/// The character that Unicode defines to prohibit a line break at its position.
///
/// It is a grapheme cluster of its own, and it does not join the clusters around it the way the zero-width joiner
/// (U+200D) does.
const wordJoiner = '\u2060';

/// The Hangul Jamo, Hangul Compatibility Jamo, Hangul Jamo Extended-A, Hangul Syllables, and Hangul Jamo Extended-B
/// blocks.
final _hangul = RegExp('[\u1100-\u11FF\u3130-\u318F\uA960-\uA97F\uAC00-\uD7AF\uD7B0-\uD7FF]');

/// An emoji character that is pictographic, a regional indicator, which a flag is made of, or the combining enclosing
/// keycap (U+20E3), which ends a keycap emoji.
///
/// The lookahead keeps out the digits, `#`, and `*`, which have the Emoji property for their keycap form, and the
/// pictographic symbols without the Emoji property, such as \u2605 (U+2605), which are text.
// The lint flags the property escapes, which the `unicode` flag allows; the tests run the pattern.
// ignore: valid_regexps
final _emoji = RegExp(r'(?=\p{Extended_Pictographic})\p{Emoji}|\p{Regional_Indicator}|\u20E3', unicode: true);

final _whitespace = RegExp(r'\s+');

/// Gives [text] with a [wordJoiner] between the grapheme clusters of each whitespace-separated word that holds
/// Hangul, so that a line breaks only at a space or a newline, as `word-break: keep-all` does in CSS.
///
/// Flutter breaks Korean text between any two syllables. A word without Hangul and a word with an emoji stay as they
/// are, and every space and newline stays in place. The joiners that a word holds are removed before its clusters are
/// joined, so the function gives the same string when it runs on its own result.
///
/// The result is for display only: a value that leaves the screen, such as a stored value or a shared text, must not
/// hold the joiners.
String keepAll(String text) {
  if (!_hangul.hasMatch(text)) return text;
  return text.splitMapJoin(_whitespace, onNonMatch: _joinClusters);
}

String _joinClusters(String word) {
  if (!_hangul.hasMatch(word) || _emoji.hasMatch(word)) return word;
  return word.replaceAll(wordJoiner, '').characters.join(wordJoiner);
}

/// A [Text] that shows its [data] through [keepAll], so that Korean text breaks between words.
///
/// The accessible label stays [data], without the joiners. The widget is a [Text] of [data], so that a finder and a
/// lookup of a [Text] read the string as the person reads it, and it builds a [Text] of the joined string in its place.
class KeepAllText extends Text {
  const new(super.data, {super.style, super.textAlign, super.softWrap, super.overflow, super.maxLines, super.key});

  @override
  Widget build(BuildContext context) {
    final data = this.data!;
    final shown = keepAll(data);
    if (shown == data) return super.build(context);
    return Text(
      shown,
      style: style,
      textAlign: textAlign,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      semanticsLabel: data,
    );
  }
}
