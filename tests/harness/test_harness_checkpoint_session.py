from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.continuation import build_continuation
from harness.execution_selector import default_checkpoint, resolve_execution
from harness.mission import load_checkpoint_acceptance, mission_from_state
from harness.git_authority import build_git_authority

POLICY = {
    "self_closing_execution": {
        "max_same_defect_fix_required_events_before_takeover": 3,
    }
}


def make_state(
    state_name: str = "VERIFIED",
    *,
    blockers: list[str] | None = None,
    findings: list[str] | None = None,
    review_state: str = "PASS",
    acceptance: dict | None = None,
    repair_count: int = 0,
    attention: list[dict] | None = None,
    hard_block_proof: dict | None = None,
    local_handoff: dict | None = None,
) -> dict:
    value = {
        "active_work_order": {
            "work_order_id": "V0-P5-R1-WO-001",
            "goal_checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "work_order_type": "IMPLEMENTATION",
            "review_required": True,
            "human_approval_required_for": ["RUNTIME_FEATURE_MERGE"],
        },
        "reduced_work_order": {
            "state": state_name,
            "work_order_id": "V0-P5-R1-WO-001",
        },
        "review": {
            "post_build_state": review_state,
            "review_target_head_sha": "a" * 40,
        },
        "repository": {"implementation_head_sha": "a" * 40},
        "checkpoint_blockers": blockers or [],
        "findings": findings or [],
        "repair": {"same_defect_fix_required_count": repair_count},
        "human_attention": {"open_items": attention or []},
        "local_execution": {
            "active_handoff": local_handoff,
            "all_handoffs": [local_handoff] if local_handoff else [],
        },
        "checkpoint_acceptance": acceptance,
    }
    if hard_block_proof is not None:
        value["hard_block_proof"] = hard_block_proof
    return value


class CheckpointSessionContinuationTests(unittest.TestCase):
    def test_role_boundary_never_closes_checkpoint_mission(self) -> None:
        result = build_continuation(make_state(review_state="MISSING"), POLICY)
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("REVIEWER", result["next_actor"])
        self.assertTrue(result["role_exit_allowed"])
        self.assertFalse(result["mission_exit_allowed"])
        self.assertFalse(result["session_exit_allowed"])
        self.assertTrue(result["mission_driver_required"])

    def test_review_fail_routes_repair_without_closing_parent_session(self) -> None:
        result = build_continuation(make_state(review_state="FAIL"), POLICY)
        self.assertEqual("IMPLEMENTER", result["next_actor"])
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertTrue(result["role_exit_allowed"])
        self.assertFalse(result["mission_exit_allowed"])

    def test_automatable_fix_required_cannot_close_role_or_mission(self) -> None:
        result = build_continuation(make_state(state_name="FIX_REQUIRED"), POLICY)
        self.assertEqual("CONTINUE_SAME_ROLE", result["handoff_class"])
        self.assertEqual("IMPLEMENTER", result["next_actor"])
        self.assertFalse(result["role_exit_allowed"])
        self.assertFalse(result["mission_exit_allowed"])
        self.assertTrue(result["closure_loop_required"])

    def test_repeated_defect_takeover_rotates_role_not_mission(self) -> None:
        result = build_continuation(
            make_state(state_name="FIX_REQUIRED", repair_count=3), POLICY
        )
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertTrue(result["role_exit_allowed"])
        self.assertFalse(result["mission_exit_allowed"])

    def test_planned_checkpoint_work_cannot_end_session(self) -> None:
        result = build_continuation(make_state(state_name="PLANNED"), POLICY)
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertEqual("DISPATCH_ACTIVE_WORK_ORDER", result["next_action"])
        self.assertFalse(result["role_exit_allowed"])
        self.assertFalse(result["mission_exit_allowed"])

    def test_generic_checkpoint_predicates_do_not_deadlock_implemented_role(self) -> None:
        result = build_continuation(
            make_state(
                state_name="IMPLEMENTED",
                blockers=["REQUIRED_PREDICATES_INCOMPLETE"],
                review_state="MISSING",
            ),
            POLICY,
        )
        self.assertEqual("REVIEWER", result["next_actor"])
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertTrue(result["role_exit_allowed"])
        self.assertFalse(result["mission_exit_allowed"])

    def test_explicit_implementer_validation_incomplete_stays_with_implementer(self) -> None:
        state = make_state(
            state_name="IMPLEMENTED",
            blockers=["REQUIRED_PREDICATES_INCOMPLETE"],
            review_state="MISSING",
        )
        state["implementation_validation"] = {"complete": False}
        result = build_continuation(state, POLICY)
        self.assertEqual("IMPLEMENTER", result["next_actor"])
        self.assertEqual("CONTINUE_SAME_ROLE", result["handoff_class"])
        self.assertFalse(result["role_exit_allowed"])

    def test_checkpoint_proposed_without_acceptance_remains_open(self) -> None:
        result = build_continuation(make_state(state_name="CHECKPOINT_PROPOSED"), POLICY)
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertFalse(result["mission_complete"])
        self.assertFalse(result["mission_exit_allowed"])

    def test_blocked_state_alone_is_not_a_terminal(self) -> None:
        result = build_continuation(make_state(state_name="BLOCKED"), POLICY)
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertFalse(result["hard_blocked"])
        self.assertFalse(result["mission_exit_allowed"])

    def test_proven_non_automatable_block_is_a_terminal(self) -> None:
        result = build_continuation(
            make_state(
                state_name="BLOCKED",
                hard_block_proof={
                    "proven_non_automatable": True,
                    "resume_condition": "EXTERNAL_DEPENDENCY_AVAILABLE",
                },
            ),
            POLICY,
        )
        self.assertTrue(result["hard_blocked"])
        self.assertTrue(result["mission_exit_allowed"])
        self.assertEqual("SYSTEM_BLOCKED", result["handoff_class"])

    def test_waiting_human_is_a_valid_session_terminal(self) -> None:
        result = build_continuation(make_state(state_name="WAITING_HUMAN"), POLICY)
        self.assertTrue(result["human_decision_required"])
        self.assertTrue(result["mission_exit_allowed"])


    def test_nonterminal_terminal_report_forbids_final_response(self) -> None:
        result = build_continuation(make_state(state_name="FIX_REQUIRED"), POLICY)
        report = result["terminal_report"]
        self.assertFalse(report["work_finished"])
        self.assertEqual("NOT_FINISHED", report["status"])
        self.assertFalse(report["final_response_allowed"])
        self.assertEqual("CONTINUE_CURRENT", report["next_step_kind"])

    def test_mission_complete_terminal_report_is_finished(self) -> None:
        acceptance = {
            "checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "status": "ACCEPTED",
            "path": "config/control/harness/acceptance/P5.v1.json",
        }
        result = build_continuation(make_state(acceptance=acceptance), POLICY)
        report = result["terminal_report"]
        self.assertTrue(report["work_finished"])
        self.assertEqual("FINISHED", report["status"])
        self.assertTrue(report["final_response_allowed"])
        self.assertEqual("NEXT_CHECKPOINT", report["next_step_kind"])

    def test_durable_local_handoff_is_not_finished_terminal(self) -> None:
        local_handoff = {
            "handoff_id": "P5-UBUNTU-VERIFY-001",
            "source_branch": "feature/test",
            "source_head_sha": "a" * 40,
            "target_environment": "UBUNTU_GODOT_DOUBLE",
            "purpose": "Run exact-head Ubuntu verification.",
            "requirements": ["Fresh detached worktree"],
            "commands": ["python -m unittest tests.harness.test_harness_checkpoint_session"],
            "success_criteria": ["exit code 0"],
            "failure_criteria": ["non-zero exit code"],
            "required_evidence": ["exact HEAD", "command output"],
            "evidence_sink": "config/control/harness/executions/E/evidence/local.json",
            "resume_condition": "LOCAL_VERIFICATION_RECORDED_DURABLY",
            "next_action_on_pass": "Resume checkpoint closure.",
            "next_action_on_fail": "Route FIX_REQUIRED.",
            "path": "config/control/harness/executions/E/handoffs/P5-UBUNTU-VERIFY-001.v1.json",
        }
        result = build_continuation(make_state(local_handoff=local_handoff), POLICY)
        self.assertEqual("LOCAL_EXECUTION_REQUIRED", result["handoff_class"])
        self.assertTrue(result["mission_exit_allowed"])
        self.assertTrue(result["local_execution_required"])
        report = result["terminal_report"]
        self.assertFalse(report["work_finished"])
        self.assertEqual("NOT_FINISHED", report["status"])
        self.assertTrue(report["final_response_allowed"])
        self.assertEqual("LOCAL_EXECUTION", report["next_step_kind"])
        self.assertEqual(local_handoff["path"], report["git_handoff_path"])
        self.assertEqual(
            "P5-UBUNTU-VERIFY-001",
            report["local_agent_instruction"]["handoff_id"],
        )

    def test_role_boundary_property_never_authorizes_parent_session_exit(self) -> None:
        states = [
            "IMPLEMENTED", "VERIFIED", "AUDITED", "CHECKPOINT_PROPOSED",
            "EPOCH_INVALIDATED", "CANCELLED", "BLOCKED",
        ]
        review_states = ["MISSING", "STALE", "FAIL", "INSUFFICIENT_EVIDENCE", "PASS"]
        blocker_sets = [[], ["EVIDENCE_MAP_MISSING"], ["REQUIRED_PREDICATES_INCOMPLETE"]]
        for state_name in states:
            for review_state in review_states:
                for blockers in blocker_sets:
                    result = build_continuation(
                        make_state(
                            state_name=state_name,
                            review_state=review_state,
                            blockers=blockers,
                        ),
                        POLICY,
                    )
                    if result["handoff_class"] == "ROLE_BOUNDARY":
                        self.assertFalse(
                            result["mission_exit_allowed"],
                            (state_name, review_state, blockers, result),
                        )
                        self.assertFalse(result["session_exit_allowed"])
                        self.assertTrue(result["mission_driver_required"])

    def test_canonical_acceptance_is_the_only_success_terminal(self) -> None:
        acceptance = {
            "checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "status": "ACCEPTED",
            "path": "config/control/harness/acceptance/P5.v1.json",
        }
        result = build_continuation(make_state(acceptance=acceptance), POLICY)
        self.assertTrue(result["mission_complete"])
        self.assertTrue(result["mission_exit_allowed"])
        self.assertEqual("MISSION_COMPLETE", result["handoff_class"])
        self.assertEqual("NONE", result["next_actor"])

    def test_declared_mission_metadata_survives_role_rotation(self) -> None:
        state = make_state(review_state="MISSING")
        state["active_work_order"]["mission"] = {
            "mission_id": "V0-P5-CHECKPOINT-CLOSURE",
            "objective": "Close P5 end to end",
            "parent_mission_id": "V0-PRODUCT-TRAIN",
            "completion_condition": "V0_P5_CHECKPOINT_ACCEPTED",
            "session_scope": "CHECKPOINT",
            "auto_continue_across_role_boundaries": True,
        }
        mission = mission_from_state(state)
        self.assertEqual("V0-P5-CHECKPOINT-CLOSURE", mission["mission_id"])
        self.assertEqual("V0-PRODUCT-TRAIN", mission["parent_mission_id"])
        self.assertFalse(mission["mission_complete"])


class ExecutionSelectorTests(unittest.TestCase):
    def test_scheduler_product_checkpoint_is_the_default(self) -> None:
        contracts = {
            "scheduler_policy": {
                "v0_product_train_routing": {"current_checkpoint": "V0_P5_EQUIPMENT_TOOLS"},
                "current_pilot_override": {"current_checkpoint": "H0_2_NX_C1_HIGH_RISK_PILOT"},
            }
        }
        self.assertEqual("V0_P5_EQUIPMENT_TOOLS", default_checkpoint(contracts))

    def test_latest_execution_for_checkpoint_is_selected_without_hardcoded_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name, issued in (("E-old", "2026-08-18T10:00:00Z"), ("E-new", "2026-08-20T10:00:00Z")):
                execution = root / "config/control/harness/executions" / name
                (execution / "work-orders").mkdir(parents=True)
                (execution / "project-epoch.v1.json").write_text("{}", encoding="utf-8")
                (execution / "work-orders" / "wo.json").write_text(
                    json.dumps(
                        {
                            "goal_checkpoint": "V0_P5_EQUIPMENT_TOOLS",
                            "work_order_id": name,
                            "issued_at_utc": issued,
                        }
                    ),
                    encoding="utf-8",
                )
            contracts = {
                "scheduler_policy": {
                    "v0_product_train_routing": {"current_checkpoint": "V0_P5_EQUIPMENT_TOOLS"}
                }
            }
            selected, checkpoint = resolve_execution(root, contracts)
            self.assertEqual("E-new", selected.name)
            self.assertEqual("V0_P5_EQUIPMENT_TOOLS", checkpoint)


class CanonicalAcceptanceTests(unittest.TestCase):
    def _git(self, root: Path, *args: str) -> None:
        completed = subprocess.run(
            ["git", *args], cwd=root, text=True, capture_output=True, check=False
        )
        if completed.returncode != 0:
            self.fail(f"git {' '.join(args)} failed: {completed.stderr}")

    def test_acceptance_is_read_from_canonical_main_ref(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self._git(root, "init", "-b", "main")
            self._git(root, "config", "user.email", "harness@example.invalid")
            self._git(root, "config", "user.name", "Harness Test")
            acceptance_dir = root / "config/control/harness/acceptance"
            acceptance_dir.mkdir(parents=True)
            (acceptance_dir / "P5.v1.json").write_text(
                json.dumps(
                    {
                        "schema": "distributed_world_simulator.v0_product_checkpoint_acceptance.v1",
                        "checkpoint": "V0_P5_EQUIPMENT_TOOLS",
                        "decision": "V0_P5_CHECKPOINT_ACCEPTED",
                        "status": "ACCEPTED",
                        "accepted_runtime_head": "b" * 40,
                        "accepted_product_lineage_head": "b" * 40,
                        "accepted_at_utc": "2026-08-20T10:00:00Z",
                    }
                ),
                encoding="utf-8",
            )
            self._git(root, "add", "config/control/harness/acceptance/P5.v1.json")
            self._git(root, "commit", "-m", "test: accept P5")
            self._git(root, "switch", "-c", "feature/test")
            # A feature-branch-only fake acceptance must not become authority.
            (acceptance_dir / "fake.v1.json").write_text(
                json.dumps(
                    {
                        "checkpoint": "V0_P6_PERSISTENT_SHARED_OUTPOST",
                        "status": "ACCEPTED",
                        "accepted_runtime_head": "c" * 40,
                    }
                ),
                encoding="utf-8",
            )
            record = load_checkpoint_acceptance(root, "V0_P5_EQUIPMENT_TOOLS", "main")
            self.assertIsNotNone(record)
            assert record is not None
            self.assertEqual("CANONICAL_MAIN_ACCEPTANCE_RECORD", record["source"])
            self.assertEqual("b" * 40, record["accepted_runtime_head"])
            self.assertIsNone(load_checkpoint_acceptance(root, "V0_P6_PERSISTENT_SHARED_OUTPOST", "main"))


class ContractRegressionTests(unittest.TestCase):
    def test_r5_json_contracts_are_valid_draft_2020_12_schemas(self) -> None:
        from jsonschema import Draft202012Validator

        for relative in (
            "config/control/harness/work-order.schema.v1.json",
            "config/control/harness/local-execution-handoff.schema.v1.json",
            "validation/harness/control-development-output.schema.v1.json",
        ):
            value = json.loads((ROOT / relative).read_text(encoding="utf-8"))
            Draft202012Validator.check_schema(value)

    def test_continuation_revision_is_bound_from_harness_policy(self) -> None:
        harness = json.loads(
            (ROOT / "config/control/harness/harness-policy.v1.json").read_text(encoding="utf-8")
        )
        continuation = json.loads(
            (ROOT / "config/control/harness/continuation-policy.v1.json").read_text(encoding="utf-8")
        )
        self.assertEqual(
            harness["continuation_layer_revision"],
            continuation["continuation_layer_revision"],
        )
        self.assertEqual(
            "config/control/harness/continuation-policy.v1.json",
            harness["continuation_policy"],
        )
        self.assertTrue(harness["principles"]["role_boundary_is_not_mission_boundary"])
        self.assertTrue(harness["principles"]["checkpoint_is_user_session_unit"])
        self.assertTrue(harness["principles"]["finished_user_report_requires_mission_complete"])
        self.assertEqual(
            "config/control/harness/local-execution-handoff.schema.v1.json",
            harness["local_execution_handoff_schema"],
        )


    def test_default_git_authority_is_pre_authorized_through_a3(self) -> None:
        harness = json.loads(
            (ROOT / "config/control/harness/harness-policy.v1.json").read_text(encoding="utf-8")
        )
        authority = build_git_authority(harness)
        self.assertEqual("PREAUTHORIZED_WITHIN_ACTIVE_CHECKPOINT_MISSION", authority["status"])
        self.assertEqual("A3_INTEGRATE_CANDIDATE", authority["autonomy_ceiling"])
        self.assertFalse(authority["routine_confirmation_required"])
        operations = set(authority["routine_operations"])
        self.assertTrue({"create_feature_or_control_branch", "commit", "push_non_force", "open_or_update_draft_pr", "request_independent_review"}.issubset(operations))
        gates = set(authority["human_confirmation_required_for"])
        self.assertIn("RUNTIME_FEATURE_MERGE", gates)
        self.assertIn("FORCE_PUSH", gates)
        self.assertNotIn("commit", gates)
        self.assertNotIn("push_non_force", gates)

    def test_agent_router_forbids_routine_git_permission_reprompt(self) -> None:
        router = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        self.assertIn("DO NOT ASK FOR BRANCH / COMMIT / NON-FORCE-PUSH / DRAFT-PR CONFIRMATION", router)
        self.assertIn("EXTERNAL_TOOL_AUTH_REQUIRED", router)

    def test_work_order_mission_extension_is_optional_and_fail_closed(self) -> None:
        from jsonschema import Draft202012Validator

        schema = json.loads(
            (ROOT / "config/control/harness/work-order.schema.v1.json").read_text(encoding="utf-8")
        )
        base = {
            "schema": "distributed_world_simulator.work_order.v1",
            "work_order_id": "WO-1",
            "project_epoch": "E-1",
            "program": "V0",
            "goal_checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "state": "PLANNED",
            "work_order_type": "IMPLEMENTATION",
            "base_sha": "a" * 40,
            "branch": "feature/test",
            "scope": "test",
            "allowed_paths": [],
            "forbidden_paths": [],
            "required_predicates": [],
            "required_outputs": [],
            "stop_conditions": [],
            "risk_class": "HIGH",
            "review_required": True,
            "evidence_map_required": True,
            "issued_at_utc": "2026-08-20T00:00:00Z",
        }
        validator = Draft202012Validator(schema)
        self.assertEqual([], list(validator.iter_errors(base)))
        with_mission = dict(base)
        with_mission["mission"] = {
            "mission_id": "P5",
            "session_scope": "CHECKPOINT",
            "auto_continue_across_role_boundaries": True,
        }
        self.assertEqual([], list(validator.iter_errors(with_mission)))
        invalid = dict(base)
        invalid["mission"] = {"session_scope": "ROLE"}
        self.assertTrue(list(validator.iter_errors(invalid)))


if __name__ == "__main__":
    unittest.main()
