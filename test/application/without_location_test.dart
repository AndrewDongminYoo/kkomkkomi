// 🎯 Dart imports:
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

// 📦 Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/application/application.dart';

import '../helpers/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `tool/photo_fixtures/make.py` made the fixtures, and its comment says what each one holds.
  final noExif = File('test/fixtures/photo_no_exif.jpg').readAsBytesSync();
  final withGps = gpsPhotoBytes();
  final withGpsMotorola = File('test/fixtures/photo_gps_orientation_6_mm.jpg').readAsBytesSync();
  final truncated = File('test/fixtures/photo_truncated.jpg').readAsBytesSync();

  /// The Exif segment that holds only the orientation 6, written out by hand from the Exif 2.3 layout.
  const orientation6 = [
    0xff, 0xe1, 0x00, 0x22, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // APP1, 34 bytes, "Exif\0\0".
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, 0x00, 0x01, // "MM", 42, IFD0 at 8, one entry.
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00, // Orientation, SHORT, 1, 6.
    0x00, 0x00, 0x00, 0x00, // No next IFD.
  ];

  group('withoutLocation', () {
    test('the fixtures hold the location and the other metadata that the function removes', () {
      for (final photo in [withGps, withGpsMotorola]) {
        for (final text in metadataTexts) {
          expect(holdsText(photo, text), isTrue, reason: text);
        }
      }
    });

    for (final (name, photo) in [('Intel', withGps), ('Motorola', withGpsMotorola)]) {
      test('removes the GPS tags and every other piece of metadata, with an Exif in $name byte order', () {
        final result = withoutLocation(photo);

        for (final text in metadataTexts) {
          expect(holdsText(result, text), isFalse, reason: text);
        }
        // The JFIF header, the new Exif segment, and then the image of the fixture as ImageMagick wrote it, with its
        // ICC profile: nothing else changed.
        final afterJfif = 4 + (noExif[4] << 8 | noExif[5]);
        expect(result, [...noExif.sublist(0, afterJfif), ...orientation6, ...noExif.sublist(afterJfif)]);
      });

      test('keeps the orientation, so the photo shows the same way up, with an Exif in $name byte order', () async {
        final before = await decode(photo);
        final after = await decode(withoutLocation(photo));

        // The pixels of the file are 8 by 6, and the orientation 6 turns them a quarter turn clockwise.
        expect((before.width, before.height), (6, 8));
        expect((after.width, after.height), (6, 8));
        expect(after.pixels, before.pixels);
        expect(PdfJpegInfo(withoutLocation(photo)).orientation, PdfImageOrientation.rightTop);
      });
    }

    test('gives a JPEG without such metadata back unchanged, and it still decodes', () async {
      expect(withoutLocation(noExif), noExif);
      expect((await decode(withoutLocation(noExif))).width, 8);
    });

    test('drops the orientation 0, which a decoder shows unturned before and after', () async {
      final afterJfif = 4 + (noExif[4] << 8 | noExif[5]);
      final exif = exifSegment(
        tiffOf([
          (0x0112, 3, 1, [0, 0]),
        ]),
      );
      final photo = Uint8List.fromList([...noExif.sublist(0, afterJfif), ...exif, ...noExif.sublist(afterJfif)]);

      final before = await decode(photo);
      final after = await decode(withoutLocation(photo));

      expect(withoutLocation(photo), noExif);
      expect((before.width, before.height), (8, 6));
      expect(after.pixels, before.pixels);
    });

    test('gives the same result when it runs again', () {
      final once = withoutLocation(withGps);

      expect(withoutLocation(once), once);
    });

    test('a truncated JPEG: throws a FormatException', () {
      expect(() => withoutLocation(truncated), throwsFormatException);
    });

    test('every cut of the fixture gives a JPEG or a FormatException, and no other object', () {
      final kept = <int>[];
      for (var length = 0; length <= withGps.length; length++) {
        try {
          withoutLocation(Uint8List.sublistView(withGps, 0, length));
          kept.add(length);
        } on FormatException {
          // A cut file is not well formed, which is what the function says.
        }
      }

      // A cut keeps the image only after its end-of-image marker, so the cuts that give a JPEG are the last ones.
      expect(kept, isNotEmpty);
      expect(kept, List.generate(kept.length, (index) => withGps.length - kept.length + 1 + index));
      expect(withoutLocation(Uint8List.sublistView(withGps, 0, kept.first)), withoutLocation(withGps));
    });

    test('every byte of the fixture set to 0x00 or 0xff gives a JPEG or a FormatException, and no other object', () {
      for (var index = 0; index < withGps.length; index++) {
        for (final value in [0x00, 0xff]) {
          final changed = Uint8List.fromList(withGps)..[index] = value;
          try {
            withoutLocation(changed);
          } on FormatException {
            // The change broke the file, which the function says.
          }
        }
      }
    });

    group('the structure of a file, with segments that no decoder reads', () {
      final jfif = segment(0xe0, 'JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00'.codeUnits);
      final quantization = segment(0xdb, [0x00, ...List.filled(64, 1)]);
      final scanHeader = segment(0xda, [0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]);
      const scanData = [0x12, 0x34];

      test('keeps the JFIF header, an ICC profile, the Adobe segment, and the segments of the image', () {
        final icc = segment(0xe2, 'ICC_PROFILE\x00\x01\x01profile'.codeUnits);
        final adobe = segment(0xee, 'Adobe\x00\x64\x00\x00\x00\x00\x01'.codeUnits);
        final restartInterval = segment(0xdd, [0x00, 0x04]);
        final photo = jpegOf([jfif, icc, adobe, quantization, restartInterval, scanHeader, scanData]);

        expect(withoutLocation(photo), photo);
      });

      test('drops every other application segment and every comment', () {
        final multiPicture = segment(0xe2, 'MPF\x00data'.codeUnits);
        // A JFXX thumbnail and segments of other vendors under the markers of the JFIF header and the Adobe segment.
        final thumbnail = segment(0xe0, 'JFXX\x00\x10thumbnail'.codeUnits);
        final otherApp0 = segment(0xe0, 'AVI1\x00data'.codeUnits);
        final otherApp14 = segment(0xee, 'Vendor\x00data'.codeUnits);
        final others = [
          for (final marker in [0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xef, 0xfe])
            segment(marker, 'data'.codeUnits),
        ];

        expect(
          withoutLocation(
            jpegOf([
              jfif,
              thumbnail,
              otherApp0,
              multiPicture,
              otherApp14,
              ...others,
              quantization,
              scanHeader,
              scanData,
            ]),
          ),
          jpegOf([jfif, quantization, scanHeader, scanData]),
        );
      });

      test('keeps the image data with its stuffed bytes and restart markers, and a second scan', () {
        const data = [0x12, 0xff, 0x00, 0x34, 0xff, 0xd0, 0x56, 0xff, 0xd7, 0x78, 0xff];
        final huffman = segment(0xc4, [0x10, ...List.filled(16, 0), 0xff, 0xd9]);
        final photo = jpegOf([jfif, quantization, scanHeader, data, huffman, scanHeader, data]);

        expect(withoutLocation(photo), photo);
      });

      test('keeps a marker without a length, and drops the fill bytes before a marker', () {
        const temporary = [0xff, 0x01];

        expect(
          withoutLocation(
            jpegOf([
              jfif,
              temporary,
              [0xff, 0xff],
              quantization,
              scanHeader,
              scanData,
            ]),
          ),
          jpegOf([jfif, temporary, quantization, scanHeader, scanData]),
        );
      });

      test('writes no Exif segment when the Exif names no orientation', () {
        final exif = exifSegment(
          tiffOf([
            (0x010f, 2, 4, [0x41, 0x42, 0x43, 0x00]),
          ]),
        );

        expect(
          withoutLocation(jpegOf([jfif, exif, quantization, scanHeader, scanData])),
          jpegOf([jfif, quantization, scanHeader, scanData]),
        );
      });

      test('reads the orientation of the first Exif segment only, also after an XMP segment', () {
        final xmp = segment(0xe1, 'http://ns.adobe.com/xap/1.0/\x00<x/>'.codeUnits);
        final first = exifSegment(
          tiffOf([
            (0x0112, 3, 1, [0x00, 0x03]),
          ], bigEndian: true),
        );
        final second = exifSegment(
          tiffOf([
            (0x0112, 3, 1, [0x08, 0x00]),
          ]),
        );

        expect(
          withoutLocation(jpegOf([jfif, xmp, first, second, quantization, scanHeader, scanData])),
          jpegOf([jfif, orientationExif(3), quantization, scanHeader, scanData]),
        );
      });

      test('writes the Exif segment right after the start of the file when the file has no JFIF header', () {
        final exif = exifSegment(
          tiffOf([
            (0x0112, 3, 1, [0x08, 0x00]),
          ]),
        );

        expect(
          withoutLocation(jpegOf([exif, quantization, scanHeader, scanData])),
          jpegOf([orientationExif(8), quantization, scanHeader, scanData]),
        );
      });

      test('drops an application segment too short to name what it holds', () {
        expect(
          withoutLocation(
            jpegOf([
              jfif,
              segment(0xe1, [0x45]),
              segment(0xe2, []),
              quantization,
              scanHeader,
              scanData,
            ]),
          ),
          jpegOf([jfif, quantization, scanHeader, scanData]),
        );
      });

      for (final (name, bytes) in <(String, List<int>)>[
        ('an empty file', []),
        ('a file that starts with no start-of-image marker', [0x89, 0x50, 0x4e, 0x47]),
        ('a file that holds only a start-of-image marker', [0xff, 0xd8]),
        ('a file that ends in fill bytes', [0xff, 0xd8, 0xff, 0xff]),
        ('a file with a byte where a marker must be', [0xff, 0xd8, 0x00, 0xff, 0xd9]),
        ('a file with the marker 0x00 outside the image data', [0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9]),
        ('a file with a second start-of-image marker', [0xff, 0xd8, 0xff, 0xd8, 0xff, 0xd9]),
        ('a file that ends inside a segment length', [0xff, 0xd8, 0xff, 0xdb, 0x00]),
        ('a segment with a length below 2', [0xff, 0xd8, 0xff, 0xdb, 0x00, 0x01, 0xff, 0xd9]),
        ('a segment that runs past the end of the file', [0xff, 0xd8, 0xff, 0xdb, 0x00, 0x10, 0x00]),
        (
          'a file that ends before its image data',
          [
            0xff,
            0xd8,
            ...segment(0xdb, [0x00]),
            0xff,
            0xd9,
          ],
        ),
      ]) {
        test('$name: throws a FormatException', () {
          expect(() => withoutLocation(Uint8List.fromList(bytes)), throwsFormatException);
        });
      }

      final orientation = (0x0112, 3, 1, [0x06, 0x00]);
      for (final (name, tiff) in <(String, List<int>)>[
        ('a TIFF header that ends early', [0x49, 0x49, 0x2a, 0x00]),
        ('no byte order', [0x58, 0x58, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00]),
        ('no TIFF header', [0x49, 0x49, 0x2b, 0x00, 0x08, 0x00, 0x00, 0x00]),
        ('a first directory outside the segment', [0x49, 0x49, 0x2a, 0x00, 0x40, 0x00, 0x00, 0x00]),
        ('a first directory that runs past the segment', tiffOf([orientation]).sublist(0, 25)),
      ]) {
        test('an Exif segment with $name: throws a FormatException, because the photo could turn', () {
          final photo = jpegOf([jfif, exifSegment(tiff), quantization, scanHeader, scanData]);

          expect(() => withoutLocation(photo), throwsFormatException);
        });
      }

      test('reads an orientation that the Exif gives as a 32-bit number', () {
        final exif = exifSegment(
          tiffOf([
            (0x0112, 4, 1, [0x06, 0x00, 0x00, 0x00]),
          ]),
        );

        expect(
          withoutLocation(jpegOf([jfif, exif, quantization, scanHeader, scanData])),
          jpegOf([jfif, orientationExif(6), quantization, scanHeader, scanData]),
        );
      });

      for (final (name, entry) in <(String, (int, int, int, List<int>))>[
        ('the orientation 0, which androidx ExifInterface writes when the camera wrote none', (0x0112, 3, 1, [0, 0])),
        ('the orientation 9', (0x0112, 3, 1, [0x09, 0x00])),
        ('an orientation of a type that is no number', (0x0112, 2, 1, [0x06, 0x00])),
        ('two orientations in one field', (0x0112, 3, 2, [0x06, 0x00, 0x06, 0x00])),
      ]) {
        test('an Exif segment with $name: writes no orientation, because it names no turn', () {
          final exif = exifSegment(tiffOf([entry]));

          expect(
            withoutLocation(jpegOf([jfif, exif, quantization, scanHeader, scanData])),
            jpegOf([jfif, quantization, scanHeader, scanData]),
          );
        });
      }
    });
  });
}

/// A JPEG file of [parts] between its start-of-image and its end-of-image markers.
Uint8List jpegOf(List<List<int>> parts) => Uint8List.fromList([
  0xff,
  0xd8,
  for (final part in parts) ...part,
  0xff,
  0xd9,
]);

/// A segment with [marker] and [payload], and the length that the segment gives.
List<int> segment(int marker, List<int> payload) => [
  0xff,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 0xff,
  ...payload,
];

/// An Exif segment with the TIFF data [tiff].
List<int> exifSegment(List<int> tiff) => segment(0xe1, [...'Exif\x00\x00'.codeUnits, ...tiff]);

/// The TIFF data of an Exif segment whose first directory holds [entries] of tag, type, count, and value.
///
/// A value is at most 4 bytes and given in the byte order of the data.
List<int> tiffOf(List<(int, int, int, List<int>)> entries, {bool bigEndian = false}) {
  final data = ByteData(8 + 2 + entries.length * 12 + 4);
  final endian = bigEndian ? Endian.big : Endian.little;
  data
    ..setUint16(0, bigEndian ? 0x4d4d : 0x4949)
    ..setUint16(2, 42, endian)
    ..setUint32(4, 8, endian)
    ..setUint16(8, entries.length, endian);
  for (final (index, (tag, type, count, value)) in entries.indexed) {
    final entry = 10 + index * 12;
    data
      ..setUint16(entry, tag, endian)
      ..setUint16(entry + 2, type, endian)
      ..setUint32(entry + 4, count, endian);
    for (final (offset, byte) in value.indexed) {
      data.setUint8(entry + 8 + offset, byte);
    }
  }
  return data.buffer.asUint8List();
}

/// The Exif segment that the function writes for [orientation].
List<int> orientationExif(int orientation) => exifSegment(
  tiffOf([
    (0x0112, 3, 1, [0x00, orientation]),
  ], bigEndian: true),
);

Future<({int width, int height, Uint8List pixels})> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  return (width: image.width, height: image.height, pixels: (await image.toByteData())!.buffer.asUint8List());
}
