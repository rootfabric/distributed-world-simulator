"""R13/R14: verify committed MVP1 leaf closure without terminalizing the parent Work Order."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError
from harness.event_reducer import load_guard_context, reduce_events

EPOCH = "E2026-09-09-V0-MVP-R1"
WO = "V0-MVP-R1-WO-001"
BRANCH = "feature/v0-mvp-playable-seamless-planet-r1"
RUNTIME_HEAD = "3973df7e53cbc9864c64448f26641a51f2a20465"
CLOSURE_HEAD = "2aadb99dfc3dd3b798dfb12eb5f50417b4f5eb7c"
MVP1 = "MVP_SHARED_GRAPHICAL_SCENE"
MVP2_PROGRESS = "MVP_TWO_CLIENT_SHARED_WORLD_IMPLEMENTATION_CONTINUED"
EX = Path("config/control/harness/executions") / EPOCH
ORDER = EX / "work-orders" / f"{WO}.v1.json"
EVENT_DIR = EX / "events" / WO
TRANSITION = EX / "transition-table.v1.json"
REVIEW = EX / "reviews" / "MVP1-WINDOWS-INDEPENDENT-REVIEW-3973DF7E-R1.v1.json"
MANIFEST = EX / "evidence" / "MVP1-NATIVE-3973df7e53cb" / "manifest.v1.json"
R13 = Path("docs/control/mvp-act0-r1/work-order-nonterminal-predicate-r13.v1.json")
R14 = Path("docs/control/mvp-act0-r1/work-order-postclosure-fixture-r14.v1.json")


def read(relative: Path) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def committed_events() -> list[dict]:
    return [
        json.loads(path.read_text(encoding="utf-8"))
        for path in sorted((ROOT / EVENT_DIR).glob("*.json"))
    ]


def next_leaf_progress_event() -> dict:
    return {
        "schema": "distributed_world_simulator.harness_event.v1",
        "event_id": f"{EPOCH}-{WO}-0007-R14-TEST",
        "project_epoch": EPOCH,
        "work_order_id": WO,
        "sequence": 7,
        "event_type": "IMPLEMENTATION_COMMITTED",
        "work_state": "IN_PROGRESS",
        "recorded_at_utc": "2026-09-11T10:29:00Z",
        "actor": "IMPLEMENTER",
        "branch": BRANCH,
        "head_sha": CLOSURE_HEAD,
        "predicate": MVP2_PROGRESS,
        "command": "R14_DRY_RUN_BEGIN_MVP2_AFTER_COMMITTED_MVP1_LEAF_CLOSURE",
        "exit_code": 0,
        "evidence_paths": [R14.as_posix()],
        "summary": "Synthetic continuation event proving MVP2 implementation may proceed after the committed non-terminal MVP1 leaf closure.",
    }


class MVPNonterminalPredicateR13Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bundle = ContractBundle.load(ROOT)
        cls.order = read(ORDER)
        cls.events = committed_events()
        cls.transition = read(TRANSITION)
        cls.context = load_guard_context(ROOT, ROOT / EX)
        cls.closure = cls.events[-1]

    def test_r13_scope_is_execution_local_and_real_closure_is_sequence_6(self):
        repair = read(R13)
        self.assertFalse(repair["runtime_mutation"])
        self.assertFalse(repair["self_acceptance_authorized"])
        self.assertFalse(repair["merge_authorized"])
        self.assertEqual(
            {
                TRANSITION.as_posix(),
                "tests/harness/test_v0_mvp_nonterminal_predicate_r13.py",
                R13.as_posix(),
            },
            set(repair["allowed_paths"]),
        )
        self.assertEqual("IN_PROGRESS", self.order["state"])
        self.assertEqual(list(range(1, 7)), [event["sequence"] for event in self.events])
        self.assertEqual(6, self.closure["sequence"])
        self.assertEqual("PREDICATE_VERIFIED", self.closure["event_type"])
        self.assertEqual("IN_PROGRESS", self.closure["work_state"])
        self.assertEqual("VERIFIER", self.closure["actor"])
        self.assertEqual(RUNTIME_HEAD, self.closure["head_sha"])
        self.assertEqual(MVP1, self.closure["predicate"])
        self.assertEqual(0, self.closure["exit_code"])
        self.assertIn(REVIEW.as_posix(), self.closure["evidence_paths"])
        self.assertIn(MANIFEST.as_posix(), self.closure["evidence_paths"])
        self.assertIn(R13.as_posix(), self.closure["evidence_paths"])

    def test_committed_mvp1_predicate_closes_without_terminalizing_parent(self):
        reduced = reduce_events(
            self.bundle,
            self.order,
            self.events,
            self.transition,
            self.context,
        )
        self.assertEqual("IN_PROGRESS", reduced["state"])
        self.assertEqual([MVP1], reduced["completed_predicates"])
        self.assertEqual(MVP1, reduced["last_completed_predicate"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])
        self.assertIsNone(reduced["open_blocker"])
        self.assertEqual(6, reduced["last_event_sequence"])

    def test_mvp2_can_continue_after_committed_nonterminal_mvp1_closure(self):
        reduced = reduce_events(
            self.bundle,
            self.order,
            self.events + [next_leaf_progress_event()],
            self.transition,
            self.context,
        )
        self.assertEqual("IN_PROGRESS", reduced["state"])
        self.assertEqual([MVP1], reduced["completed_predicates"])
        self.assertIn(MVP2_PROGRESS, reduced["observed_predicates"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])
        self.assertEqual(7, reduced["last_event_sequence"])

    def test_old_terminal_only_table_rejects_real_nonterminal_predicate(self):
        old = copy.deepcopy(self.transition)
        old["event_type_states"]["PREDICATE_VERIFIED"] = ["VERIFYING", "VERIFIED"]
        with self.assertRaisesRegex(ContractValidationError, "EVENT_TYPE_STATE_PAIR_INVALID"):
            reduce_events(
                self.bundle,
                self.order,
                self.events,
                old,
                self.context,
            )

    def test_leaf_closure_cannot_jump_parent_directly_to_verified(self):
        invalid = copy.deepcopy(self.closure)
        invalid["work_state"] = "VERIFIED"
        with self.assertRaisesRegex(ContractValidationError, "STATE_TRANSITION_INVALID:IN_PROGRESS->VERIFIED"):
            reduce_events(
                self.bundle,
                self.order,
                self.events[:-1] + [invalid],
                self.transition,
                self.context,
            )


if __name__ == "__main__":
    unittest.main()
