"""Tamper matrix for the R1.2 Windows launcher receipts, no Godot needed."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[3] / 'scripts/research/fabric_bake0/collect_r5_6_2_r1_evidence.py'
spec = importlib.util.spec_from_file_location('r562_collector', MODULE)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

class LaunchEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for stage, flags in collector.windows_stage_args().items():
            self.write(stage+'.argv.json', dict(schema='fabric.r562.windows_launch.v1', stage=stage,
                executable='C:/Godot/godot.windows.editor.double.x86_64.console.exe',
                working_directory='C:/fresh worktree/Кириллица',
                argv=['--headless','--path','C:/fresh worktree/Кириллица']+flags, timeout_seconds=1800))
            self.write(stage+'.process.json', dict(schema='fabric.r562.windows_process.v1', stage=stage,
                started=True, exit_code=0, timed_out=False, gameplay_detected=False, verdict='PASS'))
            for suffix in ['.log','.stdout.log','.stderr.log']:
                (self.root/(stage+suffix)).write_bytes(b'')
    def write(self,name,data):
        (self.root/name).write_text(json.dumps(data),encoding='utf-8')
    def mutate(self,name,action):
        value=json.loads((self.root/name).read_text())
        action(value)
        self.write(name,value)
    def reject(self):
        with self.assertRaises((ValueError,OSError)):
            collector.validate_windows_launches(self.root)
    def test_valid(self):
        self.assertEqual(collector.validate_windows_launches(self.root),10)
    def test_legacy_loss(self):
        self.mutate('import-recovery.argv.json',lambda d:d.update(argv=d['argv'][:3]));self.reject()
    def test_missing_script(self):
        self.mutate('lifecycle-1.argv.json',lambda d:d.update(argv=d['argv'][:3]));self.reject()
    def test_script_replacement(self):
        self.mutate('lifecycle-1.argv.json',lambda d:d['argv'].__setitem__(-1,'res://main.gd'));self.reject()
    def test_missing_recovery(self):
        self.mutate('import-recovery.argv.json',lambda d:d['argv'].pop());self.reject()
    def test_split_path(self):
        self.mutate('import.argv.json',lambda d:d['argv'].__setitem__(2,'C:/fresh'));self.reject()
    def test_engine_drift(self):
        self.mutate('import.argv.json',lambda d:d.update(executable='another.exe'));self.reject()
    def test_unknown_stage(self):
        self.mutate('import.argv.json',lambda d:d.update(stage='other'));self.reject()
    def test_timeout_even_if_pass(self):
        self.mutate('import.process.json',lambda d:d.update(timed_out=True));self.reject()
    def test_nonzero_even_if_pass(self):
        self.mutate('import.process.json',lambda d:d.update(exit_code=7));self.reject()
    def test_not_started(self):
        self.mutate('import.process.json',lambda d:d.update(started=False));self.reject()
    def test_gameplay_receipt(self):
        self.mutate('import.process.json',lambda d:d.update(gameplay_detected=True));self.reject()
    def test_missing_process(self):
        (self.root/'import.process.json').unlink();self.reject()
    def test_missing_stderr(self):
        (self.root/'import.stderr.log').unlink();self.reject()
    def test_modified_combined(self):
        (self.root/'import.stdout.log').write_bytes(b'SCRIPT ERROR: hidden');self.reject()
    def test_gameplay_in_raw_output(self):
        for suffix in ['.log','.stdout.log']:
            (self.root/('import'+suffix)).write_bytes(b'terrain_streaming_summary state=ACTIVE')
        self.reject()
    def test_runtime_error(self):
        for suffix in ['.log','.stderr.log']:
            (self.root/('lifecycle-1'+suffix)).write_bytes(b'SCRIPT ERROR: failure')
        self.reject()
    def test_boolean_exitcode(self):
        self.mutate('import.process.json',lambda d:d.update(exit_code=False));self.reject()
    def test_unbounded_timeout(self):
        self.mutate('import.argv.json',lambda d:d.update(timeout_seconds=999999));self.reject()

if __name__=='__main__':
    unittest.main()
