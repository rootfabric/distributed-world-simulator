import pathlib,subprocess,os,json,re,hashlib
root=pathlib.Path('C:/distributed-world-simulator/worktrees/mvp6-continuation');out=pathlib.Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181/construction-fixture-verifier')
def git(*a):return subprocess.check_output(['git',*a],cwd=root).decode().strip()
head='84ab0c0fba87f12dcfc94e32bb9cfa4eb8abb481';tree='f7e3f255bcc4878f3e738e011e3d45bf3edcdb81'
assert git('rev-parse','HEAD')==head and git('rev-parse','HEAD^{tree}')==tree and not git('status','--porcelain')
assert not git('diff','73b88181','HEAD','--','scripts')
engine=pathlib.Path('C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe');sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(engine)=='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
env=dict(os.environ,BREAKPOINT_RUNTIME_DISABLED='1',PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default',EXPECTED_HEAD=head,EXPECTED_TREE=tree,MVP6_CONSTRUCTION_RESULT=str(out/'construction.json'))
argv=[str(engine),'--headless','--path',str(root),'--script','res://tests/runtime/test_v0_mvp_6_item_construction_composition.gd']
r=subprocess.run(argv,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=300);(out/'construction.log').write_bytes(r.stdout)
t=r.stdout.decode('utf-8',errors='replace');assert r.returncode==0 and 'assertions=223 failures=0 passed=true' in t and not re.search(r'(?m)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error',t)
s=json.loads((out/'construction.json').read_bytes());assert s['subject_head']==head and s['subject_tree']==tree and s['passed'] and not s['failures']
a=s['construction']['authority']; assert [(x['before_ore'],x['after_ore']) for x in a['stages']]==[(8,6),(6,2),(2,0)]
assert a['final_construct']['build_state']=='OPERATIONAL'; assert len(a['final_bundle']['constructs'])==1
assert len(s['handoff_cases'])==2 and len(s['construction']['presentations'])==2
assert not s['mvp6_predicate_verified'] and not s['graphical_network_clients_executed'] and not s['world_restart_executed']
assert not git('status','--porcelain')
trusted=out.parent/'construction-fixture-exact-84ab0c0f';summary=json.loads((trusted/'summary.json').read_bytes())
for row in summary['commands']:
 assert sha(trusted/(row['name']+'.log'))==row['sha256'] and row['passed'] and row['exit_code']==0 and not row['fatal']
(out/'audit.json').write_text(json.dumps(dict(head=head,tree=tree,argv=argv,exit_code=r.returncode,assertions=223,log_sha256=sha(out/'construction.log'),report_sha256=sha(out/'construction.json'),engine_sha256=sha(engine),tracked_clean=True,runtime_identical_to='73b8818184c93986e3313f35f9f4548c608e47e6',stage_ore=[[8,6],[6,2],[2,0]],single_operational_construct=True,two_native_handoffs=True,two_derived_presentations=True,trusted_windows_assertions=[223,64,77],five_process_verified=False,physics_interaction_verified=False,mvp6_verified=False),indent=2)+'\n')
print('Independent exact construction223 PASS; retained64/77 hash records validated')
