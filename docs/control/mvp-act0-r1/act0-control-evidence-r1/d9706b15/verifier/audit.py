import ast, hashlib, json, subprocess, zipfile, re
from pathlib import Path
ROOT=Path('C:/distributed-world-simulator/worktrees/mvp6-journal-act0-control')
E=Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181')
OUT=E/'act0-control-verifier-d9706b15'
HEAD='d9706b157e84c653a753cc54243ce6651d53319c'
TREE='4925ea293c15d88153278437976a3b69f8985ccf'
BASE='3b82145ae946bb51aebf67f048a28420368b40be'
OLD='a7c711c4b09fe52e52a206abc13ce8b427c19cf9'
AUTH='docs/control/mvp-act0-r1/act0-journal-fence-r1'
TEST='tests/harness/test_v0_mvp_act0.py'
def git(*args): return subprocess.check_output(['git','--no-replace-objects',*args],cwd=ROOT)
def blob(ref,p): return git('show',ref+':'+p)
def sha(b): return hashlib.sha256(b).hexdigest()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
hashes={}
def check(p,h):
    assert sha(p.read_bytes())==h,str(p)
    hashes[str(p)]=h
assert git('rev-parse','HEAD').decode().strip()==HEAD
assert git('rev-parse','HEAD^{tree}').decode().strip()==TREE
assert not git('status','--porcelain').strip()
assert not git('diff',BASE,HEAD,'--','scripts','scenes','project.godot','RUN_WORLD_REGRESSION_TESTS.ps1','tests/harness/test_project_control_proposed_r3_ownership_projection.py')
git('merge-base','--is-ancestor','9fdba029d619a7a8cb29262d5a0ff3fb558d24ef',HEAD)
assert blob('9fdba029d619a7a8cb29262d5a0ff3fb558d24ef',TEST)==blob(BASE,TEST)
assert blob('9fdba029d619a7a8cb29262d5a0ff3fb558d24ef',AUTH+'/work-order.json')==blob(HEAD,AUTH+'/work-order.json')
record=blob(HEAD,AUTH+'/authorization.json')
assert sha(record)=='111dd670e3e45ad79dc874d4e1df38080c9f41b4f5ca5fe07533a7954de4036c'
a=json.loads(record)
for name,v in a['files'].items():
    b=blob(HEAD,AUTH+'/'+name)
    assert sha(b)==v['sha256'] and b==blob(a['source_commit'],v['source_path'])
    hashes[HEAD+':'+AUTH+'/'+name]=sha(b)
def nodes(ref):
    return {n.name:ast.dump(n,include_attributes=False) for n in ast.walk(ast.parse(blob(ref,TEST))) if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef))}
old,new=nodes(OLD),nodes(HEAD)
for name,node in old.items():
    if name!='fixture': assert new[name]==node,name
assert set(new)-set(old)=={'test_fixture_commits_do_not_launch_automatic_background_maintenance'}
rp=E/'act0-control-review-d9706b15/review.json'
check(rp,'c51436c50263c53c4ae165c1a6e3ad1e804a34462b25fdc3408a043453b004ba')
r=read(rp);assert (r['head'],r['tree'],r['verdict'])==(HEAD,TREE,'PASS')
for v in r['evidence']: check(Path(v['path']),v['sha256'])
w=E/'act0-fence-exact-d9706b15';ws=read(w/'summary.json')
assert (ws['head'],ws['tree'],ws['tests'],ws['exit_code'],ws['negative_git_fault_cases'])==(HEAD,TREE,18,0,23)
check(w/'tests.log',ws['log_sha256'])
assert 'Ran 18 tests' in (w/'tests.log').read_text() and (w/'tests.log').read_text().rstrip().endswith('OK')
h=E/'act0-full-harness-linux-d9706b15';z=h/'artifact.zip'
check(z,'1a29620992c1d6cf280a68ed82075f34e1f79a465f598f781e62a7965a696fc4')
with zipfile.ZipFile(z) as archive:
    for p in archive.namelist():
        if not p.endswith('/'): assert archive.read(p)==(h/'unpacked'/p).read_bytes()
hs=read(h/'unpacked/summary.json');check(h/'unpacked/tests.log',hs['log_sha256'])
assert (hs['head'],hs['tree'],hs['exit_code'],hs['tracked_status'])==(HEAD,TREE,1,'')
hl=(h/'unpacked/tests.log').read_text()
assert 'Ran 330 tests' in hl and 'FAILED (failures=1)' in hl
assert len(re.findall(r'^FAIL:',hl,re.M))==1 and not re.search(r'^ERROR:|\.\.\. skipped',hl,re.M)
assert "AssertionError: 'RED' == 'RED'" in hl
act0=[x for x in re.split(r'(?=^test_\w+ \()',hl,flags=re.M) if x.startswith('test_') and '(test_v0_mvp_act0.MVPAct0Tests.' in x.splitlines()[0]]
assert len(act0)==18 and all(x.rstrip().endswith('ok') for x in act0)
focused=(OUT/'focused.log').read_text()
assert 'Ran 3 tests' in focused and focused.rstrip().endswith('OK')
hashes[str(OUT/'focused.log')]=sha((OUT/'focused.log').read_bytes())
result=dict(role='INDEPENDENT_VERIFIER',verdict='PASS',scope='BOUNDED_ACT0_CONTROL_REPAIR_ONLY',head=HEAD,tree=TREE,risk_class='CRITICAL',required_fixes=[],
    checks=dict(exact_head_tree=True,clean_checkout=True,work_order_precedes_code=True,immutable_authorization_git_bytes=True,source_68433_ha_patch_identical=True,old_fence_and_negative_test_AST_unchanged=True,strict_cleanup_preserved=True,runtime_unchanged_from=BASE,windows_focused_tests=18,committed_negative_cases=23,independently_executed_tests=3,linux_act0_passes=18,linux_total_tests=330,linux_failures=1,linux_errors=0,linux_skips=0,all_zip_members_verified=True),
    linux_result='FAIL: only unchanged live directional PC0 RED assertion; full Harness is not PASS.',
    human_gate='Exact PR #646 baseline repair/control candidate requires HUMAN merge; this verdict is not authorization to merge.',
    continuation_after_human_merge=['Fetch exact canonical main','Run default canonical NX baseline/candidate dependency revalidation','Run actual standard and directional PC0','Prepare fresh main-owned clearance with independent roles'],
    limits=['World/core remains exact 3b82145a evidence; runtime equivalence verified, no new d970 world execution claimed.','No MVP6 live five-process or physics acceptance.','Full Windows and Linux evidence reused with independently verified hashes; three focused checks executed by this verifier.','Do not substitute explicit repair composition for accepted default canonical NX baseline.'],
    mvp6_verified=False,main_acceptance=False,merge_authorized=False,canonical_clearance=False,full_harness_pass=False,source_edits=False)
(OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
(OUT/'evidence-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(verdict='PASS',files_checked=len(hashes),result_sha256=sha((OUT/'result.json').read_bytes()))))
