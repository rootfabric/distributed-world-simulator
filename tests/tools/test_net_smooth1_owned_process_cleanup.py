"""Windows Godot owned cleanup: exact run identity, no unrelated processes."""
from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/net_smooth1"))
from owned_process_cleanup import select_windows_owned_godot, finalize_owned_processes

RUN_ID = "0123456789abcdef"
GODOT = Path(r"C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe")


def row(pid=1234, role="server", run_id=RUN_ID,
        exe=r"C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
        name="godot.windows.editor.double.x86_64.exe"):
    return {
        "pid": pid, "name": name, "executable": exe,
        "command_line": (
            '"'+exe+'" --headless --path C:\\dws-ns1-r31-803 '
            '--node-id=smooth-'+role+'-'+run_id+' --instance-id='+run_id
        ),
    }


class FakeProc:
    def __init__(self, *, timeout=False):
        self.exit_code = None
        self.timeout = timeout
        self.terminated = False

    def wait(self, timeout):
        if self.timeout and not self.terminated:
            raise subprocess.TimeoutExpired("fake-godot", timeout)
        self.exit_code = 0 if not self.terminated else 143
        return self.exit_code

    def poll(self):
        return self.exit_code

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.terminated = True


class WindowsScopedCleanup(unittest.TestCase):
    def test_exact_owned_main_godot_verified(self):
        owned, unknown = select_windows_owned_godot(
            [row(1, "server"), row(2, "a"), row(3, "b")],
            RUN_ID, GODOT)
        self.assertEqual(owned, [1, 2, 3])
        self.assertEqual(unknown, [])

    def test_other_run_id_not_touched_even_when_same_engine(self):
        owned, unknown = select_windows_owned_godot(
            [row(1, run_id="f"*16), row(2)], RUN_ID, GODOT)
        self.assertEqual(owned, [2])
        self.assertEqual(unknown, [])

    def test_different_godot_folder_is_ambiguous_not_killed(self):
        owned, unknown = select_windows_owned_godot(
            [row(1, exe=r"C:\AnotherProject\godot.exe",
                 name="godot.exe")], RUN_ID, GODOT)
        self.assertEqual(owned, [])
        self.assertEqual(unknown, [1])

    def test_run_id_without_exact_node_id_is_ambiguous(self):
        owned, unknown = select_windows_owned_godot(
            [row(1, role="unknown")], RUN_ID, GODOT)
        self.assertEqual(owned, [])
        self.assertEqual(unknown, [1])

    def test_powershell_process_never_matches(self):
        owned, unknown = select_windows_owned_godot(
            [row(1, name="pwsh.exe", exe=r"C:\PowerShell\pwsh.exe")],
            RUN_ID, GODOT)
        self.assertEqual(owned, [])
        self.assertEqual(unknown, [])

    def test_literal_prefix_or_suffix_not_run_id_match(self):
        invalid = row(1, run_id=RUN_ID + "aa")
        a, b = select_windows_owned_godot([invalid], RUN_ID, GODOT)
        self.assertEqual((a, b), ([], []))

    def test_invalid_identifier_rejected_before_any_kill(self):
        with self.assertRaisesRegex(ValueError, "INVALID_RUN_ID"):
            select_windows_owned_godot([row(1)], "not-valid", GODOT)

    def test_clean_owned_processes_allow_next_arm(self):
        with tempfile.TemporaryDirectory() as d:
            proc = FakeProc()
            result = finalize_owned_processes(
                {"server": proc}, Path(d), RUN_ID, GODOT,
                windows=True, scanner=lambda _: [], tree_killer=lambda _: self.fail("kill"))
            self.assertTrue(result["verified"])
            self.assertEqual(result["errors"], [])
            self.assertTrue((Path(d)/"server"/"stop.signal").exists() is False)
            # stop signal directory must exist for real spawned process; the
            # synthetic test deliberately omitted it and must fail closed.
            self.assertIn("server: STOP_SIGNAL_FAILED", result["errors"])

    def test_orphan_main_process_is_killed_and_declared_unaccepted(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/"server"
            p.mkdir()
            scans = iter([[row(87)], []])
            killed = []
            result = finalize_owned_processes(
                {"server": FakeProc()}, Path(d), RUN_ID, GODOT,
                windows=True, scanner=lambda _: next(scans),
                tree_killer=lambda pid: killed.append(pid))
            self.assertEqual(killed, [87])
            self.assertTrue(result["verified"])
            self.assertEqual(result["orphan_pids"], [87])
            self.assertEqual(result["remaining_owned_pids"], [])
            self.assertIn("OWNED_GODOT_ORPHAN_RECOVERED", result["errors"])

    def test_wrong_engine_process_never_killed_and_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/"server").mkdir()
            unusual = row(87, exe=r"C:\Unrelated\godot.exe", name="godot.exe")
            result = finalize_owned_processes(
                {"server": FakeProc()}, Path(d), RUN_ID, GODOT,
                windows=True, scanner=lambda _: [unusual],
                tree_killer=lambda _: self.fail("must not kill unrelated"))
            self.assertFalse(result["verified"])
            self.assertIn(87, result["ambiguous_pids"])
            self.assertIn("AMBIGUOUS_GODOT_PROCESS_NOT_KILLED", result["errors"])

    def test_graceful_timeout_forced_shutdown_preserves_failure(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/"server").mkdir()
            process = FakeProc(timeout=True)
            result = finalize_owned_processes(
                {"server": process}, Path(d), RUN_ID, GODOT,
                windows=True, scanner=lambda _: [],
                tree_killer=lambda _: self.fail("no orphan"))
            self.assertIn("server", result["forced_roles"])
            self.assertIn("server: GRACEFUL_SHUTDOWN_TIMEOUT", result["errors"])
            self.assertTrue(process.terminated)
            self.assertTrue(result["verified"])

    def test_query_failure_prevents_acceptance(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/"server").mkdir()
            def failure(_):
                raise RuntimeError("CIM disabled")
            result = finalize_owned_processes(
                {"server": FakeProc()}, Path(d), RUN_ID, GODOT,
                windows=True, scanner=failure)
            self.assertFalse(result["verified"])
            self.assertTrue(any("WINDOWS_PROCESS_CLEANUP_UNVERIFIED" in x
                                for x in result["errors"]))


if __name__ == "__main__":
    unittest.main()
