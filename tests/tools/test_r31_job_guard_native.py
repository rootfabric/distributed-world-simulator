"""REAL Windows Job tests using Python processes, not Godot or mock APIs.

No administrator rights, no external dependencies, no arbitrary PID kills.
Windows failure is a FAILURE, never converted to a skip. Non-Windows skips
are explicit. Native success does NOT prove final Godot B3 or performance.
"""
from pathlib import Path
import ctypes as C
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'tools/net_smooth1'
sys.path.insert(0, str(TOOLS))
from win_job_guard import OwnedJob, Kernel, wait_empty


def wait_file(path: Path, timeout: float = 12.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if path.exists():
            try:
                return json.loads(path.read_text(encoding='utf-8'))
            except (ValueError, OSError):
                pass
        time.sleep(.05)
    raise AssertionError('missing native ready receipt ' + str(path))


def grandchild_program(root: Path) -> str:
    leaf = "import time; time.sleep(120)"
    return ("import subprocess,sys,time,json; from pathlib import Path; "
            f"p=subprocess.Popen([sys.executable,'-c',{leaf!r}]); "
            f"Path({str(root/'leaf.json')!r}).write_text(json.dumps({{'pid':p.pid}})); "
            "time.sleep(120)")


@unittest.skipUnless(os.name == 'nt', 'Windows native APIs required; no native PASS on Linux')
class NativeWindows(unittest.TestCase):
    def setUp(self):
        evidence = os.environ.get('R31_JOB_NATIVE_EVIDENCE')
        if evidence:
            self.root = Path(evidence).resolve() / self._testMethodName
            self.root.mkdir(parents=True, exist_ok=False)
        else:
            self.temp = tempfile.TemporaryDirectory()
            self.root = Path(self.temp.name)
            self.addCleanup(self.temp.cleanup)

    def record(self, name: str, value: dict):
        (self.root/name).write_text(json.dumps(value, indent=2), encoding='utf-8')

    def test_create_is_job_member_before_first_instruction(self):
        marker = self.root/'executed.json'
        command = f"from pathlib import Path; Path({str(marker)!r}).write_text('{{}}')"
        with OwnedJob() as job:
            proc, ident = job.create_suspended([sys.executable, '-c', command],
                cwd=self.root, log=self.root/'spawn.log')
            self.record('spawn_identity.json', ident)
            self.assertTrue(ident['member_of_this_job'])
            self.assertGreater(int(ident['creation_filetime_100ns']), 0)
            self.assertEqual(Path(ident['executable']).resolve(), Path(sys.executable).resolve())
            self.assertIn(proc.pid, job.snapshot()['pids'])
            time.sleep(.08)
            self.assertFalse(marker.exists(), 'user code ran before resume')
            proc.resume()
            self.assertEqual(proc.wait(10), 0)
            wait_file(marker)
            outcome = job.finish(.5)
            self.record('job_result.json', outcome)
            self.assertEqual(outcome['acceptance'], 'CLEAN_JOB_EMPTY')

    def test_exited_wrapper_child_survives_until_job_termination(self):
        # Child does NOT contain the runner UUID or any smooth marker. Job
        # membership, not command-line pattern, proves ownership.
        child = grandchild_program(self.root)
        wrapper = ("import subprocess,sys,json; from pathlib import Path; "
                   f"p=subprocess.Popen([sys.executable,'-c',{child!r}]); "
                   f"Path({str(self.root/'child.json')!r}).write_text(json.dumps({{'pid':p.pid}}))")
        with OwnedJob() as job:
            proc, _ = job.create_suspended([sys.executable, '-c', wrapper],
                                           cwd=self.root, log=self.root/'wrapper.log')
            proc.resume()
            self.assertEqual(proc.wait(10), 0)
            child_id = wait_file(self.root/'child.json')['pid']
            leaf_id = wait_file(self.root/'leaf.json')['pid']
            before = job.snapshot()
            self.assertIn(child_id, before['pids'])
            self.assertIn(leaf_id, before['pids'])
            result = job.finish(.1)
            self.record('job_result.json', result)
            self.assertTrue(result['isolation_verified'])
            self.assertFalse(result['natural_exit'])
            self.assertTrue(result['forced_job_termination'])
            self.assertEqual(result['acceptance'], 'FORCED_CLEANUP_NOT_ACCEPTED')
            self.assertEqual(result['after']['active'], 0)
            self.assertEqual(result['after']['pids'], [])
            self.assertTrue(all(row.get('member_of_this_job') for row in result['remaining_identity']))

    def test_foreign_process_untouched(self):
        foreign = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(120)'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            with OwnedJob() as job:
                proc, _ = job.create_suspended([sys.executable, '-c', 'import time;time.sleep(120)'],
                                               cwd=self.root, log=self.root/'owned.log')
                proc.resume()
                self.assertNotIn(foreign.pid, job.snapshot()['pids'])
                self.assertEqual(job.finish(0)['acceptance'], 'FORCED_CLEANUP_NOT_ACCEPTED')
                self.assertIsNone(foreign.poll())
        finally:
            foreign.terminate()  # only our Popen handle, never searched by PID
            foreign.wait(10)

    def _assert_controller_crash(self, resume: bool):
        code = (
            "import sys,time,json; from pathlib import Path; "
            f"sys.path.insert(0,{str(TOOLS)!r}); from win_job_guard import OwnedJob; "
            f"r=Path({str(self.root)!r}); job=OwnedJob(); "
            f"p,identity=job.create_suspended([sys.executable,'-c',{grandchild_program(self.root)!r}], "
            "cwd=r,log=r/'crash.log'); "
            + ("p.resume(); " if resume else "") +
            "(r/'controller.json').write_text(json.dumps({'pid':p.pid,'identity':identity})); "
            "time.sleep(120)"
        )
        control = subprocess.Popen([sys.executable, '-c', code],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        api = Kernel()
        held = []
        try:
            info = wait_file(self.root/'controller.json')
            ids = [info['pid']]
            if resume:
                ids.append(wait_file(self.root/'leaf.json')['pid'])
            for pid in ids:
                handle = api.check(api.k.OpenProcess(0x1000 | 0x100000, False, pid), 'OpenProcess(test)')
                held.append(handle)  # stable handles prevent PID reuse confusion
            control.kill()
            control.wait(10)
            checks = [int(api.k.WaitForSingleObject(handle, 10000)) for handle in held]
            self.record('crash_result.json', {'controller_pid': control.pid,
                'held_process_pids': ids, 'wait_results': checks, 'resumed': resume})
            for result in checks:
                self.assertEqual(result, 0,
                                 'last job handle close did not stop contained process')
            if not resume:
                self.assertFalse((self.root/'leaf.json').exists())
        finally:
            if control.poll() is None:
                control.kill()
                control.wait(10)
            for handle in held:
                api.close(handle)
            if control.stderr is not None:
                control.stderr.close()

    def test_controller_crash_kills_running_descendants(self):
        self._assert_controller_crash(True)

    def test_controller_crash_before_resume_kills_suspended_root(self):
        self._assert_controller_crash(False)

    def test_failed_create_leaves_job_empty(self):
        with OwnedJob() as job:
            with self.assertRaises(FileNotFoundError):
                job.create_suspended([str(self.root/'does-not-exist.exe')],
                                     cwd=self.root, log=self.root/'bad.log')
            self.assertEqual(job.snapshot()['active'], 0)
            self.assertEqual(job.finish(0)['acceptance'], 'CLEAN_JOB_EMPTY')

    def test_runner_nonzero_cannot_become_guard_pass(self):
        receipt = self.root/'nonzero.json'
        run = subprocess.run([sys.executable, str(TOOLS/'run_r31_job_guard.py'),
            '--receipt', str(receipt), '--cwd', str(self.root), '--',
            sys.executable, '-c', 'raise SystemExit(7)'], capture_output=True, text=True, timeout=20)
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        data = json.loads(receipt.read_text(encoding='utf-8'))
        self.assertEqual(data['runner_exit_code'], 7)
        self.assertEqual(data['status'], 'GUARD_FAIL')
        self.assertTrue(data['job_cleanup']['isolation_verified'])
        self.assertFalse(data['runtime_performance_acceptance'])


if __name__ == '__main__': unittest.main()
