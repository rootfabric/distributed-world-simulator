"""Falsifiers for bounded P1A_WAIT_PRIOR_PERIODIC test-only admission retry."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "net_smooth1"))
from retry_prior_periodic_admission import retry_prior_periodic

class ControlledClock:
    def __init__(self):
        self.t = 0.0
    def now(self):
        return self.t
    def sleep(self, delta):
        self.t += delta

class TestSameIdRetry(unittest.TestCase):
    def test_rejection_reply_then_exact_success(self):
        calls = []
        sequence = [
            {"item_command": {"success": False, "error_code": "P1A_WAIT_PRIOR_PERIODIC"}},
            {"item_command": {"success": False, "error_code": "P1A_WAIT_PRIOR_PERIODIC"}},
            {"item_command": {"success": True, "error_code": "", "details": {
                "item_graph_revision_before": 1, "item_graph_revision_after": 2}}},
        ]
        def send():
            calls.append("operation/m6/1")
            return sequence.pop(0)
        clock = ControlledClock()
        result, info = retry_prior_periodic(send, "operation/m6/1",
                                            now=clock.now, sleep=clock.sleep)
        self.assertTrue(result["item_command"]["success"])
        self.assertEqual(info["prior_periodic_rejections"], 2)
        self.assertEqual(info["attempts"], 3)
        self.assertEqual(calls, ["operation/m6/1"]*3)

    def test_transient_exception_then_success(self):
        calls = []
        def send():
            calls.append("operation/m6/2")
            if len(calls) < 3:
                raise RuntimeError("P1A_WAIT_PRIOR_PERIODIC")
            return {"item_command": {"success": True, "details": {}}}
        clock = ControlledClock()
        _, info = retry_prior_periodic(send, "operation/m6/2",
                                       now=clock.now, sleep=clock.sleep)
        self.assertEqual(info["prior_periodic_rejections"], 2)
        self.assertEqual(len(calls), 3)

    def test_unknown_rejection_must_not_retry(self):
        calls = []
        def send():
            calls.append(1)
            return {"item_command": {"success": False, "error_code": "M6_DURABLE_COMMIT_FAILED"}}
        result, info = retry_prior_periodic(send, "operation/m6/3")
        self.assertFalse(result["item_command"]["success"])
        self.assertEqual(len(calls), 1)
        self.assertEqual(info["prior_periodic_rejections"], 0)

    def test_unknown_transport_error_must_not_retry(self):
        def send():
            raise TimeoutError("peer disconnected")
        with self.assertRaises(TimeoutError):
            retry_prior_periodic(send, "operation/m6/4")

    def test_budget_is_bounded_not_false_success(self):
        def send():
            return {"item_command": {"success": False, "error_code": "P1A_WAIT_PRIOR_PERIODIC"}}
        clock = ControlledClock()
        with self.assertRaisesRegex(RuntimeError, "R3_SLOW_ITEM_PRIOR_PERIODIC_BUDGET_EXHAUSTED"):
            retry_prior_periodic(send, "operation/m6/5", budget_s=1.0,
                                 now=clock.now, sleep=clock.sleep)
        self.assertGreaterEqual(clock.t, 1.0)

    def test_invalid_request(self):
        with self.assertRaises(ValueError):
            retry_prior_periodic(lambda: {}, "", budget_s=30.0)
        with self.assertRaises(ValueError):
            retry_prior_periodic(lambda: {}, "operation/m6/6", budget_s=0)

if __name__ == "__main__":
    unittest.main()
