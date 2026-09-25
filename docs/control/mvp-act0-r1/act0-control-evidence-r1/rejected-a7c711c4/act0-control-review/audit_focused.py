import json,hashlib
from pathlib import Path
root=Path('C:/distributed-world-simulator/worktrees/mvp6-journal-act0-control'); evidence=Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181'); out=Path(__file__).parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
p=evidence/'act0-fence-exact-a7c711c4'; s=json.loads((p/'summary.json').read_text())
a=json.loads((out/'source-audit.json').read_text())
assert s['head']==a['head'] and s['tree']==a['tree']
assert s['exit_code']==0 and s['tests']==17 and s['negative_git_fault_cases']==23
assert not any(s[k] for k in ['failures','errors','skipped','tracked_and_untracked_status_before','tracked_and_untracked_status_after'])
assert sha(p/'tests.log')==s['log_sha256']
assert sha(root/'tests/harness/test_v0_mvp_act0.py')==s['source_test_sha256']
assert 'Ran 17 tests in 105.553s' in (p/'tests.log').read_text() and (p/'tests.log').read_text().rstrip().endswith('OK')
import jsonschema
jsonschema.validate(json.loads((root/'docs/control/mvp-act0-r1/act0-journal-fence-r1/work-order.json').read_text()),json.loads((root/'config/control/harness/work-order.schema.v1.json').read_text()))
paths=[p/'summary.json',p/'tests.log',p/'IMPLEMENTER_HANDOFF_RU.md',out/'source-audit.json',root/'tests/harness/test_v0_mvp_act0.py']
result=dict(role='REVIEWER',verdict='PASS',scope='Bounded ACT0 journal fence control source and exact Windows focused validation',head=s['head'],tree=s['tree'],risk_class='CRITICAL',required_fixes=[],rank_up_moves=[],evidence_gaps=['Full Linux Harness addendum pending at this verdict; PC0 directional RED not waived.'],risk_assessment='Historical ACT0 runtime baseline, P7 execution/acceptance and exact scene fence retained. Sole new permitted runtime tuple is the previously approved journal ed23 to abdf, bound to fixed authorization digest and immutable copied HA/patch. No runtime authority expanded.',focused_tests=17,committed_negative_cases=23,focused_failures=0,source_audit=a,claims=dict(mvp6_verified=False,main_merge_authorized=False,canonical_pc0_clearance=False,full_harness_pass=False),evidence=[dict(path=str(q),sha256=sha(q)) for q in paths])
(out/'review.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(out/'review.md').write_text('Reviewer PASS для bounded control subject '+s['head']+' / '+s['tree']+'.\n\n17 exact Windows focused tests, 23 committed negative cases, 0 failures/errors/skips. Digests и source bytes проверены независимо. WO schema valid, WO/replan зафиксированы до изменения test. Runtime/scenes/project byte-identical 3b82145a.\n\nСохраняются original BASE и frozen main6982/tree97c61, P7 execution/acceptance и ровно одна A7 scene addition. Единственное непустое допустимое protected delta — journal mode100644, path и exact old/new blobs. Missing/altered/open/foreign authorization, другие runtime paths, journal byte/delete/rename и P7/scene mutations отвергаются. Committed HA/patch совпадают с exact68433ec7; fixed SHA исключает подмену mutable record. Git replace не участвует.\n\nRequired fixes: нет. Full Linux Harness ещё требует отдельного addendum; directional RED assertion не изменён. Этот PASS не разрешает merge, main acceptance, PC0 clearance или MVP6 VERIFIED.\n',encoding='utf-8')
print(sha(out/'review.json'))
