"""Packs PNG images into one Windows icon file.

Usage: python3 ico.py <output.ico> <image.png>...

A 256 pixel image goes in as PNG. A smaller image goes in as a 32-bit bitmap,
because a resource compiler can refuse a PNG entry below that size.
The script reads the 8-bit RGB and RGBA images that a Chromium screenshot writes.
"""

# cspell:ignore BBBBHHII IIBBBBB

import struct
import sys
import zlib


def read_png(data):
    """Return the width, the height, and the rows of RGBA bytes, top row first."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG file"
    position = 8
    compressed = b""
    header = None
    while position < len(data):
        length, kind = struct.unpack_from(">I4s", data, position)
        body = data[position + 8 : position + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed += body
        position += 12 + length
    width, height, depth, color, _, _, interlace = header
    assert depth == 8 and color in (2, 6) and interlace == 0, "unsupported PNG variant"
    channels = 4 if color == 6 else 3
    stride = width * channels
    raw = zlib.decompress(compressed)
    rows = []
    previous = bytearray(stride)
    position = 0
    for _ in range(height):
        kind = raw[position]
        line = bytearray(raw[position + 1 : position + 1 + stride])
        position += 1 + stride
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            corner = previous[i - channels] if i >= channels else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                estimate = left + up - corner
                nearest = min((abs(estimate - left), 0, left), (abs(estimate - up), 1, up), (abs(estimate - corner), 2, corner))
                line[i] = (line[i] + nearest[2]) & 255
        previous = line
        if channels == 3:
            rgba = bytearray()
            for i in range(0, stride, 3):
                rgba += line[i : i + 3] + b"\xff"
            rows.append(rgba)
        else:
            rows.append(line)
    return width, height, rows


def bitmap_entry(width, height, rows):
    """An icon bitmap: a header, BGRA rows from the bottom row up, and an empty 1-bit mask."""
    pixels = bytearray()
    for row in reversed(rows):
        for i in range(0, width * 4, 4):
            red, green, blue, alpha = row[i : i + 4]
            pixels += bytes((blue, green, red, alpha))
    mask = bytes(((width + 31) // 32) * 4) * height
    header = struct.pack("<IiiHHIIiiII", 40, width, height * 2, 1, 32, 0, len(pixels) + len(mask), 0, 0, 0, 0)
    return header + bytes(pixels) + mask


def main(output, sources):
    entries = []
    for source in sources:
        with open(source, "rb") as file:
            data = file.read()
        width, height, rows = read_png(data)
        assert width == height and width <= 256, f"{source}: an icon image is square and at most 256 pixels"
        entries.append((width, data if width == 256 else bitmap_entry(width, height, rows)))
    directory = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    bodies = b""
    for size, body in entries:
        directory += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(body), offset)
        offset += len(body)
        bodies += body
    with open(output, "wb") as file:
        file.write(directory + bodies)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
