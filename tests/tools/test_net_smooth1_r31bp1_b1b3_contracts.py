"""B1/B3 evidence contract: Win64 object identity and post-run GUI isolation."""
from __future__ import annotations
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
ANALYZER=ROOT/"tools/net_smooth1/analyze_r31bp1_durable_chunks.py"
CLEANER=ROOT/"tools/net_smooth1/owned_process_cleanup.py"
RUNNER=ROOT/"tools/net_smooth1/run_net_smooth1.py"
PROBE=ROOT/"scripts/network/smoothness/net_smooth_probe.gd"


class EvidenceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.analyzer=ANALYZER.read_text(encoding="utf-8")
        cls.cleaner=CLEANER.read_text(encoding="utf-8")
        cls.runner=RUNNER.read_text(encoding="utf-8")
        cls.probe=PROBE.read_text(encoding="utf-8")

    def test_windows_signed_object_id_accepted_without_normalization(self):
        s=self.analyzer
        self.assertIn('fence["instance_id"] == 0',s)
        self.assertIn("-9223372036854775808",s)
        self.assertIn("9223372036854775807",s)
        self.assertNotIn('fence["instance_id"] <= 0',s)
        self.assertNotIn('abs(fence["instance_id"])',s)
        for source in ("authority_owner_id","authority_epoch","state_serial",
                       "revision","tick","generation"):
            self.assertIn(source,s)

    def test_cleanup_is_exact_scoped_and_rechecked(self):
        s=self.cleaner
        self.assertIn("select_windows_owned_godot",s)
        self.assertIn("godot_binary",s)
        self.assertIn("taskkill",s)
        self.assertIn('"--instance-id=" + run_id',s)
        self.assertIn('"--node-id=smooth-" + role + "-" + run_id',s)
        self.assertIn("OWNED_GODOT_ORPHAN_RECOVERED",s)
        self.assertIn("OWNED_GODOT_PROCESSES_REMAIN",s)
        self.assertIn("WINDOWS_PROCESS_CLEANUP_UNVERIFIED",s)
        self.assertNotIn('"/IM"',s)
        self.assertNotIn("taskkill /IM",s)

    def test_r31_end_fence_ack_is_written_after_measurement_stops(self):
        p=self.probe
        self.assertIn('directory.path_join("measure.end.ack")',p)
        self.assertIn('NET_SMOOTH_MEASURE_END_ACK_WRITE_FAILED',p)
        self.assertLess(p.index("Trace.measuring = false"),p.index('directory.path_join("measure.end.ack")'))
        self.assertIn("ack.flush()",p)
        self.assertIn("ack.close()",p)

    def test_runner_waits_all_three_end_acks_before_teardown(self):
        s=self.runner
        self.assertIn("from owned_process_cleanup import finalize_owned_processes, preflight_no_smooth_godot",s)
        self.assertIn("measurement_close_ack_complete",s)
        self.assertIn("INVALID_MEASURE_END_ACK",s)
        self.assertIn("NET_SMOOTH_MEASURE_END_ACK_TIMEOUT",s)
        self.assertIn("preflight_no_smooth_godot(args.godot)",s)
        self.assertIn("finalize_owned_processes(",s)
        self.assertIn("NET_SMOOTH_RUN_PROCESS_ISOLATION_UNVERIFIED",s)
        self.assertIn("manifest['cleanup'] = cleanup",s)
        self.assertRegex(s,r"if not measure_closed:\s*close_measure_window\(\)")
        self.assertNotIn("time.sleep(.5)\n        for role in ('a','b'):",s)

    def test_failure_is_not_silent_success(self):
        s=self.runner
        self.assertIn("manifest['errors'].extend(cleanup.get('errors', []))",s)
        self.assertIn("dump(root/'manifest.json',manifest)",s)
        self.assertIn("return {'PASS':0,'FAIL':1,'INCONCLUSIVE':2}[report['verdict']]",s)


if __name__=="__main__":
    unittest.main()
