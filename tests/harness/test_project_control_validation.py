"""Reviewer R2 regressions using isolated Git trees, never remote authority."""
from __future__ import annotations

import importlib.metadata
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness import cli, control_candidate_validation as validation, project_overview as overview
from harness.contracts import ContractValidationError


class ProjectControlValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="dws-control-validation-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name) / "repo"
        subprocess.run(["git", "clone", "--shared", "--quiet", str(ROOT), str(cls.root)],
                       check=True, capture_output=True, text=True)
        cls.base = cls.git("rev-parse", "HEAD")

    @classmethod
    def git(cls, *args):
        return subprocess.check_output([
            "git", "-c", "user.name=Control test fixture", "-c", "user.email=fixture@example.invalid", *args,
        ], cwd=cls.root, text=True, stderr=subprocess.PIPE).strip()

    def setUp(self):
        self.git("reset", "--hard", self.base)
        self.git("clean", "-fd")
        self.git("update-ref", "refs/remotes/origin/main", self.base)

    def read(self, path):
        return json.loads((self.root / path).read_text())

    def commit(self, files, *, canonical=False):
        for path, value in files.items():
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(value if isinstance(value, str) else json.dumps(value, indent=2) + "\n")
            self.git("add", "--", path)
        self.git("commit", "-qm", "test-only control snapshot")
        head = self.git("rev-parse", "HEAD")
        if canonical:
            self.git("update-ref", "refs/remotes/origin/main", head)
        return head

    def invoke(self, mode="drive"):
        output = io.StringIO()
        with redirect_stdout(output):
            code = cli.main([mode, "--root", str(self.root)])
        return code, json.loads(output.getvalue())

    def validate(self, **kwargs):
        with redirect_stdout(io.StringIO()):
            return validation.validate_control(self.root, **kwargs)

    def assert_route_rejected_before_acceptance(self, expected):
        with patch.object(overview, "load_checkpoint_acceptance", side_effect=AssertionError("Invalid control cannot accept")):
            code, result = self.invoke()
        self.assertEqual(3, code, result)
        self.assertIn(expected, result["error"]["detail"])

    def test_valid_hold_routes_without_loading_obsolete_execution(self):
        with patch.object(cli, "build_state", side_effect=AssertionError("Obsolete execution must not load")):
            code, result = self.invoke()
        self.assertEqual(0, code, result)
        self.assertEqual(self.base, result["control_route"]["canonical_head"])
        self.assertFalse(result["runtime_authorized"])
        self.assertEqual("DIRECTOR", result["control_route"]["next_actor"])
        code, result = self.invoke("close-mission")
        self.assertEqual(8, code, result)

    def test_all_held_modes_require_pinned_dependency(self):
        for mode in ("status", "plan", "resume", "drive", "close-mission"):
            with self.subTest(mode=mode), patch("harness.contracts.importlib.metadata.version",
                    side_effect=importlib.metadata.PackageNotFoundError("jsonschema")):
                code, result = self.invoke(mode)
            self.assertEqual(3, code, result)
            self.assertIn("PINNED_DEPENDENCY_MISSING", result["error"]["detail"])

    def test_wrong_dependency_version_is_not_a_successful_route(self):
        with patch("harness.contracts.importlib.metadata.version", return_value="0.0.0"):
            self.assert_route_rejected_before_acceptance("PINNED_DEPENDENCY_VERSION_REQUIRED")

    def test_canonical_lease_generation_mismatch_blocks_route(self):
        scheduler = self.read(validation.SCHEDULER)
        scheduler["pre_h0_3_runtime_mutation_lease"]["effective_registry_generation"] -= 1
        self.commit({validation.SCHEDULER: scheduler}, canonical=True)
        self.assert_route_rejected_before_acceptance("LEASE_GENERATION_MISMATCH")

    def test_canonical_contract_integrity_blocks_route(self):
        goals = self.read(overview.GOALS)
        goals["harness_revision"] = "invalid-test-revision"
        self.commit({overview.GOALS: goals}, canonical=True)
        self.assert_route_rejected_before_acceptance("HARNESS_REVISION_MISMATCH")

    def test_canonical_invalid_schema_blocks_route(self):
        path = "config/control/harness/event.schema.v1.json"
        schema = self.read(path)
        schema["type"] = "invalid-test-type"
        self.commit({path: schema}, canonical=True)
        self.assert_route_rejected_before_acceptance("JSON_SCHEMA_INVALID")

    def test_canonical_product_mirror_blocks_route(self):
        train = self.read(overview.TRAIN)
        train["current_phase"] = "invalid-test-phase"
        self.commit({overview.TRAIN: train}, canonical=True)
        self.assert_route_rejected_before_acceptance("CURRENT_PHASE_MISMATCH")

    def test_canonical_control_ignores_dirty_candidate_override(self):
        (self.root / overview.GOALS).write_text('{"invalid":true}\n')
        code, result = self.invoke()
        self.assertEqual(0, code, result)
        self.assertEqual(self.base, result["control_route"]["canonical_head"])

    def test_research_local_evidence_failure_does_not_block_product_route(self):
        registry = self.read(validation.REGISTRY)
        tracks = registry["coordination"]["lanes"]["ECO"]["tracks"]
        next(iter(tracks.values()))["evidence_paths"] = ["docs/control/test-only-missing-evidence.md"]
        self.commit({validation.REGISTRY: registry}, canonical=True)
        code, result = self.invoke()
        self.assertEqual(0, code, result)
        self.assertFalse(result["runtime_authorized"])

    def test_registry_change_requires_generation_advance(self):
        registry = self.read(validation.REGISTRY)
        registry["control_checkpoint"] = "test-only changed registry"
        self.commit({validation.REGISTRY: registry})
        with self.assertRaisesRegex(ContractValidationError, "REGISTRY_GENERATION_ADVANCE_REQUIRED"):
            self.validate()

    def test_scheduler_change_requires_generation_advance(self):
        scheduler = self.read(validation.SCHEDULER)
        scheduler["test_only_change"] = True
        self.commit({validation.SCHEDULER: scheduler})
        with self.assertRaisesRegex(ContractValidationError, "REGISTRY_GENERATION_ADVANCE_REQUIRED"):
            self.validate()

    def test_generation_advance_requires_matching_lease(self):
        registry = self.read(validation.REGISTRY)
        registry["registry_generation"] += 1
        self.commit({validation.REGISTRY: registry})
        with self.assertRaisesRegex(ContractValidationError, "REGISTRY_LEASE_GENERATION_MISMATCH"):
            self.validate()

    def test_generation_advance_with_matching_lease_is_valid(self):
        registry, scheduler = self.read(validation.REGISTRY), self.read(validation.SCHEDULER)
        registry["registry_generation"] += 1
        scheduler["pre_h0_3_runtime_mutation_lease"]["effective_registry_generation"] = registry["registry_generation"]
        self.commit({validation.REGISTRY: registry, validation.SCHEDULER: scheduler})
        self.assertEqual(registry["registry_generation"], self.validate()["registry_generation"])

    def test_generation_rollback_is_invalid(self):
        registry, scheduler = self.read(validation.REGISTRY), self.read(validation.SCHEDULER)
        registry["registry_generation"] -= 1
        scheduler["pre_h0_3_runtime_mutation_lease"]["effective_registry_generation"] = registry["registry_generation"]
        self.commit({validation.REGISTRY: registry, validation.SCHEDULER: scheduler})
        with self.assertRaisesRegex(ContractValidationError, "REGISTRY_GENERATION_ROLLBACK"):
            self.validate()

    def test_boolean_is_not_a_generation(self):
        registry = self.read(validation.REGISTRY)
        registry["registry_generation"] = True
        self.commit({validation.REGISTRY: registry})
        with self.assertRaisesRegex(ContractValidationError, "REGISTRY_GENERATION_INVALID"):
            self.validate()

    def test_docs_only_commit_keeps_valid_generation(self):
        self.commit({"docs/control/test-only-note.md": "No control state changed.\n"})
        self.assertEqual(self.read(validation.REGISTRY)["registry_generation"], self.validate()["registry_generation"])

    def test_post_merge_push_checks_new_duplicate_json(self):
        self.commit({"config/control/harness/test-only-evidence.json": '{"subject":1,"subject":2}\n'}, canonical=True)
        with self.assertRaisesRegex(ContractValidationError, "JSON_DUPLICATE_KEY"):
            self.validate(event_name="push", event={"ref": "refs/heads/main", "before": self.base})

    def test_post_merge_push_checks_generation_against_before(self):
        registry = self.read(validation.REGISTRY)
        registry["control_checkpoint"] = "test-only changed registry"
        self.commit({validation.REGISTRY: registry}, canonical=True)
        with self.assertRaisesRegex(ContractValidationError, "REGISTRY_GENERATION_ADVANCE_REQUIRED"):
            self.validate(event_name="push", event={"ref": "refs/heads/main", "before": self.base})

    def test_post_merge_push_checks_new_schema(self):
        self.commit({"config/control/harness/test-only.schema.json": {
            "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "invalid-test-type",
        }}, canonical=True)
        from jsonschema.exceptions import SchemaError
        with self.assertRaises(SchemaError):
            self.validate(event_name="push", event={"ref": "refs/heads/main", "before": self.base})

    def test_initial_push_enumerates_current_control_json(self):
        path = "config/control/harness/test-only-evidence.json"
        self.commit({path: {"initial_push": True}}, canonical=True)
        base = validation.comparison_base(self.root, "push", {"ref": "refs/heads/main", "before": "0" * 40})
        self.assertIsNone(base)
        self.assertIn(path, validation.changed_paths(self.root, base))

    def test_push_without_before_uses_first_parent(self):
        self.commit({"docs/control/test-only-note.md": "Parent fallback.\n"}, canonical=True)
        self.assertEqual(self.base, validation.comparison_base(self.root, "push", {"ref": "refs/heads/main"}))

    def test_manual_and_schedule_use_pinned_canonical_main(self):
        for event_name in ("workflow_dispatch", "schedule", "pull_request"):
            with self.subTest(event_name=event_name):
                self.assertEqual(self.base, validation.comparison_base(self.root, event_name, {}))

    def test_invalid_push_before_fails_closed(self):
        for before in ("not-a-sha", 42, "1" * 40):
            with self.subTest(before=before), self.assertRaises(ContractValidationError):
                validation.comparison_base(self.root, "push", {"ref": "refs/heads/main", "before": before})


if __name__ == "__main__":
    unittest.main()
