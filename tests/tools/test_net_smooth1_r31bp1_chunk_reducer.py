"""R31b P1 GUI chunk cache diagnostics: real warmup fallback and negatives."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from analyze_r31bp1_durable_chunks import analyze


def event(n:int, *, active=True, hit=True, bypass="", correct=True, oversized=False)->dict:
    stage=({
        "valid":True,"seam_coordinator_count":1,"player_count":2,
        "item_graph_cache_hit":hit,"resource_cache_hit":hit,
        "item_graph_bypass":bypass,"resource_bypass":"",
        "item_graph_cache_bytes":5*1024*1024 if oversized else 1024,
        "resource_cache_bytes":512,
        "item_graph_ms":.1,"resource_ms":.08,
        "validation_ms":7.0,"final_checksum_ms":3.4,"total_ms":11.2,
    } if active else {"fallback_ms":10.0,"seam_coordinator_count":0})
    return {
        "kind":"checkpoint_capture","measure":True,"t_us":n*1200000,
        "data":{
            "r31bp1_durable_chunks":correct,"r3c4r2_worker_envelope":True,
            "capture_ms":11.5,"authority_ms":11.2,"replay_ms":.15,
            "r31b_durable_stages":stage
        },
    }


def run(data:list[dict])->dict:
    with tempfile.TemporaryDirectory() as temp:
        path=Path(temp)/"server.jsonl"
        path.write_text("".join(json.dumps(x)+"\n" for x in data),encoding="utf-8")
        return analyze(path)


class ChunkFalsifier(unittest.TestCase):
    def test_realistic_warmup_fallback_and_warm_hits(self):
        data=[event(i,active=False) for i in range(18)]
        data += [event(i,hit=(i>18)) for i in range(18,79)]
        result=run(data)
        self.assertEqual(result["verdict"],"R31BP1_CHUNKS_DIAGNOSTIC_PASS")
        self.assertEqual(result["counts"]["seam_fallback"],18)
        self.assertEqual(result["counts"]["active"],61)
        self.assertGreater(result["cache_hit_rates"]["item_hits"],.98)

    def test_opt_in_required(self):
        data=[event(i,correct=False) for i in range(30)]
        result=run(data)
        self.assertEqual(result["verdict"],"R31BP1_CHUNKS_DIAGNOSTIC_FAIL")
        self.assertIn("R31BP1_OPT_IN_ABSENT",result["errors"])

    def test_budget_bypass_fails_even_with_many_hits(self):
        data=[event(1,hit=False,bypass="CHUNK_MEMORY_BUDGET")]
        data += [event(i) for i in range(2,79)]
        result=run(data)
        self.assertIn("R31BP1_CACHE_BYPASS_OBSERVED",result["errors"])

    def test_silent_oversize_fails(self):
        data=[event(i,oversized=True) for i in range(50)]
        result=run(data)
        self.assertIn("R31BP1_INVALID_CACHE_MEMORY_BUDGET",result["errors"])

    def test_insufficient_active_is_inconclusive_fail(self):
        data=[event(i,active=False) for i in range(78)]
        result=run(data)
        self.assertIn("R31BP1_INSUFFICIENT_ACTIVE_0",result["errors"])

    def test_no_validation_waiver(self):
        data=[event(i) for i in range(50)]
        data[4]["data"]["r31b_durable_stages"]["validation_ms"]=None
        result=run(data)
        self.assertTrue(any("validation_ms" in e for e in result["errors"]))


if __name__=="__main__":
    unittest.main()
