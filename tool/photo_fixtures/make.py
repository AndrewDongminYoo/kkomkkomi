# cspell:words Cehi, Hzre, Tczkc, magick
"""Makes the JPEG fixtures of the location tests (issue 20) in test/fixtures/.

Usage: python3 tool/photo_fixtures/make.py

The script needs ImageMagick (`magick`) and runs on macOS, because it embeds the
sRGB color profile of macOS. It writes these files:

- photo_no_exif.jpg: 8 by 6 pixels, a JFIF header, an ICC color profile, and no
  other metadata.
- photo_gps_orientation_6.jpg: the same image with an Exif segment in Intel byte
  order (II) that holds the orientation 6 and GPS tags, an XMP segment with a
  location, an IPTC segment, a comment, and a second Exif segment with GPS tags
  after the end of the image.
- photo_gps_orientation_6_mm.jpg: the same, with the Exif in Motorola byte
  order (MM).
- photo_truncated.jpg: photo_gps_orientation_6.jpg cut inside its image data.

Each piece of metadata holds a text that starts with KKOMKKOMI-, so a test can
look for that text in the bytes without a parser of its own.
"""

# cspell:ignore IIII sRGB xmpmeta xpacket xmlns

import pathlib
import struct
import subprocess
import tempfile

FIXTURES = pathlib.Path(__file__).resolve().parents[2] / "test" / "fixtures"
ICC_PROFILE = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"

ASCII, SHORT, LONG, RATIONAL, BYTE, UNDEFINED = 2, 3, 4, 5, 1, 7


def segment(marker, payload):
    """Return a JPEG segment with its marker and its length."""
    return bytes([0xFF, marker]) + struct.pack(">H", len(payload) + 2) + payload


def ifd(entries, offset, order):
    """Return a TIFF image file directory that starts at offset, followed by the values that do not fit in an entry."""
    values_offset = offset + 2 + 12 * len(entries) + 4
    table = struct.pack(order + "H", len(entries))
    values = b""
    for tag, kind, count, value in entries:
        if len(value) <= 4:
            field = value.ljust(4, b"\0")
        else:
            field = struct.pack(order + "I", values_offset + len(values))
            values += value + (b"\0" if len(value) % 2 else b"")
        table += struct.pack(order + "HHI", tag, kind, count) + field
    return table + struct.pack(order + "I", 0) + values


def rationals(order, *pairs):
    return b"".join(struct.pack(order + "II", numerator, denominator) for numerator, denominator in pairs)


def exif(order):
    """Return the payload of an Exif segment with a camera model, the orientation 6, and a GPS directory."""
    mark = b"II" if order == "<" else b"MM"
    gps = [
        (0x0000, BYTE, 4, bytes([2, 3, 0, 0])),
        (0x0001, ASCII, 2, b"N\0"),
        (0x0002, RATIONAL, 3, rationals(order, (37, 1), (33, 1), (1234, 100))),
        (0x0003, ASCII, 2, b"E\0"),
        (0x0004, RATIONAL, 3, rationals(order, (126, 1), (58, 1), (5678, 100))),
        (0x001C, UNDEFINED, 30, b"ASCII\0\0\0KKOMKKOMI-GPS-AREA\0\0\0\0"),
    ]
    model = b"KKOMKKOMI-CAMERA-MODEL\0"

    def first(gps_offset):
        return [
            (0x0110, ASCII, len(model), model),
            (0x0112, SHORT, 1, struct.pack(order + "H", 6)),
            (0x8825, LONG, 1, struct.pack(order + "I", gps_offset)),
        ]

    size = len(ifd(first(0), 8, order))
    tiff = mark + struct.pack(order + "HI", 42, 8) + ifd(first(8 + size), 8, order) + ifd(gps, 8 + size, order)
    return b"Exif\0\0" + tiff


def xmp():
    packet = (
        '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description xmlns:exif="http://ns.adobe.com/exif/1.0/" exif:GPSLatitude="37,33.2057N"'
        ' exif:GPSLongitude="126,58.9463E" exif:UserComment="KKOMKKOMI-XMP-LOCATION"/>'
        '</rdf:RDF></x:xmpmeta><?xpacket end="w"?>'
    )
    return b"http://ns.adobe.com/xap/1.0/\0" + packet.encode()


def iptc():
    city = b"KKOMKKOMI-IPTC-CITY"
    record = b"\x1c\x02\x5a" + struct.pack(">H", len(city)) + city
    block = b"8BIM" + struct.pack(">H", 0x0404) + b"\0\0" + struct.pack(">I", len(record)) + record
    return b"Photoshop 3.0\0" + block + (b"\0" if len(record) % 2 else b"")


def main():
    with tempfile.TemporaryDirectory() as directory:
        base_path = pathlib.Path(directory) / "base.jpg"
        subprocess.run(
            [
                "magick",
                "-size",
                "8x6",
                "xc:#d04030",
                "-fill",
                "#3050d0",
                "-draw",
                "rectangle 0,0 3,2",
                "-strip",
                "-profile",
                ICC_PROFILE,
                "-quality",
                "90",
                str(base_path),
            ],
            check=True,
        )
        base = base_path.read_bytes()

    assert base[:4] == b"\xff\xd8\xff\xe0", "the base image does not start with a JFIF header"
    after_header = 4 + struct.unpack(">H", base[4:6])[0]
    assert base[-2:] == b"\xff\xd9", "the base image does not end with an end-of-image marker"

    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / "photo_no_exif.jpg").write_bytes(base)

    for order, name in (("<", "photo_gps_orientation_6.jpg"), (">", "photo_gps_orientation_6_mm.jpg")):
        metadata = (
            segment(0xE1, exif(order))
            + segment(0xE1, xmp())
            + segment(0xED, iptc())
            + segment(0xFE, b"KKOMKKOMI-COMMENT")
        )
        trailer = b"\xff\xd8" + segment(0xE1, exif(order)) + b"\xff\xd9"
        photo = base[:after_header] + metadata + base[after_header:] + trailer
        (FIXTURES / name).write_bytes(photo)
        if order == "<":
            end_of_image = len(photo) - len(trailer) - 2
            (FIXTURES / "photo_truncated.jpg").write_bytes(photo[: end_of_image - 4])


if __name__ == "__main__":
    main()
