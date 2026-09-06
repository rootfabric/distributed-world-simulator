"""Audit frozen P7 machine evidence. This command cannot accept or dispatch work."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
from typing import Any

PACKAGE = Path("docs/control/p7-canonical-closure-r1")
HEAD = "c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f"
TREE = "04679a6e67fc86ec156d4341140fd5b0225d6085"
GODOT = "4.7.1.stable.double.custom_build.a13da4feb"
FATAL = ("SCRIPT ERROR:", "Parse Error:", "Compile Error:",
         "Failed to instantiate an autoload", "Failed to load script")
ARCHIVES = {
    "runtime-evidence.tar.xz": "7fae5c5dc3e8e778262b01d91dfed9c9edb2fd1f105e8b590cb8348b928c4ea6",
    "pc0-evidence.tar.xz": "be611313835b08e73ec73b9a688bc5217d3978b8b9e6204157df9ed6c5675e96",
}


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def read_json(raw: str | bytes) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            require(key not in result, f"DUPLICATE_JSON_KEY:{key}")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs)


def read_archive(path: Path, digest: str) -> dict[str, bytes]:
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == digest, "ARCHIVE_DIGEST_MISMATCH")
    result: dict[str, bytes] = {}
    size = 0
    # Never extract archive paths or execute artifact contents.
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:xz") as archive:
        for member in archive:
            name = PurePosixPath(member.name)
            require(member.isfile() and not name.is_absolute() and ".." not in name.parts,
                    "ARCHIVE_MEMBER_INVALID")
            require(member.name not in result, "ARCHIVE_DUPLICATE_MEMBER")
            size += member.size
            require(size <= 4_000_000 and len(result) < 100, "ARCHIVE_LIMIT_EXCEEDED")
            stream = archive.extractfile(member)
            require(stream is not None, "ARCHIVE_MEMBER_UNREADABLE")
            result[member.name] = stream.read()
    return result


def audit(manifest: dict[str, Any], runtime: dict[str, bytes], pc0: dict[str, bytes]) -> dict[str, Any]:
    require(manifest["subject_head_sha"] == HEAD and manifest["subject_tree_sha"] == TREE,
            "SUBJECT_MISMATCH")
    console = runtime["runtime/v0-p7-canonical-acceptance/full-gate-console.log"].decode()
    for marker in ("V0-P7.7 GRAPHICAL DIGGING GATE GREEN", "EXACT_HEAD=" + HEAD,
                   "EXACT_TREE=" + TREE, "GODOT=" + GODOT):
        require(marker in console, "GATE_MARKER_MISSING:" + marker)
    for name, content in runtime.items():
        if name.endswith(".log"):
            text = content.decode("utf-8")
            require(not any(pattern in text for pattern in FATAL), "FATAL_LOG:" + name)
            require(not re.search(r": FAIL(?:\s|\()|[1-9]\d* failures", text), "FAILED_LOG:" + name)

    excluded = {"import.log", "p7-5-subgate.log", "full-gate-console.log"}
    leaves = {n for n in runtime if n.endswith(".log") and PurePosixPath(n).name not in excluded}
    stages = manifest["stages"]
    names = [stage["log"] for stage in stages]
    require(len(names) == len(set(names)) == 29 and set(names) == leaves, "STAGE_COVERAGE_MISMATCH")
    totals = {"direct": 0, "nested_p7_5": 0}
    for stage in stages:
        text = runtime[stage["log"]].decode()
        counts = re.findall(r"\b(\d+) assertions\b", text)
        require(len(counts) == 1 and int(counts[0]) == stage["assertions"], "ASSERTION_COUNT_MISMATCH")
        require("PASS" in text or "0 failures" in text, "STAGE_SUCCESS_MARKER_MISSING")
        require(stage["group"] in totals, "STAGE_GROUP_INVALID")
        totals[stage["group"]] += int(counts[0])
    require(totals == {"direct": 887, "nested_p7_5": 1145}, "FORMAL_TOTAL_MISMATCH")

    # Original workflow inadvertently hashed its own checksum file. Preserve it;
    # exclude only that self-entry, never a stage log. Archive digest binds all bytes.
    sum_name = "runtime/v0-p7-canonical-acceptance/SHA256SUMS"
    checked: set[str] = set()
    for line in runtime[sum_name].decode().splitlines():
        digest, original = line.split("  ", 1)
        require(original.startswith("artifacts/runtime/"), "ORIGINAL_MANIFEST_PATH_INVALID")
        name = "runtime/" + original.removeprefix("artifacts/runtime/")
        require(name not in checked, "ORIGINAL_MANIFEST_DUPLICATE")
        checked.add(name)
        if name != sum_name:
            require(name in runtime and hashlib.sha256(runtime[name]).hexdigest() == digest,
                    "ORIGINAL_MEMBER_DIGEST_MISMATCH:" + name)
    require(checked == set(runtime), "ORIGINAL_MANIFEST_COVERAGE_MISMATCH")

    standard = read_json(pc0["project-control-report.json"])
    directional = read_json(pc0["directional-watch-report.json"])
    require(standard["main_head"] == HEAD and standard["registry_generation"] == 81,
            "PC0_SUBJECT_MISMATCH")
    require(standard["overall_health"] in ("GREEN", "YELLOW") and not standard["cross_branch_overlaps"],
            "PC0_BLOCKING")
    require(all(p["health"] != "RED" or p.get("blocks_global_progress") is False
                for p in standard["programs"]), "PC0_PROGRAM_BLOCKING")
    require(directional["registry_generation"] == 81 and directional["overall_health"] in ("GREEN", "YELLOW"),
            "DIRECTIONAL_PC0_BLOCKING")
    require(not any(f["level"] == "RED" and f.get("global_blocking", True)
                    for f in directional["findings"]), "DIRECTIONAL_CRITICAL_HIT")
    return {
        "subject_head_sha": HEAD, "subject_tree_sha": TREE,
        "result": "FROZEN_MACHINE_EVIDENCE_VALID", "stages": 29,
        "assertions": sum(totals.values()), "failures": 0, "fatal_matches": 0,
        "stage_totals": totals, "runtime_files_digest_checked": len(runtime),
        "standard_pc0": standard["overall_health"], "directional_pc0": directional["overall_health"],
        "directional_findings": directional["findings"],
        "checksum_self_entry": "ORIGINAL_PRESERVED_NOT_USED_AS_AUTHORITY",
        "independent_verdict": None, "canonical_acceptance": False, "runtime_authorized": False,
        "unresolved_gates": manifest["unresolved_gates"],
    }


def git_checks(root: Path, manifest: dict[str, Any]) -> None:
    def git(*args: str) -> str:
        return subprocess.check_output(["git", *args], cwd=root, text=True, timeout=30).strip()
    require(git("rev-parse", HEAD + "^{tree}") == TREE, "GIT_SUBJECT_TREE_MISMATCH")
    git("merge-base", "--is-ancestor", HEAD, "origin/main")
    for stage in manifest["historical_p7_map"]:
        git("merge-base", "--is-ancestor", stage["merge_commit"], HEAD)
        for relative in stage["evidence_paths"]:
            git("cat-file", "-e", f"{HEAD}:{relative}")
    git("merge-base", "--is-ancestor", manifest["accepted_sm1_product_lineage"], HEAD)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--git", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        package = args.root / PACKAGE
        manifest = read_json((package / "manifest.v1.json").read_bytes())
        archives = {name: read_archive(package / name, digest) for name, digest in ARCHIVES.items()}
        report = audit(manifest, archives["runtime-evidence.tar.xz"], archives["pc0-evidence.tar.xz"])
        if args.git:
            git_checks(args.root, manifest)
        text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        print(text, end="")
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(text, encoding="utf-8")
        return 0
    except (ValueError, KeyError, TypeError, OSError, tarfile.TarError, subprocess.SubprocessError) as exc:
        print(json.dumps({"result": "EVIDENCE_INVALID", "error": str(exc), "runtime_authorized": False}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
