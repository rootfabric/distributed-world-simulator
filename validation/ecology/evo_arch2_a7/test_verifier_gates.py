"""CLI-level regression for the required graphical completion gate (no fake PASS)."""
from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

VERIFIER = Path(__file__).with_name("verify.py")
REPO = VERIFIER.parents[3]

class RequiredGraphicalGate(unittest.TestCase):
    def exercise_missing_executor(self, options: list[str]) -> None:
        spec = importlib.util.spec_from_file_location("a7_verify_under_test", VERIFIER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            dependency = root / "validation/ecology/evo_arch2_a6/verify.py"
            dependency.parent.mkdir(parents=True)
            shutil.copyfile(REPO / "validation/ecology/evo_arch2_a6/verify.py", dependency)
            argv = [str(VERIFIER), "--godot", str(root / "not-invoked"), "--head", "1" * 40, "--tree", "2" * 40, *options]
            stdout, stderr = io.StringIO(), io.StringIO()
            cwd = Path.cwd()
            try:
                with mock.patch.object(module, "ROOT", root), mock.patch.object(module.shutil, "which", return_value=None), mock.patch.object(sys, "argv", argv), redirect_stdout(stdout), redirect_stderr(stderr):
                    result = module.main()
            finally:
                os.chdir(cwd)
            summary = json.loads((root / "artifacts/a7/exact/summary.json").read_text())
            self.assertEqual(result, 1)
            self.assertEqual(summary["verdict"], "FAIL")
            self.assertTrue(summary["graphical_required"])
            self.assertEqual(summary["error"], "XVFB_REQUIRED_FOR_COMPLETE_A7")
            self.assertEqual(summary["checks"], [])
            self.assertNotIn("VERDICT=PASS", stdout.getvalue() + stderr.getvalue())

    def test_default_command_never_skips_graphics(self) -> None:
        self.exercise_missing_executor([])

    def test_legacy_graphical_flag_does_not_change_requirement(self) -> None:
        self.exercise_missing_executor(["--graphical"])

if __name__ == "__main__":
    unittest.main()
