// 🐦 Flutter imports:
import 'package:flutter/rendering.dart';

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/presentation/shared/keep_all_text.dart';

import '../../helpers/helpers.dart';

/// The text of each line of the paragraph under [finder], without the joiners and the spaces at its ends.
List<String> _linesOf(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: finder, matching: find.byType(RichText)));
  final text = paragraph.text.toPlainText();
  final lines = <StringBuffer>[];
  double? lineTop;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == wordJoiner || char == ' ') {
      if (lines.isNotEmpty) lines.last.write(char);
      continue;
    }
    final top = paragraph.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.top;
    if (lineTop == null || top > lineTop) {
      lineTop = top;
      lines.add(StringBuffer());
    }
    lines.last.write(char);
  }
  return [for (final line in lines) line.toString().replaceAll(wordJoiner, '').trim()];
}

void main() {
  group('keepAll', () {
    test('joins the syllables of each Hangul word', () {
      expect(keepAll('거래처가 없어요'), '거\u2060래\u2060처\u2060가 없\u2060어\u2060요');
    });

    test('keeps the Latin words of a mixed sentence as they are', () {
      expect(keepAll('Kkomkkomi 앱으로 report 보내기'), 'Kkomkkomi 앱\u2060으\u2060로 report 보\u2060내\u2060기');
    });

    test('joins the punctuation of a Hangul word to it', () {
      expect(keepAll('있어요.'), '있\u2060어\u2060요\u2060.');
    });

    test('keeps a non-BMP character next to Hangul in one piece', () {
      expect(keepAll('\u{20BB7}가'), '\u{20BB7}\u2060가');
    });

    test('keeps the jamo of a decomposed syllable in one piece', () {
      // 각 as three jamo, then 나 as two.
      expect(keepAll('\u1100\u1161\u11A8\u1102\u1161'), '\u1100\u1161\u11A8\u2060\u1102\u1161');
    });

    test('keeps a word with an emoji as it is', () {
      expect(keepAll('청소😀 완료'), '청소😀 완\u2060료');
      expect(keepAll('청소🇰🇷'), '청소🇰🇷');
      expect(keepAll('1\uFE0F\u20E3번'), '1\uFE0F\u20E3번');
    });

    test('joins a word with a pictographic symbol that is no emoji', () {
      expect(keepAll('★한빛'), '★\u2060한\u2060빛');
    });

    test('joins a word with a digit, which is an emoji only in a keycap', () {
      expect(keepAll('1층'), '1\u2060층');
    });

    test('keeps multiple spaces in place', () {
      expect(keepAll('거래처  추가'), '거\u2060래\u2060처  추\u2060가');
    });

    test('keeps newlines in place', () {
      expect(keepAll('첫 줄\n둘째 줄\n\n끝'), '첫 줄\n둘\u2060째 줄\n\n끝');
    });

    test('gives the empty string for the empty string', () {
      expect(keepAll(''), '');
    });

    test('gives text without Hangul unchanged', () {
      const text = 'Add a client at https://kkomkkomi.web.app 2026-10-03';

      expect(identical(keepAll(text), text), isTrue);
    });

    test('removes the joiners that a word holds before it joins the word', () {
      expect(keepAll('거\u2060\u2060래처'), '거\u2060래\u2060처');
    });

    test('gives the same string on a second pass', () {
      for (final text in [
        '거래처가 없어요',
        'Kkomkkomi 앱으로',
        '\u{20BB7}가',
        '\u1100\u1161\u11A8\u1102\u1161',
        '청소😀 완료',
        '1\uFE0F\u20E3번',
      ]) {
        final once = keepAll(text);

        expect(keepAll(once), once, reason: text);
      }
    });
  });

  group('KeepAllText', () {
    const sentence = '아직 거래처가 없어요. 거래처를 추가하면 여기에 보여요.';

    testWidgets('breaks a Korean sentence only at its spaces', (tester) async {
      await tester.pumpApp(
        const Scaffold(
          body: Center(child: SizedBox(width: 120, child: KeepAllText(sentence))),
        ),
      );

      final lines = _linesOf(tester, find.byType(KeepAllText));

      expect(lines.length, greaterThan(1));
      expect(lines.join(' '), sentence, reason: '$lines');
    });

    testWidgets('a Text breaks the same sentence inside a word, which the joiners prevent', (tester) async {
      await tester.pumpApp(
        const Scaffold(
          body: Center(child: SizedBox(width: 120, child: Text(sentence))),
        ),
      );

      final lines = _linesOf(tester, find.byType(Text));

      expect(lines.join(' '), isNot(sentence), reason: '$lines');
    });

    testWidgets('gives the style and the layout settings to the text that it shows', (tester) async {
      const style = TextStyle(fontSize: 20);
      await tester.pumpApp(
        const KeepAllText(
          '거래처',
          style: style,
          textAlign: TextAlign.center,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, '거\u2060래\u2060처');
      expect(text.style, style);
      expect(text.textAlign, TextAlign.center);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
    });

    testWidgets('gives a screen reader the text without the joiners', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(const KeepAllText(sentence));

      expect(tester.getSemantics(find.byType(KeepAllText)), matchesSemantics(label: sentence));
      expect(find.bySemanticsLabel(RegExp(wordJoiner)), findsNothing);
      semantics.dispose();
    });

    testWidgets('builds what a Text builds for text without Hangul', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(const KeepAllText('No clients yet'));

      expect(find.byType(Text), findsNothing);
      expect(tester.renderObject<RenderParagraph>(find.byType(RichText)).text.toPlainText(), 'No clients yet');
      expect(tester.getSemantics(find.byType(KeepAllText)), matchesSemantics(label: 'No clients yet'));
      semantics.dispose();
    });

    testWidgets('is a Text of the string as the person reads it', (tester) async {
      await tester.pumpApp(const KeepAllText('거래처가 없어요'));

      expect(find.text('거래처가 없어요'), findsOneWidget);
      expect(tester.widget<Text>(find.text('거래처가 없어요')), isA<KeepAllText>());
    });
  });
}
