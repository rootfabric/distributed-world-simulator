from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "parallel_controller",
    ROOT / "tools/world_packs/parallel_controller.py",
)
controller = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = controller
SPEC.loader.exec_module(controller)


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=repo, text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_state_validation_and_progress():
    config = {
        "controller_id": "WORLD_PACKS_PARALLEL_R1",
        "policy": {
            "state_path_template": "config/world_packs/parallel/workstreams/{track_id}.v1.json",
        },
    }
    track = {
        "id": "WP-X",
        "branch": "work/x",
        "milestones": ["A", "B", "C"],
    }
    state = {
        "schema": controller.STATE_SCHEMA,
        "controller_id": config["controller_id"],
        "track_id": "WP-X",
        "branch": "work/x",
        "status": "IN_PROGRESS",
        "completed_milestones": ["A"],
        "blockers": [],
        "next_action": "do B",
        "validation": [],
    }
    assert controller.validate_state(config, track, state) == []
    assert controller.first_incomplete(track, state) == "B"
    assert controller.progress_percent(track, state) == 33

    state["completed_milestones"].append("UNKNOWN")
    assert "STATE_UNKNOWN_MILESTONE" in controller.validate_state(config, track, state)


@pytest.mark.parametrize(
    ("path", "patterns", "expected"),
    [
        ("tools/world_packs/asset_fetch/fetch.py", ["tools/world_packs/asset_fetch/**"], True),
        ("scripts/simulation/matter/x.gd", ["tools/world_packs/**"], False),
        ("docs/world_packs/evidence/WP-X_A.md", ["docs/world_packs/evidence/WP-X*"], True),
    ],
)
def test_path_matches(path, patterns, expected):
    assert controller.path_matches(path, patterns) is expected


def test_collect_reports_divergence_scope_and_overlap(tmp_path: Path, monkeypatch):
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.email", "parallel@example.invalid")
    git(repo, "config", "user.name", "Parallel Test")
    (repo / "seed.txt").write_text("main\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "main")
    main_sha = git(repo, "rev-parse", "HEAD")

    git(repo, "switch", "-c", "feature/world-packs1-surface-library-contract-r1")
    (repo / "base.txt").write_text("world packs\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "base")
    base_sha = git(repo, "rev-parse", "HEAD")

    git(repo, "switch", "-c", "control/world-packs-parallel-r1")
    (repo / "controller.txt").write_text("control\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "controller")
    control_sha = git(repo, "rev-parse", "HEAD")

    config = {
        "controller_id": "WORLD_PACKS_PARALLEL_R1",
        "controller_branch": "control/world-packs-parallel-r1",
        "execution_base_branch": "feature/world-packs1-surface-library-contract-r1",
        "execution_base_sha": base_sha,
        "main_baseline_sha": main_sha,
        "remote": "origin",
        "policy": {
            "state_path_template": "config/world_packs/parallel/workstreams/{track_id}.v1.json",
            "integration_target": "control/world-packs-parallel-r1",
        },
        "hard_forbidden_paths": ["scripts/simulation/**"],
        "critical_main_watched_paths": ["scripts/simulation/**"],
        "validation_exempt_paths": [
            "config/world_packs/parallel/workstreams/**",
            "docs/world_packs/evidence/**",
        ],
        "tracks": [
            {
                "id": "WP-A",
                "branch": "work/a",
                "purpose": "a",
                "risk": "LOW",
                "allowed_paths": [
                    "a/**",
                    "config/world_packs/parallel/workstreams/WP-A.v1.json",
                ],
                "milestones": ["ONE", "TWO"],
                "first_action": "one",
            },
            {
                "id": "WP-B",
                "branch": "work/b",
                "purpose": "b",
                "risk": "LOW",
                "allowed_paths": [
                    "b/**",
                    "config/world_packs/parallel/workstreams/WP-B.v1.json",
                ],
                "milestones": ["ONE"],
                "first_action": "one",
            },
        ],
        "queued_integration": {
            "id": "JOIN",
            "requires_tracks": ["WP-A", "WP-B"],
            "requires_gates": [],
            "next_when_ready": "join",
        },
        "external_gates": [],
    }

    for track_id, branch, directory in (("WP-A", "work/a", "a"), ("WP-B", "work/b", "b")):
        git(repo, "switch", "control/world-packs-parallel-r1")
        git(repo, "switch", "-c", branch)
        (repo / directory).mkdir()
        (repo / directory / "own.txt").write_text(track_id, encoding="utf-8")
        shared = repo / "shared.txt"
        shared.write_text(track_id, encoding="utf-8")
        state_path = repo / f"config/world_packs/parallel/workstreams/{track_id}.v1.json"
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(
            json.dumps(
                {
                    "schema": controller.STATE_SCHEMA,
                    "controller_id": config["controller_id"],
                    "track_id": track_id,
                    "branch": branch,
                    "controller_base_sha": control_sha,
                    "status": "IN_PROGRESS",
                    "completed_milestones": [],
                    "blockers": [],
                    "next_action": "continue",
                    "last_checkpoint_head": None,
                    "tested_head": None,
                    "validation": [],
                    "updated_at_utc": "2026-09-05T00:00:00Z",
                    "notes": [],
                }
            ),
            encoding="utf-8",
        )
        git(repo, "add", ".")
        git(repo, "commit", "-m", track_id)

    monkeypatch.setattr(controller, "ROOT", repo)
    snapshot = controller.collect(config)

    assert snapshot["controller_head"] == control_sha
    records = {record["id"]: record for record in snapshot["tracks"]}
    assert records["WP-A"]["ahead"] == 1
    assert records["WP-A"]["behind"] == 0
    assert "shared.txt" in records["WP-A"]["scope_violations"]
    assert "shared.txt" in records["WP-B"]["scope_violations"]
    assert snapshot["overlaps"] == [{"left": "WP-A", "right": "WP-B", "files": ["shared.txt"]}]
