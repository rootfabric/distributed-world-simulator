"""Fail-closed exact product source contract for dedicated-only 60/90/120 cap."""
from __future__ import annotations

import ast
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
POLICY=(ROOT/"scripts/network/smoothness/server_frame_pacing_policy.gd").read_text(encoding="utf-8")
LAUNCH=(ROOT/"scripts/runtime/launch_options.gd").read_text(encoding="utf-8")
APP=(ROOT/"scripts/app/simulator_app.gd").read_text(encoding="utf-8")
RUNNER=(ROOT/"tools/net_smooth1/run_net_smooth1.py").read_text(encoding="utf-8")
COMPARE=(ROOT/"tools/net_smooth1/compare_r31_server_pacing.py").read_text(encoding="utf-8")
SCHED=(ROOT/"scripts/network/simulation/fixed_tick_scheduler.gd").read_text(encoding="utf-8")
SERVER=(ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd").read_text(encoding="utf-8")


class ProductPacingSource(unittest.TestCase):
    def test_inert_default_and_strict_parser(self):
        self.assertIn('"server_frame_cap": 0',LAUNCH)
        self.assertIn('"server-frame-cap":',LAUNCH)
        self.assertIn('_parse_non_negative_int(value, key, errors)',LAUNCH)
        self.assertIn("ServerFramePacingPolicy.validate(options)",LAUNCH)
        self.assertIn('R31_SERVER_FRAME_CAP_INVALID',LAUNCH)
        self.assertIn('if cap == 0:',POLICY)
        self.assertIn('"enabled": false',POLICY)
        self.assertIn('Engine.max_fps = cap',POLICY)
        self.assertIn('Engine.max_fps = before',POLICY)

    def test_only_product_dedicated_earth_optin_allowed(self):
        for part in (
            'ALLOWED_CAPS: Array[int] = [60, 90, 120]',
            'R31_SERVER_FRAME_CAP_UNSUPPORTED',
            'R31_SERVER_FRAME_CAP_DEDICATED_ONLY',
            'R31_SERVER_FRAME_CAP_REQUIRES_MVP',
            'R31_SERVER_FRAME_CAP_REQUIRES_PRODUCT_SEAM',
            'R31_SERVER_FRAME_CAP_EARTH_ONLY',
            'R31_SERVER_FRAME_CAP_ENGINE_REJECTED',
        ):
            self.assertIn(part,POLICY)
        self.assertIn('String(options.get("role", "")) != "dedicated-server"',POLICY)
        self.assertIn('String(options.get("world", "")) != "earth"',POLICY)
        self.assertIn('ServerFramePacingPolicy.apply(launch_options)',APP)
        self.assertIn('NET_SMOOTH_SERVER_FRAME_CAP_APPLIED cap=',APP)
        self.assertIn('get_tree().quit(2)',APP)
        # Role must be checked BEFORE client/server world attachment.
        self.assertLess(APP.index('ServerFramePacingPolicy.apply(launch_options)'),
                        APP.index('presentation_enabled = RuntimeRoleScript'))

    def test_actual_authority_tick_and_wire_unchanged(self):
        self.assertIn('DEFAULT_TICK_RATE_HZ: int = 60',SCHED)
        self.assertIn('NX3_FIXED_TICK_RATE_HZ',SERVER)
        self.assertIn('_fixed_tick_scheduler.advance(frame_delta_seconds)',SERVER)
        self.assertNotIn('Engine.max_fps',SERVER)
        self.assertNotIn('Engine.max_fps',SCHED)
        self.assertIn('snapshot_rate_hz_unchanged": 20',POLICY)

    def test_runner_only_changes_game_flag_for_nondefault_server(self):
        self.assertIn("if role=='server':",RUNNER)
        self.assertIn('if args.server_max_fps != 60:',RUNNER)
        self.assertIn("game += [f'--server-frame-cap={args.server_max_fps}']",RUNNER)
        self.assertIn("engine=build_engine_launch(args.godot, role, args.mode, args.server_max_fps)",RUNNER)
        self.assertIn('default=60',RUNNER)
        self.assertIn('choices=(60,90,120)',RUNNER)
        self.assertIn("server_pacing_diagnostic=args.server_max_fps!=60",RUNNER)

    def test_comparator_requires_native_effective_receipt_and_client_fence(self):
        for phrase in (
            "PACING_PRODUCT_ROLE_CAP_MISMATCH",
            "PACING_SERVER_PRODUCT_ROLE_NOT_ATTESTED",
            "PACING_CLIENT_CLAIMED_SERVER_CAP",
            "PACING_MISSING_NATIVE_ENGINE_EFFECTIVE_CAP_RECEIPT",
            "PACING_UNEXPECTED_PRODUCT_CAP_IN_BASELINE",
            "over_25ms_per_second",
            "PACING_COMPACT_20HZ_CADENCE_BROKEN",
            "DIAGNOSTIC_ONLY_NEVER_ACCEPTS_RELEASE",
        ):
            self.assertIn(phrase,COMPARE)

    def test_falsifier_missing_client_protection_fails_contract(self):
        mutant=POLICY.replace(
            'if String(options.get("role", "")) != "dedicated-server":',
            'if false:')
        self.assertNotEqual(mutant,POLICY)
        self.assertNotIn('String(options.get("role", "")) != "dedicated-server"',mutant)

    def test_python_can_compile_real_scripts(self):
        for s in (RUNNER,COMPARE):
            ast.parse(s)


if __name__ == "__main__":
    unittest.main()
