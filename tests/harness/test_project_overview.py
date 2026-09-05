"""Authority and failure-isolation regressions for the read-only overview."""
from __future__ import annotations

import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness import cli, project_overview as overview
from harness.checkpoint_planner import _enforce_runtime_mutation_lease
from harness.mission import load_checkpoint_acceptance


class ProjectOverviewTests(unittest.TestCase):
    def invoke(self, *args):
        output = io.StringIO()
        with redirect_stdout(output):
            code = cli.main([*args, "--root", str(ROOT)])
        return code, json.loads(output.getvalue())

    def test_candidate_overview_never_loads_or_dispatches_execution(self):
        with patch.object(cli, "project_overview", return_value={"consistency_findings": []}) as report:
            with patch.object(cli.ContractBundle, "load", side_effect=AssertionError("Execution dependency")):
                code, value = self.invoke("overview", "--candidate")
        self.assertEqual(0, code)
        self.assertEqual("PROJECT_OVERVIEW", value["output_kind"])
        report.assert_called_once_with(ROOT, candidate=True)

    def test_candidate_cannot_override_drive_authority(self):
        with patch.object(cli, "canonical_reconciliation_route", side_effect=AssertionError("Must reject first")):
            code, value = self.invoke("drive", "--candidate")
        self.assertEqual(2, code)
        self.assertEqual("INVALID_INVOCATION", value["error"]["code"])

    def test_research_findings_do_not_become_product_exit_gate(self):
        research = {"severity": "ERROR", "scope": "family_local:ECO", "code": "EVIDENCE_MISSING_AT_PIN"}
        with patch.object(cli, "project_overview", return_value={"consistency_findings": [research]}):
            code, value = self.invoke("check-consistency")
        self.assertEqual(0, code)
        self.assertEqual([research], value["overview"]["consistency_findings"])
        with patch.object(cli, "project_overview", return_value={"consistency_findings": [{**research, "scope": "product_blocking"}]}):
            code, _ = self.invoke("check-consistency")
        self.assertEqual(3, code)

    def route(self, checkpoint, accepted):
        scheduler = {"v0_product_train_routing": {"current_phase": overview.HOLD,
            "current_checkpoint": overview.P7, "next_runtime_checkpoint": "MVP"}}
        with patch.object(overview, "_canonical_ref", return_value="origin/main"):
            with patch.object(overview, "_git", return_value=(0, "a" * 40)):
                with patch.object(overview, "read_control", return_value=scheduler):
                    with patch.object(overview, "load_checkpoint_acceptance", return_value=accepted) as lookup:
                        result = overview.canonical_reconciliation_route(ROOT, checkpoint)
        if checkpoint in (overview.P7, "MVP", None):
            lookup.assert_called_once_with(ROOT, overview.P7, "main", canonical_head="a" * 40)
        return result

    def test_accepted_p7_can_close_without_accepting_successor(self):
        accepted = {"status": "ACCEPTED", "checkpoint": overview.P7}
        for checkpoint, expected_code in ((overview.P7, 0), ("MVP", 8)):
            with self.subTest(checkpoint=checkpoint):
                route = self.route(checkpoint, accepted)
                with patch.object(cli, "canonical_reconciliation_route", return_value=route):
                    with patch.object(cli.ContractBundle, "load", side_effect=AssertionError("Stale epoch must not load")):
                        code, value = self.invoke("close-mission", "--checkpoint", checkpoint)
                self.assertEqual(expected_code, code)
                self.assertFalse(value["runtime_authorized"])
                self.assertEqual(checkpoint == overview.P7, value["control_route"]["mission_complete"])

    def test_missing_acceptance_routes_director_and_forbids_close(self):
        route = self.route(overview.P7, None)
        self.assertEqual("RECONCILE_P7_DURABLE_CLOSURE", route["next_action"])
        with patch.object(cli, "canonical_reconciliation_route", return_value=route):
            code, _ = self.invoke("close-mission")
        self.assertEqual(8, code)
        self.assertIsNone(self.route("ECO_DIAGNOSTIC", None))

    def test_same_holder_cannot_use_old_dispatch_to_ignore_runtime_hold(self):
        scheduler = {"pre_h0_3_runtime_mutation_lease": {"capacity": 1,
            "mutating_states": ["DISPATCHED"], "holder_checkpoint": overview.P7, "holder_branch": "runtime"},
            "v0_product_train_routing": {"current_checkpoint": overview.P7, "runtime_mutation_allowed_now": False}}
        with self.assertRaisesRegex(ValueError, "PRODUCT_RUNTIME_MUTATION_ON_HOLD"):
            _enforce_runtime_mutation_lease(scheduler, {"goal_checkpoint": overview.P7, "branch": "runtime"}, "DISPATCHED")

    def test_acceptance_lookup_uses_pinned_main_tree_and_blobs(self):
        calls = []
        def git(root, *args):
            calls.append(args)
            if args[0] == "ls-tree":
                return 0, "config/control/harness/acceptance/p7.json"
            if args[0] == "show":
                return 0, json.dumps({"checkpoint": overview.P7, "status": "ACCEPTED", "accepted_runtime_head": "b" * 40})
            return 0, ""
        with patch("harness.mission._canonical_ref", return_value="origin/main"):
            with patch("harness.mission._git", side_effect=git):
                result = load_checkpoint_acceptance(ROOT, overview.P7, "main", canonical_head="a" * 40)
        self.assertEqual("a" * 40, result["canonical_head"])
        self.assertTrue(any(call[0] == "show" and call[1].startswith("a" * 40 + ":") for call in calls))


if __name__ == "__main__":
    unittest.main()
