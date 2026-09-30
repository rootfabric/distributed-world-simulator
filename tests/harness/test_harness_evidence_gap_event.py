from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.event_reducer import reduce_events


EXECUTION = ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1"
EVENTS = EXECUTION / "events/V0-MVP-R1-WO-001"
TRANSITION = read_json(EXECUTION / "transition-table.v1.json")

NONTERMINAL_COMPAT_TYPES = {
    "EVIDENCE_GAP",
    "EVIDENCE_RECORDED",
    "REVIEW_DISPATCHED",
    "VERIFICATION_DISPATCHED",
    "MERGE_COMPLETED",
}


def _event(sequence: int, event_type: str, work_state: str, *, predicate: str = "") -> dict:
    value = {
        "schema": "distributed_world_simulator.harness_event.v1",
        "event_id": f"TEST-HISTORICAL-COMPAT-{sequence:04d}",
        "project_epoch": "TEST-HISTORICAL-COMPAT-EPOCH",
        "work_order_id": "TEST-HISTORICAL-COMPAT-WO",
        "sequence": sequence,
        "event_type": event_type,
        "work_state": work_state,
        "recorded_at_utc": f"2026-09-30T00:00:0{sequence}Z",
        "actor": "DIRECTOR",
        "branch": "test/historical-compat",
        "head_sha": "1" * 40,
        "summary": event_type,
    }
    if predicate:
        value.update({
            "predicate": predicate,
            "command": "RECORD_NONTERMINAL_CONTROL_EVIDENCE",
            "exit_code": 0,
            "evidence_paths": ["artifacts/test-historical-compat.json"],
        })
    return value


class HarnessHistoricalEventCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)

    def test_entire_v0_mvp_event_ledger_validates_without_rewriting_history(self):
        events = [read_json(path) for path in sorted(EVENTS.glob("*.json"))]
        self.assertEqual(76, len(events), "fixture count intentionally binds the repaired historical ledger")
        for event in events:
            with self.subTest(sequence=event["sequence"], event_type=event["event_type"]):
                self.bundle.validate("event_schema", event, event["event_id"])

        observed_compat = {event["event_type"] for event in events if event["event_type"] in NONTERMINAL_COMPAT_TYPES}
        self.assertEqual(NONTERMINAL_COMPAT_TYPES, observed_compat)
        for event_type in NONTERMINAL_COMPAT_TYPES:
            self.assertEqual(["IN_PROGRESS"], TRANSITION["event_type_states"][event_type])

    def test_nonterminal_compat_events_are_observed_but_never_complete_predicates(self):
        work_order = {
            "work_order_id": "TEST-HISTORICAL-COMPAT-WO",
            "project_epoch": "TEST-HISTORICAL-COMPAT-EPOCH",
            "branch": "test/historical-compat",
            "state": "IN_PROGRESS",
        }

        for event_type in sorted(NONTERMINAL_COMPAT_TYPES):
            events = [
                _event(1, "WORK_ORDER_CREATED", "PLANNED"),
                _event(2, "DISPATCHED", "DISPATCHED"),
                _event(3, "IMPLEMENTATION_COMMITTED", "IN_PROGRESS"),
                _event(4, event_type, "IN_PROGRESS", predicate="INDEPENDENT_VERIFIER"),
            ]
            with self.subTest(event_type=event_type):
                with patch("harness.event_reducer._enforce_guard", return_value=None):
                    reduced = reduce_events(self.bundle, work_order, events, copy.deepcopy(TRANSITION))

                self.assertEqual("IN_PROGRESS", reduced["state"])
                self.assertIn("INDEPENDENT_VERIFIER", reduced["observed_predicates"])
                self.assertNotIn("INDEPENDENT_VERIFIER", reduced["completed_predicates"])
                self.assertIsNone(reduced["open_blocker"])
                self.assertEqual(event_type, reduced["last_event_type"])
                self.assertTrue(reduced["snapshot_matches_authoritative_state"])

    def test_nonterminal_compat_events_cannot_claim_other_control_states(self):
        work_order = {
            "work_order_id": "TEST-HISTORICAL-COMPAT-WO",
            "project_epoch": "TEST-HISTORICAL-COMPAT-EPOCH",
            "branch": "test/historical-compat",
            "state": "IN_PROGRESS",
        }
        prefix = [
            _event(1, "WORK_ORDER_CREATED", "PLANNED"),
            _event(2, "DISPATCHED", "DISPATCHED"),
            _event(3, "IMPLEMENTATION_COMMITTED", "IN_PROGRESS"),
        ]

        for event_type in sorted(NONTERMINAL_COMPAT_TYPES):
            for bad_state in ["VERIFIED", "BLOCKED", "DISPATCHED"]:
                events = prefix + [_event(4, event_type, bad_state, predicate="INDEPENDENT_VERIFIER")]
                with self.subTest(event_type=event_type, work_state=bad_state):
                    with patch("harness.event_reducer._enforce_guard", return_value=None):
                        with self.assertRaisesRegex(ContractValidationError, "EVENT_TYPE_STATE_PAIR_INVALID"):
                            reduce_events(self.bundle, work_order, events, copy.deepcopy(TRANSITION))


if __name__ == "__main__":
    unittest.main()
