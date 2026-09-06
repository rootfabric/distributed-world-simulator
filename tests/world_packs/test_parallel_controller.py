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


# --- R2-A regression fixtures -------------------------------------------------


def build_campaign_repo(tmp_path: Path, monkeypatch):
    """Create a minimal repo: main -> execution base -> controller -> worker track."""
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

    git(repo, "switch", "-c", "work/a")
    (repo / "a").mkdir()
    (repo / "a" / "impl.txt").write_text("implementation\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "impl")
    impl_sha = git(repo, "rev-parse", "HEAD")

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
        "critical_main_watched_paths": ["scripts/simulation/matter/**"],
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
                "allowed_paths": ["a/**", "config/world_packs/parallel/workstreams/WP-A.v1.json", "docs/world_packs/evidence/WP-A*"],
                "milestones": ["ONE"],
                "first_action": "one",
            }
        ],
        "queued_integration": {
            "id": "JOIN",
            "requires_tracks": ["WP-A"],
            "requires_gates": [],
            "next_when_ready": "join",
        },
        "external_gates": [],
    }
    monkeypatch.setattr(controller, "ROOT", repo)
    return repo, config, {"main": main_sha, "base": base_sha, "control": control_sha, "impl": impl_sha}


def state_path_of(repo: Path) -> Path:
    return repo / "config/world_packs/parallel/workstreams/WP-A.v1.json"


def commit_state(repo: Path, state: dict) -> str:
    path = state_path_of(repo)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "state update")
    return git(repo, "rev-parse", "HEAD")


def ready_state(config: dict, shas: dict, validation_head: str | None, tested_head: str | None) -> dict:
    state = {
        "schema": controller.STATE_SCHEMA,
        "controller_id": config["controller_id"],
        "track_id": "WP-A",
        "branch": "work/a",
        "controller_base_sha": shas["control"],
        "status": "READY_FOR_INTEGRATION",
        "completed_milestones": ["ONE"],
        "blockers": [],
        "next_action": "await review",
        "last_checkpoint_head": shas["impl"],
        "tested_head": tested_head,
        "validation": (
            [
                {
                    "name": "focused",
                    "command": "python -m pytest -q tests/world_packs",
                    "result": "PASS",
                    "head": validation_head,
                }
            ]
            if validation_head
            else []
        ),
        "updated_at_utc": "2026-09-06T00:00:00Z",
        "notes": [],
    }
    return state


def test_ready_without_pass_at_tested_head_fails(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    commit_state(repo, ready_state(config, shas, validation_head=shas["control"], tested_head=shas["impl"]))
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert "EXACT_TESTED_HEAD_VALIDATION_MISSING" in record["state_errors"]
    assert record["ready"] is False


def test_ready_with_pass_at_old_head_fails(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    # PASS recorded at a pre-implementation head, tested_head points at implementation.
    commit_state(repo, ready_state(config, shas, validation_head=shas["base"], tested_head=shas["impl"]))
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert "EXACT_TESTED_HEAD_VALIDATION_MISSING" in record["state_errors"]
    assert record["ready"] is False


def test_ready_with_pass_at_tested_head_plus_evidence_commits_passes(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=shas["impl"], tested_head=shas["impl"])
    state_head = commit_state(repo, state)
    # Evidence-only commits after tested_head are allowed.
    evidence = repo / "docs/world_packs/evidence/WP-A_notes.md"
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text("evidence\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "evidence")
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert record["state_errors"] == []
    assert record["validation_stale"] is False
    assert record["ready"] is True
    assert record["head"] != state_head  # head moved but only via exempt paths


def test_implementation_change_after_tested_head_is_stale(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=shas["impl"], tested_head=shas["impl"])
    commit_state(repo, state)
    (repo / "a" / "impl.txt").write_text("changed implementation\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "more implementation")
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert record["validation_stale"] is True
    assert "VALIDATION_STALE" in record["state_errors"]
    assert record["ready"] is False


def test_review_pass_on_old_head_is_review_stale(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=shas["impl"], tested_head=shas["impl"])
    reviewed_head = commit_state(repo, state)
    state["review_verdict"] = "PASS"
    state["reviewed_head"] = reviewed_head
    state["reviewed_tested_head"] = shas["impl"]
    state["reviewer_evidence"] = ["docs/world_packs/evidence/WP-A_review.md"]
    commit_state(repo, state)
    # Runtime/presentation implementation change after the review.
    (repo / "a" / "impl.txt").write_text("post-review implementation\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "post-review implementation")
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert "REVIEW_STALE" in record["state_errors"]
    assert record["ready"] is False


def test_review_pass_on_current_head_keeps_track_ready(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=shas["impl"], tested_head=shas["impl"])
    reviewed_head = commit_state(repo, state)
    state["review_verdict"] = "PASS"
    state["reviewed_head"] = reviewed_head
    state["reviewed_tested_head"] = shas["impl"]
    state["reviewer_evidence"] = ["docs/world_packs/evidence/WP-A_review.md"]
    final_head = commit_state(repo, state)
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert record["state_errors"] == []
    assert record["ready"] is True
    assert record["head"] == final_head


def test_prose_sha_in_next_action_is_not_authority(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=None, tested_head=None)
    # next_action prose names the "reviewed" SHA; controller must not trust it.
    state["next_action"] = f"review exact HEAD {shas['impl']} and integrate"
    commit_state(repo, state)
    snapshot = controller.collect(config)
    record = snapshot["tracks"][0]
    assert "EXACT_TESTED_HEAD_VALIDATION_MISSING" in record["state_errors"]
    assert record["ready"] is False


def test_noncritical_main_movement_is_advisory(tmp_path: Path, monkeypatch):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=shas["impl"], tested_head=shas["impl"])
    commit_state(repo, state)
    # Non-watched harness/git-transport policy file moves on main.
    git(repo, "switch", "main")
    (repo / ".github").mkdir()
    (repo / ".github" / "workflow-policy.md").write_text("git transport policy\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "harness git transport policy")
    git(repo, "switch", "work/a")
    snapshot = controller.collect(config)
    assert snapshot["main_movement"] == "MAIN_MOVED_NONCRITICAL"
    assert snapshot["critical_main_drift"] == []
    record = snapshot["tracks"][0]
    # Advisory only: does not by itself invalidate the track.
    assert record["ready"] is True


def test_critical_matter_main_movement_blocks_integration(tmp_path: Path, monkeypatch, capsys):
    repo, config, shas = build_campaign_repo(tmp_path, monkeypatch)
    state = ready_state(config, shas, validation_head=shas["impl"], tested_head=shas["impl"])
    commit_state(repo, state)
    git(repo, "switch", "main")
    matter = repo / "scripts/simulation/matter"
    matter.mkdir(parents=True)
    (matter / "matter_data.gd").write_text("changed\n", encoding="utf-8")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "matter movement")
    git(repo, "switch", "work/a")
    snapshot = controller.collect(config)
    assert snapshot["main_movement"] == "CRITICAL_MAIN_DRIFT"
    assert "scripts/simulation/matter/matter_data.gd" in snapshot["critical_main_drift"]
    controller.print_next(config, snapshot)
    output = capsys.readouterr().out
    assert "critical main drift requires review" in output
    assert "[JOIN] WAIT" in output
