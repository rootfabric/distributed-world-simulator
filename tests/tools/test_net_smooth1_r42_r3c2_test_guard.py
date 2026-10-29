"""R3C2 test-only R2 repair: fail closed before spending a runner-hour on a Godot hang.

Separate source checks never claim Windows semantic acceptance. They pin the
exact regression cause and the two independent watchdog layers.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
TEST_PATH = ROOT / "tests/runtime/test_net_smooth1_r42_r3c2_phased_item_publication.gd"
WORKFLOW_PATH = ROOT / ".github/workflows/net-smooth-r42-r3c2-client-capture-exact.yml"


class R3C2PhasedItemTestGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.test = TEST_PATH.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_integer_phase_is_checked_as_integer(self):
        self.assertIn(
            'int(server.get("_r3c2_postcommit_pending").get("stage", -1)) == 0',
            self.test
        )
        self.assertNotIn(
            'String(server.get("_r3c2_postcommit_pending").get("stage", -1))',
            self.test
        )
        self.assertIn('for phase in range(5):', self.test)

    def test_timeout_callback_is_installed_before_test_runs(self):
        self.assertIn("const R3C2_TEST_WATCHDOG_SECONDS := 90.0", self.test)
        self.assertLess(
            self.test.index('call_deferred("_arm_watchdog")'),
            self.test.index('call_deferred("_run")')
        )
        self.assertIn('create_timer(R3C2_TEST_WATCHDOG_SECONDS)', self.test)
        self.assertIn('timer.timeout.connect(_watchdog_expired)', self.test)
        self.assertIn('failures.append("R3C2_TEST_WATCHDOG_EXPIRED_OR_SCRIPT_ERROR")', self.test)
        self.assertRegex(self.test, r'func _watchdog_expired\(\) -> void:[\s\S]*?\n\t_finish\(\)')
        self.assertRegex(self.test, r'func _finish\(\) -> void:\n\tif _finished:\n\t\treturn\n\t_finished = true')
        self.assertIn('quit(0 if failures.is_empty() else 1)', self.test)

    def test_owned_godot_process_has_windows_180s_external_timeout(self):
        self.assertIn('Start-Process -FilePath $Godot', self.workflow)
        self.assertIn('$Proc.WaitForExit(180000)', self.workflow)
        self.assertIn('$Proc.Kill($true)', self.workflow)
        self.assertIn('R3C2_RUNTIME_TIMEOUT_180S', self.workflow)
        self.assertIn('-RedirectStandardOutput $Stdout -RedirectStandardError $Stderr', self.workflow)
        self.assertIn("'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:'", self.workflow)

    def test_exact_linux_is_bounded_without_mutating_any_product_code(self):
        self.assertIn('timeout --signal=TERM --kill-after=5s 180s', self.workflow)
        self.assertIn('R3C2_LINUX_SUITE_EXIT_OR_TIMEOUT', self.workflow)
        self.assertIn('R3C2 real OS crash windows, Linux double', self.workflow)
        self.assertIn('tests/runtime/test_net_smooth1_r42_r3c2_phased_item_publication.gd', self.workflow)


if __name__ == "__main__":
    unittest.main()
