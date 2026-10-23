"""R31P23 R2.0 strict real-frame COMPACT boundary/simulator/ENet reducer REDs."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from analyze_r31p23r2_flush_layers import analyze
from test_net_smooth1_r31p22_loop_stages import fixture, RUN_ID


def decorate(root:Path, mutator=None, *, no_passthrough=False, r21=None):
    (root/"server").mkdir(parents=True,exist_ok=True)
    rows=fixture()
    sample_index=0
    augmented=[]
    for row in rows[:-1]:
        if row.get("kind")=="r31p22_compact_wire_stages":
            sample_index+=1
            rid=row["data"]["engine_frame"]
            details={
                "engine_frame":rid,
                "channel":"SNAPSHOT",
                "delivery_mode":"UNRELIABLE_SEQUENCED",
                "frame_id":f"frame/peer/{sample_index}",
                "session_sequence":sample_index,
                "attempt_number":1,
                "queue_stage_ms":.001,
                "detached_frame_copy_ms":.002,
                "port_call_ms":.005,
                "success":True,
                "error_code":"",
                "simulator":{
                    "passthrough":not no_passthrough,
                    "frame_validate_ms":.001,
                    "canonical_json_ms":.001,
                    "pre_delegate_ms":.0005,
                    "delegate_ms":.0015,
                    "enet":{
                        "validate_ms":.0002,
                        "frame_encode_ms":.0005,
                        "channel_setup_ms":.0002,
                        "put_packet_ms":.0002,
                        "peer_stats_ms":.0002,
                        "total_ms":.0013,
                    } if not no_passthrough else {},
                },
            }
            if r21 is not None and not no_passthrough:
                details["simulator"]["r31p23r21_fast_encode"]=r21
                details["simulator"]["r31p23r21_size_reused"]=r21
            augmented.append({**row, "kind":"r31p23r2_flush_packet", "data":details})
        augmented.append(row)
    if mutator:
        mutator(augmented)
    for i,row in enumerate(augmented,1):
        row["n"]=i
    footer=rows[-1]
    footer["data"]["produced"]=len(augmented)
    footer["data"]["written"]=len(augmented)
    augmented.append(footer)
    trace=root/"server"/"trace.jsonl"
    trace.write_text("".join(json.dumps(x)+"\n" for x in augmented),encoding="utf-8")
    manifest={
        "run_id":RUN_ID,
        "r31p23r2_flush_attribution":True,
        "r31p22_loop_attribution":True,
        "r31bp1_durable_chunks":True,
        "r3c4r2_worker_envelope":True,
    }
    if r21 is not None:
        manifest["r31p23r21_single_pass_compact"]=r21
    (root/"manifest.json").write_text(json.dumps(manifest),encoding="utf-8")
    (root/"report.json").write_text(
        '{"verdict":"FAIL","reason":"server frame p99 >25"}',encoding="utf-8")
    return root


class LayerFalsifier(unittest.TestCase):
    def run_case(self,mutator=None,*,error=None,no_passthrough=False,r21=None):
        with tempfile.TemporaryDirectory() as d:
            root=decorate(Path(d),mutator,
                          no_passthrough=no_passthrough,r21=r21)
            if error:
                with self.assertRaisesRegex(ValueError,error):
                    analyze(root)
                return
            trace=root/"server"/"trace.jsonl"
            before=trace.read_bytes()
            x=analyze(root)
            self.assertEqual(before,trace.read_bytes())
            return x

    def test_full_100_packet_three_layer_join_preserves_orig_fail(self):
        out=self.run_case()
        self.assertEqual(out["verdict"],
            "R31P23R2_TRANSPORT_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS")
        self.assertEqual(out["normative_original_verdict"],"FAIL")
        self.assertEqual(out["all_original_compact_events"],100)
        self.assertEqual(out["all_nested_flush_events"],100)
        self.assertEqual(out["passthrough_events"],100)
        self.assertAlmostEqual(out["enet_stage_ms"]["frame_encode_ms"]["p99"],.0005)
        self.assertEqual(out["simulator_stage_ms"]["canonical_json_ms"]["n"],100)
        self.assertEqual(out["worst_flush_frames"][0]["wire_count"],2)

    def test_r21_on_and_off_every_real_compact_receipt_is_proved(self):
        on=self.run_case(r21=True)
        off=self.run_case(r21=False)
        self.assertIs(on["r21_requested"],True)
        self.assertEqual(on["r21_confirmed_passthrough_events"],100)
        self.assertIs(off["r21_requested"],False)
        self.assertEqual(off["r21_confirmed_passthrough_events"],100)
        self.assertEqual(on["normative_original_verdict"],"FAIL")
        self.assertEqual(off["normative_original_verdict"],"FAIL")

    def test_r21_one_missing_optin_activation_fails_closed(self):
        def wrong(rows):
            first=next(r for r in rows
                       if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["simulator"]["r31p23r21_fast_encode"]=False
        self.run_case(wrong,r21=True,error="R21_FAST_ENCODE_OR_SIZE_RECEIPT_MISMATCH")

    def test_r21_unexpected_fastpath_in_off_arm_fails_closed(self):
        def wrong(rows):
            first=next(r for r in rows
                       if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["simulator"]["r31p23r21_size_reused"]=True
        self.run_case(wrong,r21=False,error="R21_FAST_ENCODE_OR_SIZE_RECEIPT_MISMATCH")

    def test_r21_simulated_delayed_profile_must_stay_separate(self):
        sample=self.run_case(r21=True,no_passthrough=True)
        self.assertEqual(sample["r21_confirmed_passthrough_events"],0)
        self.assertEqual(sample["condition_queued_events"],100)
        self.assertEqual(sample["enet_stage_ms"]["put_packet_ms"]["n"],0)

    def test_simulated_profile_is_not_mislabeled_as_real_enet(self):
        x=self.run_case(no_passthrough=True)
        self.assertEqual(x["condition_queued_events"],100)
        self.assertEqual(x["passthrough_events"],0)
        self.assertEqual(x["enet_stage_ms"]["put_packet_ms"]["n"],0)

    def test_one_missing_inner_event_fails(self):
        def f(rows):
            idx=next(i for i,r in enumerate(rows)
                     if r["kind"]=="r31p23r2_flush_packet")
            rows.pop(idx)
        self.run_case(f,error="INCOMPLETE_COMPACT_COVERAGE")

    def test_one_duplicate_frame_identity_fails(self):
        def f(rows):
            selected=[r for r in rows if r["kind"]=="r31p23r2_flush_packet"]
            selected[1]["data"]["frame_id"]=selected[0]["data"]["frame_id"]
        self.run_case(f,error="DUPLICATE_OR_INVALID_FRAME_ID")

    def test_unexpected_compact_channel_fails(self):
        def f(rows):
            first=next(r for r in rows if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["delivery_mode"]="RELIABLE_ORDERED"
        self.run_case(f,error="UNEXPECTED_COMPACT_CHANNEL_OR_MODE")

    def test_failed_send_is_never_silent(self):
        def f(rows):
            first=next(r for r in rows if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["success"]=False
            first["data"]["error_code"]="ENET_SEND_FAILED"
        self.run_case(f,error="FAILED_COMPACT_WIRE_SEND")

    def test_simulator_time_exceeding_port_is_inconclusive(self):
        def f(rows):
            first=next(r for r in rows if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["simulator"]["canonical_json_ms"]=2.0
        self.run_case(f,error="SIMULATOR_EXCEEDS_PORT_CALL")

    def test_non_additive_enet_stages_rejected(self):
        def f(rows):
            first=next(r for r in rows if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["simulator"]["enet"]["frame_encode_ms"]=1.0
        self.run_case(f,error="ENET_COMPONENTS_NOT_ADDITIVE")

    def test_boundary_time_exceeding_original_compact_flush_rejected(self):
        def f(rows):
            first=next(r for r in rows if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["port_call_ms"]=.6
        self.run_case(f,error="LAYER_STAGES_EXCEED_ORIGINAL_FLUSH")

    def test_missing_simulator_metadata_rejected(self):
        def f(rows):
            first=next(r for r in rows if r["kind"]=="r31p23r2_flush_packet")
            first["data"]["simulator"]={}
        self.run_case(f,error="SIMULATOR_PROFILE_MISSING")


if __name__=="__main__":
    unittest.main()
