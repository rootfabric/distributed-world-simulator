"""R31 real GUI measurement duration must not include functional seam roundtrips.

Source-only contract; the real two-client 120s GUI run is required separately.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = (ROOT / "tools/net_smooth1/run_net_smooth1.py").read_text(encoding="utf-8")
ANALYZER = (ROOT / "tools/net_smooth1/analyze_net_smooth1.py").read_text(encoding="utf-8")

def r31_measure_clock_is_reset(source: str) -> bool:
    marker = "# Functional r31 stages (including B's mid-remote reconnect) are"
    start = source.find(marker)
    if start == -1:
        return False
    finish = source.find("        def standard_phase_loop()", start)
    if finish == -1:
        return False
    segment = source[start:finish]
    return bool(re.search(
        r"for role in processes: \(root/role/'measure.start'\)\.touch\(\)"
        r"\s*#(?:[^\n]*)\n"
        r"(?:\s*#(?:[^\n]*)\n)*"
        r"\s*started = time\.monotonic\(\)",
        segment
    ))

class TestR31MeasureWindow(unittest.TestCase):
    def test_r31_timer_reset_after_functional_roundtrip_before_perf_loop(self):
        self.assertTrue(r31_measure_clock_is_reset(RUNNER))
        self.assertIn("while time.monotonic()-started < args.duration:", RUNNER)
        self.assertIn("standard_phase_loop()", RUNNER)

    def test_negative_mutant_old_r31_timer_cannot_pass(self):
        mutant = RUNNER.replace(
            "            started = time.monotonic()\n        def standard_phase_loop() -> None:",
            "        def standard_phase_loop() -> None:",
        )
        self.assertNotEqual(mutant, RUNNER)
        self.assertFalse(r31_measure_clock_is_reset(mutant))

    def test_analyzer_duration_gate_stays_fail_closed(self):
        self.assertIn("if duration < min_seconds: problems.append(\"insufficient measured duration\")", ANALYZER)
        self.assertIn('if client_state != "CONNECTED" or unexpected_states: failures.append(', ANALYZER)
        self.assertIn("frame p99 >25ms", ANALYZER)
        self.assertIn("frame p99.9 >50ms", ANALYZER)
        self.assertIn("frame gap >100ms", ANALYZER)

    def test_other_scenarios_keep_reconnect_outside_window(self):
        self.assertIn("def close_measure_window()", RUNNER)
        for scenario in ("r3-slow-item", "durable-commands", "local", "seam-stress"):
            self.assertIn(scenario, RUNNER)
        self.assertIn("close_measure_window()", RUNNER)
        # The fixed 1.2s sleep was replaced by a stronger handshake:
        # ALL three probes must explicitly acknowledge measure.end before
        # reconnect, screenshots, or process teardown can begin. This test
        # deliberately rejects any regression to blind time-based sleeps.
        self.assertIn("'measure.end.ack'", RUNNER)
        self.assertIn("measurement_close_ack_complete", RUNNER)
        self.assertIn("NET_SMOOTH_MEASURE_END_ACK_TIMEOUT", RUNNER)
        self.assertIn("if not measure_closed:", RUNNER)
        self.assertIn("close_measure_window()", RUNNER)
        self.assertNotIn("time.sleep(1.2)", RUNNER)

if __name__ == "__main__":
    unittest.main()
