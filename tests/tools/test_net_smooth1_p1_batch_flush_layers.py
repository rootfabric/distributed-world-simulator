"""R2.2 attestation + P1 batching: exact fail-closed same-frame count/latency."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tests/tools"))
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from test_net_smooth1_r31p23r2_flush_layers import decorate
from analyze_r31p23r2_flush_layers import analyze


def batched(root:Path, *, manifest_batch:bool=True) -> Path:
    decorate(root,r21=True,manifest_overrides={
        "r31p23r22_attested_compact":True,
        "r31p1_snapshot_batching":manifest_batch,
    })
    trace=root/"server"/"trace.jsonl"
    rows=[json.loads(x) for x in trace.read_text(encoding="utf-8").splitlines()]
    counts={}
    last={}
    for index,row in enumerate(rows):
        if row["kind"]=="r31p23r2_flush_packet":
            fid=row["data"]["engine_frame"]
            counts[fid]=counts.get(fid,0)+1
        if row["kind"]=="r31p22_compact_wire_stages":
            # Per-peer event now ends after ENQUEUE, prior to global flush.
            fid=row["data"]["engine_frame"]
            row["data"]["outbound_flush_ms"]=0.0
            last[fid]=index
    rebuilt=[]
    for index,row in enumerate(rows[:-1]):
        rebuilt.append(row)
        if row["kind"]=="r31p22_compact_wire_stages":
            fid=row["data"]["engine_frame"]
            if last[fid]==index:
                count=counts[fid]
                rebuilt.append({
                    "kind":"r31p1_snapshot_batch_flush",
                    "t_us":row["t_us"],
                    "measure":True,
                    "n":0,
                    "data":{
                        "engine_frame":fid,
                        "target_peers":count,
                        "queued_compact_frames":count,
                        "attempted":count,
                        "dispatched":count,
                        "failed_count":0,
                        "blocked_stream_count":0,
                        "pending_messages":0,
                        "pending_bytes":0,
                        "complete":True,
                        "batch_flush_ms":0.2,
                    },
                })
    footer=rows[-1]
    rebuilt.append(footer)
    publish(trace,rebuilt)
    return root


def publish(trace:Path,rows:list[dict]) -> None:
    for index,row in enumerate(rows[:-1],1):
        row["n"]=index
    # Original END does not carry sequential n: expected produced/written
    # equals count of all non-END events.
    rows[-1]["data"]["written"]=len(rows)-1
    rows[-1]["data"]["produced"]=len(rows)-1
    trace.write_text("".join(json.dumps(x)+"\n" for x in rows),encoding="utf-8")


def mutate(root:Path,fn) -> None:
    trace=root/"server"/"trace.jsonl"
    rows=[json.loads(x) for x in trace.read_text(encoding="utf-8").splitlines()]
    fn(rows)
    publish(trace,rows)


class StrictP1Batch(unittest.TestCase):
    def sample(self,mutator=None,error=None):
        with tempfile.TemporaryDirectory() as tmp:
            root=batched(Path(tmp))
            if mutator:
                mutate(root,mutator)
            trace=root/"server"/"trace.jsonl"
            unchanged=trace.read_bytes()
            if error is not None:
                with self.assertRaisesRegex(ValueError,error):
                    analyze(root)
            else:
                result=analyze(root)
                self.assertEqual(result["normative_original_verdict"],"FAIL")
                self.assertTrue(result["p1_batch_expected"])
                self.assertGreater(result["p1_batch_event_count"],0)
                self.assertEqual(result["all_nested_flush_events"],100)
                self.assertEqual(result["r22_confirmed_passthrough_events"],100)
                self.assertTrue(all(f["batch_flush_ms"]>0
                                    for f in result["worst_flush_frames"]))
            self.assertEqual(unchanged,trace.read_bytes())

    def test_true_native_attested_p1_batch_is_accepted_without_relabeling_perf(self):
        self.sample()

    def test_missing_one_batch_marker_rejected(self):
        def f(rows):
            index=next(i for i,r in enumerate(rows)
                       if r["kind"]=="r31p1_snapshot_batch_flush")
            rows.pop(index)
        self.sample(f,"P1_BATCH_MISSING_OR_UNEXPECTED_FRAME")

    def test_duplicate_batch_marker_rejected(self):
        def f(rows):
            index=next(i for i,r in enumerate(rows)
                       if r["kind"]=="r31p1_snapshot_batch_flush")
            rows.insert(index+1,json.loads(json.dumps(rows[index])))
        self.sample(f,"P1_BATCH_DUPLICATE_FRAME")

    def test_partial_success_with_failed_receipt_rejected(self):
        def f(rows):
            row=next(r for r in rows if r["kind"]=="r31p1_snapshot_batch_flush")
            row["data"]["failed_count"]=1
        self.sample(f,"P1_BATCH_UNFLUSHED_MESSAGES")

    def test_positive_pending_count_rejected(self):
        def f(rows):
            row=next(r for r in rows if r["kind"]=="r31p1_snapshot_batch_flush")
            row["data"]["pending_messages"]=1
        self.sample(f,"P1_BATCH_UNFLUSHED_MESSAGES")

    def test_underdispatch_rejected(self):
        def f(rows):
            row=next(r for r in rows if r["kind"]=="r31p1_snapshot_batch_flush")
            row["data"]["dispatched"]=1
            row["data"]["attempted"]=1
            # Each fixture engine_frame has exactly two COMPACT packets.
        self.sample(f,"P1_BATCH_COUNT_INCONSISTENT")

    def test_lost_nested_packet_rejected(self):
        def f(rows):
            index=next(i for i,r in enumerate(rows)
                       if r["kind"]=="r31p23r2_flush_packet")
            rows.pop(index)
        self.sample(f,"P23R2_INCOMPLETE_COMPACT_COVERAGE")

    def test_batch_canary_does_not_accept_missing_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=decorate(Path(tmp),r21=True,manifest_overrides={
                "r31p23r22_attested_compact":True,
                "r31p1_snapshot_batching":True,
            })
            with self.assertRaisesRegex(ValueError,"P1_BATCH_MISSING_OR_UNEXPECTED_FRAME"):
                analyze(root)


if __name__=="__main__":
    unittest.main()
