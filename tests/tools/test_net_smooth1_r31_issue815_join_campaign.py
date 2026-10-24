"""Offline deterministic tests of external issue #815 fresh JOIN harness."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILE = ROOT / "tools/net_smooth1/run_r31_issue815_join_campaign.py"
spec = importlib.util.spec_from_file_location("issue815_campaign", FILE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

ID = {"head": "a"*40, "tree": "b"*40, "godot_sha256": "c"*64,
      "asset_manifest_sha256": "d"*64, "asset_count": 224}


def fake(root, connected=True, roles=(), cleaned=True, invalid=False):
    root.mkdir()
    identity = {**ID, "tracked_dirty": False}
    if invalid:
        identity["head"] = "e"*40
    (root/"manifest.json").write_text(json.dumps({
        "identity": identity, "run_id": "unique", "cleanup": {"verified": cleaned},
        "errors": [], "completed": True, "measurement_close_ack_complete": True}))
    (root/"report.json").write_text('{"verdict":"FAIL"}')
    for role in ("server", "a", "b"):
        (root/role).mkdir()
        (root/role/"runtime.log").write_text(
            "PAYLOAD_CHECKSUM_MISMATCH\n" if role in roles else "normal\n")
        if connected and role in ("a", "b"):
            (root/role/"initial-state.json").write_text(
                '{"automation":{"connection_state":"CONNECTED"}}')


class Campaign(unittest.TestCase):
    def test_healthy_join_not_perf_pass_and_not_issue_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)/"run"; fake(p)
            value = m.classify_attempt(p, 1, ID)
            self.assertEqual(value["join_verdict"], "JOIN_PASS")
            self.assertEqual(value["full_process_verdict"], "FAIL")
            self.assertTrue(value["cleanup_verified"])
        rows = [{"run_id": str(i), "join_verdict": "JOIN_PASS"} for i in range(10)]
        self.assertEqual(m.summary_status(rows, 10),
                         "NO_INCIDENT_OBSERVED_ISSUE_815_STILL_OPEN")
        self.assertEqual(m.summary_status(rows[:9], 10), "INCOMPLETE")
        rows[0]["run_id"] = "1"
        self.assertEqual(m.summary_status(rows, 10), "RUN_ID_REUSE")

    def test_join_checksum_before_two_initial_receipts(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)/"run"; fake(p, connected=False, roles=("a", "b"))
            self.assertEqual(
                m.classify_attempt(p, 1, ID)["join_verdict"],
                "CHECKSUM_BEFORE_INITIAL_STATE_CANDIDATE")

    def test_post_join_checksum_not_mislabeled_as_first_join(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)/"run"; fake(p, roles=("server",))
            self.assertEqual(m.classify_attempt(p, 1, ID)["join_verdict"],
                             "CHECKSUM_DURING_ATTEMPT")

    def test_identity_and_cleanup_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)/"run"; fake(p, invalid=True)
            self.assertEqual(m.classify_attempt(p, 0, ID)["join_verdict"],
                             "INVALID_IDENTITY")
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)/"run"; fake(p, cleaned=False)
            self.assertEqual(m.classify_attempt(p, 0, ID)["join_verdict"],
                             "PROCESS_ISOLATION_FAILED")

    def test_only_on_flag_differs_and_ten_alternate(self):
        off = m.command_for_attempt(Path("/product"), Path("/godot"),
                                    Path("/run"), False, 240)
        on = m.command_for_attempt(Path("/product"), Path("/godot"),
                                   Path("/run"), True, 240)
        self.assertEqual(on[:-1], off)
        self.assertEqual(on[-1], "--r31p23r22-attested-compact")
        self.assertIn("--r31p23r21-single-pass-compact", off)
        self.assertIn("--r31p23r2-flush-attribution", off)
        self.assertEqual([m.arm_for(i, "OFF_ON") for i in range(10)],
                         ["OFF", "ON"]*5)

    def test_sha256_manifest_retains_original(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)
            (p/"raw.log").write_text("original")
            (p/"sha256-manifest.json").write_text("derived")
            docs = m.hash_tree(p, ("sha256-manifest.json",))
            self.assertEqual(len(docs), 1)
            self.assertEqual(docs[0]["sha256"], m.sha256_file(p/"raw.log"))


if __name__ == "__main__":
    unittest.main()
