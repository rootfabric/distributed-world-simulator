"""Codex R3 falsifiers: actual JSONL traces, no read_trace mocking.

Staging MUST reject functional failures, omitted session/handshake proof,
post-reconnect packet gaps, v1/v2 downgrade, trace loss and missing assets.
"""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
import verify_815_live_deploy as stage

RUN_ID="d"*16
SOURCE_SHA="e"*40
TREE_SHA="f"*40
HASH=stage.RAW_ASSETS


def h(text:str)->str:
    return hashlib.sha256(text.encode()).hexdigest()


def event(kind:str, fmt:str, session:str, hs:str, role:str)->dict:
    data={"session_sha256":h(session),"handshake_sha256":h(hs)}
    if kind in (stage.SELECTED,*stage.TX.values()):
        data["peer_sha256"]=h("peer/"+role)
    if kind in (stage.SELECTED,stage.NEGOTIATED):
        data["selected"]=fmt
    if kind in (*stage.TX.values(),*stage.RX.values(),*stage.APPLIED.values()):
        data["schema"]=("planet_simulator.compact_gameplay_snapshot.v2"
                         if fmt=="f64-v2" else
                         "planet_simulator.compact_gameplay_snapshot.v1")
        data["server_tick"]=66
    if kind in stage.APPLIED.values():
        data["replica_revision"]=21
    return {"kind":kind,"data":data}


def build_fixture(root:Path):
    manifest={
        "scenario":"r31-reconnect-roundtrip", "profile":"LOCAL",
        "mode":"headless","r31_815_compact_server_mode":"prefer_v2",
        "r31_815_compact_client_a_mode":"require_v2",
        "r31_815_compact_client_b_mode":"off",
        "r31p23r22_attested_compact":True, "run_id":RUN_ID,
        "completed":True,"errors":[],
        "phase_results":[{"phase":"r31_reconnect_roundtrip","result":{
            "a_secondary":True,"b_reconnect":True,"a_primary_return":True}}],
        "identity":{"head":SOURCE_SHA,"tree":TREE_SHA,
                    "godot_sha256":"a"*64,
                    "asset_manifest_sha256":HASH,"asset_count":123}
    }
    reports=[
        {"role":"server","verdict":"FAIL","failures":["frame p99 >25ms"],
         "problems":[],"tick_hz":60.02,"dropped_time_delta_s":0.0},
        {"role":"a","verdict":"PASS","failures":[],"problems":[],
         "remote_distance_m":2.0},
        {"role":"b","verdict":"PASS","failures":[],"problems":[],
         "remote_distance_m":3.0},
    ]
    report={"verdict":"FAIL","functional_scenario":"PASS","infrastructure":[],
            "processes":reports}
    (root/"manifest.json").write_text(json.dumps(manifest),encoding="utf-8")
    (root/"report.json").write_text(json.dumps(report),encoding="utf-8")
    events={
        "server":[
            event(stage.SELECTED,"f64-v2","a1","ha1","a"),
            event(stage.SELECTED,"legacy-v1","b1","hb1","b"),
            event(stage.TX["f64-v2"],"f64-v2","a1","ha1","a"),
            event(stage.TX["legacy-v1"],"legacy-v1","b1","hb1","b"),
            event(stage.SELECTED,"legacy-v1","b2","hb2","b"),
            event(stage.TX["legacy-v1"],"legacy-v1","b2","hb2","b"),
        ],
        "a":[
            event(stage.NEGOTIATED,"f64-v2","a1","ha1","a"),
            event(stage.RX["f64-v2"],"f64-v2","a1","ha1","a"),
            event(stage.APPLIED["f64-v2"],"f64-v2","a1","ha1","a"),
        ],
        "b":[
            event(stage.NEGOTIATED,"legacy-v1","b1","hb1","b"),
            event(stage.RX["legacy-v1"],"legacy-v1","b1","hb1","b"),
            event(stage.APPLIED["legacy-v1"],"legacy-v1","b1","hb1","b"),
            event(stage.NEGOTIATED,"legacy-v1","b2","hb2","b"),
            event(stage.RX["legacy-v1"],"legacy-v1","b2","hb2","b"),
            event(stage.APPLIED["legacy-v1"],"legacy-v1","b2","hb2","b"),
        ]
    }
    write_actor_traces(root,events)
    return manifest,report,events


def write_actor_traces(root:Path, events:dict)->None:
    for role,typed_events in events.items():
        sub=root/role
        sub.mkdir(exist_ok=True)
        (sub/"runtime.log").write_text("normal network flow",encoding="utf-8")
        (sub/"measure.end.ack").write_text("1")
        rows=[{"kind":"header","data":{
            "schema":"dws.net_smooth.trace.v1","role":role,"run_id":RUN_ID
        }}]
        rows.extend(typed_events)
        if role in ("a","b"):
            rows.extend([
                {"kind":"compact_snapshot_stages","data":{"decode_ms":0.1}},
                {"kind":"snapshot_received","data":{"type":"COMPACT_GAMEPLAY_SNAPSHOT"}},
            ])
        written=[]
        for n,row in enumerate(rows,1):
            written.append(json.dumps({"n":n,"t_us":n*1000,"measure":n>1,
                "kind":row["kind"],"data":row["data"]},separators=(",",":")))
        end={"n":len(rows)+1,"t_us":(len(rows)+1)*1000,"measure":False,
             "kind":"end","data":{"written":len(rows),"produced":len(rows),
                                  "dropped":0,"io_errors":0}}
        written.append(json.dumps(end,separators=(",",":")))
        (sub/"trace.jsonl").write_text("\n".join(written)+"\n",encoding="utf-8")


class StrictReceipt(unittest.TestCase):
    def run_case(self,mutate=None):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            manifest,report,events=build_fixture(root)
            if mutate:
                mutate(root,manifest,report,events)
                (root/"manifest.json").write_text(json.dumps(manifest))
                (root/"report.json").write_text(json.dumps(report))
                write_actor_traces(root,events)
            return stage.validate(root)

    def test_valid_three_actor_two_session_functional_with_original_perf_fail(self):
        result=self.run_case()
        self.assertEqual(result["original_normative_verdict"],"FAIL")
        self.assertEqual(result["verified_sessions"]["a"]["verified_session_count"],1)
        self.assertEqual(result["verified_sessions"]["b"]["verified_session_count"],2)
        self.assertFalse(result["performance_accepted"])
        self.assertFalse(result["current_production_deployed"])
        self.assertFalse(result["ready_for_merge"])
        self.assertTrue(result["verified_sessions"]["b"]["matched_replica_apply_per_session"])

    def test_functional_failure_cannot_be_laundered_as_perf_fail(self):
        for role,reason in [
            ("a","prediction reconcile failures"),
            ("a","client not continuously connected in measured phase"),
            ("b","backwards EXTRAPOLATE->HOLD jump"),
            ("server","new server command rejections"),
            ("server","durable commit failures: 1"),
            ("server","scheduler dropped time"),
            ("server","simulation <59Hz"),
        ]:
            def change(root,m,r,e):
                row=next(p for p in r["processes"] if p["role"]==role)
                row["verdict"]="FAIL"
                row["failures"]=[reason]
            with self.subTest(role=role,reason=reason):
                with self.assertRaisesRegex(ValueError,"ORIGINAL_FUNCTIONAL_FAILURE"):
                    self.run_case(change)

    def test_missing_new_b_reconnect_receipt_rejected(self):
        def change(root,m,r,e):
            e["b"]=[row for row in e["b"] if not (
                row["kind"]==stage.RX["legacy-v1"] and
                row["data"]["session_sha256"]==h("b2"))]
        with self.assertRaisesRegex(ValueError,"MISSING_DECODED_COMPACT_IN_NEGOTIATED_SESSION"):
            self.run_case(change)

    def test_post_reconnect_successful_decode_does_not_prove_replica_apply(self):
        def change(root,m,r,e):
            e["b"]=[row for row in e["b"] if not (
                row["kind"]==stage.APPLIED["legacy-v1"] and
                row["data"]["session_sha256"]==h("b2"))]
        with self.assertRaisesRegex(ValueError,"MISSING_APPLIED_COMPACT_IN_NEGOTIATED_SESSION"):
            self.run_case(change)

    def test_server_old_session_receipt_cannot_prove_new_b_connection(self):
        def change(root,m,r,e):
            e["server"]=[row for row in e["server"] if not (
                row["kind"]==stage.TX["legacy-v1"] and
                row["data"]["session_sha256"]==h("b2"))]
        with self.assertRaisesRegex(ValueError,"MISSING_SERVER_SEND_IN_NEGOTIATED_SESSION"):
            self.run_case(change)

    def test_missing_session_or_handshake_fields_are_fatal(self):
        for key in ("session_sha256","handshake_sha256","peer_sha256"):
            def change(root,m,r,e):
                e["server"][0]["data"].pop(key,None)
            with self.subTest(field=key):
                with self.assertRaisesRegex(ValueError,"MISSING_SESSION_OR_HANDSHAKE_BINDING|MISSING_SERVER_PEER_BINDING"):
                    self.run_case(change)

    def test_cross_handshake_reuse_cannot_claim_proof(self):
        def change(root,m,r,e):
            next(row for row in e["b"] if row["kind"]==stage.RX["legacy-v1"] and row["data"]["session_sha256"]==h("b2"))["data"]["handshake_sha256"]=h("hb1")
        with self.assertRaisesRegex(ValueError,"MISSING_DECODED_COMPACT_IN_NEGOTIATED_SESSION"):
            self.run_case(change)

    def test_b_cannot_receive_v2(self):
        def change(root,m,r,e):
            e["b"].append(event(stage.RX["f64-v2"],"f64-v2","b2","hb2","b"))
        with self.assertRaisesRegex(ValueError,"CLIENT_RECEIVED_UNNEGOTIATED_FORMAT"):
            self.run_case(change)

    def test_wrong_assets_or_no_reconnect_scenario(self):
        def bad_assets(root,m,r,e):m["identity"]["asset_count"]=224
        with self.assertRaisesRegex(ValueError,"CANONICAL_QUATERNIUS"):
            self.run_case(bad_assets)
        def incomplete(root,m,r,e):m["phase_results"]=[]
        with self.assertRaisesRegex(ValueError,"ORIGINAL_R31_RECONNECT_SCENARIO_MISSING"):
            self.run_case(incomplete)

    def test_trace_loss_rejected_without_mock(self):
        def change(root,m,r,e):
            # This intentionally edits REAL generated JSONL after fixture creation.
            pass
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            build_fixture(root)
            path=root/"server"/"trace.jsonl"
            rows=path.read_text().splitlines()
            last=json.loads(rows[-1]);last["data"]["dropped"]=1
            rows[-1]=json.dumps(last)
            path.write_text("\n".join(rows)+"\n")
            with self.assertRaisesRegex(ValueError,"TRACE_DROPPED_OR_NOT_DRAINED"):
                stage.validate(root)


if __name__=="__main__":
    unittest.main()
