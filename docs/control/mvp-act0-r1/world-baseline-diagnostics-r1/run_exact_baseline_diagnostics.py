from pathlib import Path
import hashlib, json, os, subprocess, time
root=Path('C:/distributed-world-simulator/worktrees/mvp6-journal-baseline-diagnostics')
out=Path(__file__).parent/'world-canonical-baseline'
out.mkdir(exist_ok=False)
git=lambda *a:subprocess.check_output(['git',*a],cwd=root,text=True).strip()
head,tree=git('rev-parse','HEAD'),git('rev-parse','HEAD^{tree}')
assert head=='6982a563dd0c88c81449566131852c601ae89868' and not git('status','--porcelain')
engine='C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(engine)=='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
profile=out/'profile';profile.mkdir()
env=dict(os.environ,BREAKPOINT_RUNTIME_DISABLED='1',PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default',APPDATA=str(profile),LOCALAPPDATA=str(profile))
specs=[('import',['--editor','--import','--quit'])]+[(n,['--script','res://tests/runtime/'+n+'.gd']) for n in ['test_m5_graphical_multiplayer_acceptance','test_m6_dedicated_recovery_contracts']]
rows=[]
for name,args in specs:
    log=out/(name+'.log');argv=[engine,'--headless','--path',str(root)]+args;start=time.monotonic()
    with log.open('wb') as f:
        try: code=subprocess.run(argv,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=300).returncode
        except subprocess.TimeoutExpired: code=124
    text=log.read_text(encoding='utf-8',errors='replace')
    row=dict(name=name,argv=argv,exit_code=code,seconds=time.monotonic()-start,sha256=sha(log),diagnostics=[s for s in text.splitlines() if s.startswith(('ERROR:','SCRIPT ERROR:','WARNING:'))])
    rows.append(row);print(json.dumps(row),flush=True)
    if name=='import' and (code or row['diagnostics']):break
for rel in git('ls-files','--others','--exclude-standard','*.gd.uid').splitlines():
    p=(root/rel).resolve();assert p.is_relative_to(root.resolve());p.unlink()
record=dict(head=head,tree=tree,engine_sha256=sha(engine),git_status_after=git('status','--porcelain'),commands=rows,classification_only=True,no_source_mutation=True)
(out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n')
