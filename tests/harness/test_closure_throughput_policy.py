from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError

POLICY = "config/control/harness/closure-throughput-policy.v1.json"
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

    def test_production_work_order_validator_rejects_catalog_gate_removal_and_reorder(self) -> None:
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
