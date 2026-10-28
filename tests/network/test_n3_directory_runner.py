"""RED/GREEN guard for the documented N3 R0 shell execution entrypoint."""

import os
import shlex
import shutil
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "RUN_N3_R0_DIRECTORY_CONTRACTS.sh"

FAKE_GODOT = r'''#!/usr/bin/env bash
case "$*" in
  *test_n3_region_directory_contracts.gd*) test_id=n3_region_directory_contracts ;;
  *test_n3_directory_b0_routes.gd*) test_id=n3_directory_b0_routes ;;
  *) exit 12 ;;
esac
case "$N3_FAKE_CASE" in
  error_zero) echo 'SCRIPT ERROR: forced Godot failure'; exit 0 ;;
  empty_zero) exit 0 ;;
  fail_zero) printf '{"test":"%s","assertions":1,"failures":["oops"],"verdict":"FAIL"}\n' "$test_id"; exit 0 ;;
  wrong_id_zero) echo '{"test":"some_other_test","assertions":1,"failures":[],"verdict":"PASS"}'; exit 0 ;;
  pass_nonzero) printf '{"test":"%s","assertions":1,"failures":[],"verdict":"PASS"}\n' "$test_id"; exit 19 ;;
  good) printf '{"test":"%s","assertions":1,"failures":[],"verdict":"PASS"}\n' "$test_id"; exit 0 ;;
  *) exit 13 ;;
esac
'''


def resolve_bash() -> str:
    """Resolve a real Git Bash executable.

    On Windows, spawning the bare name ``bash`` via CreateProcess resolves
    ``C:\\Windows\\System32\\bash.exe`` (WSL) before ``PATH`` is consulted, and
    WSL bash has no ``cygpath``, which breaks Git Bash path conversion. Prefer
    an explicit Git Bash resolution instead.
    """
    if os.name != "nt":
        return "bash"
    candidates = []
    found = shutil.which("bash")
    if found and "system32" not in Path(found).parts.__str__().lower():
        candidates.append(found)
    git_exe = shutil.which("git")
    if git_exe:
        candidates.append(str(Path(git_exe).resolve().parents[1] / "bin" / "bash.exe"))
    candidates.append(r"C:\Program Files\Git\bin\bash.exe")
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    return "bash"


class RunnerReceiptTests(unittest.TestCase):
    @staticmethod
    def bash_path(path: Path) -> str:
        if os.name != "nt":
            return str(path)
        # Git Bash expects a POSIX path, even when Python starts on Windows.
        result = subprocess.run(
            [resolve_bash(), "-lc", "cygpath -u " + shlex.quote(str(path))],
            text=True, capture_output=True, check=True,
        )
        return result.stdout.strip()

    def run_case(self, mode: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="n3-runner-") as temp:
            executable = Path(temp) / "fake-godot.sh"
            executable.write_bytes(FAKE_GODOT.encode("utf-8"))
            executable.chmod(0o755)
            env = dict(
                os.environ,
                N3_FAKE_CASE=mode,
                N3_R0_LOG_DIR=str(Path(temp) / "logs"),
                # Pin the receipt validator to this interpreter: on Windows,
                # the script's default "python3" probe can hit the Store stub.
                N3_R0_PYTHON=sys.executable,
            )
            return subprocess.run(
                [resolve_bash(), self.bash_path(RUNNER), self.bash_path(executable)],
                cwd=ROOT, env=env, encoding="utf-8", text=True, capture_output=True,
                timeout=30, check=False,
            )

    def test_script_error_even_when_exit_zero_is_rejected(self) -> None:
        self.assertNotEqual(self.run_case("error_zero").returncode, 0)

    def test_empty_exit_zero_is_rejected(self) -> None:
        self.assertNotEqual(self.run_case("empty_zero").returncode, 0)

    def test_explicit_fail_receipt_is_rejected(self) -> None:
        self.assertNotEqual(self.run_case("fail_zero").returncode, 0)

    def test_foreign_pass_receipt_is_rejected(self) -> None:
        self.assertNotEqual(self.run_case("wrong_id_zero").returncode, 0)

    def test_pass_with_nonzero_exit_is_rejected(self) -> None:
        self.assertNotEqual(self.run_case("pass_nonzero").returncode, 0)

    def test_two_correct_receipts_are_accepted(self) -> None:
        result = self.run_case("good")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("N3_NATIVE_VERIFIED"), 2)


if __name__ == "__main__":
    unittest.main()
