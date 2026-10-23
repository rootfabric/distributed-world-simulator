"""P2.2 source fence: only source timing / ID fields, no M6 or wire mutation."""
from __future__ import annotations
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
PROBE=ROOT/"scripts/network/smoothness/net_smooth_probe.gd"
HARNESS=ROOT/"tools/net_smooth1/run_net_smooth1.py"
REDUCER=ROOT/"tools/net_smooth1/analyze_r31p22_loop_stages.py"


def method(text: str, name: str) -> str:
    hit=re.search(r"(?ms)^func " + re.escape(name) +
                  r"\(.*?(?=^func |\Z)",text)
    if not hit:
        raise AssertionError("missing method "+name)
    return hit.group()


class Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=SERVER.read_text(encoding="utf-8")
        cls.probe=PROBE.read_text(encoding="utf-8")
        cls.harness=HARNESS.read_text(encoding="utf-8")
        cls.reducer=REDUCER.read_text(encoding="utf-8")

    def test_runtime_optin_fail_closed_default_off(self):
        s=method(self.server,"setup")
        self.assertIn("DWS_NET_R31P22_LOOP_ATTRIBUTION",s)
        self.assertIn("R31P22_INVALID_MODE",s)
        self.assertIn("R31P22_REQUIRES_P1_P0_REPLAY_R2_PERSISTENCE_SEAM",s)
        self.assertIn("r31p22_loop_attribution_canary",s)
        self.assertIn("var _r31p22_loop_attribution_enabled := false",self.server)
        self.assertIn('not bool(config.get("product_seam_enabled", false))',s)

    def test_server_original_function_calls_same_order(self):
        s=method(self.server,"_process")
        calls=[
            "_r3c2_drain_postcommit_stage()",
            "_p1b_poll_item_async_commit()",
            "_complete_async_movement_checkpoint(false)",
            "_drain_deferred_disconnects()",
            "_r3c_drain_deferred_admissions()",
            "_boundary.poll_events(128)",
            "_advance_fixed_simulation(delta)",
            "_maybe_publish_movement_snapshot()",
            "_maybe_persist_movement_checkpoint()",
            "_update_runtime_telemetry()",
        ]
        positions=[s.index(x) for x in calls]
        self.assertEqual(positions,sorted(positions))
        for call in calls:
            self.assertEqual(s.count(call),1)
        self.assertIn('SmoothTrace.emit("server_loop", p22_server_loop_record)',s)
        self.assertIn('SmoothTrace.emit("r31p22_loop_stages"',s)
        self.assertIn("p22_marks.size() == 12",s)
        self.assertIn('"engine_frame": Engine.get_process_frames()',s)
        self.assertIn('"message_span_ms"',s)
        self.assertIn('"boundary_poll_ms"',s)
        self.assertIn('"message_dispatch_ms"',s)
        self.assertNotIn("delay_msec(",s)

    def test_compact_wire_order_exact_and_same_three_sends(self):
        s=method(self.server,"_send_on_channel")
        self.assertIn('message_type == "COMPACT_GAMEPLAY_SNAPSHOT"',s)
        order=[
            'data.duplicate(false) if message_type == "COMPACT_GAMEPLAY_SNAPSHOT"',
            "_boundary.create_frame_for_peer(",
            "_boundary.send_to_peer(",
            "_boundary.flush_outbound(32, peer_id)",
        ]
        loc=[s.index(k) for k in order]
        self.assertEqual(loc,sorted(loc))
        for name in order[1:]:
            self.assertEqual(s.count(name),1)
        for kind in ("payload_clone_ms","frame_create_ms","boundary_send_ms",
                     "outbound_flush_ms","total_ms"):
            self.assertIn('"'+kind+'"',s)
        self.assertIn('"r31p22_compact_wire_failed"',s)
        self.assertIn('"r31p22_compact_wire_stages"',s)
        self.assertIn('"engine_frame": Engine.get_process_frames()',s)
        self.assertIn("_messages_sent += 1",s)
        self.assertNotIn("await ",s)

    def test_snapshot_and_probe_only_add_frame_identity_optin(self):
        s=method(self.server,"_maybe_publish_movement_snapshot")
        self.assertIn("p22_snapshot_stage_record",s)
        self.assertIn('["engine_frame"] = Engine.get_process_frames()',s)
        self.assertIn('SmoothTrace.emit("movement_snapshot_stages"',s)
        self.assertIn('"compact_send_ms"',s)
        p=method(self.probe,"_process")
        self.assertIn('OS.get_environment("DWS_NET_R31P22_LOOP_ATTRIBUTION") == "1"',p)
        self.assertIn('frame_data["engine_frame"] = Engine.get_process_frames()',p)
        self.assertIn('Trace.emit("frame", frame_data)',p)
        self.assertIn('Trace.emit("measure_end")',p)
        self.assertIn('Trace.measuring = false',p)

    def test_gui_flag_only_on_server(self):
        h=self.harness
        self.assertIn("r31p22_loop_attribution=args.r31p22_loop_attribution",h)
        self.assertIn("if role == 'server' and args.r31p22_loop_attribution:",h)
        self.assertIn("env['DWS_NET_R31P22_LOOP_ATTRIBUTION']='1'",h)
        self.assertIn("P2.2 server-loop stage attribution requires --r31bp1-durable-chunks",h)

    def test_new_tool_is_read_only_preserves_original_fail(self):
        r=self.reducer
        self.assertIn('"STAGE_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS"',r)
        self.assertIn('"original_normative_verdict":report.get("verdict")',r)
        self.assertIn("TRACE_SEQUENCE_LOSS",r)
        self.assertIn("TRACE_LOSS_OR_IO_ERROR",r)
        self.assertIn("DUPLICATE_ENGINE_FRAME",r)
        self.assertIn("FRAME_JOIN_INCOMPLETE",r)
        self.assertIn("COMPACT_WITHOUT_SNAPSHOT_ENGINE_FRAME",r)
        self.assertIn("wire_total>compact_time+TOLERANCE_MS",r)
        self.assertNotIn("taskkill",r)


if __name__=="__main__":
    unittest.main()
