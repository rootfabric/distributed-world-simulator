"""P2.3 R1 debug FIFO audit falsifiers: no unlogged generations or timestamp drift."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
from validate_r31p23r1_debug_fifo import audit

RUN_ID="0123456789abcdef"
PID=2323
GENERATIONS=[7,8]


def record(kind: str,t: int, *,details=None,measure=True):
    return {"kind":kind,"t_us":t,"data":details or {},"measure":measure}


def fixture(root:Path, *,generations=None,logged=None,
            overflow=False,wrong_pid=False,drop=False,
            enabled=True,reverse_stdout=False,
            missing_m6=False,missing_profiled=False) -> Path:
    generations=generations if generations is not None else GENERATIONS
    logged=logged if logged is not None else generations
    (root/"server").mkdir(parents=True,exist_ok=True)
    (root/"manifest.json").write_text(json.dumps({
        "run_id":RUN_ID,"r31p23_completion_attribution":True,
        "r31p23r1_defer_checkpoint_debug":enabled,
    }))
    (root/"report.json").write_text('{"verdict":"FAIL","reason":"p99>25ms"}')
    rows=[
        record("header",1,details={
            "schema":"dws.net_smooth.trace.v1","pid":PID,"role":"server",
            "run_id":RUN_ID,"clock":"PROCESS_LOCAL_MONOTONIC_US"},measure=False),
        record("measure_start",10),
    ]
    for i,gen in enumerate(generations):
        if not missing_m6:
            rows.append(record("checkpoint_complete",11+i,details={
                "generation":gen,
            }))
        if not missing_profiled:
            rows.append(record("r31p23_movement_completion",11+i,details={
                "generation":gen,
            }))
        rows.append(record("r31p23r1_debug_queued",11+i,details={
            "generation":gen,"time_msec":100+gen,"engine_frame":i+10,
            "pending":i+1,
        }))
    if overflow:
        rows.append(record("r31p23r1_debug_overflow",20,details={
            "generation":90,"engine_frame":42,"pending":32,
        }))
    if generations:
        rows.append(record("r31p23r1_debug_flushed",21,details={
            "generation":generations[0],"engine_frame":50,
            "original_engine_frame":10,"pending":len(generations)-1,
            "print_ms":.2,
        }))
    rows.append(record("measure_end",100,measure=True))
    for i,row in enumerate(rows,1):
        row["n"]=i
    footer=record("end",101,measure=False,details={
        "produced":len(rows),"written":len(rows),
        "dropped":int(drop),"io_errors":0})
    rows.append(footer)
    (root/"server"/"trace.jsonl").write_text(
        "".join(json.dumps(z)+"\n" for z in rows),encoding="utf-8")
    printed=list(logged)
    if reverse_stdout:
        printed.reverse()
    text=""
    for gen in printed:
        data={
            "event":"MOVEMENT_CHECKPOINT_COMMITTED",
            "process_id":PID+1 if wrong_pid else PID,
            "time_msec":100+gen,
            "details":{"generation":gen,"async":True},
        }
        text+="[m7_server] "+json.dumps(data)+"\n"
    (root/"server"/"runtime.log").write_text(text,encoding="utf-8")
    return root


def run_test(*,expected=None,**kwargs):
    with tempfile.TemporaryDirectory() as t:
        root=fixture(Path(t),**kwargs)
        if expected is not None:
            with unittest.TestCase().assertRaisesRegex(ValueError,expected):
                audit(root)
            return
        return audit(root)


class FIFOAudit(unittest.TestCase):
    def test_two_generations_stdout_exact_and_normative_fail_preserved(self):
        data=run_test()
        self.assertEqual(data["verdict"],"P23R1_DEBUG_AUDIT_PASS_NOT_PERF_PASS")
        self.assertEqual(data["queued"],2)
        self.assertEqual(data["printed"],2)
        self.assertEqual(data["first_generation"],7)
        self.assertEqual(data["last_generation"],8)
        self.assertEqual(data["original_normative_verdict"],"FAIL")
        self.assertEqual(data["shutdown_flush_or_untraced"],1)

    def test_m6_checkpoint_missing_in_trace_fails_closed(self):
        run_test(expected="M6_COMPLETION_TO_DEBUG_QUEUE_MISMATCH",
                 missing_m6=True)

    def test_p23_completion_missing_in_trace_fails_closed(self):
        run_test(expected="PROFILED_COMPLETION_TO_DEBUG_QUEUE_MISMATCH",
                 missing_profiled=True)

    def test_one_queued_generation_not_printed_is_inconclusive(self):
        run_test(expected="DEBUG_LOG_COUNT_MISMATCH",logged=[7])

    def test_extra_undocumented_generation_is_inconclusive(self):
        run_test(expected="DEBUG_LOG_COUNT_MISMATCH",logged=[7,8,9])

    def test_same_count_wrong_generation_fails(self):
        run_test(expected="DEBUG_GENERATION_OR_TIMESTAMP_MISMATCH",logged=[7,9])

    def test_fifo_order_swap_fails_without_silent_reorder(self):
        run_test(expected="DEBUG_FIFO_ORDER_MISMATCH",reverse_stdout=True)

    def test_wrapper_pid_vs_main_pid_is_disallowed(self):
        run_test(expected="WRAPPER_VS_MAIN_PID_MISMATCH",wrong_pid=True)

    def test_any_saturation_invalidates_perf_evidence(self):
        run_test(expected="DEBUG_QUEUE_OVERFLOW_RECORDED",overflow=True)

    def test_lost_trace_is_inconclusive_even_if_stdout_matches(self):
        run_test(expected="TRACE_LOSS_OR_IO_ERROR",drop=True)

    def test_missing_canary_never_gets_a_false_pass(self):
        run_test(expected="MISSING_EXACT_CANARY",enabled=False)

    def test_no_real_event_is_inconclusive(self):
        run_test(expected="NO_COMPLETION_DEBUG_QUEUED",generations=[],logged=[])


if __name__=="__main__":
    unittest.main()
