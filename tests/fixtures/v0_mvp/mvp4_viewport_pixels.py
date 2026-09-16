"""Bounded standard-library PNG decoder + terrain-only comparison for MVP4 evidence.

Review 4001519528: the previous fixed "everything below row 160 is terrain"
cutoff was a false-positive risk because the real HUD (label at y=18, font
size 19, 8+ status lines) extends below row 160, so HUD-only changes could
satisfy the terrain gate.  Captures are now produced with the complete UI
hidden (terrain-only by construction) and the comparison additionally excludes
only the UI region derived from the live UI tree at capture time.  No guessed
row constant participates in the accept decision anymore; the legacy row-160
criterion is retained ONLY inside the explicit HUD-only falsification control.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import random
import struct
import zlib

MINIMUM_TERRAIN_PIXELS = 32


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


def normalize_region(region: dict, width: int, height: int) -> tuple[int, int, int, int]:
    """Clamp a derived UI region {x,y,w,h} to integer image pixels."""
    if not isinstance(region, dict) or set(region) != {"x", "y", "w", "h"}:
        raise ValueError("UI_REGION_MALFORMED")
    x, y = max(0, int(round(float(region["x"])))), max(0, int(round(float(region["y"]))))
    w, h = int(round(float(region["w"]))), int(round(float(region["h"])))
    if w <= 0 or h <= 0 or x >= width or y >= height: raise ValueError("UI_REGION_INVALID")
    return x, y, min(w, width - x), min(h, height - y)


def union_region(a: dict, b: dict, width: int, height: int) -> tuple[int, int, int, int]:
    """Union of two derived UI regions (HUD text length changes between phases)."""
    ax, ay, aw, ah = normalize_region(a, width, height)
    bx, by, bw, bh = normalize_region(b, width, height)
    x, y = min(ax, bx), min(ay, by)
    return x, y, max(ax + aw, bx + bw) - x, max(ay + ah, by + bh) - y


def _changed(first: bytes, last: bytes, width: int, height: int, exclude: tuple[int, int, int, int] | None) -> tuple[int, bytes, bytes]:
    """Count per-pixel differences outside `exclude`.  Returns the count and
    the concatenated compared RGBA bytes of both images for hashing."""
    ex, ey, ew, eh = exclude if exclude else (-1, -1, -1, -1)
    compared_first, compared_last = bytearray(), bytearray()
    count = 0
    for y in range(height):
        row_start = y * width * 4
        in_hud_rows = ey <= y < ey + eh
        for x in range(width):
            if in_hud_rows and ex <= x < ex + ew: continue
            i = row_start + x * 4
            if any(abs(first[i + c] - last[i + c]) > 2 for c in range(3)): count += 1
            compared_first.extend(first[i:i + 4])
            compared_last.extend(last[i:i + 4])
    return count, bytes(compared_first), bytes(compared_last)


def write_rgba_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    """Bounded standard-library RGBA encoder (filter 0) for falsification images."""
    if len(pixels) != width * height * 4: raise ValueError("RGBA_SIZE_INVALID")
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * width * 4:(y + 1) * width * 4])
    def chunk(name: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + name + payload + struct.pack(">I", zlib.crc32(name + payload) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def terrain_change_rgba(width: int, height: int, first: bytes, last: bytes, exclude: tuple[int, int, int, int] | None) -> dict:
    count, compared_first, compared_last = _changed(first, last, width, height, exclude)
    return {
        "terrain_changed_pixels": count,
        "minimum_required": MINIMUM_TERRAIN_PIXELS,
        "ui_excluded_region": list(exclude) if exclude else None,
        "before_terrain_sha256": hashlib.sha256(compared_first).hexdigest(),
        "after_terrain_sha256": hashlib.sha256(compared_last).hexdigest(),
        "passed": count >= MINIMUM_TERRAIN_PIXELS,
    }


def terrain_change(before: Path, after: Path, ui_region: dict | None = None) -> dict:
    """Compare two viewport captures as terrain-only evidence.

    `ui_region` is the complete UI region DERIVED from the live UI tree and
    recorded in the capture evidence (never a guessed constant); those pixels
    are excluded from the comparison as defense in depth on top of the
    construction-level guarantee that the whole UI was hidden for both frames.
    """
    width, height, first = rgba(before)
    width2, height2, last = rgba(after)
    if (width2, height2) != (width, height): raise ValueError("VIEWPORT_SIZE_DRIFT")
    exclude = normalize_region(ui_region, width, height) if ui_region is not None else None
    return terrain_change_rgba(width, height, first, last, exclude)


def legacy_row160_rgba(width: int, height: int, first: bytes, last: bytes) -> dict:
    count = sum(any(abs(first[i + c] - last[i + c]) > 2 for c in range(3)) for i in range(160 * width * 4, len(first), 4))
    return {"legacy_row160_changed_pixels": count, "legacy_row160_would_pass": count >= MINIMUM_TERRAIN_PIXELS}


def legacy_row160_false_positive(before: Path, after: Path) -> dict:
    """REJECTED legacy criterion, kept ONLY for the HUD-only falsification.

    It counts every pixel below row 160 as terrain.  The falsification control
    proves that HUD-only differences (identical terrain) can satisfy it, which
    is exactly review finding 4001519528.  It must never gate acceptance.
    """
    width, height, first = rgba(before)
    width2, height2, last = rgba(after)
    if (width2, height2) != (width, height): raise ValueError("VIEWPORT_SIZE_DRIFT")
    return legacy_row160_rgba(width, height, first, last)


def hud_only_pair(source: Path, region: tuple[int, int, int, int], seed: int) -> tuple[bytes, bytes]:
    """Synthesize a HUD-only-difference image pair from REAL captured pixels.

    Both outputs share the source capture's terrain bit-for-bit; their only
    differences are pseudo-glyph blocks painted strictly inside the derived UI
    region (the bottom band, emulating the changing MVP4 status line that the
    real HUD renders below row 160).
    """
    width, height, base = rgba(source)
    x, y, w, h = region
    band_top = y + (h * 3) // 5
    if band_top < 160:
        raise ValueError("HUD_REGION_DOES_NOT_EXTEND_BELOW_ROW160")
    left, right = x + w // 8, x + w - w // 8
    band_height = min(y + h - band_top, 56)
    images = []
    for variant in range(2):
        rng = random.Random(seed + variant)
        image = bytearray(base)
        for gy in range(band_top, band_top + band_height):
            pen = 235 if rng.random() < 0.5 else 24
            for gx in range(left, right):
                if rng.random() < 0.42:
                    pen = 235 if pen == 24 else 24
                if rng.random() < 0.5:
                    i = (gy * width + gx) * 4
                    image[i:i + 3] = bytes((pen, pen, pen))
        images.append(bytes(image))
    return images[0], images[1]
