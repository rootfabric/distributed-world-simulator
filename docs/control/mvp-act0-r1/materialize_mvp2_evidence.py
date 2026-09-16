"""Verify and materialize frozen MVP2 evidence; never commit or issue a verdict."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import zipfile

HEAD = "287df80c69840fea7ae9ac0ea69a07581f192d34"
TREE = "e591dc6c5346139bc1b4659915c54bf80603713e"
RUN = "34605253942"
ZIP_SHA = "850c2422884493c4bd8aeccc2e5dad286c7550610bf43397fe3722f05c746f1f"
MANIFEST_SHA = "885a15a7552918a67ada595796bb1e4cfe25fb77c68de5c896dac5cdaea4300f"
SINK = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP2-NATIVE-287df80c6984-34605253942"


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def materialize(archive: Path, repository: Path) -> Path:
    raw = archive.read_bytes()
    require(digest(raw) == ZIP_SHA, "ARCHIVE_DIGEST_MISMATCH")
    import io
    with zipfile.ZipFile(io.BytesIO(raw)) as zipped:
        names = zipped.namelist()
        require(len(names) == len(set(names)), "DUPLICATE_ARCHIVE_MEMBER")
        manifest_raw = zipped.read("manifest.v1.json")
        require(digest(manifest_raw) == MANIFEST_SHA, "MANIFEST_DIGEST_MISMATCH")
        manifest = json.loads(manifest_raw)
        expected = {
            "schema": "distributed_world_simulator.harness_machine_evidence_manifest.v1",
            "work_order_id": "V0-MVP-R1-WO-001",
            "project_epoch": "E2026-09-09-V0-MVP-R1",
            "subject_head_sha": HEAD,
            "subject_tree_sha": TREE,
            "run_id": RUN,
            "tracked_checkout_clean_before": True,
            "tracked_checkout_clean_after": True,
            "intended_manifest_path": SINK + "/manifest.v1.json",
        }
        require(all(type(manifest.get(k)) is type(v) and manifest[k] == v
                    for k, v in expected.items()), "MANIFEST_IDENTITY_MISMATCH")
        require(len(manifest["artifacts"]) == 35, "ARTIFACT_COUNT_MISMATCH")
        files = {"manifest.v1.json": manifest_raw}
        for entry in manifest["artifacts"]:
            name = entry["archive_member"]
            path = PurePosixPath(name)
            require(not path.is_absolute() and path.as_posix() == name
                    and not any(p in (".", "..", ".git") for p in path.parts)
                    and not any(c in name for c in ("\\", ":", "\x00")), "UNSAFE_MEMBER")
            require(name not in files and entry["path"] == SINK + "/" + name,
                    "ARTIFACT_PATH_MISMATCH")
            require(entry["subject_head_sha"] == HEAD and entry["run_id"] == RUN,
                    "ARTIFACT_IDENTITY_MISMATCH")
            data = zipped.read(name)
            require(digest(data) == entry["sha256"], "MEMBER_DIGEST_MISMATCH:" + name)
            files[name] = data
        require(set(names) == set(files), "UNINDEXED_ARCHIVE_MEMBER")
        result = json.loads(files["result.json"])
        require(result.get("passed") is True and result.get("errors") == []
                and result.get("subject_head_sha") == HEAD
                and result.get("subject_tree_sha") == TREE, "EXACT_RESULT_NOT_SUCCESS")
    root = repository.resolve(strict=True)
    target = root / SINK
    require(target.resolve().is_relative_to(root), "DESTINATION_ESCAPES_REPOSITORY")
    require(not target.exists() and not target.is_symlink(), "DESTINATION_ALREADY_EXISTS")
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".mvp2-evidence-", dir=target.parent))
    try:
        for name, data in files.items():
            destination = staging / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("xb") as stream:
                stream.write(data)
        require(not target.exists() and not target.is_symlink(), "DESTINATION_ALREADY_EXISTS")
        staging.rename(target)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--repo", required=True, type=Path)
    args = parser.parse_args()
    try:
        target = materialize(args.archive, args.repo)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        parser.exit(1, f"MVP2_EVIDENCE_MATERIALIZATION_FAILED: {exc}\n")
    print(json.dumps({"status": "RAW_EVIDENCE_MATERIALIZED_NOT_COMMITTED",
                      "path": str(target), "indexed_artifacts": 35,
                      "subject_head_sha": HEAD, "independent_verdict": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
