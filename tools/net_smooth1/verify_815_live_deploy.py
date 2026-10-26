#!/usr/bin/env python3
"""Strict read-only TEST DEPLOY receipt for real headless M3 v1/v2 mixed peers.

This test does NOT claim GUI PERF PASS / historical #815 FIXED or production
deployment. It checks original 3-process traces and real negotiated receipts
with exact role/session binding; no fallback on checksum failure.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def sha(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as fp:
        for block in iter(lambda:fp.read(1024*1024),b""):
            h.update(block)
    return h.hexdigest()


def read_trace(root: Path, role: str, run_id: str) -> dict:
    path=root/role/"trace.jsonl"
    count=0
    n=0
    header=None
    end=None
    kinds=Counter()
    matching=[]
    time_last=-1
    for line in path.read_text(encoding="utf-8").splitlines():
        if len(line)>1048576:
            raise ValueError("OVERSIZED_TRACE_RECORD")
        entry=json.loads(line)
        if not isinstance(entry,dict) or not isinstance(entry.get("data"),dict):
            raise ValueError("INVALID_TRACE_RECORD")
        stamp=entry.get("t_us")
        if type(stamp) not in (float,int) or stamp<time_last:
            raise ValueError("NONMONOTONIC_TRACE")
        time_last=stamp
        kind=entry.get("kind")
        if end is not None:
            raise ValueError("TRACE_AFTER_END")
        if kind=="end":
            end=entry["data"]
            continue
        count+=1
        if entry.get("n")!=count:
            raise ValueError("TRACE_SEQUENCE_GAP")
        if kind=="header":
            if header is not None or count!=1:
                raise ValueError("BAD_TRACE_HEADER_ORDER")
            header=entry["data"]
        kinds[kind]+=1
        if kind.startswith("r31_815_compact_"):
            matching.append((kind,entry["data"]))
        n+=1
    if (header is None or header.get("role")!=role
        or header.get("run_id")!=run_id or end is None):
        raise ValueError("INCOMPLETE_ROLE_TRACE:"+role)
    if (end.get("written")!=n or end.get("produced")!=n
        or end.get("dropped")!=0 or end.get("io_errors")!=0):
        raise ValueError("TRACE_DROPPED_OR_NOT_DRAINED:"+role)
    return {"role":role,"sha256":sha(path),
            "kinds":dict(kinds),"messages":matching,"count":n}


def validate(root: Path) -> dict:
    manifest_file=root/"manifest.json"
    report_file=root/"report.json"
    manifest=json.loads(manifest_file.read_text(encoding="utf-8"))
    report=json.loads(report_file.read_text(encoding="utf-8"))
    if (manifest.get("scenario")!="r31-reconnect-roundtrip"
        or manifest.get("profile")!="LOCAL"
        or manifest.get("mode") not in ("headless","gui")
        or manifest.get("r31_815_compact_server_mode")!="prefer_v2"
        or manifest.get("r31_815_compact_client_a_mode")!="require_v2"
        or manifest.get("r31_815_compact_client_b_mode")!="off"
        or manifest.get("r31p23r22_attested_compact") is not True):
        raise ValueError("WRONG_TEST_DEPLOY_MODE")
    if manifest.get("completed") is not True or manifest.get("errors"):
        raise ValueError("ORIGINAL_RUN_NOT_COMPLETE")
    if report.get("verdict") not in ("PASS","FAIL"):
        raise ValueError("ORIGINAL_REPORT_INCONCLUSIVE")
    if report.get("infrastructure"):
        raise ValueError("ORIGINAL_INFRASTRUCTURE_ERROR")
    ident=manifest.get("identity",{})
    if not isinstance(ident,dict) or any(
        type(ident.get(x)) is not str or not ident[x]
        for x in ("head","tree","godot_sha256","asset_manifest_sha256")
    ):
        raise ValueError("UNPINNED_SOURCE_OR_ASSETS")
    run_id=manifest.get("run_id")
    if type(run_id) is not str or len(run_id)!=16:
        raise ValueError("WRONG_RUN_ID")
    results={r:read_trace(root,r,run_id) for r in ("server","a","b")}
    server=results["server"]["messages"]
    a=results["a"]["messages"]
    b=results["b"]["messages"]
    def anykind(rows,kind,fmt):
        return any(k==kind and v.get("selected")==fmt for k,v in rows)
    if not anykind(server,"r31_815_compact_codec_selected","f64-v2"):
        raise ValueError("NO_REAL_SERVER_V2_HANDSHAKE")
    if not anykind(server,"r31_815_compact_codec_selected","legacy-v1"):
        raise ValueError("NO_REAL_SERVER_MIXED_V1_HANDSHAKE")
    if not anykind(a,"r31_815_compact_codec_negotiated","f64-v2"):
        raise ValueError("NO_REAL_CLIENT_A_V2_ACK")
    if not anykind(b,"r31_815_compact_codec_negotiated","legacy-v1"):
        raise ValueError("NO_REAL_CLIENT_B_V1_ACK")
    if not any(k=="r31_815_compact_v2_sent" for k,_ in server):
        raise ValueError("NO_ACTUAL_SERVER_V2_PACKET")
    if not any(k=="r31_815_compact_v2_received" for k,_ in a):
        raise ValueError("NO_ACTUAL_CLIENT_A_V2_DECODE")
    if any(k=="r31_815_compact_v2_received" for k,_ in b):
        raise ValueError("CLIENT_B_RECEIVED_UNOFFERED_V2")
    if results["b"]["kinds"].get("snapshot_received",0)<1:
        raise ValueError("CLIENT_B_NEVER_RECEIVED_LEGACY_SNAPSHOT")
    for role in ("server","a","b"):
        logfile=root/role/"runtime.log"
        body=logfile.read_text(encoding="utf-8",errors="replace")
        if "PAYLOAD_CHECKSUM_MISMATCH" in body or "COMPACT_CODEC_VERSION_MISMATCH" in body:
            raise ValueError("CHECKSUM_OR_VERSION_FAILURE:"+role)
        if not (root/role/"measure.end.ack").is_file():
            raise ValueError("MEASURE_ACK_MISSING:"+role)
    return {
        "schema":"dws.net_smooth.815.live_v2_staging_test_deploy.v1",
        "verdict":"TEST_DEPLOY_FUNCTIONAL_EVIDENCE_ONLY_NO_GUI_PERF_ACCEPTANCE",
        "head":ident["head"],"tree":ident["tree"],"run_id":run_id,
        "original_normative_verdict":report["verdict"],
        "roles":{k:{"trace_sha256":v["sha256"],"event_count":v["count"],
                    "v2_receipts":sum(t=="r31_815_compact_v2_received" for t,_ in v["messages"])}
                 for k,v in results.items()},
        "manifest_sha256":sha(manifest_file),
        "report_sha256":sha(report_file),
        "current_production_deployed":False,
        "historical_815_closed":False,
        "performance_accepted":False,
        "ready_for_merge":False,
    }


def main()->int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("run_root",type=Path)
    p.add_argument("--output",required=True,type=Path)
    args=p.parse_args()
    try:
        result=validate(args.run_root)
    except (OSError,ValueError,TypeError,KeyError,json.JSONDecodeError) as exc:
        print("NS1_815_STAGING_DEPLOY_FAILED:"+str(exc))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding="utf-8")
    print(json.dumps({"verdict":result["verdict"],"run_id":result["run_id"]}))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
