"""R31 P2.3 R0 completion-stage source safety and canary propagation."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
RUNNER=ROOT/"tools/net_smooth1/run_net_smooth1.py"
REDUCER=ROOT/"tools/net_smooth1/analyze_r31p22_loop_stages.py"
WRITER=ROOT/"scripts/persistence/async_checkpoint_writer.gd"


def method(src: str,name: str)->str:
    result=re.search(r"(?ms)^func "+re.escape(name)+r"\(.*?(?=^func |\Z)",src)
    if result is None:
        raise AssertionError(name)
    return result.group()


class CompletionSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=SERVER.read_text(encoding="utf-8")
        cls.runner=RUNNER.read_text(encoding="utf-8")
        cls.reducer=REDUCER.read_text(encoding="utf-8")
        cls.writer=WRITER.read_text(encoding="utf-8")

    def test_default_off_and_requires_exact_p22(self):
        setup=method(self.server,"setup")
        self.assertIn("var _r31p23_completion_attribution_enabled := false",self.server)
        self.assertIn("DWS_NET_R31P23_COMPLETION_ATTRIBUTION",setup)
        self.assertIn("R31P23_INVALID_MODE",setup)
        self.assertIn("R31P23_REQUIRES_R31P22_LOOP_ATTRIBUTION",setup)
        self.assertIn("r31p23_completion_attribution_canary",setup)

    def test_original_m6_durability_and_ack_paths_intact(self):
        src=method(self.server,"_complete_async_movement_checkpoint")
        self.assertEqual(src.count("_movement_checkpoint_writer.poll_completed()"),1)
        self.assertIn("_movement_checkpoint_writer.wait_completed() if wait",src)
        self.assertIn("_checkpoint_generation = generation",src)
        self.assertIn("observe_periodic_commit(generation)",src)
        self.assertIn("_debug_event(\"MOVEMENT_CHECKPOINT_COMMITTED\"",src)
        self.assertIn("_write_report(\"READY\", false)",src)
        self.assertIn("_r3c2_deferred_diagnostic_reports += 1",src)
        self.assertIn('SmoothTrace.emit("r31p23_movement_completion",',src)
        self.assertNotIn("OS.delay_msec",src)
        self.assertNotIn("Thread.new()",src)
        self.assertNotIn("await ",src)
        assert src.index("poll_completed()") < src.index("observe_periodic_commit(")
        assert src.index("observe_periodic_commit(") < src.index("r31p23_movement_completion")
        assert src.index("_write_report(\"READY\"") < src.index("r31p23_movement_completion")

    def test_completion_measurements_cover_post_worker_processing(self):
        src=method(self.server,"_complete_async_movement_checkpoint")
        for key in ("poll_completed_ms","generation_ack_gate_ms","metadata_copy_ms",
                    "completion_trace_ms","telemetry_ms","debug_event_ms",
                    "diagnostic_report_ms","total_ms","engine_frame",
                    "diagnostic_report_deferred"):
            self.assertIn('"'+key+'"',src)
        self.assertIn("Time.get_ticks_usec()",src)

    def test_worker_still_produces_only_bounded_metadata(self):
        s=self.writer
        self.assertIn("func poll_completed()",s)
        self.assertIn("_completion.duplicate(true)",s)
        self.assertIn('"generation": int(job["generation"])',s)
        self.assertIn("var _wake := Semaphore.new()",s)
        self.assertIn("Thread.new()",s)

    def test_server_only_real_gui_flag(self):
        s=self.runner
        self.assertIn("r31p23_completion_attribution=args.r31p23_completion_attribution",s)
        self.assertIn("if role == 'server' and args.r31p23_completion_attribution:",s)
        self.assertIn("env['DWS_NET_R31P23_COMPLETION_ATTRIBUTION']='1'",s)
        self.assertIn("P2.3 movement completion stage attribution requires --r31p22-loop-attribution",s)

    def test_readonly_reducer_keeps_all_frames_and_existing_original_fail(self):
        s=self.reducer
        self.assertIn('"r31p23_movement_completion"',s)
        self.assertIn('"original_normative_verdict":report.get("verdict")',s)
        self.assertIn("COMPLETION_STAGE_ACCOUNTING_MISMATCH",s)
        self.assertIn("COMPLETION_EXCEEDS_P22_MOVEMENT_STAGE",s)
        self.assertIn("P23_NO_REAL_MOVEMENT_COMPLETION_RECORDED",s)
        self.assertIn("require_completion",s)
        self.assertIn("FRAME_JOIN_INCOMPLETE",s)
        self.assertIn('"compact_wire_sums_ms"',s)
        self.assertNotIn("taskkill",s)


if __name__=="__main__":
    unittest.main()
