"""ARCHIVE_SAFETY_FIXTURES: safe archive inspection for WP-ASSET1.

Fail-closed validation of zip archives (the format WP-ASSET1 consumes
from the raw cache) BEFORE any extraction happens:

- entry names must be relative, normalized, and stay inside the
  extraction root (no ``..`` traversal, no absolute paths, no drive
  letters, no backslash separators);
- no encrypted entries;
- per-entry declared size cap, total declared size cap and entry
  count cap (zip-bomb protection);
- declared compression ratio cap (highly compressible bombs);
- symlink/hardlink style members are refused (zip: entries whose name
  ends in a link marker; tar path is future work).

Extraction itself is provided as a guarded operation that re-checks
every entry and writes only regular files under the target root.
"""

from __future__ import annotations

import posixpath
import zipfile
from dataclasses import dataclass, field
from io import BytesIO
from pathlib import PurePosixPath, PureWindowsPath
from typing import List

DEFAULT_MAX_ENTRIES = 512
DEFAULT_MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
DEFAULT_MAX_ENTRY_BYTES = 64 * 1024 * 1024
DEFAULT_MAX_COMPRESSION_RATIO = 100


class ArchiveSafetyError(RuntimeError):
    """Typed archive-safety refusal."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


@dataclass(frozen=True)
class ArchiveSafetyPolicy:
    max_entries: int = DEFAULT_MAX_ENTRIES
    max_total_uncompressed_bytes: int = DEFAULT_MAX_TOTAL_UNCOMPRESSED_BYTES
    max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES
    max_compression_ratio: int = DEFAULT_MAX_COMPRESSION_RATIO
    # Case-insensitive extraction targets (Windows and macOS default FS)
    # must never receive two entries whose normalized names differ only
    # by case: refuse before extraction instead of silently overwriting.
    case_insensitive_targets: bool = True


@dataclass(frozen=True)
class ArchiveScanReport:
    entry_count: int
    total_uncompressed_bytes: int
    entries: List[str] = field(default_factory=list)


def _check_member_name(name: str) -> str:
    if not name:
        raise ArchiveSafetyError("EMPTY_ENTRY_NAME", "archive contains an empty entry name")
    if "\\" in name:
        raise ArchiveSafetyError(
            "BACKSLASH_ENTRY_NAME", f"entry name uses backslash separators: {name!r}"
        )
    if name.startswith("/") or name.startswith("~"):
        raise ArchiveSafetyError("ABSOLUTE_ENTRY_PATH", f"absolute entry path: {name!r}")
    # Windows drive / reserved forms (zip-slip on Windows extraction).
    if PureWindowsPath(name).is_absolute():
        raise ArchiveSafetyError("ABSOLUTE_ENTRY_PATH", f"windows-absolute entry path: {name!r}")
    normalized = posixpath.normpath(name)
    if normalized.startswith("..") or normalized == ".":
        raise ArchiveSafetyError("PATH_TRAVERSAL", f"entry escapes root: {name!r}")
    if any(part == ".." for part in PurePosixPath(normalized).parts):
        raise ArchiveSafetyError("PATH_TRAVERSAL", f"entry escapes root: {name!r}")
    if "\x00" in name:
        raise ArchiveSafetyError("NUL_IN_ENTRY_NAME", "entry name contains NUL")
    return normalized


_S_IFMT = 0o170000
_S_IFREG = 0o100000
_S_IFLNK = 0o120000


def _require_regular_mode(mode: int, name: str) -> None:
    """Refuse every non-regular Unix file type encoded in mode bits.

    FIFOs, sockets, character devices, block devices, symlinks and any
    other non-regular mode encoded in ``external_attr`` (zip) or
    ``tarinfo.mode`` (tar) are rejected before extraction.
    """
    file_type = mode & _S_IFMT
    if file_type == _S_IFLNK:
        raise ArchiveSafetyError("LINK_ENTRY", f"symlink member refused: {name!r}")
    if file_type and file_type != _S_IFREG:
        kinds = {
            0o010000: "FIFO",
            0o140000: "socket",
            0o020000: "character device",
            0o060000: "block device",
        }
        kind = kinds.get(file_type, f"mode 0{file_type:o}")
        raise ArchiveSafetyError(
            "NON_REGULAR_ENTRY", f"{kind} member refused: {name!r}"
        )


class _SeenNames:
    """Duplicate-detection across exact, normalized and case-folded names."""

    def __init__(self, *, case_insensitive: bool) -> None:
        self.case_insensitive = case_insensitive
        self.exact: set = set()
        self.folded: set = set()

    def add(self, normalized: str, original: str) -> None:
        if normalized in self.exact:
            raise ArchiveSafetyError(
                "DUPLICATE_ENTRY_PATH",
                f"duplicate normalized entry path: {original!r} -> {normalized!r}",
            )
        if self.case_insensitive:
            folded = normalized.casefold()
            if folded in self.folded:
                raise ArchiveSafetyError(
                    "CASE_INSENSITIVE_COLLISION",
                    f"entries collide on a case-insensitive target: "
                    f"{original!r} vs earlier entry normalizing to {normalized!r}",
                )
            self.folded.add(folded)
        self.exact.add(normalized)


def scan_zip(data: bytes, policy: ArchiveSafetyPolicy = ArchiveSafetyPolicy()) -> ArchiveScanReport:
    """Validate every zip entry BEFORE extraction. Typed refusals only."""
    try:
        archive = zipfile.ZipFile(BytesIO(data))
    except (zipfile.BadZipFile, ValueError) as exc:
        raise ArchiveSafetyError("NOT_A_ZIP", f"payload is not a valid zip: {exc}") from exc

    with archive:
        infos = archive.infolist()
        if len(infos) > policy.max_entries:
            raise ArchiveSafetyError(
                "TOO_MANY_ENTRIES",
                f"{len(infos)} entries exceeds cap {policy.max_entries}",
            )
        total = 0
        names: List[str] = []
        seen = _SeenNames(case_insensitive=policy.case_insensitive_targets)
        for info in infos:
            name = _check_member_name(info.filename)
            seen.add(name, info.filename)
            if info.flag_bits & 0x1:
                raise ArchiveSafetyError(
                    "ENCRYPTED_ENTRY", f"encrypted entry refused: {info.filename!r}"
                )
            if info.is_dir():
                names.append(name)
                continue
            # Unix mode bits: only regular files (or mode 0) are allowed.
            mode = info.external_attr >> 16
            _require_regular_mode(mode, info.filename)
            if info.file_size > policy.max_entry_bytes:
                raise ArchiveSafetyError(
                    "ENTRY_TOO_LARGE",
                    f"entry {name!r} declares {info.file_size} bytes "
                    f"(cap {policy.max_entry_bytes})",
                )
            if info.compress_size > 0:
                ratio = info.file_size / info.compress_size
                if ratio > policy.max_compression_ratio:
                    raise ArchiveSafetyError(
                        "COMPRESSION_BOMB",
                        f"entry {name!r} declares ratio {ratio:.1f}"
                        f" (cap {policy.max_compression_ratio})",
                    )
            total += info.file_size
            names.append(name)
        if total > policy.max_total_uncompressed_bytes:
            raise ArchiveSafetyError(
                "TOTAL_TOO_LARGE",
                f"total uncompressed {total} exceeds cap {policy.max_total_uncompressed_bytes}",
            )
    return ArchiveScanReport(
        entry_count=len(names), total_uncompressed_bytes=total, entries=names
    )


def extract_zip_safe(
    data: bytes,
    target_root,
    policy: ArchiveSafetyPolicy = ArchiveSafetyPolicy(),
) -> ArchiveScanReport:
    """Scan-then-extract: refuses unsafe archives before writing files."""
    from pathlib import Path

    root = Path(target_root)
    report = scan_zip(data, policy)
    archive = zipfile.ZipFile(BytesIO(data))
    with archive:
        for info in archive.infolist():
            name = _check_member_name(info.filename)
            if info.is_dir():
                (root / name).mkdir(parents=True, exist_ok=True)
                continue
            destination = (root / name).resolve()
            root_resolved = root.resolve()
            if root_resolved != destination and root_resolved not in destination.parents:
                raise ArchiveSafetyError(
                    "PATH_TRAVERSAL", f"resolved destination escapes root: {info.filename!r}"
                )
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as src, open(destination, "wb") as dst:
                written = 0
                while True:
                    chunk = src.read(64 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > policy.max_entry_bytes:
                        raise ArchiveSafetyError(
                            "ENTRY_TOO_LARGE",
                            f"entry {name!r} exceeded byte cap during extraction",
                        )
                    dst.write(chunk)
    return report


# ---------------------------------------------------------------------------
# Tar archives: same fail-closed contract via tarfile.
# ---------------------------------------------------------------------------


def scan_tar(data: bytes, policy: ArchiveSafetyPolicy = ArchiveSafetyPolicy()) -> ArchiveScanReport:
    """Validate every tar member BEFORE extraction. Typed refusals only."""
    import tarfile

    try:
        archive = tarfile.open(fileobj=BytesIO(data), mode="r:*")
    except (tarfile.TarError, ValueError, OSError) as exc:
        raise ArchiveSafetyError("NOT_A_TAR", f"payload is not a valid tar: {exc}") from exc

    with archive:
        members = archive.getmembers()
        if len(members) > policy.max_entries:
            raise ArchiveSafetyError(
                "TOO_MANY_ENTRIES",
                f"{len(members)} members exceeds cap {policy.max_entries}",
            )
        total = 0
        names: List[str] = []
        seen = _SeenNames(case_insensitive=policy.case_insensitive_targets)
        for member in members:
            name = _check_member_name(member.name)
            seen.add(name, member.name)
            if member.issym() or member.islnk():
                raise ArchiveSafetyError(
                    "LINK_ENTRY", f"symlink/hardlink member refused: {member.name!r}"
                )
            if member.isdir():
                names.append(name)
                continue
            if not member.isreg():
                # FIFO / char dev / block dev / any non-regular member.
                raise ArchiveSafetyError(
                    "NON_REGULAR_ENTRY", f"non-regular member refused: {member.name!r}"
                )
            if member.size > policy.max_entry_bytes:
                raise ArchiveSafetyError(
                    "ENTRY_TOO_LARGE",
                    f"entry {name!r} declares {member.size} bytes "
                    f"(cap {policy.max_entry_bytes})",
                )
            total += member.size
            names.append(name)
        if total > policy.max_total_uncompressed_bytes:
            raise ArchiveSafetyError(
                "TOTAL_TOO_LARGE",
                f"total uncompressed {total} exceeds cap {policy.max_total_uncompressed_bytes}",
            )
    return ArchiveScanReport(
        entry_count=len(names), total_uncompressed_bytes=total, entries=names
    )


def extract_tar_safe(
    data: bytes,
    target_root,
    policy: ArchiveSafetyPolicy = ArchiveSafetyPolicy(),
) -> ArchiveScanReport:
    """Scan-then-extract a tar: refuses unsafe archives before writing files."""
    import tarfile
    from pathlib import Path

    root = Path(target_root)
    report = scan_tar(data, policy)
    archive = tarfile.open(fileobj=BytesIO(data), mode="r:*")
    with archive:
        for member in archive.getmembers():
            name = _check_member_name(member.name)
            if member.isdir():
                (root / name).mkdir(parents=True, exist_ok=True)
                continue
            if not member.isreg():
                # scan_tar already refused non-regular members; re-check
                # defensively before any write.
                raise ArchiveSafetyError(
                    "NON_REGULAR_ENTRY", f"non-regular member refused: {member.name!r}"
                )
            destination = (root / name).resolve()
            root_resolved = root.resolve()
            if root_resolved != destination and root_resolved not in destination.parents:
                raise ArchiveSafetyError(
                    "PATH_TRAVERSAL", f"resolved destination escapes root: {member.name!r}"
                )
            destination.parent.mkdir(parents=True, exist_ok=True)
            source = archive.extractfile(member)
            if source is None:
                raise ArchiveSafetyError(
                    "NON_REGULAR_ENTRY", f"member has no file stream: {member.name!r}"
                )
            with source, open(destination, "wb") as dst:
                written = 0
                while True:
                    chunk = source.read(64 * 1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > policy.max_entry_bytes:
                        raise ArchiveSafetyError(
                            "ENTRY_TOO_LARGE",
                            f"entry {name!r} exceeded byte cap during extraction",
                        )
                    dst.write(chunk)
    return report
