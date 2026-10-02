import 'dart:typed_data';

/// Returns the JPEG file [jpeg] without the metadata that can hold the place where the photo was taken.
///
/// The camera app can write the location into a photo, and `image_picker_android` copies it into the smaller file
/// that the app keeps (issue 20). So the function keeps only the segments that show the picture: the image data, the
/// JFIF header (APP0 with `JFIF`), an ICC color profile (APP2 with `ICC_PROFILE`), and the Adobe color transform
/// (APP14 with `Adobe`). It drops every other application segment, which includes Exif and XMP (APP1), IPTC (APP13),
/// and a JFXX thumbnail (APP0), every comment, and whatever follows the end of the image, such as the second picture
/// of a multi-picture file.
///
/// The picker leaves the rotation of a photo in the Exif orientation tag and does not turn the pixels, on Android
/// (`ImageResizer` and `ExifDataCopier` of `image_picker_android` 0.8.13+23) and on iOS (`FLTImagePickerImageUtil`
/// and `FLTImagePickerPhotoAssetUtil` of `image_picker_ios` 0.8.13+9). So the function writes the orientation of the
/// first Exif segment into a new Exif segment that holds nothing else, after the JFIF header, and the photo shows the
/// same way up. The result is never longer than [jpeg], and a file without those segments and without fill bytes
/// before a marker comes back unchanged.
///
/// Throws a [FormatException], and no other object, when [jpeg] is not a well-formed JPEG file: when it does not
/// start with a start-of-image marker, when a segment runs past the end of the file, when the file ends before its
/// end-of-image marker, or when the TIFF header or the first directory of its first Exif segment cannot be read. An
/// orientation outside 1 to 8 names no turn, so the result holds no orientation then.
Uint8List withoutLocation(Uint8List jpeg) => _LocationStripper(jpeg).strip();

/// The second byte of each marker that the stripper treats by name.
const _app0 = 0xe0;
const _app1 = 0xe1;
const _app2 = 0xe2;
const _app14 = 0xee;
const _comment = 0xfe;
const _startOfImage = 0xd8;
const _endOfImage = 0xd9;
const _startOfScan = 0xda;

/// The identifier at the start of an Exif segment, `Exif` and two zero bytes.
const _exifIdentifier = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];

/// The identifier at the start of a JFIF header, `JFIF` and a zero byte.
const _jfifIdentifier = [0x4a, 0x46, 0x49, 0x46, 0x00];

/// The identifier at the start of the Adobe segment, `Adobe`.
const _adobeIdentifier = [0x41, 0x64, 0x6f, 0x62, 0x65];

/// The identifier at the start of an ICC profile segment, `ICC_PROFILE` and a zero byte.
const _iccIdentifier = [0x49, 0x43, 0x43, 0x5f, 0x50, 0x52, 0x4f, 0x46, 0x49, 0x4c, 0x45, 0x00];

/// The TIFF tag of the orientation.
const _orientationTag = 0x0112;

/// The TIFF field type of an unsigned 16-bit number.
const _short = 3;

/// The TIFF field type of an unsigned 32-bit number.
const _long = 4;

final class _LocationStripper {
  new(this._bytes);

  final Uint8List _bytes;

  /// The parts of the file that the result keeps, in their order.
  final _kept = <Uint8List>[];

  /// Whether the stripper read the first Exif segment.
  bool _sawExif = false;

  /// The orientation of the first Exif segment, or null when it names none.
  int? _orientation;

  Uint8List strip() {
    if (_bytes.length < 2 || _bytes[0] != 0xff || _bytes[1] != _startOfImage) {
      throw const FormatException('The file does not start with a JPEG start-of-image marker');
    }
    var sawScan = false;
    var position = 2;
    while (true) {
      position = _markerAt(position);
      final marker = _bytes[position + 1];
      if (marker == _endOfImage) break;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        // A marker without a length: TEM or a restart marker.
        _kept.add(_part(position, position + 2));
        position += 2;
        continue;
      }
      if (marker == 0x00 || marker == _startOfImage) {
        throw FormatException('The file holds the marker 0x${marker.toRadixString(16)} at byte $position');
      }
      final end = _segmentEnd(position);
      if (marker == _app1 && !_sawExif && _starts(position + 4, end, _exifIdentifier)) {
        _sawExif = true;
        _orientation = _orientationIn(position + 4 + _exifIdentifier.length, end);
      } else if (_keeps(marker, position, end)) {
        _kept.add(_part(position, end));
      }
      position = end;
      if (marker == _startOfScan) {
        final dataEnd = _scanEnd(position);
        _kept.add(_part(position, dataEnd));
        position = dataEnd;
        sawScan = true;
      }
    }
    if (!sawScan) throw const FormatException('The file ends before its image data');

    final result = BytesBuilder(copy: false)..add(_part(0, 2));
    var index = 0;
    if (_kept.first[1] == _app0) result.add(_kept[index++]);
    if (_orientation case final orientation?) result.add(_exifWith(orientation));
    for (; index < _kept.length; index++) {
      result.add(_kept[index]);
    }
    result.add(const [0xff, _endOfImage]);
    return result.takeBytes();
  }

  /// The position of the marker at [position], after the fill bytes that can come before it.
  int _markerAt(int position) {
    if (position >= _bytes.length || _bytes[position] != 0xff) {
      throw FormatException('The file holds no marker at byte $position', null, position);
    }
    var marker = position;
    while (marker + 1 < _bytes.length && _bytes[marker + 1] == 0xff) {
      marker++;
    }
    if (marker + 1 >= _bytes.length) throw const FormatException('The file ends before its end-of-image marker');
    return marker;
  }

  /// The end of the segment whose marker is at [position], from the length that the segment gives.
  int _segmentEnd(int position) {
    if (position + 4 > _bytes.length) throw const FormatException('The file ends inside a segment length');
    final length = _bytes[position + 2] << 8 | _bytes[position + 3];
    final end = position + 2 + length;
    if (length < 2 || end > _bytes.length) {
      throw FormatException('The segment at byte $position runs past the end of the file', null, position);
    }
    return end;
  }

  /// The end of the image data that starts at [position], which is the position of the next marker.
  ///
  /// Inside the image data, `0xff` is followed by a zero byte or a restart marker, and the fill bytes `0xff` can come
  /// before a marker.
  int _scanEnd(int position) {
    var index = position;
    while (index + 1 < _bytes.length) {
      if (_bytes[index] != 0xff) {
        index++;
        continue;
      }
      final next = _bytes[index + 1];
      if (next == 0xff) {
        index++;
      } else if (next == 0x00 || (next >= 0xd0 && next <= 0xd7)) {
        index += 2;
      } else {
        return index;
      }
    }
    throw const FormatException('The file ends inside its image data');
  }

  /// Whether the result keeps the segment with [marker] from [start] to [end].
  bool _keeps(int marker, int start, int end) => switch (marker) {
    // Each kept application segment must name what it holds, because a vendor can put any payload under the same
    // marker, such as the thumbnail of a JFXX segment.
    _app0 => _starts(start + 4, end, _jfifIdentifier),
    _app2 => _starts(start + 4, end, _iccIdentifier),
    _app14 => _starts(start + 4, end, _adobeIdentifier),
    _comment => false,
    _ => marker < _app0 || marker > 0xef,
  };

  /// Whether the bytes from [start] to [end] start with [prefix].
  bool _starts(int start, int end, List<int> prefix) {
    if (end - start < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (_bytes[start + index] != prefix[index]) return false;
    }
    return true;
  }

  /// The orientation in the TIFF data from [start] to [end] of an Exif segment, or null when it names none.
  ///
  /// Only the first directory (IFD0) holds the orientation of the picture.
  int? _orientationIn(int start, int end) {
    final tiff = ByteData.sublistView(_bytes, start, end);
    if (tiff.lengthInBytes < 8) throw const FormatException('The Exif segment ends inside its TIFF header');
    final Endian endian;
    if (tiff.getUint16(0) == 0x4949) {
      endian = Endian.little;
    } else if (tiff.getUint16(0) == 0x4d4d) {
      endian = Endian.big;
    } else {
      throw const FormatException('The Exif segment names no byte order');
    }
    if (tiff.getUint16(2, endian) != 42) throw const FormatException('The Exif segment holds no TIFF header');
    final directory = tiff.getUint32(4, endian);
    if (directory + 2 > tiff.lengthInBytes) {
      throw const FormatException('The first Exif directory is outside its segment');
    }
    final count = tiff.getUint16(directory, endian);
    // The directory ends with the offset of the next directory, which is 4 bytes long.
    if (directory + 2 + count * 12 + 4 > tiff.lengthInBytes) {
      throw const FormatException('The first Exif directory runs past the end of its segment');
    }
    for (var index = 0; index < count; index++) {
      final entry = directory + 2 + index * 12;
      if (tiff.getUint16(entry, endian) != _orientationTag) continue;
      if (tiff.getUint32(entry + 4, endian) != 1) return null;
      final value = switch (tiff.getUint16(entry + 2, endian)) {
        _short => tiff.getUint16(entry + 8, endian),
        _long => tiff.getUint32(entry + 8, endian),
        _ => 0,
      };
      // A value outside 1 to 8 names no turn, and a decoder shows the pixels as they are. `ExifInterface` of androidx
      // writes 0 when the camera wrote no orientation, and `ExifDataCopier` of the picker copies it.
      return value >= 1 && value <= 8 ? value : null;
    }
    return null;
  }

  Uint8List _part(int start, int end) => Uint8List.sublistView(_bytes, start, end);

  /// An Exif segment in big-endian byte order whose one directory holds only [orientation].
  static Uint8List _exifWith(int orientation) => Uint8List.fromList([
    0xff, _app1, 0x00, 0x22, // The marker and the length of the segment: 34 bytes.
    ..._exifIdentifier,
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, // The TIFF header: big endian, 42, the directory at 8.
    0x00, 0x01, // One entry.
    0x01, 0x12, 0x00, _short, 0x00, 0x00, 0x00, 0x01, 0x00, orientation, 0x00, 0x00, // The orientation.
    0x00, 0x00, 0x00, 0x00, // No next directory.
  ]);
}
