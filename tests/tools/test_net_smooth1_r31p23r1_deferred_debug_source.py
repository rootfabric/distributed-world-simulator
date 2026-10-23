"""P2.3 R1 source fences: deferred DEBUG ONLY; M6/ACK/wire untouched.

These checks supplement real native Godot tests and full two-client GUI
acceptance. They must never be counted as PERF_PASS on their own.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
RUNNER=ROOT/"tools/net_smooth1/run_net_smooth1.py"
WRITER=ROOT/"scripts/persistence/async_checkpoint_writer.gd"
BOUNDARY=ROOT/"scripts/network/transports/v2/network_transport_boundary_v2.gd"
FRAME=ROOT/"scripts/network/transports/v2/protocol_frame_v2.gd"


def method(src: str, name: str) -> str:
    hit=re.search(r"(?ms)^func "+re.escape(name)+r"\(.*?(?=^func |\Z)", src)
    if hit is None:
        raise AssertionError("missing func: "+name)
    return hit.group()


class DeferredCheckpointDebug(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=SERVER.read_text(encoding="utf-8")
        cls.runner=RUNNER.read_text(encoding="utf-8")
        cls.writer=WRITER.read_text(encoding="utf-8")
        cls.boundary=BOUNDARY.read_text(encoding="utf-8")
        cls.frame=FRAME.read_text(encoding="utf-8")

    def test_default_off_requires_exact_p23_stack(self):
        src=self.server
        self.assertIn("var _r31p23r1_deferred_checkpoint_debug_enabled := false",src)
        setup=method(src,"setup")
        self.assertIn("DWS_NET_R31P23R1_DEFER_CHECKPOINT_DEBUG",setup)
        self.assertIn("R31P23R1_INVALID_MODE",setup)
        self.assertIn("R31P23R1_REQUIRES_P23_COMPLETION_ATTRIBUTION",setup)
        self.assertIn("r31p23r1_defer_checkpoint_debug_canary",setup)
        self.assertIn("r31p23r1_mode not in [\"0\", \"1\"]",setup)

    def test_only_completed_periodic_debug_event_is_deferred(self):
        done=method(self.server,"_complete_async_movement_checkpoint")
        self.assertIn('if _r31p23r1_deferred_checkpoint_debug_enabled:',done)
        self.assertIn("_r31p23r1_enqueue_completion_debug(generation)",done)
        self.assertIn('else:\n\t\t_debug_event("MOVEMENT_CHECKPOINT_COMMITTED"',done)
        self.assertEqual(done.count("_r31p23r1_enqueue_completion_debug(generation)"),1)
        # Durable generation and periodic ACK must finish BEFORE queued output.
        self.assertLess(done.index("_checkpoint_generation = generation"),
                        done.index("observe_periodic_commit(generation)"))
        self.assertLess(done.index("observe_periodic_commit(generation)"),
                        done.index("_r31p23r1_enqueue_completion_debug(generation)"))
        self.assertIn("if not bool(completed.get(\"success\", false)):",done)
        self.assertIn("_movement_checkpoint_writer.poll_completed()",done)
        self.assertIn("_movement_checkpoint_writer.wait_completed() if wait",done)
        self.assertIn('_debug_event("MOVEMENT_CHECKPOINT_COMMITTED"',done)
        self.assertIn("r31p23_movement_completion",done)
        # Ordinary movement checkpoint, ITEM/CONSTRUCTION, JOIN and
        # DISCONNECT durability cannot enter the deferred debug queue.
        for fn in ("_handle_item_command","_handle_join","_handle_leave",
                   "_p1b_begin_item_async_commit","_maybe_publish_movement_snapshot",
                   "_send_on_channel"):
            self.assertNotIn("_r31p23r1_enqueue_completion_debug",method(self.server,fn))
        self.assertIn("Checkpoint",self.writer)
        self.assertIn('checkpoint_id',self.writer)

    def test_exact_legacy_stdout_shape_and_bounded_fifo(self):
        enqueue=method(self.server,"_r31p23r1_enqueue_completion_debug")
        for v in ("MOVEMENT_CHECKPOINT_COMMITTED","OS.get_process_id()",
                  "Time.get_ticks_msec()","generation",
                  "JSON.stringify","_r31p23r1_debug_lines.append",
                  "_r31p23r1_debug_queued += 1"):
            self.assertIn(v,enqueue)
        self.assertIn("R31P23R1_MAX_DEBUG_QUEUE",enqueue)
        self.assertIn("R31P23R1_MAX_DEBUG_QUEUE := 32",self.server)
        self.assertIn("_r31p23r1_debug_overflow_sync += 1",enqueue)
        self.assertIn('_debug_event("MOVEMENT_CHECKPOINT_COMMITTED"',enqueue)
        self.assertIn('SmoothTrace.emit("r31p23r1_debug_queued"',enqueue)
        original=method(self.server,"_debug_event")
        self.assertIn('print("[m7_server] %s" % JSON.stringify',original)
        self.assertIn('"time_msec":Time.get_ticks_msec()',original)
        self.assertIn('"details":details',original)

    def test_log_cannot_print_in_same_completion_frame(self):
        take=method(self.server,"_r31p23r1_take_next_debug_line")
        self.assertIn('int(head.get("engine_frame", -1)) >= engine_frame',take)
        self.assertIn("_r31p23r1_debug_lines.pop_front()",take)
        self.assertIn("return {}",take)
        idle=method(self.server,"_r31p23r1_flush_one_idle_debug")
        for text in ("_last_movement_snapshot_tick",
                     "_p1b_item_pending.is_empty()",
                     "_r3c2_postcommit_pending.is_empty()",
                     "R31P23R1_IDLE_FRAME_BUDGET_US",
                     "_r31p23r1_take_next_debug_line",
                     'print(String(item["line"]))',
                     'SmoothTrace.emit("r31p23r1_debug_flushed"'):
            self.assertIn(text,idle)
        self.assertIn("R31P23R1_IDLE_FRAME_BUDGET_US := 8000",self.server)

    def test_shutdown_flush_explicit_outside_measured_gameplay(self):
        stopped=method(self.server,"stop")
        self.assertLess(stopped.index("set_process(false)"),
                        stopped.index("_r31p23r1_flush_shutdown_debug()"))
        self.assertLess(stopped.index("_complete_async_movement_checkpoint(true)"),
                        stopped.index("_r31p23r1_flush_shutdown_debug()"))
        done=method(self.server,"_r31p23r1_flush_shutdown_debug")
        self.assertIn('print(String(item["line"]))',done)
        self.assertIn("_r31p23r1_debug_flushed += 1",done)
        self.assertIn("_r31p23r1_debug_lines.is_empty()",done)
        self.assertNotIn("Thread",done)
        self.assertNotIn("await",done)

    def test_no_change_to_protocol_sessions_or_fps(self):
        proto=self.frame
        for token in ('"payload_checksum": UtilsScript.payload_hash(canonical_payload)',
                      "FrameScript","func validate("):
            if token=="FrameScript": continue
            self.assertIn(token,proto)
        for phrase in ("peek_next_outgoing_sequence()","commit_outgoing_sequence",
                       "create_frame_for_peer","flush_outbound"):
            self.assertIn(phrase,self.boundary)
        src=method(self.server,"_send_on_channel")
        self.assertNotIn("r31p23r1",src)
        self.assertIn("_boundary.create_frame_for_peer(",src)
        self.assertIn("_boundary.send_to_peer(",src)
        self.assertIn("_boundary.flush_outbound(32, peer_id)",src)
        self.assertIn("NX3_FIXED_TICK_RATE_HZ := 60",self.server)
        self.assertIn("NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS := 3",self.server)

    def test_runner_is_server_only_and_has_no_inert_flags(self):
        runner=self.runner
        self.assertIn("r31p23r1_defer_checkpoint_debug=args.r31p23r1_defer_checkpoint_debug",runner)
        self.assertIn("if role == 'server' and args.r31p23r1_defer_checkpoint_debug:",runner)
        self.assertIn("env['DWS_NET_R31P23R1_DEFER_CHECKPOINT_DEBUG']='1'",runner)
        self.assertIn("P2.3 R1 debug deferral requires --r31p23-completion-attribution",runner)
        self.assertIn("--r31p23r1-defer-checkpoint-debug",runner)


if __name__=="__main__":
    unittest.main()
