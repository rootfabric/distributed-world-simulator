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


def _event(sequence: int, event_type: str, work_state: str, *, predicate: str = "") -> dict:
    value = {
        "schema": "distributed_world_simulator.harness_event.v1",
        "event_id": f"TEST-EVIDENCE-GAP-{sequence:04d}",
        "project_epoch": "TEST-EVIDENCE-GAP-EPOCH",
        "work_order_id": "TEST-EVIDENCE-GAP-WO",
        "sequence": sequence,
        "event_type": event_type,
        "work_state": work_state,
        "recorded_at_utc": f"2026-09-30T00:00:0{sequence}Z",
        "actor": "DIRECTOR",
        "branch": "test/evidence-gap",
        "head_sha": "1" * 40,
        "summary": event_type,
    }
    if predicate:
        value.update({
            "predicate": predicate,
            "command": "RECORD_EVIDENCE_GAP",
            "exit_code": 0,
            "evidence_paths": ["artifacts/test-evidence-gap.json"],
        })
    return value


class HarnessEvidenceGapEventTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)

    def test_historical_mvp8_evidence_gap_events_validate_without_rewrite(self):
        for filename in [
            "0045-mvp8-independent-verifier-evidence-gap.v1.json",
            "0046-mvp8-windows-r2-carrier-dispatched.v1.json",
        ]:
            event = read_json(EVENTS / filename)
            self.assertEqual("EVIDENCE_GAP", event["event_type"])
            self.assertEqual("IN_PROGRESS", event["work_state"])
            self.bundle.validate("event_schema", event, filename)

        self.assertEqual(["IN_PROGRESS"], TRANSITION["event_type_states"]["EVIDENCE_GAP"])

    def test_evidence_gap_is_observed_but_not_completed_or_hard_blocking(self):
        work_order = {
            "work_order_id": "TEST-EVIDENCE-GAP-WO",
            "project_epoch": "TEST-EVIDENCE-GAP-EPOCH",
            "branch": "test/evidence-gap",
            "state": "IN_PROGRESS",
        }
        events = [
            _event(1, "WORK_ORDER_CREATED", "PLANNED"),
            _event(2, "DISPATCHED", "DISPATCHED"),
            _event(3, "IMPLEMENTATION_COMMITTED", "IN_PROGRESS"),
            _event(4, "EVIDENCE_GAP", "IN_PROGRESS", predicate="INDEPENDENT_VERIFIER"),
        ]

        with patch("harness.event_reducer._enforce_guard", return_value=None):
            reduced = reduce_events(self.bundle, work_order, events, copy.deepcopy(TRANSITION))

        self.assertEqual("IN_PROGRESS", reduced["state"])
        self.assertIn("INDEPENDENT_VERIFIER", reduced["observed_predicates"])
        self.assertNotIn("INDEPENDENT_VERIFIER", reduced["completed_predicates"])
        self.assertIsNone(reduced["open_blocker"])
        self.assertEqual("EVIDENCE_GAP", reduced["last_event_type"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])

    def test_evidence_gap_cannot_claim_verified_or_blocked_state(self):
        work_order = {
            "work_order_id": "TEST-EVIDENCE-GAP-WO",
            "project_epoch": "TEST-EVIDENCE-GAP-EPOCH",
            "branch": "test/evidence-gap",
            "state": "IN_PROGRESS",
        }
        prefix = [
            _event(1, "WORK_ORDER_CREATED", "PLANNED"),
            _event(2, "DISPATCHED", "DISPATCHED"),
            _event(3, "IMPLEMENTATION_COMMITTED", "IN_PROGRESS"),
        ]

        for bad_state in ["VERIFIED", "BLOCKED", "DISPATCHED"]:
            events = prefix + [_event(4, "EVIDENCE_GAP", bad_state, predicate="INDEPENDENT_VERIFIER")]
            with self.subTest(work_state=bad_state):
                with patch("harness.event_reducer._enforce_guard", return_value=None):
                    with self.assertRaisesRegex(ContractValidationError, "EVENT_TYPE_STATE_PAIR_INVALID"):
                        reduce_events(self.bundle, work_order, events, copy.deepcopy(TRANSITION))


if __name__ == "__main__":
    unittest.main()
