"""R31 #815: original complete trace must prove guard withheld receiver-invalid bytes."""
import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
sys.path.insert(0,str(ROOT/"tests/tools"))
import analyze_r31_815_wire_fingerprints as r
import test_net_smooth1_r31_815_wire_fingerprints as fixtures

FRAME="frame/815/guard/rejected"
HASH="f"*64


def prepare_guard_case(root,*,manifest_optin=True,leak=False,mutated=False):
    fixtures.setup(root)
    manifest_path=root/"manifest.json"
    manifest=json.loads(manifest_path.read_text())
    manifest["r31_815_outbound_guard"]=manifest_optin
    manifest_path.write_text(json.dumps(manifest))
    server=root/"server"/"trace.jsonl"
    rows=[json.loads(x) for x in server.read_text().splitlines()]
    guard={
        "n":3,"t_us":300,"kind":"r31_815_outbound_preflight_reject",
        "measure":False,
        "data":{
            "frame_id":fixtures.FRAME_ID if leak else FRAME,
            "packet_sha256":fixtures.SHA if leak else HASH,
            "decoder_error_code":"PAYLOAD_CHECKSUM_MISMATCH",
            "packet_bytes_mutated":mutated,
            "reject_index":1,
            "packet_bytes":1234,
        }
    }
    rows.insert(-1,guard)
    rows[-1]["data"]["produced"]=3
    rows[-1]["data"]["written"]=3
    server.write_text("".join(json.dumps(x)+"\n" for x in rows))
    return server


class GuardReceipt(unittest.TestCase):
    def test_pinned_guard_prevents_exact_receivable_packet_and_original_incidents_preserved(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            trace=prepare_guard_case(root)
            before=trace.read_bytes()
            report=r.analyze(root)
            self.assertEqual(before,trace.read_bytes())
            self.assertEqual(report["outbound_guard_reject_count"],1)
            self.assertTrue(report["outbound_guard_enabled"])
            self.assertEqual(report["outbound_guard_rejected_exact_packets"][0]["packet_sha256"],HASH)
            # There is one independent original unmodified RX reject fixture;
            # our guard must never relabel it as PASS.
            self.assertEqual(report["actual_decode_reject_count"],1)
            self.assertEqual(report["original_normative_verdict"],"INCONCLUSIVE")
            self.assertIn("ISSUE_815_OPEN",report["verdict"])

    def test_missing_guard_manifest_is_unattested_not_success(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            prepare_guard_case(root,manifest_optin=False)
            with self.assertRaisesRegex(ValueError,"GUARD_UNATTESTED_EVENTS"):
                r.analyze(root)

    def test_guarded_packet_that_was_actually_transmitted_is_fatal(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            prepare_guard_case(root,leak=True)
            with self.assertRaisesRegex(ValueError,"GUARD_LEAKED_EXACT_PACKET"):
                r.analyze(root)

    def test_false_mutation_flag_is_mandatory(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            prepare_guard_case(root,mutated=True)
            with self.assertRaisesRegex(ValueError,"GUARD_RECEIPT_INVALID"):
                r.analyze(root)

    def test_old_r1_no_guard_event_retains_same_classification(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            fixtures.setup(root,bad_sender_checksum=True)
            result=r.analyze(root)
            self.assertFalse(result["outbound_guard_enabled"])
            self.assertEqual(result["outbound_guard_reject_count"],0)
            self.assertEqual(result["actual_decode_reject_count"],1)
            self.assertEqual(result["rejects"][0]["classification"],
                             "SAME_EXACT_PACKET_R22_ORIGINAL_SOURCE_ATTESTATION_MISSING")


if __name__=="__main__":
    unittest.main()
