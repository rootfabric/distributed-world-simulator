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
      "asset_manifest_sha256": "d"*64, "asset_count": 123}


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


    def test_asset_pack_uses_123_raw_sources_not_224_total_files(self):
        # Synthetic canonical pack: exact 123 raw files plus 101 .import
        # sidecars, same distinction as R2.2 runner identity, no data copied.
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for index in range(123):
                (root/("raw-%03d.asset" % index)).write_bytes(
                    ("source-%03d" % index).encode())
            for index in range(101):
                (root/("raw-%03d.asset.import" % index)).write_text(
                    "[remap]\nimporter=resource\n")
            first = m.scan_asset_pack(root)
            self.assertEqual(first["asset_count"], 123)
            self.assertEqual(first["asset_import_sidecars"], 101)
            self.assertEqual(first["asset_pack_file_count"], 224)
            m.check_asset_pack(first, 123, first["asset_manifest_sha256"])
            with self.assertRaisesRegex(ValueError, "QUATERNIUS_ASSET_COUNT_MISMATCH"):
                m.check_asset_pack(first, 224)
            with self.assertRaisesRegex(ValueError, "QUATERNIUS_ASSET_MANIFEST_SHA_MISMATCH"):
                m.check_asset_pack(first, 123, "0"*64)

            # Raw-byte corruption MUST be detected even though file count
            # remains 123. Changing an import sidecar never changes raw hash.
            (root/"raw-000.asset").write_bytes(b"CORRUPTED SOURCE")
            corrupt = m.scan_asset_pack(root)
            self.assertEqual(corrupt["asset_count"], 123)
            self.assertNotEqual(corrupt["asset_manifest_sha256"],
                                first["asset_manifest_sha256"])
            with self.assertRaisesRegex(ValueError, "QUATERNIUS_ASSET_MANIFEST_SHA_MISMATCH"):
                m.check_asset_pack(corrupt, 123, first["asset_manifest_sha256"])

    def test_sidecar_changes_cannot_mutate_source_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/"raw.asset").write_bytes(b"same-source")
            (root/"raw.asset.import").write_bytes(b"one-sidecar")
            first = m.scan_asset_pack(root)
            (root/"raw.asset.import").write_bytes(b"different-sidecar")
            second = m.scan_asset_pack(root)
            self.assertEqual(first["asset_manifest_sha256"],
                             second["asset_manifest_sha256"])
            self.assertEqual(first["asset_count"], second["asset_count"])
            (root/"raw.asset.uid").write_bytes(b"uid")
            third = m.scan_asset_pack(root)
            self.assertEqual(third["asset_uid_sidecars"], 1)
            self.assertEqual(third["asset_count"], 1)
            self.assertEqual(third["asset_manifest_sha256"],
                             first["asset_manifest_sha256"])

    def test_parser_defaults_match_exact_product_source_filter(self):
        content = FILE.read_text(encoding="utf-8")
        self.assertIn('parser.add_argument("--expected-asset-count", type=int, default=123', content)
        self.assertIn('--expected-asset-manifest-sha256', content)
        self.assertIn("QUATERNIUS_ASSET_MANIFEST_SHA_MISMATCH", content)
        self.assertNotIn('default=224', content)


if __name__ == "__main__":
    unittest.main()
