#!/usr/bin/env python3
"""Fail-closed, read-only source/sink proof for LIVE F64-v2 mixed M3 staging.

The original 3 actor trace is required. Original normative FPS/tail verdicts
are preserved as FAIL; ONLY an explicit narrow list of performance failures
may coexist with a functional staging receipt. Every transport-session,
including B's reconnect, must have a separately authenticated offer+choice,
server COMPACT transmit and successful client COMPACT decode.

Do not infer historical #815 root cause or production readiness from this tool.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

SCHEMA="dws.net_smooth.815.live_v2_staging_test_deploy.v2"
RAW_ASSETS="d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d"
PERFORMANCE_ONLY_FAILURES={
    "frame p99 >25ms",
    "frame p99.9 >50ms",
    "frame gap >100ms",
    "server loop gap >100ms",
    "main-thread persistence >50ms",
}
SELECTED="r31_815_compact_codec_selected"
NEGOTIATED="r31_815_compact_codec_negotiated"
TX={"f64-v2":"r31_815_compact_v2_sent",
    "legacy-v1":"r31_815_compact_v1_sent"}
RX={"f64-v2":"r31_815_compact_v2_received",
    "legacy-v1":"r31_815_compact_v1_received"}
KNOWN_KINDS={SELECTED,NEGOTIATED,*TX.values(),*RX.values()}


def sha(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as fp:
        for block in iter(lambda:fp.read(1024*1024),b""):
            h.update(block)
    return h.hexdigest()


def _hex64(value) -> bool:
    return (type(value) is str and len(value)==64 and
            all(ch in "0123456789abcdef" for ch in value))


def read_trace(root: Path, role: str, run_id: str) -> dict:
    path=root/role/"trace.jsonl"
    count=0
    n=0
    header=None
    end=None
    kinds=Counter()
    matching=[]
    time_last=-1
    with path.open(encoding="utf-8") as file:
        for line in file:
            if len(line)>1048576 or count>1000000:
                raise ValueError("OVERSIZED_TRACE_RECORD")
            entry=json.loads(line)
            if not isinstance(entry,dict) or not isinstance(entry.get("data"),dict):
                raise ValueError("INVALID_TRACE_RECORD")
            stamp=entry.get("t_us")
            if type(stamp) not in (int,float) or stamp<time_last:
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
            if kind in KNOWN_KINDS:
                d=entry["data"]
                if not _hex64(d.get("session_sha256")) or not _hex64(d.get("handshake_sha256")):
                    raise ValueError("MISSING_SESSION_OR_HANDSHAKE_BINDING:"+role+":"+str(kind))
                if (kind in (SELECTED,*TX.values())
                    and not _hex64(d.get("peer_sha256"))):
                    raise ValueError("MISSING_SERVER_PEER_BINDING:"+role+":"+str(kind))
                if kind in (SELECTED,NEGOTIATED) and d.get("selected") not in ("f64-v2","legacy-v1"):
                    raise ValueError("INVALID_CODEC_CHOICE")
                if kind in (*TX.values(),*RX.values()):
                    expected_schema=("planet_simulator.compact_gameplay_snapshot.v2"
                                     if "v2_" in kind else
                                     "planet_simulator.compact_gameplay_snapshot.v1")
                    if d.get("schema")!=expected_schema:
                        raise ValueError("WIRE_RECEIPT_SCHEMA_MISMATCH:"+str(kind))
                    if type(d.get("server_tick")) is not int or d["server_tick"]<1:
                        raise ValueError("MISSING_NATIVE_COMPACT_TICK")
                matching.append((kind,d))
            n+=1
    if (header is None or header.get("role")!=role or
        header.get("schema")!="dws.net_smooth.trace.v1" or
        header.get("run_id")!=run_id or end is None):
        raise ValueError("INCOMPLETE_ROLE_TRACE:"+role)
    if (end.get("written")!=n or end.get("produced")!=n or
        end.get("dropped")!=0 or end.get("io_errors")!=0):
        raise ValueError("TRACE_DROPPED_OR_NOT_DRAINED:"+role)
    return {"role":role,"sha256":sha(path),
            "kinds":dict(kinds),"messages":matching,"count":n}


def _session_rows(events:list, kind:str, selected:str|None=None)->dict:
    rows={}
    for tag,d in events:
        if tag!=kind or (selected is not None and d.get("selected")!=selected):
            continue
        sess=d["session_sha256"]
        proof=d["handshake_sha256"]
        if sess in rows:
            prev=rows[sess]
            if (prev["handshake_sha256"]!=proof or
                ("selected" in prev and prev["selected"]!=d.get("selected", prev["selected"]))):
                raise ValueError("AMBIGUOUS_RENEGOTIATED_SESSION")
        rows[sess]=d
    return rows


def _reject_functional_failures(report:dict)->None:
    processes=report.get("processes")
    if (not isinstance(processes,list) or len(processes)!=3 or
        {p.get("role") for p in processes}!={"server","a","b"} or
        any(p.get("verdict") not in ("PASS","FAIL") for p in processes)):
        raise ValueError("INCOMPLETE_ORIGINAL_THREE_PROCESS_REPORT")
    for p in processes:
        failures=p.get("failures")
        problems=p.get("problems")
        if (not isinstance(failures,list) or not isinstance(problems,list)
            or problems or any(type(f) is not str for f in failures)):
            raise ValueError("ORIGINAL_FUNCTIONAL_COVERAGE_INCOMPLETE:"+str(p.get("role")))
        unsafe=[v for v in failures if v not in PERFORMANCE_ONLY_FAILURES]
        if unsafe:
            raise ValueError("ORIGINAL_FUNCTIONAL_FAILURE:"+str(p.get("role"))+":"+repr(unsafe))
        if p.get("verdict")== "PASS" and failures:
            raise ValueError("INCONSISTENT_ORIGINAL_ROLE_VERDICT")
        if p.get("verdict")== "FAIL" and not failures:
            raise ValueError("INCONSISTENT_ORIGINAL_ROLE_VERDICT")
        if p.get("role")=="server":
            try:
                hz=float(p["tick_hz"])
                dropped=float(p["dropped_time_delta_s"])
            except (TypeError,KeyError,ValueError) as err:
                raise ValueError("SERVER_FIXED_TICK_EVIDENCE_MISSING") from err
            if hz<59 or dropped>1e-6 or dropped<0:
                raise ValueError("SERVER_AUTHORITATIVE_FIXED_TICK_REGRESSED")
        else:
            if (p.get("remote_distance_m") is None or
                float(p["remote_distance_m"])<=0.2):
                raise ValueError("REMOTE_GAMEPLAY_MOVEMENT_NOT_PROVEN")


def _validate_session_evidence(events:dict)->dict:
    srv=events["server"]["messages"]
    client_a=events["a"]["messages"]
    client_b=events["b"]["messages"]
    server_selections=_session_rows(srv,SELECTED)
    a_selections=_session_rows(client_a,NEGOTIATED)
    b_selections=_session_rows(client_b,NEGOTIATED)
    if not a_selections:
        raise ValueError("NO_REAL_CLIENT_A_V2_ACK")
    if len(b_selections)<2:
        raise ValueError("NO_POST_RECONNECT_CLIENT_B_V1_HANDSHAKE")
    if set(a_selections).intersection(b_selections):
        raise ValueError("SAME_TRANSPORT_SESSION_USED_BY_TWO_CLIENTS")
    results={}
    for client,selected,rows in (
        ("a","f64-v2",a_selections),("b","legacy-v1",b_selections)
    ):
        server_sent=_session_rows(srv,TX[selected])
        client_received=_session_rows(events[client]["messages"],RX[selected])
        unexpected=RX["legacy-v1"] if selected=="f64-v2" else RX["f64-v2"]
        if any(k==unexpected for k,_ in events[client]["messages"]):
            raise ValueError("CLIENT_RECEIVED_UNNEGOTIATED_FORMAT:"+client)
        for session,proof in rows.items():
            server_choice=server_selections.get(session)
            if (server_choice is None or server_choice.get("selected")!=selected
                or server_choice["handshake_sha256"]!=proof["handshake_sha256"]):
                raise ValueError("SERVER_AND_CLIENT_HANDSHAKE_SESSION_MISMATCH:"+client)
            actual_sent=server_sent.get(session)
            if (actual_sent is None or
                actual_sent["handshake_sha256"]!=proof["handshake_sha256"] or
                actual_sent["peer_sha256"]!=server_choice["peer_sha256"]):
                raise ValueError("MISSING_SERVER_SEND_IN_NEGOTIATED_SESSION:"+client)
            actual_rx=client_received.get(session)
            if (actual_rx is None or
                actual_rx["handshake_sha256"]!=proof["handshake_sha256"]):
                raise ValueError("MISSING_ACCEPTED_COMPACT_IN_NEGOTIATED_SESSION:"+client)
        results[client]={
            "selected":selected,
            "verified_session_count":len(rows),
            "session_sha256s":sorted(rows),
            "matched_tx_rx_per_session":True,
        }
    return results


def validate(root: Path)->dict:
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
    if report.get("verdict") not in ("PASS","FAIL") or report.get("infrastructure"):
        raise ValueError("ORIGINAL_REPORT_INCONCLUSIVE")
    if report.get("functional_scenario")!="PASS":
        raise ValueError("ORIGINAL_FUNCTIONAL_SCENARIO_NOT_PASSED")
    _reject_functional_failures(report)
    phases=manifest.get("phase_results")
    if (not isinstance(phases,list) or not any(
        p.get("phase")=="r31_reconnect_roundtrip" for p in phases
        if isinstance(p,dict))):
        raise ValueError("ORIGINAL_R31_RECONNECT_SCENARIO_MISSING")
    ident=manifest.get("identity",{})
    if not isinstance(ident,dict) or any(
        type(ident.get(x)) is not str or not ident[x]
        for x in ("head","tree","godot_sha256","asset_manifest_sha256")
    ):
        raise ValueError("UNPINNED_SOURCE_OR_ASSETS")
    if (ident.get("asset_count")!=123 or
        ident["asset_manifest_sha256"]!=RAW_ASSETS):
        raise ValueError("CANONICAL_QUATERNIUS_RAW_ASSETS_NOT_PRESENT")
    run_id=manifest.get("run_id")
    if type(run_id) is not str or len(run_id)!=16:
        raise ValueError("WRONG_RUN_ID")
    traces={r:read_trace(root,r,run_id) for r in ("server","a","b")}
    sessions=_validate_session_evidence(traces)
    for role in ("a","b"):
        if traces[role]["kinds"].get("compact_snapshot_stages",0)<1:
            raise ValueError("CLIENT_"+role.upper()+"_NEVER_APPLIED_COMPACT")
    for role in ("server","a","b"):
        logfile=root/role/"runtime.log"
        body=logfile.read_text(encoding="utf-8",errors="replace")
        for bad in ("PAYLOAD_CHECKSUM_MISMATCH","COMPACT_CODEC_VERSION_MISMATCH",
                    "CLIENT_CONNECTION_FAILED","R31_815_OUTBOUND_RECEIVER_REJECTED"):
            if bad in body:
                raise ValueError("ORIGINAL_NATIVE_NETWORK_FAILURE:"+role+":"+bad)
        if not (root/role/"measure.end.ack").is_file():
            raise ValueError("MEASURE_ACK_MISSING:"+role)
    return {
        "schema":SCHEMA,
        "verdict":"TEST_DEPLOY_FUNCTIONAL_EVIDENCE_ONLY_NO_GUI_PERF_ACCEPTANCE",
        "head":ident["head"],"tree":ident["tree"],"run_id":run_id,
        "original_normative_verdict":report["verdict"],
        "verified_sessions":sessions,
        "roles":{r:{"trace_sha256":v["sha256"],"event_count":v["count"]}
                 for r,v in traces.items()},
        "manifest_sha256":sha(manifest_file),"report_sha256":sha(report_file),
        "current_production_deployed":False,"historical_815_closed":False,
        "performance_accepted":False,"ready_for_merge":False,
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
    args.output.write_text(json.dumps(result,indent=2,ensure_ascii=False),
                           encoding="utf-8")
    print(json.dumps({"verdict":result["verdict"],"run_id":result["run_id"],
                      "b_post_reconnect_sessions":
                        result["verified_sessions"]["b"]["verified_session_count"]}))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
