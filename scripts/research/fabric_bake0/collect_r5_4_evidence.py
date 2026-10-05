#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path
PREFIX="FABRIC_R5_4_RESULT="
PASS="FABRIC R5.4 MIXED COMPLEXITY 100K MACHINE: PASS ("
FATAL=re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:",re.I)
LINUX_GODOT_SHA256="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
WINDOWS_GODOT_SHA256="3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"
CANONICAL_ENGINE_IDENTITY_LINES={
    "GODOT_SHA256="+LINUX_GODOT_SHA256,
    "GODOT_SHA256="+WINDOWS_GODOT_SHA256,
}
EXPECTED={
 "checks":1001,"machine_parts":100000,"recursive_levels":4,"recursive_nodes":15,
 "baseline_recursive_physical_components":1812,"final_recursive_physical_components":1852,
 "recursive_compiled_input_components":24,"recursive_executable_equations":4,
 "local_full_peak":20,"local_reconstructed_parts":20,"local_metadata_parts_scanned":0,
 "local_range_query_count":4,"local_range_query_prefix_reads":80,
 "local_recursive_changed":4,"local_recursive_reused":11,
 "global_structural_parts_scanned":100000,"global_recursive_changed":15,"global_recursive_reused":0,
 "steady_calls":320,
}
def req(ok,msg):
    if not ok: raise ValueError(msg)
def strict(s):
    def bad(v): raise ValueError("nonfinite "+v)
    return json.loads(s,parse_constant=bad)
def digest(d): return hashlib.sha256(json.dumps(d,sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()
def sample(path:Path):
    t=path.read_text(encoding="utf-8-sig");req(PASS in t and not FATAL.search(t),"sample fail "+path.name)
    rows=[x[len(PREFIX):] for x in t.splitlines() if x.startswith(PREFIX)];req(len(rows)==1,"result marker count")
    d=strict(rows[0]);req(d.get("schema")=="fabric.r5_4.mixed_complexity_100k.result.v1","schema");req(d.get("failures")==[],"failures")
    for k,v in EXPECTED.items(): req(d.get(k)==v,"mismatch "+k)
    req(re.fullmatch(r"[0-9a-f]{64}",d.get("final_machine_hash","")) is not None,"machine hash")
    return rows[0],d
def validate_identity(before:list[str],after:list[str]):
    req(before==after,"identity moved")
    req(len(before)==4,"identity shape")
    req(re.fullmatch(r"HEAD=[0-9a-f]{40}",before[0]) is not None,"head identity")
    req(re.fullmatch(r"TREE=[0-9a-f]{40}",before[1]) is not None,"tree identity")
    req(before[2]=="GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb","engine version")
    req(before[3] in CANONICAL_ENGINE_IDENTITY_LINES,"engine sha")
def collect(root:Path):
    rows=[sample(root/f"sample-{i}.log") for i in (1,2,3)];req(rows[0][0]==rows[1][0]==rows[2][0],"payload mismatch")
    for name,marker in (("r53","FABRIC R5.3 RECURSIVE HIERARCHICAL EXECUTION: PASS (1231 assertions)"),("r51","FABRIC R5.1 QUANTITATIVE SCALE: PASS")):
        t=(root/f"{name}-regression.log").read_text(encoding="utf-8-sig");req(marker in t and not FATAL.search(t),"regression "+name)
    for name in ("import","parse"):
        req(not FATAL.search((root/f"{name}.log").read_text(encoding="utf-8-sig")),name+" fatal")
    before=(root/"identity-before.txt").read_text().splitlines();after=(root/"identity-after.txt").read_text().splitlines();validate_identity(before,after)
    h=digest(rows[0][1])
    return {"schema":"fabric.r5_4.exact_evidence.v1","status":"IMPLEMENTER_EXACT_PASS","identity":before,"deterministic_hash":h,"result":rows[0][1],"logs":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob("*.log"))}}
def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",required=True,type=Path);ns=ap.parse_args();e=collect(ns.root);(ns.root/"evidence.json").write_text(json.dumps(e,sort_keys=True,indent=2)+"\n");print("FABRIC_R5_4_DETERMINISTIC_HASH="+e["deterministic_hash"]);print("FABRIC_R5_4_EVIDENCE=PASS")
if __name__=="__main__":main()
