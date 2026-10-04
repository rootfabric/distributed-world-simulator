#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, math, re
from pathlib import Path
PREFIX="FABRIC_R5_3_RESULT="
PASS="FABRIC R5.3 RECURSIVE HIERARCHICAL EXECUTION: PASS (1200 assertions)"
FATAL=re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:",re.I)
EXPECTED={
 "checks":1200,"levels":4,"nodes":15,"leaves":8,"steady_calls":512,
 "baseline_physical_components":1812,"final_physical_components":1852,
 "machine_compiled_input_components":24,"machine_executable_equations":4,
 "parity_rows":21,"leaf_rebuild_levels":4,"module_rebuild_levels":3,
 "assembly_rebuild_levels":2,"machine_rebuild_levels":1,
 "runtime_prepare_events":25,"runtime_reuse_events":50,"runtime_execute_events":548,
}
REGRESSIONS={
 "t16":"FABRIC R5.2 T16 NO SAFE BAKE: PASS (980 assertions)",
 "t15":"FABRIC R5.2 T15 LOCAL DAMAGE UNBAKE REBAKE: PASS (506 assertions)",
 "t14":"FABRIC R5.2 T14 OBSERVATION REFINEMENT: PASS (1208 assertions)",
 "t13-5":"FABRIC R5.2 T13.5 SHARED FAMILIES: PASS (777 assertions)",
 "t13":"FABRIC R5.2 T13 SHARED INSTANCES: PASS (1377 assertions)",
 "t12":"FABRIC R5.2 T12 SHIP MATRYOSHKA: PASS (8386 assertions)",
}
def req(ok,msg):
    if not ok: raise ValueError(msg)
def obj(pairs):
    d={}
    for k,v in pairs:
        req(k not in d,"duplicate JSON key: "+k);d[k]=v
    return d
def strict(s):
    def bad(v): raise ValueError("nonfinite JSON: "+v)
    d=json.loads(s,parse_constant=bad,object_pairs_hook=obj);req(isinstance(d,dict),"result object required");return d
def digest(d): return hashlib.sha256(json.dumps(d,sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()
def validate(d):
    req(d.get("schema")=="fabric.r5_3.recursive_rom.result.v1" and d.get("failures")==[],"schema/failures")
    for k,v in EXPECTED.items(): req(type(d.get(k)) is int and d[k]==v,"mismatch "+k)
    for k in ("baseline_expanded_system_hash","final_expanded_system_hash","final_root_node_hash","final_root_capsule_checksum"):
        req(re.fullmatch(r"[0-9a-f]{64}",d.get(k,"")) is not None,"bad hash "+k)
    for k,b in (("max_flow_error",2e-8),("max_power_error",2e-7)):
        v=d.get(k);req(type(v) in (int,float) and math.isfinite(v) and 0<=v<=b,"bound "+k)
    req(d["final_physical_components"]>d["baseline_physical_components"],"hidden complexity did not grow")
    req(d["machine_compiled_input_components"]*10<d["final_physical_components"],"hierarchy compression insufficient")
def sample(path):
    t=path.read_text(encoding="utf-8-sig",errors="strict");req(PASS in t and not FATAL.search(t),"sample fail "+path.name)
    rows=[x[len(PREFIX):] for x in t.splitlines() if x.startswith(PREFIX)];req(len(rows)==1,"result marker count")
    d=strict(rows[0]);validate(d);return rows[0],d
def collect(root:Path,expected_hash:str|None=None):
    rows=[sample(root/f"sample-{i}.log") for i in (1,2,3)];req(rows[0][0]==rows[1][0]==rows[2][0],"result payload mismatch")
    h=digest(rows[0][1]);req(expected_hash is None or h==expected_hash,"deterministic hash mismatch")
    for name,marker in REGRESSIONS.items():
        t=(root/f"{name}-regression.log").read_text(encoding="utf-8-sig");req(marker in t and not FATAL.search(t),"regression "+name)
    for name in ("import","parse"):
        req(not FATAL.search((root/f"{name}.log").read_text(encoding="utf-8-sig")),name+" fatal")
    before=(root/"identity-before.txt").read_text(encoding="utf-8-sig").splitlines();after=(root/"identity-after.txt").read_text(encoding="utf-8-sig").splitlines();req(before==after,"identity moved")
    req(len(before)==4 and re.fullmatch(r"HEAD=[0-9a-f]{40}",before[0]) and re.fullmatch(r"TREE=[0-9a-f]{40}",before[1]),"identity shape")
    req(before[2]=="GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb","engine version")
    req(before[3] in ("GODOT_SHA256=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7","GODOT_SHA256=3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"),"engine sha")
    return {"schema":"fabric.r5_3.exact_evidence.v1","status":"IMPLEMENTER_EXACT_PASS","identity":before,"deterministic_hash":h,"result":rows[0][1],"logs":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob("*.log"))}}
def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",type=Path,required=True);ap.add_argument("--expected-hash");ns=ap.parse_args();e=collect(ns.root,ns.expected_hash);(ns.root/"evidence.json").write_text(json.dumps(e,sort_keys=True,indent=2)+"\n",encoding="utf-8");print("FABRIC_R5_3_DETERMINISTIC_HASH="+e["deterministic_hash"]);print("FABRIC_R5_3_EVIDENCE=PASS")
if __name__=="__main__":main()
