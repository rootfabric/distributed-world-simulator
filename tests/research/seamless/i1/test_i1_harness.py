from __future__ import annotations

import json
import sys
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))

from tools.research.seamless.i1.harness import (  # noqa: E402
    DeterministicLinkPlanner,
    EvidenceRecorder,
    GlobalEvidenceAnalyzer,
    HarnessContractError,
    LinkProfile,
    ProcessSpec,
    ProcessSupervisor,
    load_network_profiles,
)


class I1HarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rec = EvidenceRecorder("i1/test", 123)
        self.analyzer = GlobalEvidenceAnalyzer()

    def _base_clean_events(self) -> list[dict]:
        self.rec.record(
            "WRITER_STATE",
            process_role="authority",
            process_id="A",
            process_incarnation=1,
            observation_id="tick-1",
            subject_id="domain/1",
            authority_id="A",
            active_writer=True,
        )
        self.rec.record(
            "WRITER_STATE",
            process_role="authority",
            process_id="B",
            process_incarnation=1,
            observation_id="tick-1",
            subject_id="domain/1",
            authority_id="B",
            active_writer=False,
        )
        self.rec.record(
            "IDENTITY_STATE",
            process_role="authority",
            process_id="A",
            process_incarnation=1,
            subject_id="domain/1",
            identity_id="identity/1",
        )
        self.rec.record(
            "MUTATION_RESULT",
            process_role="authority",
            process_id="A",
            process_incarnation=1,
            stale_owner=False,
            accepted=True,
        )
        self.rec.record(
            "CANONICAL_COMMIT",
            process_role="authority",
            process_id="A",
            process_incarnation=1,
            operation_id="op/1",
            commit_id="commit/1",
            accepted=True,
        )
        self.rec.record(
            "PROJECTION_WRITE_RESULT",
            process_role="gateway",
            process_id="G1",
            process_incarnation=1,
            canonical_write_accepted=False,
        )
        self.rec.record(
            "REVISION_STATE",
            process_role="authority",
            process_id="A",
            process_incarnation=1,
            subject_id="domain/1",
            state_revision=10,
        )
        self.rec.record(
            "REVISION_STATE",
            process_role="authority",
            process_id="B",
            process_incarnation=1,
            subject_id="domain/1",
            state_revision=11,
        )
        return self.rec.events

    def test_clean_global_evidence_passes(self) -> None:
        report = self.analyzer.analyze(self._base_clean_events())
        self.assertEqual(report["result"], "PASS")
        self.assertTrue(all(value == 0 for value in report["oracles"].values()))

    def test_writer_split_brain_detected_globally(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "WRITER_STATE",
            process_role="authority",
            process_id="B",
            process_incarnation=1,
            observation_id="tick-1",
            subject_id="domain/1",
            authority_id="B",
            active_writer=True,
        )
        report = self.analyzer.analyze(events)
        self.assertEqual(report["oracles"]["writer_violations"], 1)
        self.assertEqual(report["result"], "FAIL")

    def test_identity_change_detected(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "IDENTITY_STATE",
            process_role="authority",
            process_id="B",
            process_incarnation=1,
            subject_id="domain/1",
            identity_id="identity/forged",
        )
        self.assertEqual(
            self.analyzer.analyze(events)["oracles"]["identity_changes_due_to_topology"],
            1,
        )

    def test_stale_owner_accept_detected(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "MUTATION_RESULT",
            process_role="authority",
            process_id="A",
            process_incarnation=2,
            stale_owner=True,
            accepted=True,
        )
        self.assertEqual(
            self.analyzer.analyze(events)["oracles"]["stale_owner_mutations_accepted"],
            1,
        )

    def test_duplicate_canonical_commit_detected(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "CANONICAL_COMMIT",
            process_role="authority",
            process_id="B",
            process_incarnation=1,
            operation_id="op/1",
            commit_id="commit/2",
            accepted=True,
        )
        self.assertEqual(
            self.analyzer.analyze(events)["oracles"]["duplicate_canonical_commits"],
            1,
        )

    def test_exact_commit_replay_is_not_duplicate_commit(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "CANONICAL_COMMIT",
            process_role="authority",
            process_id="A",
            process_incarnation=1,
            operation_id="op/1",
            commit_id="commit/1",
            accepted=True,
        )
        self.assertEqual(
            self.analyzer.analyze(events)["oracles"]["duplicate_canonical_commits"],
            0,
        )

    def test_projection_canonical_write_detected(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "PROJECTION_WRITE_RESULT",
            process_role="gateway",
            process_id="G1",
            process_incarnation=1,
            canonical_write_accepted=True,
        )
        self.assertEqual(
            self.analyzer.analyze(events)["oracles"]["projection_canonical_writes"],
            1,
        )

    def test_revision_rollback_detected(self) -> None:
        events = self._base_clean_events()
        self.rec.record(
            "REVISION_STATE",
            process_role="authority",
            process_id="A",
            process_incarnation=2,
            subject_id="domain/1",
            state_revision=9,
        )
        self.assertEqual(
            self.analyzer.analyze(events)["oracles"]["unexpected_revision_rollback"],
            1,
        )

    def test_network_planner_is_reproducible_and_order_independent(self) -> None:
        profile = LinkProfile(
            latency_ms=50,
            jitter_ms=15,
            loss_rate=0.2,
            duplicate_rate=0.3,
            reorder_rate=0.4,
        )
        planner = DeterministicLinkPlanner(444)
        forward = [planner.plan_packet("G1->A", i, profile) for i in range(40)]
        reverse_calls = {
            i: planner.plan_packet("G1->A", i, profile) for i in reversed(range(40))
        }
        self.assertEqual(forward, [reverse_calls[i] for i in range(40)])
        self.assertEqual(
            forward,
            [
                DeterministicLinkPlanner(444).plan_packet("G1->A", i, profile)
                for i in range(40)
            ],
        )

    def test_network_profile_catalog_loads(self) -> None:
        profiles = load_network_profiles(
            ROOT / "config" / "research" / "seamless" / "i1" / "network-profiles.v1.json"
        )
        self.assertIn("LOCAL", profiles)
        self.assertIn("EXTREME", profiles)
        self.assertEqual(profiles["LOCAL"].loss_rate, 0.0)

    def test_invalid_profile_fails_closed(self) -> None:
        with self.assertRaises(HarnessContractError):
            LinkProfile(loss_rate=1.1)

    def test_missing_evidence_field_fails_closed(self) -> None:
        with self.assertRaises(HarnessContractError):
            self.analyzer.analyze(
                [{"schema": "distributed_world_simulator.sm1_i1_evidence.v1"}]
            )

    def test_process_supervisor_restart_changes_incarnation(self) -> None:
        probe = ROOT / "tools" / "research" / "seamless" / "i1" / "probe_process.py"
        supervisor = ProcessSupervisor()
        managed = supervisor.register(
            ProcessSpec(
                role="authority",
                process_id="authority/test",
                command=[sys.executable, str(probe), "--heartbeat-ms", "20"],
            )
        )
        try:
            self.assertEqual(supervisor.start("authority/test"), 1)
            time.sleep(0.05)
            self.assertTrue(managed.is_alive())
            self.assertEqual(supervisor.restart("authority/test"), 2)
            time.sleep(0.05)
            self.assertTrue(managed.is_alive())
            self.assertEqual(supervisor.status()["authority/test"]["incarnation"], 2)
        finally:
            supervisor.terminate_all()
        self.assertFalse(managed.is_alive())

    def test_json_lines_are_machine_replayable(self) -> None:
        self._base_clean_events()
        lines = self.rec.to_json_lines().splitlines()
        decoded = [json.loads(line) for line in lines]
        self.assertEqual(decoded, self.rec.events)
        self.assertEqual(self.analyzer.analyze(decoded)["result"], "PASS")


if __name__ == "__main__":
    unittest.main()
