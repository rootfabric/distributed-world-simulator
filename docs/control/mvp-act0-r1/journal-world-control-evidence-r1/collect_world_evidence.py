import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path('C:/distributed-world-simulator/worktrees/mvp6-journal-main-repair')
out = Path(__file__).parent / 'world-core-final'
summary_path = root / 'artifacts/test-results/world-regression-summary.json'
summary = json.loads(summary_path.read_text(encoding='utf-8-sig'))
assert summary['passed'], 'World runner has not completed successfully'
git = lambda *a: subprocess.check_output(['git', *a], cwd=root, text=True).strip()
assert git('rev-parse', 'HEAD') == '3b82145ae946bb51aebf67f048a28420368b40be'
assert not git('status', '--porcelain', '--untracked-files=no')
out.mkdir(exist_ok=True)
shutil.copyfile(summary_path, out / 'summary.json')
shutil.copyfile(root / 'artifacts/journal-world-core.log', out / 'world.log')
shutil.copyfile(root / 'artifacts/journal-full-harness.log', out / 'windows-full-harness.log')
soak = root / 'artifacts/test-results/p6-r3-soak-persistence-32720'
for source in soak.glob('*.json'):
    shutil.copyfile(source, out / source.name)
current = 'runner'
diagnostics = []
for number, line in enumerate((out / 'world.log').read_text(encoding='utf-8-sig', errors='replace').splitlines(), 1):
    if line.startswith('Running '):
        current = line[8:]
    if any(marker in line for marker in ('ERROR:', 'WARNING:', 'SCRIPT ERROR', 'Parse Error', 'Compile Error', ': FAIL')):
        diagnostics.append(dict(line=number, step=current, message=line))
engine = Path('C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe')
result = dict(head=git('rev-parse','HEAD'), tree=git('rev-parse','HEAD^{tree}'), tracked_status='',
              engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
              argv=['pwsh','-NoProfile','-File','./RUN_WORLD_REGRESSION_TESTS.ps1'],
              environment=dict(GODOT_BIN=str(engine), BREAKPOINT_RUNTIME_DISABLED='1'),
              declared_tests=summary['declared_test_count'], discovered_tests=summary['discovered_test_count'],
              step_count=len(summary['steps']), failed_steps=[s for s in summary['steps'] if not s['passed']],
              runner_passed=summary['passed'], diagnostics=diagnostics, mvp6_verified=False,
              scope='Frozen main journal repair full world/core; not five-process MVP6 acceptance')
(out / 'provenance.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
files = [dict(path=p.name, size=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(out.iterdir()) if p.is_file() and p.name != 'manifest.json']
(out/'manifest.json').write_text(json.dumps(dict(subject=result['head'],tree=result['tree'],files=files),indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(steps=result['step_count'], failed_steps=result['failed_steps'], diagnostics=diagnostics, files=len(files)),indent=2))
