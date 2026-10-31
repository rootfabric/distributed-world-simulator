"""R3C2 R2 trace-worker stage guard.

The R2 external flush feature introduced a second String(int) construction,
this time inside the SmoothTrace IO worker (net_smooth_trace.gd). The first
r3c2_postcommit_stage record with an integer stage raised
``SCRIPT ERROR: Invalid call 'String' constructor`` on the worker thread, the
trace thread died, END was never written, and every real GUI canary degraded
to INCONCLUSIVE ``server missing END``. This source falsifier pins the str()
boundary; the production-entry reproduction is the r3-slow-item GUI canary.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TRACE_PATH = ROOT / "scripts/network/smoothness/net_smooth_trace.gd"


class R3C2TraceStageGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.trace = TRACE_PATH.read_text(encoding="utf-8")

    def test_stage_coerced_with_str_not_string_constructor(self):
        self.assertIn(
            'var record_stage := str(record.get("data", {}).get("stage", ""))',
            self.trace,
        )
        self.assertNotIn(
            'String(record.get("data", {}).get("stage"',
            self.trace,
        )

    def test_flush_paths_for_durable_and_preack_records_remain(self):
        self.assertIn('record_kind == "p1b_item_async_stages"', self.trace)
        self.assertIn('record_stage in ["SUBMIT", "DURABLE_COMMIT"]', self.trace)
        self.assertIn('record_kind == "r3c2_pre_ack_hold"', self.trace)
        self.assertIn("file.flush()", self.trace)

    def test_missing_end_is_still_reported_as_inconclusive(self):
        analyzer = (
            ROOT / "tools/net_smooth1/analyze_net_smooth1.py"
        ).read_text(encoding="utf-8")
        committed_view = (
            ROOT / "tools/net_smooth1/analyze_r3_committed_view.py"
        ).read_text(encoding="utf-8")
        self.assertIn("missing END / process did not drain", analyzer)
        self.assertIn("missing END", committed_view)


if __name__ == "__main__":
    unittest.main()
