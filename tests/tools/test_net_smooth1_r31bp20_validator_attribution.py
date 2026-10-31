"""P2.0 exact validator instrumentation and strict trace reducer falsifiers."""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from analyze_r31bp20_validator_stages import analyze, P20_STAGES

P2=ROOT/"scripts/runtime/networked_gameplay/networked_gameplay_service_p2.gd"
P3=ROOT/"scripts/runtime/networked_gameplay/p3/networked_gameplay_service_p3.gd"
SEAM=ROOT/"scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
RUNNER=ROOT/"tools/net_smooth1/run_net_smooth1.py"


def method(src:str,name:str)->str:
    m=re.search(r"(?ms)^func "+re.escape(name)+r"\(.*?(?=^func |\Z)",src)
    if not m:
        raise AssertionError("missing GDScript func "+name)
    return m.group(0)


def event(index:int, *,fallback:bool=False, missing:str="",
          total:float=.5, enabled:bool=True, valid:bool=True)->dict:
    inner={k:.05 for k in P20_STAGES}
    inner["total_ms"]=total
    inner["base_layer_total_ms"]=.3
    inner.pop(missing,None)
    p0=({"fallback_ms":.2,"seam_coordinator_count":0}
        if fallback else {"validation_ms":2.0,"valid":valid,
                          "seam_coordinator_count":1,
                          "r31bp20_validation_stages":inner})
    return {
        "t_us":1000+index*1500000,"kind":"checkpoint_capture","measure":True,
        "data":{"r31bp20_validator_attribution":enabled,
                "r3c4r2_worker_envelope":True,"r31_cache_hit":True,
                "r31bp1_durable_chunks":{"enabled":True},
                "r31b_durable_stages":p0,"capture_ms":3.0,"authority_ms":2.7},
    }


def run(values:list[dict])->dict:
    with tempfile.TemporaryDirectory() as d:
        path=Path(d)/"trace.jsonl"
        path.write_text("".join(json.dumps(x)+"\n" for x in values),encoding="utf-8")
        return analyze(path)


class P20Trace(unittest.TestCase):
    def test_realistic_seam_unbound_warmup_count_is_separate(self):
        rows=[event(i,fallback=True) for i in range(18)]
        rows.extend(event(i) for i in range(18,79))
        d=run(rows)
        self.assertEqual(d["verdict"],"P20_VALIDATOR_ATTRIBUTION_VALID_ONLY")
        self.assertEqual(d["measured_captures"],79)
        self.assertEqual(d["active_seam_captures"],61)
        self.assertEqual(d["unbound_seam_fallback_captures"],18)
        self.assertEqual(d["components_ms"]["item_validator_validate_ms"]["p99"],.05)

    def test_missing_stage_rejected(self):
        with self.assertRaisesRegex(ValueError,"P20_STAGE_MISSING_OR_NONFINITE_json_safety_ms"):
            run([event(i,missing="json_safety_ms") for i in range(32)])

    def test_no_optin_rejected(self):
        with self.assertRaisesRegex(ValueError,"P20_CANARY_FLAG_NOT_ON"):
            run([event(i,enabled=False) for i in range(32)])

    def test_partial_warmup_only_not_accepted(self):
        with self.assertRaisesRegex(ValueError,"INSUFFICIENT_ACTIVE"):
            run([event(i,fallback=True) for i in range(79)])

    def test_bad_nested_validation_fails(self):
        with self.assertRaisesRegex(ValueError,"UNACCEPTED_ACTIVE_CHECKPOINT"):
            run([event(i,valid=False) for i in range(30)])

    def test_impossible_total_rejected(self):
        with self.assertRaisesRegex(ValueError,"TOTAL_EXCEEDS_OLD_VALIDATION"):
            run([event(i,total=5) for i in range(30)])

    def test_missing_p1_chunk_fails(self):
        samples=[event(i) for i in range(30)]
        samples[2]["data"]["r31bp1_durable_chunks"]["enabled"]=False
        with self.assertRaisesRegex(ValueError,"P20_P1_CACHE_NOT_ON"):
            run(samples)


class P20Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p2=P2.read_text(encoding="utf-8")
        cls.p3=P3.read_text(encoding="utf-8")
        cls.seam=SEAM.read_text(encoding="utf-8")
        cls.server=SERVER.read_text(encoding="utf-8")
        cls.runner=RUNNER.read_text(encoding="utf-8")

    def test_original_validator_interface_and_result_are_not_changed(self):
        base=method(self.p2,"validate_durable_state")
        self.assertIn("func validate_durable_state(value: Dictionary) -> Dictionary:",base)
        for token in ("players_validator.validate_durable_state",
                      "ownership_validator.validate_durable_state",
                      "shared_validator.validate_durable_state",
                      "item_validator.setup(",
                      "item_validator.validate_durable_state",
                      "Utils.canonicalize(value",
                      "_state_checksum(value)"):
            self.assertIn(token,base)
        self.assertIn('super.validate_durable_state(value)',method(self.p3,"validate_durable_state"))
        self.assertIn('validator.validate_durable_state(resource_state)',method(self.p3,"validate_durable_state"))

    def test_one_real_native_validation_call_not_two(self):
        profile=method(self.p2,"validate_durable_state_p20_profiled")
        self.assertEqual(profile.count("var result: Dictionary = validate_durable_state(value)"),1)
        self.assertIn("_r31bp20_validation_profile_sink.clear()",profile)
        self.assertNotIn("await ",profile)
        self.assertNotIn("Thread.new",profile)
        periodic=method(self.seam,"export_durable_state_r31b_profiled")
        self.assertIn("validate_durable_state_p20_profiled(durable)",periodic)
        self.assertIn("validated = validate_durable_state(durable)",periodic)
        self.assertIn('"r31bp20_validation_stages"',periodic)
        self.assertNotIn("await ",periodic)
        direct=method(self.seam,"export_durable_state")
        self.assertIn("validate_durable_state(state)",direct)
        self.assertNotIn("validate_durable_state_p20_profiled",direct)

    def test_p2_p3_native_stage_instrumentation_present(self):
        base=method(self.p2,"validate_durable_state")
        for stage in ("envelope_ms","outer_checksum_validation_ms",
                      "player_registry_ms","ownership_ms","shared_item_ms",
                      "item_validator_setup_ms","item_validator_validate_ms",
                      "cross_domain_ms","json_safety_ms"):
            self.assertIn('"'+stage+'"',base)
        resource=method(self.p3,"validate_durable_state")
        for stage in ("base_layer_total_ms","resource_validator_ms",
                      "resource_authority_ms"):
            self.assertIn('"'+stage+'"',resource)

    def test_canary_requires_current_durable_m6_stack(self):
        setup=method(self.server,"setup")
        self.assertIn("DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION",setup)
        self.assertIn("R31BP20_INVALID_MODE",setup)
        self.assertIn("R31BP20_REQUIRES_P1_P0_REPLAY_R2_PERSISTENCE_SEAM",setup)
        self.assertIn("r31bp20_validator_attribution_canary",setup)
        self.assertIn('capture_event["r31bp20_validator_attribution"] = true',self.server)
        self.assertIn("if role == 'server' and args.r31bp20_validator_attribution:",self.runner)
        self.assertIn("r31bp20_validator_attribution=args.r31bp20_validator_attribution",self.runner)


if __name__=="__main__":
    unittest.main()
