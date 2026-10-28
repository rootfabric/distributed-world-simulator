#!/usr/bin/env python3
"""NET-SMOOTH1 #815: fail-closed exact-packet SHA correlation across actors.

Read-only, DIAGNOSTIC_ONLY. Unlike original frame-time profiles, safe join
between independent process clocks is by packet_sha256 + frame_id, never by
walltime/monotonic timestamps. Never alters original manifest/report/trace.
No unverified packet, matched SHA or zero incidents can close issue #815.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

KIND="r31_815_wire_fingerprint"
SCHEMA="dws.net_smooth.r31_815.wire_checksum_fingerprint.v1"
MAX_LINE=1048576


def sha(path:Path)->str:
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_role(path:Path,run_id:str,role:str)->dict:
    by_sha=defaultdict(list)
    rows=0
    first=None
    last=None
    footer=None
    previous_t=-1
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            rows+=1
            if rows>1000000 or len(line)>MAX_LINE:
                raise ValueError("R31_815_TRACE_ROW_LIMIT")
            obj=json.loads(line)
            if not isinstance(obj,dict) or not isinstance(obj.get("data"),dict):
                raise ValueError("R31_815_TRACE_INVALID_JSON_RECORD")
            t=obj.get("t_us")
            if type(t) not in (int,float) or t<previous_t:
                raise ValueError("R31_815_TRACE_NONMONOTONIC_CLOCK")
            previous_t=t
            if first is None:
                first=obj
                if (obj.get("kind")!="header"
                    or obj["data"].get("schema")!="dws.net_smooth.trace.v1"
                    or obj["data"].get("role")!=role
                    or obj["data"].get("run_id")!=run_id):
                    raise ValueError("R31_815_TRACE_IDENTITY_MISMATCH")
            if footer is not None:
                raise ValueError("R31_815_TRAILING_EVENTS_AFTER_END")
            if obj.get("kind")=="end":
                footer=obj["data"]
                last=obj
                continue
            if type(obj.get("n")) is not int or obj["n"]!=rows:
                raise ValueError("R31_815_TRACE_SEQUENCE_LOSS")
            if type(obj.get("measure")) is not bool:
                raise ValueError("R31_815_MEASURE_FLAG_UNTYPED")
            if obj.get("kind")==KIND:
                d=obj["data"]
                if (d.get("schema")!=SCHEMA
                    or d.get("phase") not in ("tx_enet","rx_enet","rx_reject")
                    or type(d.get("packet_sha256")) is not str
                    or len(d["packet_sha256"])!=64
                    or type(d.get("frame_id")) is not str
                    or type(d.get("raw_payload_redacted")) is not bool
                    or d["raw_payload_redacted"] is not True):
                    raise ValueError("R31_815_MALFORMED_FINGERPRINT")
                by_sha[d["packet_sha256"]].append(d)
    if footer is None or last is None:
        raise ValueError("R31_815_TRACE_MISSING_FOOTER")
    # Header is also counted by trace writer: produced/written exclude END.
    if (footer.get("written")!=rows-1 or footer.get("produced")!=rows-1
        or footer.get("dropped")!=0 or footer.get("io_errors")!=0):
        raise ValueError("R31_815_TRACE_FOOTER_DROPPED_OR_MISMATCH")
    return {"role":role,"sha256":sha(path),"fingerprints":by_sha,
            "count":sum(map(len,by_sha.values())),"total_rows":rows}


def analyze(root:Path)->dict:
    manifest_p=root/"manifest.json"
    report_p=root/"report.json"
    manifest=json.loads(manifest_p.read_text(encoding="utf-8"))
    report=json.loads(report_p.read_text(encoding="utf-8"))
    run_id=manifest.get("run_id")
    if type(run_id) is not str or len(run_id)!=16:
        raise ValueError("R31_815_BAD_RUN_ID")
    if (manifest.get("r31_815_wire_forensics") is not True
        or manifest.get("forensic_evidence_class")!="CHECKSUM_FINGERPRINT_DIAGNOSTIC_ONLY"
        or manifest.get("scenario")!="r31-reconnect-roundtrip"
        or manifest.get("mode")!="gui"):
        raise ValueError("R31_815_FORENSIC_OPT_IN_MISSING")
    identity=manifest.get("identity",{})
    if (not isinstance(identity,dict) or
        any(type(identity.get(key)) is not str or not identity[key]
            for key in ("head","tree","godot_sha256","asset_manifest_sha256"))
        or identity.get("asset_count")!=123):
        raise ValueError("R31_815_SOURCE_OR_ASSET_IDENTITY_MISSING")
    original_verdict=report.get("verdict")
    if original_verdict not in ("PASS","FAIL","INCONCLUSIVE"):
        raise ValueError("R31_815_ORIGINAL_VERDICT_MISSING")
    traces={role:load_role(root/role/"trace.jsonl",run_id,role)
            for role in ("server","a","b")}
    tx_by_sha=defaultdict(list)
    rejected=[]
    for role,item in traces.items():
        for digest,receipts in item["fingerprints"].items():
            for d in receipts:
                if d["phase"]=="tx_enet":
                    tx_by_sha[digest].append({"role":role,"receipt":d})
                if d["phase"]=="rx_reject":
                    rejected.append({"role":role,"receipt":d})
    correlations=[]
    for rx in rejected:
        d=rx["receipt"]
        senders=tx_by_sha.get(d["packet_sha256"],[])
        # Do not match only by packet SHA when the claimed frame IDs differ.
        senders=[v for v in senders
                 if v["receipt"]["frame_id"]==d["frame_id"]]
        exact_drift=[
            v for v in senders
            if (v["receipt"].get("sender_checksum_matches") is True
                and v["receipt"].get("postparse_checksum_matches") is False
                and d.get("postparse_checksum_matches") is False
                and d.get("error_code")=="PAYLOAD_CHECKSUM_MISMATCH")
        ]
        classification=("SAME_EXACT_PACKET_SENDER_VALID_RECEIVER_FLOAT_DRIFT"
                        if exact_drift else
                        "SAME_EXACT_PACKET_REJECT_CAUSE_NOT_PROVEN"
                        if senders else
                        "UNMATCHED_RECEIVE_REJECT_SOURCE_BYTES_UNKNOWN")
        correlations.append({
            "receiving_role":rx["role"],
            "frame_id":d["frame_id"],
            "packet_sha256":d["packet_sha256"],
            "error_code":d.get("error_code",""),
            "message_type":d.get("message_type",""),
            "source_roles":sorted({v["role"] for v in senders}),
            "classification":classification,
        })
    mismatch_productions=sum(
        1 for senders in tx_by_sha.values() for item in senders
        if (item["receipt"].get("sender_checksum_matches") is True
            and item["receipt"].get("postparse_checksum_matches") is False)
    )
    return {
        "schema":"dws.net_smooth.r31_815.fingerprint_correlator.v1",
        "verdict":"INDEPENDENT_DIAGNOSTIC_ONLY_ISSUE_815_OPEN",
        "run_id":run_id,"product_head":identity["head"],
        "product_tree":identity["tree"],
        "original_normative_verdict":original_verdict,
        "manifest_sha256":sha(manifest_p),
        "report_sha256":sha(report_p),
        "trace_sha256":{k:v["sha256"] for k,v in traces.items()},
        "fingerprint_events":{k:v["count"] for k,v in traces.items()},
        "sender_postparse_mismatch_count":mismatch_productions,
        "actual_decode_reject_count":len(rejected),
        "rejects":correlations,
        "limitations":[
            "Exact matching sender/receiver packet SHA and frame_id is required.",
            "Sender numeric drift is a reproducible candidate, not historical incident proof.",
            "No raw packets/payloads or personal identifiers are emitted.",
            "Trace time is process-local: never join by t_us across actors.",
            "No successful rerun, source CI or zero checksum rejection closes #815.",
            "This forensic opt-in adds overhead and cannot be used for normative GUI p99.",
        ]
    }


def main()->int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("run_root",type=Path)
    p.add_argument("--output",type=Path,required=True)
    args=p.parse_args()
    try:
        result=analyze(args.run_root)
    except (OSError,ValueError,TypeError,KeyError,json.JSONDecodeError) as err:
        print("R31_815_FORENSIC_INCONCLUSIVE:"+str(err))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),
                           encoding="utf-8")
    print(json.dumps({
        "verdict":result["verdict"],
        "decode_rejects":result["actual_decode_reject_count"],
        "sender_numeric_drift":result["sender_postparse_mismatch_count"],
    }))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
