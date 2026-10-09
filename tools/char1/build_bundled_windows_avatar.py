#!/usr/bin/env python3
"""Package CHAR1 with the *real* Quaternius avatar and Godot Windows runtime.

Uses local official CC0 model/animation files already present on Windows.
The output is a self-contained interactive preview, not a production game
export. Fails closed on missing assets, engine mismatches and procedural fallback.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

from build_windows_test import build as build_exact_source

ROOT_NAME = "CHAR1_REALISTIC_WITH_AVATAR"
ENGINE_CONSOLE = "godot.windows.editor.double.x86_64.console.exe"
ENGINE_GUI = "godot.windows.editor.double.x86_64.exe"
ENGINE_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
ENGINE_CONSOLE_SHA = "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"
ASSET_MODE_TEST = "tests/characters/test_char1_embedded_quaternius_assets.gd"
BODY_VISIBILITY_TEST = "tests/characters/test_char1_first_person_body_visibility.gd"
SOURCE_TEST = "tests/characters/test_char1_production_avatar.gd"
AVATAR_SCENE = "res://scenes/labs/character/char1_realistic_avatar_viewer.tscn"
SKIP_ASSET_ENTRIES = {".git", ".godot", "__pycache__", "Thumbs.db", ".DS_Store"}


def sha(path: pathlib.Path) -> str:
    hash_value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hash_value.update(block)
    return hash_value.hexdigest()


def git(repo: pathlib.Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def find_assets(repo: pathlib.Path, specified: str | None) -> pathlib.Path:
    candidates: list[pathlib.Path] = []
    for value in (specified, os.environ.get("DWS_QUATERNIUS_ASSET_ROOT")):
        if value:
            candidates.append(pathlib.Path(value))
    candidates.extend([
        repo / "assets" / "external" / "quaternius",
        pathlib.Path("C:/distributed-world-simulator/char1-realistic-r1/assets/external/quaternius"),
        pathlib.Path("C:/distributed-world-simulator/distributed-world-simulator/char1-realistic-r1/assets/external/quaternius"),
        pathlib.Path("C:/distributed-world-simulator/assets/external/quaternius"),
        pathlib.Path("C:/dwsv-char1-git-hotfix-test/CHAR1_REALISTIC_WINDOWS_TEST/project/assets/external/quaternius"),
        pathlib.Path("C:/DWS-CHAR1-Test/CHAR1_REALISTIC_WINDOWS_TEST/project/assets/external/quaternius"),
    ])
    for original in candidates:
        for value in [original, original / "assets" / "external" / "quaternius"]:
            if not value.is_dir():
                continue
            base = value / "base_characters"
            animation = value / "animation_library"
            if not base.is_dir() or not animation.is_dir():
                continue
            fullbody = [p for p in base.rglob("*") if p.is_file()
                        and p.name.lower() == "superhero_male_fullbody.gltf"]
            ual = [p for p in animation.rglob("*") if p.is_file()
                   and p.name.lower() == "ual1_standard.glb"]
            if fullbody and ual:
                print("CHAR1_ASSET_SOURCE", value.resolve(), flush=True)
                return value.resolve()
    raise RuntimeError(
        "REAL_QUATERNIUS_ASSETS_NOT_FOUND: supply --assets-root pointing to "
        "base_characters/ and animation_library/ containing Superhero_Male_FullBody.gltf "
        "and UAL1_Standard.glb. No fallback/empty package will be emitted."
    )


def copy_assets(source: pathlib.Path, dest: pathlib.Path) -> dict:
    asset_count = 0
    asset_bytes = 0
    if dest.exists():
        raise RuntimeError("tracked source unexpectedly contains external Quaternius assets")
    for folder in ["base_characters", "animation_library"]:
        original = source / folder
        if not original.is_dir():
            raise RuntimeError("missing Quaternius asset directory: " + str(original))
        for file in original.rglob("*"):
            if file.is_symlink():
                raise RuntimeError("external Quaternius asset symlink not accepted: " + str(file))
        target = dest / folder
        shutil.copytree(original, target, ignore=lambda _d, names: [
            name for name in names if name in SKIP_ASSET_ENTRIES or name.endswith(".tmp")
        ])
        for file in target.rglob("*"):
            if file.is_file():
                asset_count += 1
                asset_bytes += file.stat().st_size
    model = next((file for file in (dest / "base_characters").rglob("*")
                  if file.is_file() and file.name.lower() == "superhero_male_fullbody.gltf"), None)
    animation = next((file for file in (dest / "animation_library").rglob("*")
                      if file.is_file() and file.name.lower() == "ual1_standard.glb"), None)
    if not model or not animation:
        raise RuntimeError("copied asset payload incomplete; no build emitted")
    return {
        "source_file_count": asset_count,
        "uncompressed_bytes": asset_bytes,
        "model_relative_path": model.relative_to(dest.parent.parent.parent).as_posix(),
        "model_sha256": sha(model),
        "animation_relative_path": animation.relative_to(dest.parent.parent.parent).as_posix(),
        "animation_sha256": sha(animation),
        "source": "Quaternius Universal Base Characters + Universal Animation Library CC0",
        "license": "https://creativecommons.org/publicdomain/zero/1.0/",
        "model_pack": "https://quaternius.itch.io/universal-base-characters",
        "animation_pack": "https://quaternius.itch.io/universal-animation-library",
    }


def run_checked(command: list[str], name: str, cwd: pathlib.Path,
                logs: pathlib.Path, timeout: int) -> str:
    print("CHAR1_VERIFY_START", name, flush=True)
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True,
                                   text=True, errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as ex:
        raise RuntimeError("GODOT_TIMEOUT " + name) from ex
    combined = completed.stdout + "\n" + completed.stderr
    (logs / (name + ".log")).write_text(combined, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(name + " exited " + str(completed.returncode) + "\n" + combined[-6000:])
    if re.search(r"SCRIPT ERROR:|Parse Error:|Compile Error:", combined):
        raise RuntimeError(name + " script/parse/compile errors\n" + combined[-6000:])
    print("CHAR1_VERIFY_PASS", name, flush=True)
    return combined


def extract_source(source_zip: pathlib.Path, dest: pathlib.Path) -> None:
    with zipfile.ZipFile(source_zip) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Git tracked-source archive CRC failure")
        root = dest.resolve()
        prefix = "CHAR1_REALISTIC_WINDOWS_TEST/"
        for entry in archive.infolist():
            if not entry.filename.startswith(prefix):
                raise RuntimeError("Unexpected Git source package prefix")
            relative = entry.filename[len(prefix):]
            if not relative:
                continue
            output = (dest / relative).resolve()
            if not output.is_relative_to(root):
                raise RuntimeError("Unsafe package path: " + entry.filename)
            if entry.is_dir():
                output.mkdir(parents=True, exist_ok=True)
            else:
                output.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as input_stream, output.open("wb") as output_stream:
                    shutil.copyfileobj(input_stream, output_stream, length=1024 * 1024)


def make_launchers(folder: pathlib.Path) -> None:
    for filename in ["START_CHAR1.cmd", "VERIFY_CHAR1.cmd", "START_NETWORK_CHAR1.cmd"]:
        dest = folder / filename
        if not dest.is_file():
            raise RuntimeError("Missing tracked Windows launcher: " + filename)
        replacement = (
            '@echo off\r\n'
            'setlocal\r\n'
            'cd /d "%~dp0"\r\n'
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File '
            '"%~dp0tools\\' + filename.replace(".cmd", ".ps1") + '" '
            '-GodotConsole "%~dp0runtime\\' + ENGINE_CONSOLE + '" %*\r\n'
            'if errorlevel 1 (\r\n'
            '  echo CHAR1 launch / verification FAILED. See error above and evidence logs.\r\n'
            '  pause\r\n'
            '  exit /b 1\r\n'
            ')\r\n'
            'exit /b 0\r\n'
        )
        dest.write_bytes(replacement.encode("ascii"))


def build(args: argparse.Namespace) -> dict:
    repo = pathlib.Path(args.repo).resolve()
    if not (repo / "tools/char1/build_windows_test.py").is_file():
        raise RuntimeError("--repo must be the exact CHAR1 Git worktree")
    head = git(repo, "rev-parse", "HEAD")
    tree = git(repo, "rev-parse", "HEAD^{tree}")
    if args.expected_head and head != args.expected_head:
        raise RuntimeError("HEAD_MOVED: expected " + args.expected_head + ", got " + head)
    if git(repo, "status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("Tracked files dirty: cannot package an unfrozen candidate")
    assets = find_assets(repo, args.assets_root)

    console = pathlib.Path(args.godot_console).resolve()
    gui = console.with_name(ENGINE_GUI)
    if not console.is_file() or not gui.is_file():
        raise RuntimeError("GODOT_DOUBLE_WINDOWS_BINARIES_MISSING: " + str(console))
    if sha(console) != ENGINE_CONSOLE_SHA:
        raise RuntimeError("GODOT_DOUBLE_SHA256_MISMATCH: " + sha(console))
    version = subprocess.run([str(console), "--version"], capture_output=True,
                             text=True, timeout=20, check=True).stdout.strip()
    if version != ENGINE_VERSION:
        raise RuntimeError("GODOT_VERSION_MISMATCH: " + version)
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise RuntimeError("Output already exists: do not overwrite " + str(output))

    with tempfile.TemporaryDirectory(prefix="dws-char1-embedded-") as tmp_name:
        tmp = pathlib.Path(tmp_name)
        source_zip = tmp / "tracked-source.zip"
        source_info = build_exact_source(repo, source_zip)
        if source_info["head"] != head or source_info["tree"] != tree:
            raise RuntimeError("Embedded Git identity changed while building")
        package = tmp / ROOT_NAME
        package.mkdir()
        extract_source(source_zip, package)
        project = package / "project"
        asset_data = copy_assets(assets, project / "assets" / "external" / "quaternius")
        engine_folder = package / "runtime"
        engine_folder.mkdir()
        shutil.copy2(console, engine_folder / ENGINE_CONSOLE)
        shutil.copy2(gui, engine_folder / ENGINE_GUI)
        # Native runtime DLLs beside the canonical engine may be required by Windows.
        for dll in console.parent.glob("*.dll"):
            shutil.copy2(dll, engine_folder / dll.name)
        make_launchers(package)
        license_dest = package / "LICENSES"
        license_dest.mkdir()
        for notice in ("GODOT_MIT_LICENSE.txt", "QUATERNIUS_CC0_PROVENANCE.txt"):
            source = project / "tools" / "char1" / "licenses" / notice
            if not source.is_file():
                raise RuntimeError("Required redistributed license notice missing: " + notice)
            shutil.copy2(source, license_dest / notice)

        evidence = package / "evidence"
        evidence.mkdir(exist_ok=True)
        preflight = "res://scripts/characters/importing/quaternius_asset_preflight.gd"
        imported = run_checked([
            str(console), "--headless", "--path", str(project),
            "--script", preflight
        ], "quaternius-uri-preflight", project, evidence, 180)
        if "asset preflight: PASS" not in imported:
            raise RuntimeError("Quaternius URI preflight did not prove PASS")
        # The validated CH4 preflight may safely normalize glTF texture URI
        # spelling/case. Hash the *post*-normalization bytes actually shipped.
        asset_data["model_sha256"] = sha(project / asset_data["model_relative_path"])
        asset_data["animation_sha256"] = sha(project / asset_data["animation_relative_path"])
        run_checked([
            str(console), "--headless", "--editor", "--import", "--path",
            str(project), "--quit"
        ], "cold-import", project, evidence, 1200)
        checks = [
            ("avatar-strict", ASSET_MODE_TEST, "CHAR1 EMBEDDED REAL AVATAR: PASS"),
            ("body-visibility", BODY_VISIBILITY_TEST, "CHAR1 FIRST-PERSON BODY VISIBILITY: PASS"),
            ("char1-provider", SOURCE_TEST, "CHAR1 PRODUCTION AVATAR: PASS"),
        ]
        for name, scene, marker in checks:
            log = run_checked([
                str(console), "--headless", "--path", str(project),
                "--script", "res://" + scene
            ], name, project, evidence, 300)
            if marker not in log:
                raise RuntimeError(name + " expected PASS marker missing")
        # The shipped project includes official source files, so the imported
        # cache can be rebuilt deterministically on first launch at a new path.
        cache = project / ".godot"
        if cache.exists():
            shutil.rmtree(cache)
        # Preserve reproducible original tracked source identity, but record that
        # the assembled payload also contains CC0 resources and engine binaries.
        embedded = {
            "package": "CHAR1 Realistic Avatar Bundled Windows Preview",
            "kind": "PORTABLE_GODOT_EDITOR_RUNTIME_AND_CC0_ASSETS",
            "product_head": head,
            "product_tree": tree,
            "original_source_revision": source_info["launcher_revision"],
            "build_utc": datetime.now(timezone.utc).isoformat(),
            "godot_version": version,
            "godot_console_sha256": sha(engine_folder / ENGINE_CONSOLE),
            "godot_gui_sha256": sha(engine_folder / ENGINE_GUI),
            "real_quaternius_asset_mode": "RETARGET_OR_EMBEDDED_PROVED_BY_STRICT_GATE",
            "model_and_animation": asset_data,
            "test_gates": [name for name, _scene, _marker in checks],
            "cold_import": "PASS",
            "portable_launcher": "PS51_EXITCODE_HANDLE_R2",
            "avatar_included": True,
            "first_person_local_body_hidden": True,
            "third_person_local_body_visible": True,
        }
        (package / "EMBEDDED_BUILD_INFO.json").write_text(
            json.dumps(embedded, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8"
        )
        (package / "README_WITH_AVATAR_RU.txt").write_text(
            "CHAR1: ready-to-run Windows preview with real Quaternius avatar.\n"
            "Unpack to a writable directory and run START_CHAR1.cmd.\n"
            "For actual dedicated server + two ENet clients use START_NETWORK_CHAR1.cmd.\n"
            "Host World as a, then Join World as b on port 24580.\n"
            "In actual game clients V/F7 toggles camera; remote avatars always visible.\n"
            "No Godot installation and no separate Quaternius downloads required.\n"
            "First launch may re-import assets. C/V switches first/third person;\n"
            "first person hides the local body. 1 selects real Quaternius,\n"
            "2/3 switch to procedural comparisons; I/W/R choose idle/walk/run.\n"
            "The package is a portable Godot editor-runtime preview, NOT\n"
            "an exported standalone production game binary.\n"
            "Quaternius Universal Base Characters and Universal Animation\n"
            "Library are CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/\n"
            "Licenses: LICENSES/GODOT_MIT_LICENSE.txt and\n"
            "LICENSES/QUATERNIUS_CC0_PROVENANCE.txt.\n",
            encoding="utf-8"
        )
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=6, allowZip64=True) as archive:
            for file in sorted(package.rglob("*")):
                if file.is_file():
                    archive.write(file, file.relative_to(tmp).as_posix())
        with zipfile.ZipFile(output, "r") as archived:
            damaged = archived.testzip()
            if damaged is not None:
                raise RuntimeError("Final ZIP CRC error: " + damaged)
            prefix = ROOT_NAME + "/"
            meta = json.loads(archived.read(prefix + "EMBEDDED_BUILD_INFO.json"))
            if meta["product_head"] != head or not meta["avatar_included"]:
                raise RuntimeError("Final ZIP missing embedded avatar identity")
            model_path = prefix + "project/" + asset_data["model_relative_path"]
            anim_path = prefix + "project/" + asset_data["animation_relative_path"]
            if sha_in_zip(archived, model_path) != asset_data["model_sha256"]:
                raise RuntimeError("Final ZIP model hash mismatch")
            if sha_in_zip(archived, anim_path) != asset_data["animation_sha256"]:
                raise RuntimeError("Final ZIP animation library hash mismatch")
    return {
        "verdict": "BUILT_AND_STRICT_HEADLESS_VERIFIED",
        "head": head, "tree": tree,
        "output": str(output),
        "output_bytes": output.stat().st_size,
        "sha256": sha(output),
        "avatar_included": True,
        "asset_source_count": asset_data["source_file_count"],
    }


def sha_in_zip(archive: zipfile.ZipFile, name: str) -> str:
    hash_value = hashlib.sha256()
    with archive.open(name) as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            hash_value.update(block)
    return hash_value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=str(pathlib.Path(__file__).resolve().parents[2]))
    parser.add_argument("--godot-console", default="C:/Godot/godot/bin/" + ENGINE_CONSOLE)
    parser.add_argument("--assets-root", default=None)
    parser.add_argument("--expected-head", default=None)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        result = build(args)
    except (RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        print("CHAR1_BUNDLED_BUILD_FAIL", str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1) from exc
    print("CHAR1_BUNDLED_BUILD_PASS " + json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
