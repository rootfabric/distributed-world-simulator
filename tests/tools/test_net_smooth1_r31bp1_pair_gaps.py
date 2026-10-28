"""P1 paired gap comparison recognizes OFF=P1 disabled, R31a/P0 both ON."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from compare_r31bp1_paired_gaps import compare


def fixture(root:Path,enabled:bool,sha:str="engine")->None:
    root.mkdir()
    manifest={
        "mode":"gui","profile":"LOCAL","scenario":"r31-reconnect-roundtrip",
        "completed":True,"errors":[],"duration_s":120,
        "r3c4r31_replay_projection":True,"r3c4r31b_durable_attribution":True,
        "r3c4r2_worker_envelope":True,"r3c4_periodic_frame_pacing":True,
        "r31bp1_durable_chunks":enabled,
        "identity":{"head":"head","tree":"tree","tracked_dirty":False,
                    "godot_sha256":sha,"asset_manifest_sha256":"assets",
                    "asset_count":123}
    }
    (root/"manifest.json").write_text(json.dumps(manifest),encoding="utf-8")
    for role in ("server","a","b"):
        directory=root/role
        directory.mkdir()
        events=[{"kind":"header","t_us":0,"data":{}}]
        for i in range(150):
            t=15000+17000*i
            ms=120.0 if i==55 and enabled and role=="server" else 17.0
            events.append({"kind":"frame","t_us":t,"measure":True,
                           "data":{"interval_ms":ms}})
            if role=="server":
                events.append({"kind":"server_loop","t_us":t+1,
                               "measure":True,"data":{"process_ms":5.0}})
        events.append({"kind":"end","t_us":4000000,"data":{}})
        (directory/"trace.jsonl").write_text(
            "".join(json.dumps(x)+"\n" for x in events),encoding="utf-8")


class PairedGate(unittest.TestCase):
    def test_three_pairs_compare_and_gap_visible(self):
        with tempfile.TemporaryDirectory() as d:
            pairs=[]
            for i in range(3):
                off=Path(d)/f"off{i}"
                on=Path(d)/f"on{i}"
                fixture(off,False)
                fixture(on,True)
                pairs.append((off,on))
            summary=compare(pairs)
            self.assertEqual(summary["verdict"],"PAIRED_GAP_DIAGNOSTIC_ONLY")
            self.assertEqual(summary["arm_summary"]["off"]["server"][
                "frame_gap_over_100ms"],[0,0,0])
            self.assertEqual(summary["arm_summary"]["on"]["server"][
                "frame_gap_over_100ms"],[1,1,1])
            self.assertIn("P1 durable chunks disabled",summary["notes"][1])

    def test_mismatched_engine_fails(self):
        with tempfile.TemporaryDirectory() as d:
            pairs=[]
            for i in range(3):
                off=Path(d)/f"off{i}"
                on=Path(d)/f"on{i}"
                fixture(off,False)
                fixture(on,True,sha="different" if i==1 else "engine")
                pairs.append((off,on))
            with self.assertRaisesRegex(ValueError,"godot_sha256_MISMATCH"):
                compare(pairs)

    def test_missing_common_flag_fails(self):
        with tempfile.TemporaryDirectory() as d:
            pairs=[]
            for i in range(3):
                off=Path(d)/f"off{i}"
                on=Path(d)/f"on{i}"
                fixture(off,False)
                fixture(on,True)
                pairs.append((off,on))
            m=pairs[0][0]/"manifest.json"
            data=json.loads(m.read_text())
            data["r3c4r31b_durable_attribution"]=False
            m.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,"P1_MISSING_COMMON_FLAG"):
                compare(pairs)

    def test_not_three_pairs_invalid(self):
        with self.assertRaisesRegex(ValueError,"P1_NEEDS_THREE_MATCHED_PAIRS"):
            compare([])


if __name__=="__main__":
    unittest.main()
