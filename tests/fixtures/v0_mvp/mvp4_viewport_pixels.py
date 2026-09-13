"""Bounded standard-library PNG decoder for real Godot viewport evidence."""
from __future__ import annotations
import hashlib
from pathlib import Path
import struct
import zlib


def rgba(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if len(data) > 8 * 1024 * 1024 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("INVALID_PNG")
    offset, compressed = 8, bytearray()
    width = height = channels = 0
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        name = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        crc = data[offset + 8 + length:offset + 12 + length]
        if len(payload) != length or len(crc) != 4 or zlib.crc32(name + payload) & 0xffffffff != struct.unpack(">I", crc)[0]:
            raise ValueError("PNG_CRC_MISMATCH")
        if name == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if width != 720 or not 400 <= height <= 480 or depth != 8 or color not in (2, 6) or compression or filtering or interlace:
                raise ValueError("UNSUPPORTED_VIEWPORT_PNG")
            channels = 4 if color == 6 else 3
        elif name == b"IDAT": compressed.extend(payload)
        elif name == b"IEND": break
        offset += length + 12
    if not channels: raise ValueError("PNG_HEADER_REQUIRED")
    stride = width * channels
    expected = height * (stride + 1)
    decoder = zlib.decompressobj()
    decoded = decoder.decompress(bytes(compressed), expected + 1)
    if len(decoded) != expected or not decoder.eof: raise ValueError("PNG_DECOMPRESSED_SIZE_INVALID")
    previous = bytearray(stride)
    result = bytearray()
    def paeth(a: int, b: int, c: int) -> int:
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        return a if pa <= pb and pa <= pc else b if pb <= pc else c
    for y in range(height):
        start = y * (stride + 1)
        filtering = decoded[start]
        row = bytearray(decoded[start + 1:start + 1 + stride])
        if filtering not in range(5): raise ValueError("PNG_FILTER_INVALID")
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            up = previous[x]
            corner = previous[x - channels] if x >= channels else 0
            if filtering == 1: row[x] = (row[x] + left) & 255
            elif filtering == 2: row[x] = (row[x] + up) & 255
            elif filtering == 3: row[x] = (row[x] + (left + up) // 2) & 255
            elif filtering == 4: row[x] = (row[x] + paeth(left, up, corner)) & 255
        if channels == 4: result.extend(row)
        else:
            for x in range(0, stride, 3): result.extend(row[x:x + 3] + b"\xff")
        previous = row
    return width, height, bytes(result)


def terrain_change(before: Path, after: Path) -> dict:
    width, height, first = rgba(before)
    width2, height2, last = rgba(after)
    if (width2, height2) != (width, height): raise ValueError("VIEWPORT_SIZE_DRIFT")
    # HUD occupies the first 120 rows. The accepted fixed camera shows terrain
    # below row 160. Tests separately require stable player/camera transforms.
    start = 160 * width * 4
    count = sum(any(abs(first[i + c] - last[i + c]) > 2 for c in range(3)) for i in range(start, len(first), 4))
    return {"terrain_changed_pixels": count, "minimum_required": 32, "hud_excluded_rows": 160, "before_terrain_sha256": hashlib.sha256(first[start:]).hexdigest(), "after_terrain_sha256": hashlib.sha256(last[start:]).hexdigest(), "passed": count >= 32}
