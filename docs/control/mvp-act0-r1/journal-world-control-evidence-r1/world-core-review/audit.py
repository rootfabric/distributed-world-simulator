import json, hashlib, subprocess, re
from pathlib import Path
root=Path('C:/distributed-world-simulator/worktrees/mvp6-journal-main-repair')
evidence=Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181')
out=evidence/'world-core-review'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
git=lambda *a:subprocess.check_output(['git',*a],cwd=root,text=True).strip()
head='3b82145ae946bb51aebf67f048a28420368b40be'
tree='6b1b8c9ead5c16d15dc8565813d3abb1bf94d880'
assert git('rev-parse','HEAD')==head and git('rev-parse','HEAD^{tree}')==tree
assert not git('status','--porcelain','--untracked-files=no')
final=evidence/'world-core-final'
manifest=json.loads((final/'manifest.json').read_text())
assert manifest['subject']==head and manifest['tree']==tree
for f in manifest['files']:
 assert sha(final/f['path'])==f['sha256'], f['path']
s=json.loads((final/'summary.json').read_text(encoding='utf-8-sig'))
assert s['passed'] and s['declared_test_count']==s['discovered_test_count']==327
assert all(t['passed'] and t['exit_code']==0 for t in s['steps'])
assert s['steps'][-1]['name']=='main_scene_cli_all'
log=(final/'world.log').read_text(encoding='utf-8-sig')
assert not re.search(r': FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:',log)
assert '[p6-r3-soak] all 51 assertions passed (literal 30.00 real-time minutes, two concurrent client sessions)' in log
assert 'elapsed=1800002 ms' in log
allowed={'test_m5_graphical_multiplayer_acceptance':'BASELINE_PEEKNAMEDPIPE_CLEANUP','test_m6_dedicated_recovery_contracts':'BASELINE_RESOURCE_EXIT_DEBT','test_partition_foundation':'INTENTIONAL_INVALID_NAMESPACE_GRID_REJECTION','test_persistence_roundtrip':'INTENTIONAL_FOREIGN_INSTANCE_GRID_REJECTION','test_mw7_matter_interest_replication':'BASELINE_RESOURCE_EXIT_DEBT','test_v0_p7_5_two_client_convergence':'BASELINE_RESOURCE_EXIT_DEBT'}
errors=[]; warnings=[]; current='runner'
for n,line in enumerate(log.splitlines(),1):
 if line.startswith('Running '): current=line[8:]
 if 'ERROR:' in line:
  assert current in allowed,(current,line)
  errors.append(dict(line=n,step=current,message=line,classification=allowed[current]))
 if 'WARNING:' in line: warnings.append(dict(line=n,step=current,message=line))
assert len(errors)==9
baseline=[]
for directory in ['world-canonical-baseline','world-canonical-baseline-mw7','world-canonical-baseline-p75']:
 p=evidence/directory/'provenance.json'; v=json.loads(p.read_text())
 assert v['head']=='6982a563dd0c88c81449566131852c601ae89868' and v['git_status_after']==''
 if 'commands' in v:
  for cmd in v['commands']:
   name={'import':'import.log','test_m5_graphical_multiplayer_acceptance':'test_m5_graphical_multiplayer_acceptance.log','test_m6_dedicated_recovery_contracts':'test_m6_dedicated_recovery_contracts.log'}[cmd['name']]
   q=p.parent/name
   assert sha(q)==cmd['sha256'] and cmd['exit_code']==0
 else:
  assert sha(p.parent/'test.log')==v['sha256'] and v['exit_code']==0
 baseline.append(dict(path=str(p),sha256=sha(p)))
h=evidence/'full-harness-linux/unpacked/summary.json'; hs=json.loads(h.read_text()); hl=h.parent/'tests.log'
assert hs['head']==head and hs['tree']==tree and sha(hl)==hs['log_sha256'] and hs['exit_code']==1
assert 'Ran 325 tests' in hl.read_text() and 'FAILED (failures=2)' in hl.read_text()
wlog=(final/'windows-full-harness.log').read_text(encoding='utf-8-sig')
assert 'Ran 303 tests' in wlog and 'FAILED (failures=4, errors=8, skipped=3)' in wlog
result=dict(role='REVIEWER',verdict='PASS',scope='Bounded journal main repair full world/core evidence addendum only',head=head,tree=tree,risk_class='CRITICAL',required_fixes=[],rank_up_moves=['Existing cleanup/resource diagnostics remain separate maintenance debt.'],evidence_gaps=['No whole MVP6 live five-process or physics interaction acceptance in this subject.','Canonical PC0 directional RED and main merge remain unresolved.'],risk_assessment='No new world/core regression identified; runner success is not fatal-free or product acceptance.',world=dict(runner_passed=True,steps=len(s['steps']),standalone_scripts=327,soak_ms=1800002,soak_assertions=51,errors=errors,warnings=warnings),harness=dict(linux='FAIL:325 tests,2 failures (PC0 directional RED and stale ACT0 fence)',windows='FAIL:303 tests,4 failures,8 errors,3 skips; extra failures absent on Linux',linux_log_sha256=sha(hl)),manifest=dict(path=str(final/'manifest.json'),sha256=sha(final/'manifest.json'),checked_files=len(manifest['files'])),baseline=baseline,mvp6_verified=False,main_acceptance=False,canonical_clearance=False,reviewer_source_changes=False)
(out/'review.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
paths=[final/f['path'] for f in manifest['files']]+[final/'manifest.json',h,hl,evidence/'full-harness-linux/artifact.zip']
for directory in ['world-canonical-baseline','world-canonical-baseline-mw7','world-canonical-baseline-p75']:
 paths.extend(p for p in (evidence/directory).iterdir() if p.is_file())
(out/'evidence-hashes.json').write_text(json.dumps(dict(head=head,tree=tree,files=[dict(path=str(p),sha256=sha(p)) for p in paths]),indent=2)+'\n')
(out/'review.md').write_text('Reviewer PASS: только full world/core addendum для '+head+' / '+tree+'.\n\n327 standalone scripts, '+str(len(s['steps']))+' runner steps, все exit0; literal soak 1 800 002 ms / 51 assertions. Runner unchanged; main_scene_cli_all выполнен. Все 9 raw ERROR сохранены: 2 M5 PeekNamedPipe, M6/MW7/P7.5 cleanup resource errors воспроизведены на exact canonical main6982; 4 partition/persistence ошибки соответствуют явным негативным assertions. Warning-only C23 cleanup debt также сохранён; результат не называется error-free.\n\nLinux Harness raw FAIL325/2 (directional RED, устаревший ACT0 fence); Windows raw FAIL303/4 failures/8 errors/3 skips остаётся FAIL. Linux не воспроизвёл Windows import/provenance failures.\n\nНе подтверждает MVP6 five-process flow, real collision physics, canonical clearance, main acceptance или MVP6 VERIFIED. Новый control-only subject требует отдельного review.\n',encoding='utf-8')
print(json.dumps(dict(verdict=result['verdict'],steps=len(s['steps']),errors=len(errors),manifest_sha256=result['manifest']['sha256'])))
