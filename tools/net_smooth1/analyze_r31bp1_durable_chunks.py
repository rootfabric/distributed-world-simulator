#!/usr/bin/env python3
"""R31b P1 detached durable chunk cache: read-only GUI trace reducer.

This is DIAGNOSTIC ONLY, never substitutes normative analyze_net_smooth1.py,
M6 native byte/disk parity, or real 2-client GUI functional acceptance.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path

FIELDS=("capture_ms","authority_ms","replay_ms")
DOMAINS=("item_graph_ms","resource_ms","validation_ms","final_checksum_ms","total_ms")


def percentile(values:list[float],q:float)->float|None:
    if not values:
        return None
    s=sorted(values)
    return s[min(len(s)-1,max(0,math.ceil(q*len(s))-1))]


def analyze(path:Path, min_active:int=10, min_hit_rate:float=.9)->dict:
    counts={"measured":0,"seam_fallback":0,"active":0,"item_hits":0,"resource_hits":0}
    samples={key:[] for key in FIELDS+DOMAINS}
    errors=[]
    bypasses={}
    with path.open(encoding="utf-8") as stream:
        for line_no,raw in enumerate(stream,1):
            if len(raw)>1024*1024:
                raise ValueError("R31BP1_OVERSIZED_EVENT")
            event=json.loads(raw)
            if event.get("kind")!="checkpoint_capture" or event.get("measure") is not True:
                continue
            counts["measured"]+=1
            value=event.get("data",{})
            if not isinstance(value,dict) or value.get("r31bp1_durable_chunks") is not True:
                errors.append("R31BP1_OPT_IN_ABSENT")
                continue
            if value.get("r3c4r2_worker_envelope") is not True:
                errors.append("R31BP1_R2_WORKER_MISSING")
            data=value.get("r31b_durable_stages",{})
            if not isinstance(data,dict):
                errors.append("R31BP1_STAGES_MISSING")
                continue
            if "fallback_ms" in data:
                if type(data["fallback_ms"]) not in (float,int) or data["fallback_ms"]<0:
                    errors.append("R31BP1_INVALID_FALLBACK")
                elif data.get("seam_coordinator_count")!=0:
                    errors.append("R31BP1_FALLBACK_WITH_ACTIVE_SEAM")
                else:
                    counts["seam_fallback"]+=1
                continue
            counts["active"]+=1
            if data.get("valid") is not True or data.get("seam_coordinator_count",0)<1:
                errors.append("R31BP1_INVALID_ACTIVE_DOMAIN")
            for name in ("item_graph_cache_hit","resource_cache_hit"):
                if type(data.get(name)) is not bool:
                    errors.append("R31BP1_MISSING_"+name)
            if data.get("item_graph_cache_hit") is True:
                counts["item_hits"]+=1
            if data.get("resource_cache_hit") is True:
                counts["resource_hits"]+=1
            for name in ("item_graph_bypass","resource_bypass"):
                reason=data.get(name)
                if type(reason) is not str:
                    errors.append("R31BP1_MISSING_"+name)
                elif reason:
                    bypasses[reason]=bypasses.get(reason,0)+1
            for field in DOMAINS:
                metric=data.get(field)
                if type(metric) not in (int,float) or not math.isfinite(metric) or metric<0:
                    errors.append(f"R31BP1_INVALID_{field}_LINE_{line_no}")
                else:
                    samples[field].append(float(metric))
            for field in FIELDS:
                metric=value.get(field)
                if type(metric) not in (int,float) or not math.isfinite(metric) or metric<0:
                    errors.append("R31BP1_INVALID_"+field)
                else:
                    samples[field].append(float(metric))
            cache_bytes=[data.get("item_graph_cache_bytes"),data.get("resource_cache_bytes")]
            if any(type(x) is not int or x<0 or x>4*1024*1024 for x in cache_bytes):
                errors.append("R31BP1_INVALID_CACHE_MEMORY_BUDGET")
    active=counts["active"]
    ratios={k:counts[k]/active if active else 0.0 for k in ("item_hits","resource_hits")}
    if active<min_active:
        errors.append(f"R31BP1_INSUFFICIENT_ACTIVE_{active}")
    if counts["measured"]!=counts["seam_fallback"]+active:
        errors.append("R31BP1_INCOMPLETE_CLASSIFICATION")
    if any(len(series)!=active for series in samples.values()):
        errors.append("R31BP1_INCOMPLETE_METRICS")
    if bypasses:
        errors.append("R31BP1_CACHE_BYPASS_OBSERVED")
    for k,v in ratios.items():
        if v<min_hit_rate:
            errors.append(f"R31BP1_{k}_RATE_TOO_LOW")
    return {
        "schema":"dws.net_smooth.r31bp1.chunk_cache.v1",
        "verdict":"R31BP1_CHUNKS_DIAGNOSTIC_PASS" if not errors else "R31BP1_CHUNKS_DIAGNOSTIC_FAIL",
        "counts":counts,
        "cache_hit_rates":ratios,
        "bypasses":bypasses,
        "metrics_ms":{k:{"p50":percentile(vals,.5),"p99":percentile(vals,.99),
                         "max":max(vals,default=None),"n":len(vals)}
                      for k,vals in samples.items()},
        "errors":sorted(set(errors)),
        "requirements":"Run unmodified normative analyzer + M6 disk/replay checks separately; no merge approval",
        "note":"Do not sum independent stage percentiles; warmup seam fallbacks tracked separately",
    }


def main()->int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("trace",type=Path)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    try:
        result=analyze(a.trace)
    except (OSError,TypeError,ValueError,json.JSONDecodeError) as e:
        print("R31BP1_TRACE_INCONCLUSIVE:"+str(e))
        return 2
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"verdict":result["verdict"],"counts":result["counts"],
                      "cache_hit_rates":result["cache_hit_rates"],"errors":result["errors"]}))
    return 0 if not result["errors"] else 1

if __name__=="__main__":
    raise SystemExit(main())
