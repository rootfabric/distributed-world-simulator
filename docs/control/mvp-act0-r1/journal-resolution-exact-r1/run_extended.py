import hashlib, json, os, pathlib, re, subprocess, time
root = pathlib.Path('C:/distributed-world-simulator/worktrees/mvp6-journal-exact-73b88181')
out = pathlib.Path(__file__).parent / 'extended'
out.mkdir(exist_ok=False)
git = lambda *a: subprocess.check_output(['git', *a], cwd=root, text=True).strip()
head, tree = git('rev-parse','HEAD'), git('rev-parse','HEAD^{tree}')
assert head.startswith('73b88181') and not git('status','--porcelain','--untracked-files=no')
engine = 'C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe'
digest = lambda p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
assert digest(engine) == '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
env = dict(os.environ, PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1', BREAKPOINT_RUNTIME_DISABLED='1', PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default', MVP6_CONSTRUCTION_RESULT=str(out/'construction.json'))
specs = ['tests/network/test_nx6_predicted_item_interactions.gd', 'tests/network/test_nx6_predicted_item_interactions_integration.gd', 'tests/runtime/test_v0_mvp_4_shared_canonical_dig.gd', 'tests/runtime/test_v0_mvp_4_replica_rejection.gd', 'tests/runtime/test_v0_mvp_6_item_construction_composition.gd', 'tests/runtime/test_v0_p4_live_mvp_composition_ordering.gd']
rows=[]
for script in specs:
    log=out/(pathlib.Path(script).stem+'.log')
    argv=[engine,'--headless','--path',str(root),'--script','res://'+script]
    start=time.monotonic()
    with log.open('wb') as stream:
        try: code=subprocess.run(argv,cwd=root,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=300).returncode
        except subprocess.TimeoutExpired: code=124
    text=log.read_text(encoding='utf-8',errors='replace')
    fatal=re.findall(r'(?m)^\s*(?:SCRIPT ERROR|ERROR):.*|.*Parse Error.*|.*Compile Error.*',text)
    counts=re.findall(r'PASS \((\d+) assertions\)|assertions=(\d+) failures=0',text)
    passed=code==0 and not fatal and len(counts)==1 and int(next(x for x in counts[0] if x))>0
    row=dict(script=script,argv=argv,exit_code=code,fatal=fatal,assertions=int(next(x for x in counts[0] if x)) if len(counts)==1 else None,passed=passed,log_sha256=digest(log),seconds=time.monotonic()-start)
    rows.append(row)
    (out/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
    print(json.dumps(row),flush=True)
construction=json.loads((out/'construction.json').read_text(encoding='utf-8-sig')) if (out/'construction.json').exists() else {}
checks={key:construction.get(key) is True for key in ['passed','native_nonempty_carry_executed','real_resource_construction_executed','two_client_derived_replication_executed','construction_collision_present']}
checks['no_self_acceptance']=construction.get('mvp6_predicate_verified') is False
checks['exact_construction']=construction.get('subject_head')==head and construction.get('subject_tree')==tree
checks['tracked_clean']=not git('status','--porcelain','--untracked-files=no')
summary=dict(head=head,tree=tree,engine_sha256=digest(engine),passed=all(r['passed'] for r in rows) and all(checks.values()),checks=checks,commands=rows,mvp6_verified=False,five_process=False,full_world_core=False)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
raise SystemExit(0 if summary['passed'] else 1)
