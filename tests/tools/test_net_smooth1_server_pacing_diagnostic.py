"""Fail-closed source + algorithm tests for server-only engine pacing diagnostic."""
from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/net_smooth1"))
import compare_r31_server_pacing as c

SRC=(ROOT/"tools/net_smooth1/run_net_smooth1.py").read_text(encoding="utf-8")
RUNTIME=(ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text(encoding="utf-8")
SCHED=(ROOT/"scripts/network/simulation/fixed_tick_scheduler.gd").read_text(encoding="utf-8")


def isolated_engine_builder():
    module=ast.parse(SRC)
    funcs=[n for n in module.body if isinstance(n,ast.FunctionDef)
           and n.name=="build_engine_launch"]
    assert len(funcs)==1
    code=compile(ast.Module(body=funcs,type_ignores=[]),"<isolated>", "exec")
    ns={"Path":Path,"ROOT":ROOT}
    exec(code,ns)
    return ns["build_engine_launch"]


class ServerOnlyPacing(unittest.TestCase):
    def test_original_60fps_engine_argv_is_byte_parity(self):
        build=isolated_engine_builder()
        godot=Path("C:/Godot/godot.windows.editor.double.x86_64.console.exe")
        old=[str(godot),"--path",str(ROOT),"--max-fps","60",
             "--disable-vsync","--headless"]
        self.assertEqual(build(godot,"server","gui",60),old)

    def test_90_and_120_affect_only_dedicated_headless_server(self):
        build=isolated_engine_builder()
        godot=Path("C:/pin/godot.exe")
        a=build(godot,"a","gui",60)
        b=build(godot,"b","gui",60)
        for cap in (90,120):
            server=build(godot,"server","gui",cap)
            self.assertEqual(c.max_fps_from_command(server,"server"),cap)
            self.assertIn("--headless",server)
            self.assertEqual(build(godot,"a","gui",cap),a)
            self.assertEqual(build(godot,"b","gui",cap),b)
            self.assertEqual(c.max_fps_from_command(a,"a"),60)
            self.assertEqual(c.max_fps_from_command(b,"b"),60)
            self.assertNotIn("--headless",a)
            self.assertIn("--disable-vsync",a)

    def test_invalid_caps_roles_fail_closed(self):
        build=isolated_engine_builder()
        for cap in (0,-1,30,59,61,144,240):
            with self.assertRaisesRegex(ValueError,"INVALID_SERVER_FRAME_PACING_MODE"):
                build(Path("godot"),"server","gui",cap)
        for role,mode in (("x","gui"),("server","editor"),("a","window")):
            with self.assertRaisesRegex(ValueError,"INVALID_PACING_ROLE_OR_MODE"):
                build(Path("godot"),role,mode,60)

    def test_inherited_fixed_tick_and_default_source_guards(self):
        self.assertIn("--server-max-fps",SRC)
        self.assertIn("choices=(60,90,120),default=60",SRC)
        self.assertIn("server_max_fps=args.server_max_fps",SRC)
        self.assertIn("server_pacing_diagnostic=args.server_max_fps!=60",SRC)
        self.assertIn("args.mode != 'gui' or args.scenario != 'r31-reconnect-roundtrip'",SRC)
        self.assertIn("args.profile != 'LOCAL'",SRC)
        self.assertIn("engine=build_engine_launch(args.godot, role, args.mode, args.server_max_fps)",SRC)
        self.assertIn("_fixed_tick_scheduler.advance(frame_delta_seconds)",RUNTIME)
        self.assertIn("NX3_FIXED_TICK_RATE_HZ",RUNTIME)
        self.assertIn("DEFAULT_TICK_RATE_HZ: int = 60",SCHED)
        self.assertIn("if tick_hz<59", (ROOT/"tools/net_smooth1/analyze_net_smooth1.py").read_text())
        self.assertNotIn("Engine.max_fps",RUNTIME)

    def test_increasing_frame_count_does_not_hide_slow_rate(self):
        baseline=c.frame_profile_ms([16.7]*1080+[33.3]*120,120)
        candidate=c.frame_profile_ms([8.3]*2200+[33.3]*120,120)
        self.assertLess(candidate["original_frame_interval_ms"]["p99"],
                        baseline["original_frame_interval_ms"]["p99"])
        self.assertEqual(candidate["over_25ms_per_second"],
                         baseline["over_25ms_per_second"])
        self.assertEqual(candidate["over_25ms_per_second"],1.0)

    def test_invalid_role_command_cannot_pass(self):
        with self.assertRaisesRegex(ValueError,"PACING_SERVER_NOT_HEADLESS"):
            c.max_fps_from_command(["exe","--max-fps","120","--disable-vsync"],"server")
        with self.assertRaisesRegex(ValueError,"PACING_CLIENT_HARDWARE_GUI_NOT_PROVEN"):
            c.max_fps_from_command(["exe","--max-fps","60","--disable-vsync",
                                   "--headless"],"a")
        with self.assertRaisesRegex(ValueError,"INVALID_a_ENGINE_FPS_COMMAND"):
            c.max_fps_from_command(["exe","--max-fps","60","--max-fps","120"],"a")

    def test_pair_must_have_identical_identity_and_unique_run_ids(self):
        def dummy(cap,run_id="foo"):
            return {
                "server_max_fps":cap,"run_id":run_id,
                "source_identity":{"head":"h","tree":"t",
                                  "godot_sha256":"s","asset_manifest_sha256":"a"},
                "original_role_frame_p99_ms":{"server":26.0},
                "server_frame_profile":{"over_25ms_per_second":1.0},
            }
        with patch.object(c,"inspect_run",side_effect=[dummy(60,"a"),dummy(120,"b")]):
            out=c.compare_pairs([(Path("baseline"),Path("trial"))])
            self.assertEqual(out["verdict"],"DIAGNOSTIC_ONLY_NEVER_ACCEPTS_RELEASE")
            self.assertEqual(out["candidate_fps"],120)
        with patch.object(c,"inspect_run",side_effect=[dummy(60,"x"),dummy(120,"x")]):
            with self.assertRaisesRegex(ValueError,"DUPLICATE_RUN_ID"):
                c.compare_pairs([(Path("baseline"),Path("trial"))])
        changed=dummy(120,"y")
        changed["source_identity"]["head"]="other"
        with patch.object(c,"inspect_run",side_effect=[dummy(60,"x"),changed]):
            with self.assertRaisesRegex(ValueError,"SOURCE_DRIFT"):
                c.compare_pairs([(Path("baseline"),Path("trial"))])

    def test_no_artificial_normative_relaxation(self):
        analyzer=(ROOT/"tools/net_smooth1/analyze_net_smooth1.py").read_text()
        for hard_gate in ("frame p99 >25ms","frame p99.9 >50ms",
                          "frame gap >100ms","simulation <59Hz"):
            self.assertIn(hard_gate,analyzer)
        self.assertIn("PACING_COMPACT_20HZ_CADENCE_BROKEN",
                      (ROOT/"tools/net_smooth1/compare_r31_server_pacing.py").read_text())


if __name__=="__main__":
    unittest.main()
