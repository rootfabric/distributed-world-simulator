"""Strict proof for real three-actor v2/v1 staging; do not launder PERF FAIL.

Fixtures are synthetic ONLY to falsify receipt-validation logic; actual staging
must still provide complete signed/hashed original Godot traces and manifests.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
import verify_815_live_deploy as d

RAW="d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d"


def generate(root:Path, count=123, raw=RAW):
    manifest={
        "scenario":"r31-reconnect-roundtrip","profile":"LOCAL","mode":"headless",
        "r31_815_compact_server_mode":"prefer_v2",
        "r31_815_compact_client_a_mode":"require_v2",
        "r31_815_compact_client_b_mode":"off",
        "r31p23r22_attested_compact":True,
        "run_id":"a"*16,"completed":True,"errors":[],
        "identity":{"head":"b"*40,"tree":"c"*40,"godot_sha256":"d"*64,
                    "asset_manifest_sha256":raw,"asset_count":count}
    }
    report={
        "verdict":"FAIL","infrastructure":[],
        "processes":[{"role":"server","verdict":"FAIL","tick_hz":59.95,
                      "dropped_time_delta_s":0.0},
                     {"role":"a","verdict":"PASS"},
                     {"role":"b","verdict":"PASS"}]
    }
    (root/"manifest.json").write_text(json.dumps(manifest))
    (root/"report.json").write_text(json.dumps(report))
    for role in ("server","a","b"):
        (root/role).mkdir()
        (root/role/"runtime.log").write_text("normal native double")
        (root/role/"measure.end.ack").write_text("ack")
    return manifest,report


def trace(role):
    messages={
        "server":[("r31_815_compact_codec_selected",{"selected":"f64-v2"}),
                  ("r31_815_compact_codec_selected",{"selected":"legacy-v1"}),
                  ("r31_815_compact_v2_sent",{"schema":"planet_simulator.compact_gameplay_snapshot.v2"})],
        "a":[("r31_815_compact_codec_negotiated",{"selected":"f64-v2"}),
             ("r31_815_compact_v2_received",{"schema":"planet_simulator.compact_gameplay_snapshot.v2"})],
        "b":[("r31_815_compact_codec_negotiated",{"selected":"legacy-v1"})]
    }[role]
    kinds={"header":1,"snapshot_received":10}
    if role in ("a","b"):
        kinds["compact_snapshot_stages"]=4
    return {"role":role,"sha256":"f"*64,"count":40,
            "kinds":kinds,"messages":messages}


class StrictMixedDeployment(unittest.TestCase):
    def test_real_mixed_receipts_keep_original_p99_fail(self):
        with TemporaryDirectory() as t:
            root=Path(t)
            generate(root)
            with patch.object(d,"read_trace",side_effect=lambda _root,r,_id: trace(r)):
                result=d.validate(root)
            self.assertEqual(result["original_normative_verdict"],"FAIL")
            self.assertEqual(result["verdict"],
                             "TEST_DEPLOY_FUNCTIONAL_EVIDENCE_ONLY_NO_GUI_PERF_ACCEPTANCE")
            self.assertFalse(result["current_production_deployed"])
            self.assertFalse(result["historical_815_closed"])
            self.assertFalse(result["ready_for_merge"])

    def test_wrong_asset_source_count_or_hash_fails_before_trace(self):
        for count,raw in ((0,RAW),(224,RAW),(123,"f"*64)):
            with TemporaryDirectory() as t:
                root=Path(t)
                generate(root,count,raw)
                with self.assertRaisesRegex(ValueError,"CANONICAL_QUATERNIUS_RAW_ASSETS"):
                    d.validate(root)

    def test_missing_real_v2_decoder_or_v1_movement_stage_is_not_success(self):
        for missing in ("v2_received","legacy_received"):
            with TemporaryDirectory() as t:
                root=Path(t)
                generate(root)
                def fake(_root,role,_id):
                    r=trace(role)
                    if missing=="v2_received" and role=="a":
                        r["messages"]=[v for v in r["messages"] if v[0]!="r31_815_compact_v2_received"]
                    if missing=="legacy_received" and role=="b":
                        r["kinds"].pop("compact_snapshot_stages",None)
                    return r
                with patch.object(d,"read_trace",side_effect=fake):
                    with self.assertRaisesRegex(ValueError,"NO_ACTUAL_CLIENT_A_V2_DECODE|CLIENT_B_NEVER_DECODED_ACCEPTED_COMPACT"):
                        d.validate(root)

    def test_missing_ack_or_checksum_error_fails_closed(self):
        for incident in ("noack","checksum"):
            with TemporaryDirectory() as t:
                root=Path(t)
                generate(root)
                if incident=="noack":
                    (root/"a"/"measure.end.ack").unlink()
                else:
                    (root/"server"/"runtime.log").write_text("PAYLOAD_CHECKSUM_MISMATCH")
                with patch.object(d,"read_trace",side_effect=lambda _root,r,_id: trace(r)):
                    with self.assertRaisesRegex(ValueError,"MEASURE_ACK_MISSING|CHECKSUM_OR_VERSION_FAILURE"):
                        d.validate(root)

    def test_server_fixed_tick_below_original_threshold_is_not_accepted(self):
        with TemporaryDirectory() as t:
            root=Path(t)
            _manifest,report=generate(root)
            report["processes"][0]["tick_hz"]=58
            (root/"report.json").write_text(json.dumps(report))
            with patch.object(d,"read_trace",side_effect=lambda _root,r,_id: trace(r)):
                with self.assertRaisesRegex(ValueError,"SERVER_AUTHORITATIVE_FIXED_TICK_REGRESSED"):
                    d.validate(root)


if __name__=="__main__":
    unittest.main()
