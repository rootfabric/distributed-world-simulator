import json,hashlib,subprocess
from pathlib import Path
root=Path('C:/distributed-world-simulator/worktrees/mvp6-journal-act0-control'); evidence=Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181'); out=Path(__file__).parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
a=json.loads((out/'source-audit.json').read_text()); w=evidence/'act0-fence-exact-d9706b15'; ws=json.loads((w/'summary.json').read_text()); l=evidence/'act0-full-harness-linux-d9706b15'; ls=json.loads((l/'unpacked/summary.json').read_text()); log=(l/'unpacked/tests.log').read_text()
for s in (ws,ls): assert s['head']==a['head'] and s['tree']==a['tree']
assert ws['tests']==18 and ws['negative_git_fault_cases']==23 and ws['exit_code']==0
assert not any(ws[k] for k in ('failures','errors','skipped','status_before','status_after'))
assert sha(w/'tests.log')==ws['log_sha256'] and sha(root/'tests/harness/test_v0_mvp_act0.py')==ws['source_sha256']
assert sha(l/'unpacked/tests.log')==ls['log_sha256']=='024b03d9f9ffa30a4a8ed9b350e298f5230a6442534b184d34a1c9285df23670'
assert sha(l/'artifact.zip')=='1a29620992c1d6cf280a68ed82075f34e1f79a465f598f781e62a7965a696fc4'
assert ls['exit_code']==1 and ls['tracked_status']==''
assert 'Ran 330 tests in 128.510s' in log and log.rstrip().endswith('FAILED (failures=1)')
assert '\nERROR:' not in log and log.count('\nFAIL:')==1
assert '\nFAIL: test_live_proposed_r3_standard_and_directional_are_non_red' in log
act0=[line for line in log.splitlines() if line.startswith('test_') and '(test_v0_mvp_act0.' in line]
assert len(act0)==18
import re
chunks=re.split(r'(?m)(?=^test_)',log)
for chunk in chunks:
 if chunk.startswith('test_') and '(test_v0_mvp_act0.' in chunk.splitlines()[0]:
  assert chunk.rstrip().endswith('ok'),chunk
assert 'test_fixture_commits_do_not_launch_automatic_background_maintenance' in log
paths=[w/'summary.json',w/'tests.log',w/'IMPLEMENTER_HANDOFF_RU.md',l/'artifact.zip',l/'unpacked/summary.json',l/'unpacked/tests.log',out/'source-audit.json',root/'tests/harness/test_v0_mvp_act0.py']
r=dict(role='REVIEWER',verdict='PASS',scope='Fresh bounded journal ACT0 control repair, exact Windows focused and full Linux Harness classification',head=a['head'],tree=a['tree'],risk_class='CRITICAL',required_fixes=[],rank_up_moves=[],evidence_gaps=['Canonical main merge, default NX dependency revalidation and real directional clearance remain pending.','World/core evidence is exact3b82145a; d970 has identical runtime but is not mislabeled as that tested HEAD.','Whole MVP6 live five-process product/physics verification remains pending.'],risk_assessment='The fixture lifetime fix removes detached automatic Git maintenance before checkout and preserves strict cleanup and all negative assertions. Fixed immutable ACT0 runtime/P7/scene guards admit only the previously approved exact journal delta. No new runtime authority or ownership change.',windows=dict(tests=18,negative_committed_cases=23,failures=0,errors=0,skips=0),linux=dict(run_id=ls['run_id'],artifact_id=10449318113,tests=330,failures=1,errors=0,skips=0,act0_tests_passed=18,raw_result='FAIL',only_failure='Unchanged live proposed R3 current-main directional PC0 RED',artifact_sha256=sha(l/'artifact.zip')),human_gate_assessment=dict(genuine=True,action='Human approve exact PR646 journal baseline repair with reviewed ACT0 control guard; merge remains separately Human-owned.',reason='Default canonical NX baseline must use an accepted journal repair before truthful main-owned clearance can be prepared. Existing directional RED is preserved rather than bypassed.',forbidden=['Edit PC0 assertion to green','Create ACCEPTED clearance from explicit repair-composition evidence','Self-merge or self-accept','Claim all automatic CI gates green'],after_merge=['Fetch exact canonical main','Run default canonical NX baseline/candidate probe','Run real standard and directional auditors','Prepare fresh main-owned clearance and independent roles']),claims=dict(mvp6_verified=False,main_merge_authorized=False,canonical_pc0_clearance=False,full_harness_pass=False),evidence=[dict(path=str(q),sha256=sha(q)) for q in paths])
(out/'review.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(out/'review.md').write_text('Reviewer PASS для fresh bounded control subject '+a['head']+' / '+a['tree']+'.\n\nWindows:18tests,23committed negative cases,0fail/error/skip. Linux35103955408:330tests,1failure (неизменённый live directional PC0 RED),0errors/0skips; все18ACT0 tests PASS. Raw Linux result остаётся FAIL. ZIP10449318113 и все использованные logs проверены SHA256.\n\nRepair сохраняет строгий TemporaryDirectory cleanup, все original/negative assertions и exact immutable authorization guard. Clone-local auto maintenance отключён до checkout; Trace2 проверяет real commit и отсутствие maintenance/gc children. Исторический a7 Linux FAIL не переписан. Required fixes для этого bounded control repair:нет.\n\nPR646 baseline merge остаётся HUMAN gate; это причинный journal repair перед default canonical NX revalidation, не accepted directional clearance. Нельзя менять PC0 assertion, выдавать ACCEPTED из repair-composition или называть CI полностью green. После merge нужны exact main/default probe/real auditors/fresh clearance roles. World/core проверен на3b82145a при identical runtime; d970 не выдаётся за runtime-tested3b. MVP6 five-process и real physics acceptance не подтверждены.\n',encoding='utf-8')
print(sha(out/'review.json'))
