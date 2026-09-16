from pathlib import Path
import os, subprocess, hashlib, json, re
root=Path('C:/distributed-world-simulator/worktrees/mvp6-continuation')
out=Path(__file__).parent/'construction-fixture-exact-84ab0c0f';out.mkdir(exist_ok=False)
git=lambda *a:subprocess.check_output(['git',*a],cwd=root,text=True).strip()
head,tree=git('rev-parse','HEAD'),git('rev-parse','HEAD^{tree}')
assert head=='84ab0c0fba87f12dcfc94e32bb9cfa4eb8abb481' and tree=='f7e3f255bcc4878f3e738e011e3d45bf3edcdb81' and not git('status','--porcelain')
assert not git('diff','--name-only','73b88181','HEAD','--','scripts')
engine='C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(engine)=='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
env=dict(os.environ,BREAKPOINT_RUNTIME_DISABLED='1',PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default',EXPECTED_HEAD=head,EXPECTED_TREE=tree,MVP6_CONSTRUCTION_RESULT=str(out/'construction.json'))
specs=[('construction','test_v0_mvp_6_item_construction_composition',223),('p4','test_v0_p4_live_mvp_composition_ordering',64),('rollback','test_v0_mvp_6_prediction_rollback',77)]
rows=[]
for name,script,count in specs:
    argv=[engine,'--headless','--path',str(root),'--script','res://tests/runtime/'+script+'.gd'];log=out/(name+'.log')
    with log.open('wb') as f: code=subprocess.run(argv,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=300).returncode
    text=log.read_text(encoding='utf-8',errors='replace')
    counts=[int(a or b) for a,b in re.findall(r'PASS \((\d+) assertions\)|assertions=(\d+) failures=0',text)]
    fatal=re.findall(r'(?m)^\s*(?:SCRIPT ERROR|ERROR):.*|.*Parse Error.*|.*Compile Error.*',text)
    rows.append(dict(name=name,argv=argv,exit_code=code,assertions=counts,fatal=fatal,passed=code==0 and not fatal and counts==[count],sha256=sha(log)))
    print(json.dumps(rows[-1]),flush=True)
result=json.loads((out/'construction.json').read_text(encoding='utf-8-sig'))
checks={key:result.get(key) is True for key in ['passed','native_nonempty_carry_executed','real_resource_construction_executed','two_client_derived_replication_executed','construction_collision_present']}
checks['exact_report']=result.get('subject_head')==head and result.get('subject_tree')==tree
checks['no_self_acceptance']=result.get('mvp6_predicate_verified') is False and result.get('independent_verdict') is False
checks['clean_after']=not git('status','--porcelain')
report=dict(head=head,tree=tree,engine_sha256=sha(engine),commands=rows,checks=checks,passed=all(r['passed'] for r in rows) and all(checks.values()),runtime_unchanged_since='73b88181',five_process_executed=False,physics_interaction_executed=False,mvp6_verified=False)
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if report['passed'] else 1)
