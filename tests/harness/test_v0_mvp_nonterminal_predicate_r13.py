"""R13: MVP leaf predicates may complete without terminalizing the parent MVP1-MVP8 Work Order."""
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
MVP1 = "MVP_SHARED_GRAPHICAL_SCENE"
MVP2_PROGRESS = "MVP_TWO_CLIENT_SHARED_WORLD_IMPLEMENTATION_CONTINUED"
EX = Path("config/control/harness/executions") / EPOCH
ORDER = EX / "work-orders" / f"{WO}.v1.json"
EVENT_DIR = EX / "events" / WO
TRANSITION = EX / "transition-table.v1.json"
REVIEW = EX / "reviews" / "MVP1-WINDOWS-INDEPENDENT-REVIEW-3973DF7E-R1.v1.json"
MANIFEST = EX / "evidence" / "MVP1-NATIVE-3973df7e53cb" / "manifest.v1.json"
R13 = Path("docs/control/mvp-act0-r1/work-order-nonterminal-predicate-r13.v1.json")


def read(relative: Path) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def committed_events() -> list[dict]:
    return [
        json.loads(path.read_text(encoding="utf-8"))
        for path in sorted((ROOT / EVENT_DIR).glob("*.json"))
    ]


def predicate_event(*, work_state: str = "IN_PROGRESS") -> dict:
    return {
        "schema": "distributed_world_simulator.harness_event.v1",
        "event_id": f"{EPOCH}-{WO}-0006-R13-TEST",
        "project_epoch": EPOCH,
        "work_order_id": WO,
        "sequence": 6,
        "event_type": "PREDICATE_VERIFIED",
        "work_state": work_state,
        "recorded_at_utc": "2026-09-11T10:20:00Z",
        "actor": "VERIFIER",
        "branch": BRANCH,
        "head_sha": RUNTIME_HEAD,
        "predicate": MVP1,
        "command": "R13_DRY_RUN_MVP1_NONTERMINAL_PREDICATE_CLOSURE",
        "exit_code": 0,
        "evidence_paths": [REVIEW.as_posix(), MANIFEST.as_posix()],
        "summary": "Synthetic R13 test event: verify the MVP1 leaf without advancing the parent MVP1-MVP8 Work Order out of IN_PROGRESS.",
    }


def next_leaf_progress_event() -> dict:
    return {
        "schema": "distributed_world_simulator.harness_event.v1",
        "event_id": f"{EPOCH}-{WO}-0007-R13-TEST",
        "project_epoch": EPOCH,
        "work_order_id": WO,
        "sequence": 7,
        "event_type": "IMPLEMENTATION_COMMITTED",
        "work_state": "IN_PROGRESS",
        "recorded_at_utc": "2026-09-11T10:21:00Z",
        "actor": "IMPLEMENTER",
        "branch": BRANCH,
        "head_sha": RUNTIME_HEAD,
        "predicate": MVP2_PROGRESS,
        "command": "R13_DRY_RUN_BEGIN_MVP2_AFTER_MVP1_LEAF_CLOSURE",
        "exit_code": 0,
        "evidence_paths": [R13.as_posix()],
        "summary": "Synthetic R13 continuation event proving that MVP2 implementation may proceed after non-terminal MVP1 leaf closure.",
    }


class MVPNonterminalPredicateR13Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bundle = ContractBundle.load(ROOT)
        cls.order = read(ORDER)
        cls.events = committed_events()
        cls.transition = read(TRANSITION)
        cls.context = load_guard_context(ROOT, ROOT / EX)

    def test_r13_scope_is_execution_local(self):
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
        self.assertEqual(5, max(event["sequence"] for event in self.events))

    def test_mvp1_predicate_closes_without_terminalizing_parent(self):
        reduced = reduce_events(
            self.bundle,
            self.order,
            self.events + [predicate_event()],
            self.transition,
            self.context,
        )
        self.assertEqual("IN_PROGRESS", reduced["state"])
        self.assertEqual([MVP1], reduced["completed_predicates"])
        self.assertEqual(MVP1, reduced["last_completed_predicate"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])
        self.assertIsNone(reduced["open_blocker"])

    def test_mvp2_can_continue_after_nonterminal_mvp1_closure(self):
        reduced = reduce_events(
            self.bundle,
            self.order,
            self.events + [predicate_event(), next_leaf_progress_event()],
            self.transition,
            self.context,
        )
        self.assertEqual("IN_PROGRESS", reduced["state"])
        self.assertEqual([MVP1], reduced["completed_predicates"])
        self.assertIn(MVP2_PROGRESS, reduced["observed_predicates"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])

    def test_old_terminal_only_table_rejects_nonterminal_predicate(self):
        old = copy.deepcopy(self.transition)
        old["event_type_states"]["PREDICATE_VERIFIED"] = ["VERIFYING", "VERIFIED"]
        with self.assertRaisesRegex(ContractValidationError, "EVENT_TYPE_STATE_PAIR_INVALID"):
            reduce_events(
                self.bundle,
                self.order,
                self.events + [predicate_event()],
                old,
                self.context,
            )

    def test_leaf_closure_cannot_jump_parent_directly_to_verified(self):
        with self.assertRaisesRegex(ContractValidationError, "STATE_TRANSITION_INVALID:IN_PROGRESS->VERIFIED"):
            reduce_events(
                self.bundle,
                self.order,
                self.events + [predicate_event(work_state="VERIFIED")],
                self.transition,
                self.context,
            )


if __name__ == "__main__":
    unittest.main()
