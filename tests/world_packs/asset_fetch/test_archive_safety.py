"""ARCHIVE_SAFETY_FIXTURES tests: zip-slip, bombs, links, caps — all offline."""

from __future__ import annotations

import io
import zipfile

import pytest

from asset_fetch import archive as archive_mod


def build_zip(entries, *, symlink_names=()):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            zf.writestr(name, data)
        for name in symlink_names:
            info = zipfile.ZipInfo(name)
            # S_IFLNK | 0777 in external_attr high bits.
            info.external_attr = (0o120777 << 16) | 0x0
            zf.writestr(info, "target-of-link")
    return buf.getvalue()


def test_clean_archive_passes_and_extracts(tmp_path):
    data = build_zip([("a.txt", b"hello"), ("sub/b.txt", b"world")])
    report = archive_mod.scan_zip(data)
    assert report.entry_count == 2
    archive_mod.extract_zip_safe(data, tmp_path)
    assert (tmp_path / "a.txt").read_bytes() == b"hello"
    assert (tmp_path / "sub" / "b.txt").read_bytes() == b"world"


def test_not_a_zip_refused():
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(b"definitely not a zip file")
    assert excinfo.value.code == "NOT_A_ZIP"


@pytest.mark.parametrize(
    ("name", "code"),
    [
        ("../escape.txt", "PATH_TRAVERSAL"),
        ("a/../../escape.txt", "PATH_TRAVERSAL"),
        ("/abs/path.txt", "ABSOLUTE_ENTRY_PATH"),
        ("C:/win/path.txt", "ABSOLUTE_ENTRY_PATH"),
        ("~/home.txt", "ABSOLUTE_ENTRY_PATH"),
    ],
)
def test_dangerous_entry_names_refused(name, code):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr(name, b"x")
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(buf.getvalue())
    assert excinfo.value.code == code


@pytest.mark.parametrize(
    ("name", "code"),
    [
        # zipfile rewrites backslashes on Windows, so these are checked
        # at the name-validator level (still enforced for hostile zips).
        ("C:\\win\\path.txt", "BACKSLASH_ENTRY_NAME"),
        ("dir\\file.txt", "BACKSLASH_ENTRY_NAME"),
        ("", "EMPTY_ENTRY_NAME"),
        ("bad\x00name", "NUL_IN_ENTRY_NAME"),
    ],
)
def test_name_validator_backslash_and_empty(name, code):
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod._check_member_name(name)
    assert excinfo.value.code == code


def test_symlink_member_refused():
    data = build_zip([("real.txt", b"x")], symlink_names=("link.txt",))
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(data)
    assert excinfo.value.code == "LINK_ENTRY"


def test_compression_bomb_refused():
    # 10 MB of zeros compresses to a few KB -> huge declared ratio.
    bomb = ("bomb.txt", b"\x00" * (10 * 1024 * 1024))
    data = build_zip([bomb])
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(data)
    assert excinfo.value.code == "COMPRESSION_BOMB"


def test_entry_count_cap():
    entries = [(f"f{i}.txt", b"x") for i in range(16)]
    data = build_zip(entries)
    policy = archive_mod.ArchiveSafetyPolicy(max_entries=8)
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(data, policy)
    assert excinfo.value.code == "TOO_MANY_ENTRIES"


def test_entry_size_cap():
    # Incompressible random data: high declared size, low compression.
    import random

    rng = random.Random(1234)
    payload = rng.randbytes(512 * 1024)  # 512 KiB, ~incompressible
    data = build_zip([("big.bin", payload)])
    assert len(data) > 400_000  # genuinely stored, not deflated away
    policy = archive_mod.ArchiveSafetyPolicy(max_entry_bytes=1024)
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(data, policy)
    assert excinfo.value.code == "ENTRY_TOO_LARGE"


def test_total_size_cap():
    import random

    rng = random.Random(4321)
    payload = rng.randbytes(512 * 1024)  # 512 KiB each, ~incompressible
    data = build_zip([("a.bin", payload), ("b.bin", payload)])
    policy = archive_mod.ArchiveSafetyPolicy(
        max_total_uncompressed_bytes=600 * 1024,
        max_entry_bytes=1024 * 1024,
        max_compression_ratio=10**9,  # disable ratio gate for this test
    )
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(data, policy)
    assert excinfo.value.code == "TOTAL_TOO_LARGE"


def test_encrypted_entry_refused():
    import struct

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("secret.txt", "data")
    raw = bytearray(buf.getvalue())
    # Flip the general-purpose flag to "encrypted" in every central
    # directory header (PK\x01\x02; flag field at offset +8).
    offset = 0
    while True:
        offset = raw.find(b"PK\x01\x02", offset)
        if offset == -1:
            break
        flag = struct.unpack_from("<H", raw, offset + 8)[0]
        struct.pack_into("<H", raw, offset + 8, flag | 0x1)
        offset += 4
    with pytest.raises(archive_mod.ArchiveSafetyError) as excinfo:
        archive_mod.scan_zip(bytes(raw))
    assert excinfo.value.code == "ENCRYPTED_ENTRY"


def test_extraction_rechecks_traversal(tmp_path):
    # scan would pass for one valid entry, then extraction double-checks
    # the resolved destination; craft a name that normalizes outside root.
    data = build_zip([("ok.txt", b"x"), ("../evil.txt", b"y")])
    with pytest.raises(archive_mod.ArchiveSafetyError):
        archive_mod.extract_zip_safe(data, tmp_path)
    assert not (tmp_path.parent / "evil.txt").exists()
    # nothing written after refusal? a.txt may exist only if it preceded
    # the refusal in iteration order; assert no file escaped the root.
    assert list(tmp_path.rglob("evil.txt")) == []
