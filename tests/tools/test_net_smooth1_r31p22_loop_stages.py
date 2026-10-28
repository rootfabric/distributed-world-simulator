"""Strict R31 P2.2 engine-frame stage reducer: positive and RED falsifiers."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/"tools/net_smooth1"))
from analyze_r31p22_loop_stages import (
    STAGES, WIRE_STAGES, analyze_events, read_trace, analyze_run,
)

RUN_ID="0123456789abcdef"
BASIC_STAGES={
    "postcommit_ms":1.0,
    "item_completion_ms":.1,
    "movement_completion_ms":.1,
    "deferred_disconnect_ms":.2,
    "deferred_admission_ms":.3,
    "boundary_poll_ms":.4,
    "message_dispatch_ms":.5,
    "fixed_simulation_ms":1.0,
    "snapshot_publication_ms":2.0,
    "movement_persistence_ms":.5,
    "telemetry_ms":.1,
}
MSG_SUM=sum(BASIC_STAGES[k] for k in STAGES[:7])
TOTAL=sum(BASIC_STAGES.values())


def make_event(kind, frame, t, data, measure=True):
    return {"kind":kind,"t_us":t, "measure":measure,
            "data":{**data, "engine_frame":frame}}


def fixture(*,frames=150,fail_wire=False,missing_loop=None,
            corrupt_accounting=False,unknown_wire=False,missing_snapshot=False,
            include_completion=False, invalid_completion=False):
    rows=[]
    def add(kind,t,data,measure=False):
        rows.append({"kind":kind,"t_us":t,"measure":measure,"data":data})
    add("header",0,{"schema":"dws.net_smooth.trace.v1",
                    "role":"server", "run_id":RUN_ID,
                    "clock":"PROCESS_LOCAL_MONOTONIC_US"})
    add("measure_start",1000,{},True)
    for i in range(1,frames+1):
        t=5000 + i*20000
        have_snap = i % 3 == 0
        if have_snap and not missing_snapshot:
            for _ in range(2):
                if unknown_wire:
                    kind="r31p22_compact_wire_failed"
                    data={"phase":"FLUSH"}
                else:
                    kind="r31p22_compact_wire_stages"
                    data={
                        "payload_clone_ms":.05,"frame_create_ms":.2,
                        "boundary_send_ms":.08,"outbound_flush_ms":.02,
                        "total_ms":.35,
                    }
                rows.append(make_event(kind,i,t+1, data))
            rows.append(make_event("movement_snapshot_stages",i,t+2,{
                "peers":2,"capture_ms":.1,"encode_ms":.2,
                "compact_send_ms":.3 if fail_wire else 1.0,
                "seam_check_send_ms":.2,
            }))
        if include_completion and i % 60 == 0:
            stages={
                "poll_completed_ms":.01, "generation_ack_gate_ms":.01,
                "metadata_copy_ms":.01, "completion_trace_ms":.01,
                "telemetry_ms":.01, "debug_event_ms":.01,
                "diagnostic_report_ms":.01,
            }
            if invalid_completion and i==60:
                stages["generation_ack_gate_ms"]=1.0
            rows.append(make_event("r31p23_movement_completion",i,t+2,{
                "generation":i//60,
                **stages,
                "total_ms":.07,
                "diagnostic_report_deferred":True,
            }))
        rows.append(make_event("server_message",i,t+3,{
            "duration_ms":.15,"type":"PLAYER_INPUT_BATCH"
        }))
        rows.append(make_event("server_loop",i,t+4,{
            "message_ms":MSG_SUM+.02,
            "process_ms":TOTAL+.9,
            "snapshot_ms":2.0,
        }))
        if i != missing_loop:
            vals=dict(BASIC_STAGES)
            if corrupt_accounting and i==4:
                vals["message_dispatch_ms"]=20.0
            rows.append(make_event("r31p22_loop_stages",i,t+5,{
                "server_tick":i,"polled_events":2,
                **vals, "message_span_ms":MSG_SUM,
                "measured_total_ms":TOTAL,
            }))
        rows.append(make_event("frame",i,t+10,{"interval_ms":32.0 if i==80 else 27.0 if i==79 else 20.0,
                                              "engine_process_ms":5.0}))
    add("measure_end",5000+(frames+1)*20000,{},True)
    # Every produced row (including header/start/end-of-measure) has a gap-free
    # sequence. The final trace footer does NOT use the regular n numbering.
    for k,row in enumerate(rows,1):
        row["n"]=k
    rows.append({"kind":"end","t_us":5000+(frames+1)*20000+100,
                 "data":{"dropped":0,"io_errors":0,
                         "written":len(rows),"produced":len(rows)}})
    return rows


def write(root:Path, *, mutator=None, **options)->Path:
    d=root/"server"
    d.mkdir(parents=True,exist_ok=True)
    rows=fixture(**options)
    if mutator:
        mutator(rows)
    file=d/"trace.jsonl"
    file.write_text("".join(json.dumps(x)+"\n" for x in rows),encoding="utf-8")
    return file


class StageReducer(unittest.TestCase):
    def test_exact_engine_frame_join_and_no_normative_reinterpretation(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp))
            result=analyze_events(read_trace(path,RUN_ID))
            self.assertEqual(result["verdict"],"STAGE_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS")
            self.assertEqual(result["same_frame_count"],150)
            self.assertEqual(result["snapshot_frame_count"],50)
            self.assertEqual(result["compact_wire_event_count"],100)
            self.assertEqual(result["message_handler_event_count"],150)
            self.assertAlmostEqual(result["worst_frame_samples"][0][
                "message_handler_sum_ms"],.15)
            self.assertGreater(result["worst_frame_samples"][0][
                "unattributed_dispatch_ms"],.30)
            self.assertAlmostEqual(result["components_ms"]["postcommit_ms"]["p99"],1.0)
            self.assertAlmostEqual(result["compact_wire_components_ms"]["frame_create_ms"]["p99"],.2)
            self.assertEqual(result["p99_tail_frame_count"],2)
            self.assertEqual(result["worst_frame_samples"][0]["engine_frame"],80)
            self.assertEqual(result["frame_interval_ms"]["p99"],27.0)

    def test_completion_stages_exact_engine_frame_are_attributed(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),include_completion=True)
            r=analyze_events(read_trace(path,RUN_ID))
            self.assertEqual(r["movement_completion_event_count"],2)
            self.assertAlmostEqual(r["movement_completion_components_ms"][
                "poll_completed_ms"]["p99"], .01)
            matched=[x for x in r["worst_frame_samples"]
                     if x["has_movement_completion"]]
            self.assertGreaterEqual(len(matched), 1)
            self.assertAlmostEqual(matched[0]["movement_completion_stages_ms"][
                "poll_completed_ms"],.01)
            self.assertEqual(r["verdict"],"STAGE_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS")

    def test_invalid_completion_accounting_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),include_completion=True,invalid_completion=True)
            with self.assertRaisesRegex(ValueError,"COMPLETION_STAGE_ACCOUNTING_MISMATCH"):
                analyze_events(read_trace(path,RUN_ID))

    def test_even_one_missing_non_snapshot_stage_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),missing_loop=11)
            rows=read_trace(path,RUN_ID)
            # Do not let the handler-specific orphan guard mask the exact
            # frame coverage guard we are falsifying in this case.
            rows["server_message"]=[
                r for r in rows["server_message"]
                if r["data"]["engine_frame"] != 11]
            with self.assertRaisesRegex(ValueError,"FRAME_JOIN_INCOMPLETE"):
                analyze_events(rows)

    def test_extra_stage_not_joined_to_any_measured_frame_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            rows=read_trace(write(Path(temp)),RUN_ID)
            import copy
            extra=copy.deepcopy(rows["r31p22_loop_stages"][0])
            extra["data"]["engine_frame"]=9999
            rows["r31p22_loop_stages"].append(extra)
            base=copy.deepcopy(rows["server_loop"][0])
            base["data"]["engine_frame"]=9999
            rows["server_loop"].append(base)
            with self.assertRaisesRegex(ValueError,"STAGE_WITHOUT_MEASURED_FRAME"):
                analyze_events(rows)

    def test_wire_exceeding_compact_send_invalid(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),fail_wire=True)
            with self.assertRaisesRegex(ValueError,"WIRE_COMPONENTS_EXCEED_COMPACT_SEND"):
                analyze_events(read_trace(path,RUN_ID))

    def test_handler_time_exceeding_dispatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp))
            rows=read_trace(path,RUN_ID)
            rows["server_message"][0]["data"]["duration_ms"]=4.0
            with self.assertRaisesRegex(ValueError,"HANDLERS_EXCEED_DISPATCH"):
                analyze_events(rows)

    def test_compact_send_failure_cannot_be_reported_as_success(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),unknown_wire=True)
            with self.assertRaisesRegex(ValueError,"COMPACT_WIRE_FAILED"):
                analyze_events(read_trace(path,RUN_ID))

    def test_impossible_stage_accounting_is_invalid(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),corrupt_accounting=True)
            with self.assertRaisesRegex(ValueError,"STAGE_ACCOUNTING_MISMATCH"):
                analyze_events(read_trace(path,RUN_ID))

    def test_no_snapshot_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp),missing_snapshot=True)
            with self.assertRaisesRegex(ValueError,"INSUFFICIENT_FRAME_OR_SNAPSHOT"):
                analyze_events(read_trace(path,RUN_ID))

    def test_trace_loss_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            def poison(rows):
                rows[-2]["n"]=rows[-3]["n"]  # duplicate produced sequence, not footer
            path=write(Path(temp),mutator=poison)
            with self.assertRaisesRegex(ValueError,"TRACE_SEQUENCE_LOSS"):
                read_trace(path,RUN_ID)

    def test_footer_dropped_events_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp))
            rows=[json.loads(s) for s in path.read_text().splitlines()]
            rows[-1]["data"]["dropped"]=1
            path.write_text("".join(json.dumps(r)+"\n" for r in rows))
            with self.assertRaisesRegex(ValueError,"TRACE_LOSS_OR_IO_ERROR"):
                read_trace(path,RUN_ID)

    def test_cross_process_clock_never_joined(self):
        with tempfile.TemporaryDirectory() as temp:
            path=write(Path(temp))
            rows=[json.loads(s) for s in path.read_text().splitlines()]
            rows[0]["data"]["role"]="a"
            path.write_text("".join(json.dumps(r)+"\n" for r in rows))
            with self.assertRaisesRegex(ValueError,"WRONG_TRACE_IDENTITY"):
                read_trace(path,RUN_ID)

    def test_normative_report_fail_remains_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            write(root)
            (root/"manifest.json").write_text(json.dumps({
                "mode":"gui","profile":"LOCAL","scenario":"r31-reconnect-roundtrip",
                "completed":True,"errors":[],"r31bp1_durable_chunks":True,
                "r3c4r2_worker_envelope":True,"r31p22_loop_attribution":True,
                "run_id":RUN_ID, "identity":{"head":"same","tree":"same"}
            }))
            (root/"report.json").write_text('{"verdict":"FAIL","reason":"server p99>25"}')
            result=analyze_run(root)
            self.assertEqual(result["source"]["original_normative_verdict"],"FAIL")
            self.assertEqual(result["verdict"],"STAGE_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS")


if __name__=="__main__":
    unittest.main()
