import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final _startXref = RegExp(r'startxref\s+(\d+)\s+%%EOF\s*$');
final _reference = RegExp(r'(\d+) 0 R');
final _mediaBox = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]');
final _mapping = RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]+)>');
final _hexString = RegExp('<([0-9A-Fa-f]*)>');

/// The operators of a page that the reader follows: a font choice, a text that is shown with the position that the
/// `pdf` package moves to before it, an image that is drawn, a change of the coordinates, and a save or a restore of
/// the graphics state.
final _operator = RegExp(
  r'/(\w+)\s+[\d.]+\s+Tf|(?:(-?[\d.]+\s+-?[\d.]+)\s+Td\s*)?\[([^\]]*)\]\s*TJ|/(\w+)\s+Do\b'
  r'|((?:-?[\d.]+\s+){6})cm\b|\b([qQ])\b',
);

/// What a test reads of a PDF file that the `pdf` package wrote: its pages, with their size, text, and images.
///
/// The reader is not a PDF library. It follows the path that a viewer follows: from the cross-reference offset at
/// the end of the file to the cross-reference stream, and from the object offsets in that stream to the catalog,
/// the page tree, and each page. It decodes every compressed stream on that path: the cross-reference stream, the
/// content of each page, and the character map of each font. It reads only the forms that the `pdf` package
/// writes, and it throws a [FormatException] for another form.
final class PdfSummary {
  const new({required this.pages});

  /// Reads [bytes], and throws a [FormatException] for a file that does not have the structure of a PDF.
  factory read(Uint8List bytes) => _PdfReader(bytes).summary();

  /// The pages in the order of the page tree.
  final List<PdfPage> pages;

  int get pageCount => pages.length;

  /// The text of all pages, joined with a space.
  String get text => pages.map((page) => page.text).join(' ');
}

/// One page of a PDF file.
final class PdfPage {
  const new({required this.width, required this.height, required this.texts, required this.images});

  /// The width of the page in points.
  final double width;

  /// The height of the page in points.
  final double height;

  /// The words that the page shows, in the order in which the file draws them, joined with a space.
  ///
  /// The `pdf` package draws the footer of a page before its content, so the text of the footer comes first.
  String get text => texts.map((text) => text.text).join(' ');

  /// Each text that the page shows, in the order in which the file draws them, with the distance in points from the
  /// left edge of the page to where its drawing starts.
  ///
  /// The `pdf` package draws each word of a text widget as a text of its own. The reader follows the changes of the
  /// coordinates that the package writes around the text (`cm`, `q`, and `Q`), and the move to the text (`Td`).
  final List<({String text, double x})> texts;

  /// The pixel size of each image that the page shows, in the order in which the file draws them.
  final List<({int width, int height})> images;
}

final class _PdfReader {
  new(this._bytes) : _text = latin1.decode(_bytes);

  final Uint8List _bytes;

  /// The file as text with one character for each byte, so that an index in the text is an offset in the file.
  final String _text;

  final _characterMaps = <int, Map<int, String>>{};

  /// The offset of each object that the cross-reference stream names as in use, by object number.
  final _offsets = <int, int>{};

  PdfSummary summary() {
    if (!_text.startsWith('%PDF-1.')) throw const FormatException('The file has no PDF header');
    final startXref = _startXref.firstMatch(_text);
    if (startXref == null) throw const FormatException('The file does not end with a cross-reference offset');
    final xrefOffset = int.parse(startXref.group(1)!);
    final xrefStart = xrefOffset < _text.length ? RegExp(r'\d+ 0 obj\b').matchAsPrefix(_text, xrefOffset) : null;
    if (xrefStart == null) throw const FormatException('The cross-reference offset does not point at an object');
    final xref = _dictionaryAt(xrefStart.end);
    if (!xref.source.contains('/Type/XRef')) throw const FormatException('The file has no cross-reference stream');
    _readOffsets(xref);

    final catalog = _object(_referenceIn(xref.source, 'Root'));
    if (!catalog.source.contains('/Type/Catalog')) throw const FormatException('The root object is no catalog');
    final pageTree = _object(_referenceIn(catalog.source, 'Pages'));
    final kids = RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(pageTree.source);
    final count = RegExp(r'/Count\s+(\d+)').firstMatch(pageTree.source);
    if (!pageTree.source.contains('/Type/Pages') || kids == null || count == null) {
      throw const FormatException('The catalog names no page tree');
    }
    final pages = [for (final kid in _reference.allMatches(kids.group(1)!)) _page(int.parse(kid.group(1)!))];
    if (pages.length != int.parse(count.group(1)!)) {
      throw const FormatException('The page tree counts other pages than it names');
    }
    return PdfSummary(pages: pages);
  }

  PdfPage _page(int number) {
    final page = _object(number);
    final mediaBox = _mediaBox.firstMatch(page.source);
    if (!RegExp(r'/Type/Page\b').hasMatch(page.source) || mediaBox == null) {
      throw FormatException('The page tree names object $number, which is no page');
    }
    final content = latin1.decode(_streamOf(_object(_referenceIn(page.source, 'Contents'))));
    final texts = <({String text, double x})>[];
    final images = <({int width, int height})>[];
    var characterMap = const <int, String>{};
    // The current transformation matrix [a, b, c, d, e, f], which takes a point of the current coordinates to the
    // page, and the matrices that each save of the graphics state keeps.
    var matrix = const [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
    final savedMatrices = <List<double>>[];
    for (final operator in _operator.allMatches(content)) {
      if (operator.group(1) case final font?) {
        characterMap = _characterMapOf(_referenceIn(page.source, font));
      } else if (operator.group(3) case final shown?) {
        final position = operator.group(2);
        if (position == null) throw FormatException('A text of page object $number has no position before it');
        // A text object starts at the origin of the current coordinates, and the move goes from there.
        final [x, y] = _numbers(position);
        final glyphs = _hexString.allMatches(shown).map((match) => match.group(1)!).join();
        texts.add((
          text: [
            for (var index = 0; index + 4 <= glyphs.length; index += 4)
              characterMap[int.parse(glyphs.substring(index, index + 4), radix: 16)] ??
                  (throw FormatException('A text of page object $number shows a glyph that its font does not map')),
          ].join(),
          x: x * matrix[0] + y * matrix[2] + matrix[4],
        ));
      } else if (operator.group(4) case final name?) {
        final image = _object(_referenceIn(page.source, name)).source;
        images.add((width: _numberIn(image, 'Width'), height: _numberIn(image, 'Height')));
      } else if (operator.group(5) case final change?) {
        // The change applies before the current matrix: the product of the change and the current matrix.
        final [a, b, c, d, e, f] = _numbers(change);
        final [ca, cb, cc, cd, ce, cf] = matrix;
        matrix = [
          a * ca + b * cc,
          a * cb + b * cd,
          c * ca + d * cc,
          c * cb + d * cd,
          e * ca + f * cc + ce,
          e * cb + f * cd + cf,
        ];
      } else if (operator.group(6) == 'q') {
        savedMatrices.add(matrix);
      } else {
        matrix = savedMatrices.removeLast();
      }
    }
    return PdfPage(
      width: double.parse(mediaBox.group(1)!),
      height: double.parse(mediaBox.group(2)!),
      texts: texts,
      images: images,
    );
  }

  /// The numbers of the operands [source], separated by white space.
  List<double> _numbers(String source) => source.trim().split(RegExp(r'\s+')).map(double.parse).toList();

  /// What each glyph number of the font in object [number] shows, from the character map of the font.
  Map<int, String> _characterMapOf(int number) => _characterMaps.putIfAbsent(number, () {
    final map = latin1.decode(_streamOf(_object(_referenceIn(_object(number).source, 'ToUnicode'))));
    if (map.contains('beginbfrange')) throw const FormatException('The character map has a range, which is not read');
    return {
      for (final mapping in _mapping.allMatches(map))
        int.parse(mapping.group(1)!, radix: 16): String.fromCharCodes([
          for (var index = 0; index + 4 <= mapping.group(2)!.length; index += 4)
            int.parse(mapping.group(2)!.substring(index, index + 4), radix: 16),
        ]),
    };
  });

  /// Reads the offset of each object from the cross-reference stream with the dictionary [xref].
  ///
  /// An entry of the stream has three fields of the byte widths that `/W` names: the type, which is 1 for an object
  /// in use, the offset, and the generation. `/Index` names the first object number and the count of each run of
  /// entries.
  void _readOffsets(({String source, int end}) xref) {
    final widths = RegExp(r'/W\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s*\]').firstMatch(xref.source);
    if (widths == null) throw const FormatException('The cross-reference stream names no field widths');
    final [typeWidth, offsetWidth, generationWidth] = [
      for (var field = 1; field <= 3; field++) int.parse(widths[field]!),
    ];
    final index = RegExp(r'/Index\s*\[([^\]]*)\]').firstMatch(xref.source)?.group(1);
    final runs = index == null
        ? [0, _numberIn(xref.source, 'Size')]
        : [for (final number in RegExp(r'\d+').allMatches(index)) int.parse(number.group(0)!)];
    final entries = _streamOf(xref);
    var position = 0;
    int field(int width) {
      var value = 0;
      for (var byte = 0; byte < width; byte++) {
        value = (value << 8) | entries[position++];
      }
      return value;
    }

    if (entries.length !=
        (typeWidth + offsetWidth + generationWidth) *
            [for (var run = 1; run < runs.length; run += 2) runs[run]].fold(0, (sum, count) => sum + count)) {
      throw const FormatException('The cross-reference stream does not hold the entries that it names');
    }
    for (var run = 0; run + 1 < runs.length; run += 2) {
      for (var number = runs[run]; number < runs[run] + runs[run + 1]; number++) {
        final type = field(typeWidth);
        final offset = field(offsetWidth);
        field(generationWidth);
        if (type == 1) _offsets[number] = offset;
      }
    }
  }

  /// The dictionary of the object with [number], which stands at the offset that the cross-reference stream names.
  ({String source, int end}) _object(int number) {
    final offset = _offsets[number];
    if (offset == null) throw FormatException('The cross-reference stream names no object $number');
    final start = offset < _text.length ? RegExp('$number 0 obj\\b').matchAsPrefix(_text, offset) : null;
    if (start == null) throw FormatException('Object $number is not at the offset of the cross-reference stream');
    return _dictionaryAt(start.end);
  }

  /// The dictionary that starts at or after [offset]: its source with the outer brackets, and the offset after it.
  ({String source, int end}) _dictionaryAt(int offset) {
    final start = _text.indexOf('<<', offset);
    if (start < 0 || _text.substring(offset, start).trim().isNotEmpty) {
      throw FormatException('The object at offset $offset has no dictionary');
    }
    var depth = 0;
    for (var index = start; index < _text.length - 1; index++) {
      final isPair = _text[index + 1] == _text[index];
      if (_text[index] == '<' && isPair) {
        depth++;
        index++;
      } else if (_text[index] == '<') {
        // A hexadecimal string, which can end next to the end of a dictionary.
        index = _text.indexOf('>', index);
        if (index < 0) break;
      } else if (_text[index] == '(') {
        // A literal string, which can hold any bracket. A backslash escapes the character after it.
        while (++index < _text.length && _text[index] != ')') {
          if (_text[index] == r'\') index++;
        }
      } else if (_text[index] == '>' && isPair) {
        depth--;
        index++;
        if (depth == 0) return (source: _text.substring(start, index + 1), end: index + 1);
      }
    }
    throw FormatException('The dictionary at offset $start does not end');
  }

  /// The bytes of the stream of the object with [dictionary], decoded when the stream is compressed.
  Uint8List _streamOf(({String source, int end}) dictionary) {
    final keyword = RegExp(r'\s*stream\r?\n').matchAsPrefix(_text, dictionary.end);
    if (keyword == null) throw FormatException('The object that ends at offset ${dictionary.end} has no stream');
    final length = _numberIn(dictionary.source, 'Length');
    final after = keyword.end + length;
    if (after > _text.length || !_text.startsWith(RegExp(r'\s*endstream'), after)) {
      throw FormatException('The stream at offset ${keyword.end} does not have the length that it names');
    }
    final stream = Uint8List.sublistView(_bytes, keyword.end, after);
    if (!dictionary.source.contains('/Filter/FlateDecode')) return stream;
    try {
      return Uint8List.fromList(zlib.decode(stream));
    } on FormatException {
      throw FormatException('The stream at offset ${keyword.end} does not decode');
    }
  }

  int _referenceIn(String dictionary, String key) => _numberIn(dictionary, key, suffix: ' 0 R');

  int _numberIn(String dictionary, String key, {String suffix = ''}) {
    final match = RegExp('/$key\\s+(\\d+)$suffix\\b').firstMatch(dictionary);
    if (match == null) throw FormatException('A dictionary lacks /$key');
    return int.parse(match.group(1)!);
  }
}
