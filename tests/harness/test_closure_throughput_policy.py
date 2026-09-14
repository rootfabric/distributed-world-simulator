from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = "config/control/harness/closure-throughput-policy.v1.json"
CATALOG = "config/control/harness/checkpoint-catalog.v1.json"
WO = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-001.v1.json"
REPAIR_WO = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-002.v1.json"
EPOCH = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/project-epoch.v1.json"
WORKFLOW = ".github/workflows/mvp4-shared-dig-validation.yml"
CHECKPOINT = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"


def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


class ClosureThroughputPolicyTests(unittest.TestCase):
    def test_acceptance_refinement_preserves_catalog_and_may_strengthen_it(self) -> None:
        policy = load(POLICY)["acceptance_refinement"]
        catalog = load(CATALOG)["checkpoints"][CHECKPOINT]["required_predicates"]
        required = load(WO)["required_predicates"]
        self.assertEqual("ORDERED_SUBSEQUENCE_OF_WORK_ORDER_REQUIRED_PREDICATES", policy["catalog_required_predicates_relation"])
        self.assertTrue(policy["work_order_extra_predicates_allowed"])
        self.assertTrue(policy["catalog_predicate_removal_forbidden"])
        self.assertTrue(policy["catalog_predicate_reorder_forbidden"])
        self.assertEqual(len(required), len(set(required)), "required predicates must be unique")
        positions = [required.index(predicate) for predicate in catalog]
        self.assertEqual(positions, sorted(positions), "catalog predicates must remain an ordered subsequence")
        self.assertGreaterEqual(len(required), len(catalog))

    def test_repair_work_order_matches_declared_epoch_identity(self) -> None:
        epoch = load(EPOCH)
        work_order = load(REPAIR_WO)
        self.assertEqual(epoch["epoch_id"], work_order["project_epoch"])
        self.assertEqual(epoch["base_sha"], work_order["base_sha"])
        self.assertIn(work_order["goal_checkpoint"], epoch["eligible_checkpoints"])

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
