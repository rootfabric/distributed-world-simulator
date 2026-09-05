"""Authority and failure-isolation regressions for the read-only overview."""
from __future__ import annotations

import io
import json
import sys
import unittest
from contextlib import ExitStack, redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness import cli, project_overview as overview
from harness.checkpoint_planner import _enforce_runtime_mutation_lease
from harness.mission import load_checkpoint_acceptance
from harness.contracts import ContractValidationError
from tests.harness.test_harness_checkpoint_session import make_state


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

    def test_candidate_rejects_changed_or_missing_observed_main(self):
        registry = json.loads((ROOT / overview.REGISTRY).read_text())
        observed = registry["coordination"]["observed_main"]
        canonical = "b" * 40
        original_git = overview._git
        original_read = overview.read_control

        def git(root, *args):
            if args == ("rev-parse", "origin/main"):
                return 0, canonical
            return original_git(root, *args)

        def read(root, path, ref):
            if path == overview.REGISTRY:
                return registry
            return original_read(root, path, None)

        for value in (observed, None):
            with self.subTest(observed=value), ExitStack() as stack:
                registry["coordination"]["observed_main"] = value
                stack.enter_context(patch.object(overview, "_canonical_ref", return_value="origin/main"))
                stack.enter_context(patch.object(overview, "_git", side_effect=git))
                stack.enter_context(patch.object(overview, "read_control", side_effect=read))
                stack.enter_context(patch.object(overview, "load_checkpoint_acceptance", return_value=None))
                code, result = self.invoke("check-consistency", "--candidate")
            self.assertEqual(3, code)
            findings = result["overview"]["consistency_findings"]
            self.assertTrue(any(item["code"] == "CANDIDATE_MAIN_DRIFT"
                                and item["scope"] == "product_blocking" for item in findings))
            self.assertFalse(result["overview"]["runtime_authorized"])

    def test_canonical_snapshot_keeps_observed_main_as_historical_provenance(self):
        original_read = overview.read_control
        with ExitStack() as stack:
            stack.enter_context(patch.object(overview, "_canonical_ref", return_value="origin/main"))
            stack.enter_context(patch.object(overview, "_git", return_value=(0, "b" * 40)))
            stack.enter_context(patch.object(overview, "read_control",
                                       side_effect=lambda root, path, ref: original_read(root, path, None)))
            stack.enter_context(patch.object(overview, "load_checkpoint_acceptance", return_value=None))
            result = overview.project_overview(ROOT)
        self.assertFalse(any(item["code"] == "CANDIDATE_MAIN_DRIFT"
                             for item in result["consistency_findings"]))
        self.assertFalse(result["provenance"]["candidate_preview"])
        self.assertFalse(result["runtime_authorized"])

    def test_role_handoff_is_derived_from_execution_not_parent_acceptance(self):
        route = self.route(overview.P7, None)
        execution = ROOT / "config/control/harness/executions/E2026-08-30-V0-P7-R1"
        for work_type in ("REVIEW", "VALIDATION"):
            for state_name, expected in (("VERIFIED", 0), ("IN_PROGRESS", 7)):
                with self.subTest(work_type=work_type, state=state_name), ExitStack() as stack:
                    state = make_state(state_name=state_name)
                    state["active_work_order"].update(goal_checkpoint=overview.P7, work_order_type=work_type)
                    stack.enter_context(patch.object(cli, "canonical_reconciliation_route", return_value=route))
                    stack.enter_context(patch.object(cli, "resolve_execution", return_value=(execution, overview.P7)))
                    build = stack.enter_context(patch.object(cli, "build_state", return_value=state))
                    stack.enter_context(patch.object(cli, "load_checkpoint_acceptance", return_value=None))
                    code, result = self.invoke("close-role", "--execution", str(execution))
                self.assertEqual(expected, code)
                build.assert_called_once_with(ROOT, execution)
                self.assertEqual(expected == 0, result["control_route"]["role_exit_allowed"])
                self.assertFalse(result["control_route"]["mission_exit_allowed"])
                self.assertFalse(result["control_route"]["mission_complete"])
                self.assertFalse(result["runtime_authorized"])

    def test_close_role_cannot_use_a_stale_epoch_to_claim_handoff(self):
        route = self.route(overview.P7, None)
        execution = ROOT / "config/control/harness/executions/E2026-08-30-V0-P7-R1"
        with ExitStack() as stack:
            stack.enter_context(patch.object(cli, "canonical_reconciliation_route", return_value=route))
            stack.enter_context(patch.object(cli, "resolve_execution", return_value=(execution, overview.P7)))
            stack.enter_context(patch.object(cli, "build_state", side_effect=ContractValidationError(
                "EPOCH_REGISTRY_GENERATION_MISMATCH")))
            code, result = self.invoke("close-role", "--execution", str(execution))
        self.assertEqual(3, code)
        self.assertEqual("EPOCH_REGISTRY_GENERATION_MISMATCH", result["error"]["detail"])

    def test_role_exit_and_mission_exit_flags_are_not_interchangeable(self):
        for role_allowed, mission_allowed, role_code, mission_code in (
            (True, False, 0, 8), (False, True, 7, 0),
        ):
            route = {"role_exit_allowed": role_allowed, "mission_exit_allowed": mission_allowed}
            for command, expected in (("CLOSE_ROLE", role_code), ("CLOSE_MISSION", mission_code)):
                with self.subTest(command=command, route=route), redirect_stdout(io.StringIO()):
                    self.assertEqual(expected, cli._emit_control_route(command, route))

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
