#!/usr/bin/env python3
"""R3 separate acceptance: 20Hz transport+client continuity DURING ITEM pending.

Do not infer availability of movement from a pure wire fixture. This checker
requires real server enqueues, real client receives, and an ITEM in-flight
window on a trace recorded by the running Earth two-client harness.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import sys


def pct(values: list[float], q: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    return values[min(len(values) - 1, math.ceil(q * len(values)) - 1)]


def load_trace(path: Path, role: str, run_id: str) -> list[dict]:
    events: list[dict] = []
    with path.open(encoding='utf-8') as stream:
        for line in stream:
            event = json.loads(line)
            if event.get('kind') == 'end':
                if event.get('data', {}).get('dropped', 0):
                    raise ValueError(f'{role}: lost trace events')
                continue
            if event.get('kind') == 'header':
                if event.get('data', {}).get('run_id') != run_id:
                    raise ValueError(f'{role}: run_id mismatch')
            if event.get('measure'):
                events.append(event)
    return events


def examine(root: Path) -> dict:
    manifest = json.loads((root/'manifest.json').read_text(encoding='utf-8'))
    run_id = manifest['run_id']
    if manifest.get('completed') is not True:
        raise ValueError('run incomplete')
    if manifest.get('scenario') != 'r3-slow-item':
        raise ValueError('not an R3 real ITEM movement scenario')
    server = load_trace(root/'server'/'trace.jsonl', 'server', run_id)
    clients = {
        role: load_trace(root/role/'trace.jsonl', role, run_id)
        for role in ('a', 'b')
    }
    slow_ms = int(manifest.get('slow_item_writer_ms', 0))
    pending = False
    frames: list[dict] = []
    intervals_ms: list[float] = []
    gaps: list[int] = []
    submit_count = 0
    completed_count = 0
    last_frame = None
    mismatches = 0
    for event in server:
        kind = event.get('kind')
        data = event.get('data', {})
        if kind == 'p1b_item_async_stages':
            stage = data.get('stage')
            if stage == 'SUBMIT':
                submit_count += 1
                if pending:
                    mismatches += 1
                pending = True
                last_frame = None
            if stage == 'DURABLE_COMMIT':
                completed_count += 1
                if not pending:
                    mismatches += 1
                pending = False
                last_frame = None
        if kind == 'movement_snapshot_stages' and data.get('committed_view') is True:
            tick = int(data.get('tick', -1))
            if not pending:
                mismatches += 1
            frame = {'tick': tick,
                     'peers': int(data.get('peers', 0)),
                     'enqueued': int(data.get('committed_enqueues', 0)),
                     'all_enqueued': data.get('all_enqueued') is True}
            frames.append(frame)
            if last_frame is not None:
                intervals_ms.append((event['t_us']-last_frame['t_us'])/1000.0)
                gaps.append(tick-int(last_frame['data']['tick']))
            last_frame = event
    received = {
        role: [e for e in events if e.get('kind')=='r3_committed_view_received']
        for role, events in clients.items()
    }
    issues = []
    if submit_count < 2 or completed_count < 2 or mismatches:
        issues.append(f'M6 in-flight proof mismatch submit={submit_count} commit={completed_count} mismatches={mismatches}')
    if slow_ms >= 500:
        if len(frames) < 20:
            issues.append(f'insufficient in-flight committed frames: {len(frames)} (need 20)')
        if any(f['peers'] != 2 or f['enqueued'] < 2 or not f['all_enqueued'] for f in frames):
            issues.append('failed to enqueue one or both peer frames while ITEM pending')
        if gaps and any(g != 3 for g in gaps):
            issues.append('20Hz fixed tick periodicity violated within ITEM pending')
        if intervals_ms and (pct(intervals_ms, .95) > 80.0 or max(intervals_ms) > 150.0):
            issues.append(f'committed-view walltime gap p95={pct(intervals_ms,.95)}, max={max(intervals_ms)}ms')
        for role, events in received.items():
            if len(events) < 10:
                issues.append(f'{role}: missing real client committed-view reception ({len(events)})')
    result = {
        'schema':'dws.net_smooth.r3_committed_view_acceptance.v1',
        'run_id':run_id,
        'evidence_class': 'GUI' if manifest.get('mode')=='gui' else 'DIAGNOSTIC',
        'injected_writer_ms':slow_ms,
        'verdict':'FAIL' if issues else 'PASS',
        'item_submissions':submit_count,'item_durable_completions':completed_count,
        'pending_server_frames':len(frames),
        'client_receives':{k:len(v) for k,v in received.items()},
        'frame_interval_ms':{'p95':pct(intervals_ms,.95),'max':max(intervals_ms,default=None)},
        'tick_intervals':{'count':len(gaps),'not_three':sum(x!=3 for x in gaps)},
        'issues':issues,
    }
    (root/'r3-committed-view-acceptance.json').write_text(
        json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('output_root',type=Path)
    args = parser.parse_args()
    try:
        result = examine(args.output_root)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f'R3 INCONCLUSIVE: {exc}')
        return 2
    print(json.dumps(result,indent=2,ensure_ascii=False))
    return 0 if result['verdict']=='PASS' else 1


if __name__=='__main__':
    raise SystemExit(main())
