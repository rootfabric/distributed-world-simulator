"""R3C2 recovery proof cannot accept fake postcommit/corrupt replay evidence."""
import importlib.util
import json
import tempfile
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[2] / "tools/net_smooth1/fault_kill_r3c2.py"
spec = importlib.util.spec_from_file_location("r3c2_fault", MODULE)
fault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fault)


class R3C2KillEvidenceTest(unittest.TestCase):
    def checkpoint(self, root, generation, op=""):
        root.mkdir(parents=True, exist_ok=True)
        record = {
            "schema": "planet_simulator.authoritative_checkpoint.v1",
            "schema_version": 1,
            "generation": generation,
            "previous_generation": generation - 1,
            "checksum": "1" * 64,
            "authority_state": {"server_tick": 100},
            "replay_state": {"committed_outbox": [{"operation_id": op}] if op else []},
        }
        (root / "authoritative-checkpoint.json").write_text(
            json.dumps(record), encoding="utf-8")
        return record

    def test_original_empty_operation_fails_precommit_presence(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            self.checkpoint(p, 1)
            c = fault.active_checkpoint(p)
            self.assertEqual(c["generation"], 1)
            self.assertFalse(fault.committed_operation(c, "operation/r3c2/a"))

    def test_committed_operation_is_only_one_canonical_outbox_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            self.checkpoint(p, 2, "operation/r3c2/a")
            c = fault.active_checkpoint(p)
            self.assertTrue(fault.committed_operation(c, "operation/r3c2/a"))
            self.assertFalse(fault.committed_operation(c, "operation/r3c2/b"))
            c["replay_state"]["committed_outbox"].append(
                {"operation_id": "operation/r3c2/a"})
            with self.assertRaisesRegex(ValueError, "duplicate"):
                fault.committed_operation(c, "operation/r3c2/a")

    def test_missing_replay_or_checksum_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            path = p / "authoritative-checkpoint.json"
            base = {
                "schema": "planet_simulator.authoritative_checkpoint.v1",
                "schema_version": 1,
                "generation": 1, "previous_generation": 0,
                "checksum": "1" * 64, "authority_state": {},
            }
            path.write_text(json.dumps(base), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "replay_state"):
                fault.active_checkpoint(p)
            missing_checksum = dict(base, replay_state={}, checksum="abc")
            path.write_text(json.dumps(missing_checksum), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "lowercase SHA-256"):
                fault.active_checkpoint(p)

    def test_window_requires_exact_durable_before_no_ack(self):
        source = MODULE.read_text(encoding="utf-8")
        self.assertIn('commit["t_us"] < hold["t_us"]', source)
        self.assertIn('hold.get("data", {}).get("forced_until_kill") is True', source)
        server = (MODULE.parent.parent.parent / "scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text(encoding="utf-8")
        self.assertIn('DWS_NET_R3C2_TEST_FORCE_PRE_ACK_HOLD', server)
        self.assertIn("if forced_kill_window or (requested_hold_ms", server)
        self.assertIn('recovery.get("recovered") is True', source)
        self.assertIn('recovery.get("recovery_source") == "ACTIVE"', source)
        self.assertIn('recovery.get("r3c2_test_operation_recovered")', source)
        self.assertIn('in_memory is has_record', source)
        self.assertIn('outbox_count == expected_outbox', source)
        self.assertIn("server1.kill()", source)
        self.assertIn("server2 is a different OS process", source)
        self.assertIn("same_generation and same_checksum", source)
        trace = (MODULE.parent.parent.parent / "scripts/network/smoothness/net_smooth_trace.gd").read_text(encoding="utf-8")
        self.assertIn('record_kind == "r3c2_pre_ack_hold"', trace)
        self.assertIn('"DURABLE_COMMIT"', trace)
        self.assertIn("passed\": True, \"completed\": True", source)


if __name__ == "__main__":
    unittest.main()
