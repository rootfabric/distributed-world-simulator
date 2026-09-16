from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.continuation import build_continuation
from harness.contracts import ContractBundle, ContractValidationError

POLICY = "config/control/harness/closure-throughput-policy.v1.json"
CONTINUATION_POLICY = "config/control/harness/continuation-policy.v1.json"
CATALOG = "config/control/harness/checkpoint-catalog.v1.json"
WO = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-001.v1.json"
REJECTED_REPAIR_WO = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-002.v1.json"
WORKFLOW = ".github/workflows/mvp4-shared-dig-validation.yml"
VALIDATION_WORKFLOW = ".github/workflows/harness-closure-throughput-validation.yml"
CHECKPOINT = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"


def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


class ClosureThroughputPolicyTests(unittest.TestCase):
    def test_acceptance_refinement_preserves_catalog_and_may_strengthen_it(self) -> None:
        policy = load(POLICY)["acceptance_refinement"]
        catalog = load(CATALOG)["checkpoints"][CHECKPOINT]["required_predicates"]
        required = load(WO)["required_predicates"]
        self.assertEqual(
            "ORDERED_SUBSEQUENCE_OF_WORK_ORDER_REQUIRED_PREDICATES",
            policy["catalog_required_predicates_relation"],
        )
        self.assertTrue(policy["work_order_extra_predicates_allowed"])
        self.assertTrue(policy["catalog_predicate_removal_forbidden"])
        self.assertTrue(policy["catalog_predicate_reorder_forbidden"])
        self.assertTrue(policy["production_validator_required"])
        self.assertEqual(len(required), len(set(required)), "required predicates must be unique")
        positions = [required.index(predicate) for predicate in catalog]
        self.assertEqual(positions, sorted(positions), "catalog predicates must remain an ordered subsequence")
        self.assertGreaterEqual(len(required), len(catalog))

    def test_only_parent_product_work_order_remains_active(self) -> None:
        self.assertTrue((ROOT / WO).is_file())
        self.assertFalse((ROOT / REJECTED_REPAIR_WO).exists())
        work_orders = sorted((ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders").glob("*.json"))
        ids = [load(path.relative_to(ROOT).as_posix())["work_order_id"] for path in work_orders]
        self.assertEqual(["V0-MVP-R1-WO-001"], ids)

    def test_production_work_order_validator_rejects_current_product_gate_removal_and_reorder(self) -> None:
        bundle = ContractBundle.load(ROOT)
        work_order = load(WO)
        catalog = bundle.contracts["checkpoint_catalog"]["checkpoints"][CHECKPOINT]["required_predicates"]
        bundle.validate("work_order_schema", work_order, "current-parent-work-order")

        missing = copy.deepcopy(work_order)
        missing["required_predicates"].remove(catalog[0])
        with self.assertRaisesRegex(ContractValidationError, "WORK_ORDER_CATALOG_PREDICATE_MISSING"):
            bundle.validate("work_order_schema", missing, "missing-catalog-gate")

        reordered = copy.deepcopy(work_order)
        first = reordered["required_predicates"].index(catalog[0])
        second = reordered["required_predicates"].index(catalog[1])
        reordered["required_predicates"][first], reordered["required_predicates"][second] = (
            reordered["required_predicates"][second],
            reordered["required_predicates"][first],
        )
        with self.assertRaisesRegex(ContractValidationError, "WORK_ORDER_CATALOG_PREDICATE"):
            bundle.validate("work_order_schema", reordered, "reordered-catalog-gates")

        duplicated = copy.deepcopy(work_order)
        duplicated["required_predicates"].append(duplicated["required_predicates"][0])
        with self.assertRaisesRegex(ContractValidationError, "WORK_ORDER_REQUIRED_PREDICATES_NOT_UNIQUE"):
            bundle.validate("work_order_schema", duplicated, "duplicate-predicate")

    def test_current_product_refinement_does_not_rewrite_historical_or_control_vocabularies(self) -> None:
        bundle = ContractBundle.load(ROOT)
        control = copy.deepcopy(load(WO))
        control["work_order_id"] = "CONTROL-COMPATIBILITY-FIXTURE"
        control["program"] = "H0"
        control["goal_checkpoint"] = "H0_1_CLOSED_LOOP_C22_PILOT"
        control["work_order_type"] = "CONTROL"
        control["required_predicates"] = []
        # Current product refinement is not a retroactive migration of durable
        # historical/control Work Orders. Their own schema/epoch semantics remain authoritative.
        bundle.validate("work_order_schema", control, "historical-control-vocabulary")

    def test_freeze_then_fanout_keeps_single_runtime_writer(self) -> None:
        fanout = load(POLICY)["freeze_then_fanout"]
        self.assertTrue(fanout["exact_frozen_head_and_tree_required"])
        self.assertEqual(1, fanout["runtime_mutation_workers_capacity"])
        self.assertTrue(fanout["read_only_gates_do_not_consume_runtime_mutation_lease"])
        self.assertTrue(fanout["closure_barrier_requires_all_mandatory_gates"])
        self.assertEqual(
            {
                "FULL_WORLD_CORE_REGRESSION",
                "PROJECT_CONTROL_AND_PC0",
                "INDEPENDENT_REVIEW",
                "INDEPENDENT_VERIFICATION_EVIDENCE_CONSUMPTION",
            },
            set(fanout["parallel_read_only_gates"]),
        )

    def test_production_continuation_emits_post_freeze_parallel_actions(self) -> None:
        target = "a" * 40
        state = {
            "active_work_order": {
                "work_order_id": "FANOUT-WO-001",
                "goal_checkpoint": CHECKPOINT,
                "work_order_type": "INTEGRATION",
                "review_required": True,
                "required_predicates": [
                    "FULL_WORLD_CORE_REGRESSION_PASS",
                    "INDEPENDENT_REVIEWER_PASS",
                    "INDEPENDENT_VERIFIER_PASS",
                    "STANDARD_PC0_NON_RED",
                    "DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS",
                ],
            },
            "reduced_work_order": {
                "state": "IMPLEMENTED",
                "work_order_id": "FANOUT-WO-001",
                "completed_predicates": [],
            },
            "review": {
                "post_build_state": "MISSING",
                "review_target_head_sha": target,
            },
            "repository": {"implementation_head_sha": target},
            "checkpoint_blockers": [
                "REQUIRED_PREDICATES_INCOMPLETE",
                "POST_BUILD_REVIEW_NOT_FRESH_PASS",
                "EVIDENCE_MAP_MISSING",
            ],
            "findings": [],
            "repair": {"same_defect_fix_required_count": 0},
            "human_attention": {"open_items": []},
            "checkpoint_acceptance": None,
            "epoch": {"registry_generation": 82},
        }
        result = build_continuation(state, load(CONTINUATION_POLICY))
        self.assertEqual("PARALLEL_ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertEqual("FAN_OUT_POST_FREEZE_READ_ONLY_CLOSURE_GATES", result["next_action"])
        self.assertEqual(
            {
                "FULL_WORLD_CORE_REGRESSION",
                "PROJECT_CONTROL_AND_PC0",
                "INDEPENDENT_REVIEW",
                "INDEPENDENT_VERIFICATION_EVIDENCE_CONSUMPTION",
            },
            {item["gate"] for item in result["parallel_actions"]},
        )
        self.assertNotIn("IMPLEMENTER", {item["actor"] for item in result["parallel_actions"]})
        self.assertTrue(all(item["subject_head_sha"] == target for item in result["parallel_actions"]))

        # The real CLI exposes the complete continuation object under state.next,
        # so callers of CONTROL_DEVELOPMENT -Drive receive parallel_actions without
        # a second orchestration protocol or another Work Order.
        cli = (ROOT / "scripts/harness/cli.py").read_text(encoding="utf-8")
        self.assertIn('state["next"] = {', cli)
        self.assertIn("**continuation", cli)

    def test_old_policy_snapshot_keeps_serial_role_boundary(self) -> None:
        state = {
            "active_work_order": {
                "work_order_id": "SERIAL-WO-001",
                "goal_checkpoint": CHECKPOINT,
                "work_order_type": "INTEGRATION",
                "review_required": True,
                "required_predicates": ["INDEPENDENT_VERIFIER_PASS"],
            },
            "reduced_work_order": {
                "state": "IMPLEMENTED",
                "completed_predicates": [],
            },
            "review": {"post_build_state": "MISSING", "review_target_head_sha": "a" * 40},
            "repository": {"implementation_head_sha": "a" * 40},
            "checkpoint_blockers": ["REQUIRED_PREDICATES_INCOMPLETE"],
            "findings": [],
            "repair": {"same_defect_fix_required_count": 0},
            "human_attention": {"open_items": []},
            "checkpoint_acceptance": None,
        }
        result = build_continuation(state, {"self_closing_execution": {}})
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("REVIEWER", result["next_actor"])
        self.assertNotIn("parallel_actions", result)

    def test_only_explicit_pre_freeze_validation_may_cancel_stale_runs(self) -> None:
        policy = load(POLICY)["superseded_validation"]
        self.assertTrue(policy["explicit_pre_freeze_workflow_may_cancel_in_progress"])
        self.assertTrue(policy["queued_pre_freeze_run_for_older_subject_may_cancel"])
        self.assertTrue(policy["mixed_or_frozen_required_gate_workflow_must_not_cancel_in_progress"])
        self.assertTrue(policy["terminal_failure_must_remain_visible"])
        self.assertTrue(policy["frozen_subject_required_gate_must_run_to_terminal"])
        mixed = (ROOT / WORKFLOW).read_text(encoding="utf-8")
        prefreeze = (ROOT / VALIDATION_WORKFLOW).read_text(encoding="utf-8")
        self.assertIn("cancel-in-progress: false", mixed)
        self.assertNotIn("cancel-in-progress: true", mixed)
        self.assertIn("cancel-in-progress: true", prefreeze)

    def test_unavailable_preferred_verifier_fails_forward_without_self_verification(self) -> None:
        verifier = load(POLICY)["verifier_fallback"]
        self.assertFalse(verifier["preferred_executor_unavailable_is_blocking"])
        self.assertTrue(verifier["implementer_may_supply_machine_evidence"])
        self.assertTrue(verifier["implementer_may_not_issue_independent_verdict"])
        self.assertTrue(verifier["fresh_role_context_is_required_when_verifier_role_is_required"])
        route = verifier["on_preferred_executor_unavailable"]
        self.assertEqual("RECORD_ROUTE_UNAVAILABLE_ONCE", route[0])
        self.assertIn("DO_NOT_WAIT", route)
        self.assertIn("DO_NOT_RETRY_IDENTICAL_ROUTE", route)
        self.assertIn("SELECT_FRESH_ISOLATED_ROLE_CONTEXT_WITH_AVAILABLE_TOOLS", route)
        self.assertIn("CONSUME_HASH_BOUND_EXACT_HEAD_MACHINE_EVIDENCE", route)

    def test_world_core_control_driver_rebinds_exact_sha_to_declared_branch(self) -> None:
        text = (ROOT / WORKFLOW).read_text(encoding="utf-8")
        marker = 'git switch -C feature/v0-mvp-playable-seamless-planet-r1 "$EXPECTED_HEAD"'
        self.assertIn(marker, text)
        self.assertLess(text.index(marker), text.index("CONTROL_DEVELOPMENT Status Resume Drive"))
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD"', text)

    def test_doctrine_forbids_gate_removal(self) -> None:
        text = (ROOT / "docs/control/HARNESS_CLOSURE_THROUGHPUT_R1_RU.md").read_text(encoding="utf-8")
        self.assertIn("DO NOT REMOVE GATES", text)
        self.assertIn("Freeze → fan-out → barrier", text)
        self.assertIn("DO NOT WAIT", text)
        self.assertIn("Implementer", text)
        self.assertIn("не может сам выдать independent verdict", text)


if __name__ == "__main__":
    unittest.main()
