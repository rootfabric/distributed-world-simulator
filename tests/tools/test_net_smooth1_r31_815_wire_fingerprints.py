"""#815 fingerprint joins must use exact SHA, never cross-clock timestamps.

Synthetic minimal original trace fixtures; native Godot numeric test is separate.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
import analyze_r31_815_wire_fingerprints as reducer

RUN_ID="b"*16
SHA="a"*64
FRAME_ID="frame/r31/815/float/7"
SCHEMA="dws.net_smooth.r31_815.wire_checksum_fingerprint.v1"


def fingerprint(phase, *, sender=True, digest=SHA, frame_id=FRAME_ID):
    return {
        "schema":SCHEMA,"phase":phase,"error_code":
            "PAYLOAD_CHECKSUM_MISMATCH" if phase=="rx_reject" else "",
        "packet_sha256":digest,"frame_id":frame_id,
        "message_type":"JOIN_ACK",
        "advertised_payload_sha256":"a"*64,
        "postparse_payload_sha256":"b"*64,
        "sender_checksum_matches":True if sender else None,
        "postparse_checksum_matches":False,
        "raw_payload_redacted":True,
    }


def write_trace(root:Path,role:str,received=None,dropped=0):
    (root/role).mkdir(parents=True)
    rows=[
        {"n":1,"t_us":100 if role=="server" else 999999,
         "kind":"header","measure":False,"data":{
            "schema":"dws.net_smooth.trace.v1","run_id":RUN_ID,
            "role":role,"clock":"PROCESS_LOCAL_MONOTONIC_US"}},
    ]
    if received:
        rows.append({"n":2,"t_us":222 if role=="server" else 1000000,
                     "kind":"r31_815_wire_fingerprint","measure":False,
                     "data":received})
    rows.append({"n":0,"t_us":350 if role=="server" else 1100000,
                 "kind":"end","measure":False,"data":{
                    "produced":len(rows),"written":len(rows),
                    "dropped":dropped,"io_errors":0}})
    (root/role/"trace.jsonl").write_text(
        "".join(json.dumps(x,separators=(",",":"))+"\n" for x in rows),
        encoding="utf-8")


def setup(root:Path,*,changed_hash=False,changed_frame=False,
          bad_sender_checksum=False,dropped=0):
    (root/"manifest.json").write_text(json.dumps({
        "run_id":RUN_ID,"mode":"gui","scenario":"r31-reconnect-roundtrip",
        "r31_815_wire_forensics":True,
        "forensic_evidence_class":"CHECKSUM_FINGERPRINT_DIAGNOSTIC_ONLY",
        "identity":{"head":"c"*40,"tree":"d"*40,
                    "asset_count":123,"godot_sha256":"e"*64,
                    "asset_manifest_sha256":"f"*64},
    }),encoding="utf-8")
    (root/"report.json").write_text('{"verdict":"INCONCLUSIVE"}',
                                   encoding="utf-8")
    sender=fingerprint("tx_enet",sender=not bad_sender_checksum)
    target=fingerprint("rx_reject",sender=False,
        digest="d"*64 if changed_hash else SHA,
        frame_id="frame/other/815" if changed_frame else FRAME_ID)
    write_trace(root,"server",sender,dropped=dropped)
    write_trace(root,"a",target)
    write_trace(root,"b")


class Wire815(unittest.TestCase):
    def test_exact_packet_and_frame_correlation_is_non_normative(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            setup(root)
            pre=(root/"server"/"trace.jsonl").read_bytes()
            got=reducer.analyze(root)
            self.assertEqual(pre,(root/"server"/"trace.jsonl").read_bytes())
            self.assertEqual(got["original_normative_verdict"],"INCONCLUSIVE")
            self.assertEqual(got["actual_decode_reject_count"],1)
            self.assertEqual(got["rejects"][0]["classification"],
                "SAME_EXACT_PACKET_SOURCE_VALID_POSTPARSE_CHECKSUM_MISMATCH")
            self.assertEqual(got["rejects"][0]["source_roles"],["server"])
            self.assertTrue(got["rejects"][0]["sender_receipts"][0]["sender_checksum_matches"])
            self.assertFalse(got["rejects"][0]["numeric_root_cause_proven"])
            self.assertEqual(got["sender_original_proof_missing_count"],0)
            self.assertEqual(got["verdict"],
                "INDEPENDENT_DIAGNOSTIC_ONLY_ISSUE_815_OPEN")

    def test_changed_packet_or_frame_never_joins_by_approximate_clock(self):
        for kwargs in ({"changed_hash":True},{"changed_frame":True}):
            with TemporaryDirectory() as d:
                root=Path(d)
                setup(root,**kwargs)
                got=reducer.analyze(root)
                self.assertEqual(got["rejects"][0]["classification"],
                                 "UNMATCHED_RECEIVE_REJECT_SOURCE_BYTES_UNKNOWN")

    def test_sender_checksum_not_verified_cannot_claim_float_drift(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            setup(root,bad_sender_checksum=True)
            got=reducer.analyze(root)
            self.assertEqual(got["rejects"][0]["classification"],
                             "SAME_EXACT_PACKET_R22_ORIGINAL_SOURCE_ATTESTATION_MISSING")
            self.assertEqual(got["sender_original_proof_missing_count"],1)
            self.assertEqual(got["unattested_sender_postparse_mismatch_count"],1)
            self.assertIsNone(got["rejects"][0]["sender_receipts"][0]["sender_checksum_matches"])

    def test_same_exact_packet_sender_and_receiver_parses_disagree(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            setup(root)
            path=root/"server"/"trace.jsonl"
            lines=[json.loads(row) for row in path.read_text().splitlines()]
            lines[1]["data"]["postparse_checksum_matches"]=True
            path.write_text("".join(json.dumps(row)+"\n" for row in lines))
            got=reducer.analyze(root)
            self.assertEqual(got["rejects"][0]["classification"],
                "SAME_EXACT_PACKET_TX_RX_POSTPARSE_DIVERGENCE")
            self.assertFalse(got["rejects"][0]["numeric_root_cause_proven"])

    def test_present_but_invalid_sender_source_checksum_is_not_drift_proof(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            setup(root)
            path=root/"server"/"trace.jsonl"
            lines=[json.loads(row) for row in path.read_text().splitlines()]
            lines[1]["data"]["sender_checksum_matches"]=False
            path.write_text("".join(json.dumps(row)+"\n" for row in lines))
            got=reducer.analyze(root)
            self.assertEqual(got["rejects"][0]["classification"],
                "SAME_EXACT_PACKET_SOURCE_CHECKSUM_INVALID")

    def test_trace_loss_rejected_not_silently_ignored(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            setup(root,dropped=1)
            with self.assertRaisesRegex(ValueError,"R31_815_TRACE_FOOTER"):
                reducer.analyze(root)

    def test_no_fingerprint_optin_rejected(self):
        with TemporaryDirectory() as d:
            root=Path(d)
            setup(root)
            p=root/"manifest.json"
            value=json.loads(p.read_text())
            value["r31_815_wire_forensics"]=False
            p.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError,"OPT_IN_MISSING"):
                reducer.analyze(root)

    def test_native_sources_are_pure_forensic_and_fences_stay_enabled(self):
        enet=(ROOT/"scripts/network/transports/v2/enet_multi_peer_transport_port.gd").read_text()
        helper=(ROOT/"scripts/network/smoothness/r31_815_wire_checksum_forensics.gd").read_text()
        runner=(ROOT/"tools/net_smooth1/run_net_smooth1.py").read_text()
        proto=(ROOT/"scripts/network/transports/v2/protocol_frame_v2.gd").read_text()
        for needle in ("_r31_815_emit_wire(\"rx_reject\"","r31_815_wire_fingerprint",
                       "R31ChecksumForensics.MAX_EVENTS_PER_PROCESS"):
            # Code may break across lines; verify real behavior in source.
            self.assertTrue(needle in enet or needle.replace("_r31_815_emit_wire(\"rx_reject\"","\"rx_reject\"") in enet)
        self.assertIn("if not R31ChecksumForensics.enabled()",enet)
        self.assertIn("FrameScript.decode(packet, MAX_PACKET_BYTES)",enet)
        self.assertIn("FrameScript.validate(frame)",enet)
        self.assertIn("MAX_EVENTS_PER_PROCESS: int = 16000",helper)
        self.assertIn('OS.get_environment(OPT_IN_ENV) == "1"',helper)
        self.assertIn('env.pop(\'DWS_NET_R31_815_WIRE_FORENSICS\',None)',runner)
        self.assertIn("r31_815_wire_forensics=args.r31_815_wire_forensics",runner)
        self.assertIn('return UtilsScript.validation_failure("PAYLOAD_CHECKSUM_MISMATCH"',proto)
        self.assertIn("r31_815_original_payload_sha256",enet)
        self.assertIn('NetworkUtilsScript.payload_hash(Dictionary(frame.get("payload", {})))',enet)
        self.assertIn('attested_source_payload_sha256',helper)
        self.assertIn('R22_ORIGINAL_VALIDATED_FRAME',helper)
        self.assertIn('sender_original_proof_missing_count',
                      (ROOT/"tools/net_smooth1/analyze_r31_815_wire_fingerprints.py").read_text())


if __name__=="__main__":
    unittest.main()
