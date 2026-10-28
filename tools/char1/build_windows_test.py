#!/usr/bin/env python3
"""Build an auditable, portable CHAR1 Windows test ZIP from the exact Git HEAD.

No third-party assets, ignored files, local working-tree edits or Godot binaries
are included. Windows launchers come from tracked portable_windows/ sources.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from datetime import datetime, timezone

SOURCE_DIR = pathlib.PurePosixPath("tools/char1/portable_windows")
PACKAGE_ROOT = "CHAR1_REALISTIC_WINDOWS_TEST"
REVISION = "PS51_EXITCODE_HANDLE_R2"
CRITICAL = (
    "scripts/characters/lab/char1_realistic_avatar_viewer.gd",
    "tests/characters/test_char1_first_person_body_visibility.gd",
    "tests/characters/test_char1_realistic_viewmode.gd",
    "scripts/characters/providers/quaternius_avatar_adapter.gd",
    "scripts/characters/providers/quaternius_avatar_engine.gd",
    "scenes/labs/character/char1_realistic_avatar_viewer.tscn",
    "config/characters/production-avatar-catalog.v1.json",
)


def git(*args: str, cwd: pathlib.Path | None = None) -> str:
    completed = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True, check=True
    )
    return completed.stdout.strip()


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_git_archive(repo: pathlib.Path, dest: pathlib.Path, tmp: pathlib.Path) -> None:
    tar_path = tmp / "source.tar"
    subprocess.run(
        ["git", "-C", str(repo), "archive", "--format=tar",
         f"--output={tar_path}", "HEAD"], check=True
    )
    root = dest.resolve()
    with tarfile.open(tar_path, "r") as tf:
        for member in tf:
            # Use only regular tracked Git source, never symlink out of the archive.
            target = (dest / member.name).resolve()
            if not target.is_relative_to(root):
                raise RuntimeError(f"unsafe archive path: {member.name}")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                source = tf.extractfile(member)
                if source is None:
                    raise RuntimeError(f"missing tar member: {member.name}")
                with source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
            else:
                raise RuntimeError(f"unsupported archive entry: {member.name}")


def build(repo: pathlib.Path, output: pathlib.Path) -> dict:
    head = git("rev-parse", "HEAD", cwd=repo)
    tree = git("rev-parse", "HEAD^{tree}", cwd=repo)
    if git("status", "--porcelain", "--untracked-files=no", cwd=repo):
        raise RuntimeError("tracked worktree dirty: commit first")
    if not git("ls-files", "--error-unmatch", str(SOURCE_DIR / "tools/CHAR1-Common.ps1"), cwd=repo):
        raise RuntimeError("portable launchers not tracked")

    with tempfile.TemporaryDirectory(prefix="char1-portable-") as temp_string:
        tmp = pathlib.Path(temp_string)
        package = tmp / PACKAGE_ROOT
        project = package / "project"
        project.mkdir(parents=True)
        read_git_archive(repo, project, tmp)

        # Copy from git-archived source, not from a mutable checkout.
        launchers = project / SOURCE_DIR
        if not launchers.is_dir():
            raise RuntimeError("missing portable launcher sources in exact snapshot")
        for item in sorted(launchers.rglob("*")):
            if not item.is_file():
                continue
            relative = item.relative_to(launchers)
            target = package / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)

        common_path = package / "tools/CHAR1-Common.ps1"
        common = common_path.read_text(encoding="utf-8")
        if "$null = $process.Handle" not in common:
            raise RuntimeError("PS51 Process.Handle hotfix not present")
        if common.index("$null = $process.Handle") > common.index("WaitForExit("):
            raise RuntimeError("Process.Handle must be initialized before WaitForExit")
        for required in ("START_CHAR1.cmd", "VERIFY_CHAR1.cmd",
                         "tools/START_CHAR1.ps1", "tools/VERIFY_CHAR1.ps1"):
            if not (package / required).is_file():
                raise RuntimeError(f"missing launcher: {required}")
        if (project / ".godot").exists():
            raise RuntimeError(".godot cache must not ship")
        if (project / "assets/external/quaternius/base_characters").exists():
            raise RuntimeError("external Quaternius packages must not ship")
        checksums = {}
        for relative in CRITICAL:
            file = project / relative
            if not file.is_file():
                raise RuntimeError(f"missing tracked CHAR1 source: {relative}")
            checksums[relative] = sha256(file)
        info = {
            "package": "CHAR1 Realistic Avatar Windows Test",
            "product_head": head,
            "product_tree": tree,
            "origin_branch": git("branch", "--show-current", cwd=repo) or "detached",
            "built_utc": datetime.now(timezone.utc).isoformat(),
            "godot_version": "4.7.1.stable.double.custom_build.a13da4feb",
            "windows_console_sha256":
                "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
            "external_quaternius_included": False,
            "contents": "exact tracked GitHub source + versioned Windows launcher",
            "critical_sha256": checksums,
            "portable_launcher_revision": REVISION,
            "portable_launcher_sha256": sha256(common_path),
        }
        (package / "BUILD_INFO.json").write_text(
            json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (package / "evidence").mkdir()
        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=6, allowZip64=True) as result:
            for file in sorted(package.rglob("*")):
                if not file.is_file():
                    continue
                relative = file.relative_to(tmp).as_posix()
                # Stable archive timestamps; BUILD_INFO carries build time.
                zi = zipfile.ZipInfo(relative, date_time=(2020, 1, 1, 0, 0, 0))
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.external_attr = 0o644 << 16
                result.writestr(zi, file.read_bytes(), compress_type=zipfile.ZIP_DEFLATED,
                                compresslevel=6)

    with zipfile.ZipFile(output, "r") as packaged:
        first_bad = packaged.testzip()
        if first_bad is not None:
            raise RuntimeError(f"ZIP CRC check failed: {first_bad}")
        embedded = json.loads(packaged.read(
            f"{PACKAGE_ROOT}/BUILD_INFO.json").decode("utf-8"))
        if embedded["product_head"] != head or embedded["product_tree"] != tree:
            raise RuntimeError("identity mismatch in built archive")
        if embedded["portable_launcher_revision"] != REVISION:
            raise RuntimeError("launcher revision mismatch")
        common = packaged.read(
            f"{PACKAGE_ROOT}/tools/CHAR1-Common.ps1").decode("utf-8")
        if "$null = $process.Handle" not in common:
            raise RuntimeError("PS51 launcher missing in final zip")

    return {"head": head, "tree": tree, "zip": str(output),
            "zip_sha256": sha256(output), "bytes": output.stat().st_size,
            "launcher_revision": REVISION}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=None)
    args = parser.parse_args()
    repo = pathlib.Path(
        git("rev-parse", "--show-toplevel",
            cwd=pathlib.Path(__file__).resolve().parent)).resolve()
    head = git("rev-parse", "HEAD", cwd=repo)
    output = (args.output if args.output is not None
              else repo / f"CHAR1_Realistic_Avatar_Windows_Test_{head[:8]}_PS51_Hotfix.zip")
    result = build(repo, output.resolve())
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
