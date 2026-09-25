import json,hashlib,subprocess
from pathlib import Path
import jsonschema
root=Path('C:/distributed-world-simulator/worktrees/mvp6-continuation'); out=Path(__file__).parent
ha_path=root/'config/control/harness/executions/E2026-09-09-V0-MVP-R1/human-attention/HA-V0-MVP6-JOURNAL-BASELINE-MERGE-R1.v1.json'
doc=root/'docs/control/mvp-act0-r1/MVP6_JOURNAL_MERGE_HANDOFF_R1_RU.md'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
ha=json.loads(ha_path.read_text()); jsonschema.validate(ha,json.loads((root/'config/control/harness/human-attention.schema.v1.json').read_text()))
e=root/'docs/control/mvp-act0-r1/act0-control-evidence-r1/d9706b15'; m=json.loads((e/'final-manifest.json').read_text())
for f in m['files']: assert sha(e/f['path'])==f['sha256'],f['path']
v=json.loads((e/'verifier/result.json').read_text()); assert v['verdict']=='PASS' and v['head']==m['head'] and v['tree']==m['tree']
assert sha(e/'verifier/result.json')=='3a8999f8b77cf9a436aeff81b9267a54160f61500cc765bdc0ccf0873b4c1cdf'
assert ha['status']=='OPEN' and ha['blocking'] is True and ha['risk_class']=='CRITICAL'
assert m['head']=='d9706b157e84c653a753cc54243ce6651d53319c' and m['tree']=='4925ea293c15d88153278437976a3b69f8985ccf'
for path in ha['evidence_paths']: assert (root/path).is_file(),path
pr=json.loads(subprocess.check_output(['gh','pr','view','646','--json','headRefOid,baseRefName,state,isDraft,url'],cwd=root,text=True))
assert pr['headRefOid']==m['head'] and pr['baseRefName']=='main' and pr['state']=='OPEN'
main=subprocess.check_output(['git','rev-parse','origin/main'],cwd=root,text=True).strip(); assert main=='6982a563dd0c88c81449566131852c601ae89868'
result=dict(role='INDEPENDENT_REVIEWER',verdict='PASS',scope='Final exact Human Attention and handoff document only; no new source review or merge authority',candidate_head=m['head'],candidate_tree=m['tree'],canonical_main=main,pr=pr,required_fixes=[],checks=dict(ha_schema_valid=True,evidence_paths_exist=True,final_manifest_file_count=len(m['files']),all_manifest_hashes_valid=True,verifier_pass_exact_subject=True,open_blocking_critical_human_gate=True,only_exact_pr646_baseline_merge_requested=True,raw_linux_and_pr_ci_fail_preserved=True,pc0_red_not_waived=True,mvp6_in_progress_explicit=True,world_runtime_subject_3b_distinguished=True,construction_fixture_not_physics_or_five_process_acceptance=True),assessment='Genuine declared Human merge prerequisite for causal canonical journal baseline repair. It is not permission to accept clearance/MVP6 or waive the directional assertion. After authorized merge, default canonical NX revalidation, real auditors and fresh main-owned clearance remain required. Parent must commit these exact reviewable bytes and obtain actual Drive/Close Human gate before final mission handoff.',files=[dict(path=str(p.relative_to(root)),sha256=sha(p)) for p in (ha_path,doc,e/'final-manifest.json',e/'verifier/result.json')],mvp6_verified=False,main_merge_authorized=False,source_edits=False)
(out/'handoff-review.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(sha(out/'handoff-review.json'))
