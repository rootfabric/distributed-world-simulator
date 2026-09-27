import pathlib,json,hashlib,subprocess,re,os,datetime
root=pathlib.Path('C:/distributed-world-simulator')
out=root/'artifacts/mvp6-journal-73b88181/verifier'
primary=root/'worktrees/mvp6-continuation'
evidence=primary/'docs/control/mvp-act0-r1/journal-resolution-exact-r1'
mraw=(evidence/'machine-manifest.json').read_bytes(); m=json.loads(mraw)
assert hashlib.sha256(mraw).hexdigest()=='e0cb0b4793b5b89846c0defca471dcd2feb023a8ba7a86af1768d98c8ce27ce8'
checks=[]
for row in m['files']:
 b=(evidence/row['path']).read_bytes()
 assert len(b)==row['bytes'] and hashlib.sha256(b).hexdigest()==row['sha256'],row['path']
 gb=subprocess.check_output(['git','show','fd50004e:docs/control/mvp-act0-r1/journal-resolution-exact-r1/'+row['path']],cwd=primary)
 assert gb==b,row['path']
 checks.append(row['path'])
subjects={}
for label,folder,sha,tree in [('feature','mvp6-journal-exact-73b88181','73b8818184c93986e3313f35f9f4548c608e47e6','a1bbe30fd68af5db3a9535bee942683ebe761bc1'),('main','mvp6-journal-main-repair','3b82145ae946bb51aebf67f048a28420368b40be','6b1b8c9ead5c16d15dc8565813d3abb1bf94d880')]:
 cwd=root/'worktrees'/folder
 def git(*args): return subprocess.check_output(['git',*args],cwd=cwd).decode().strip()
 assert git('rev-parse','HEAD')==sha
 assert git('rev-parse','HEAD^{tree}')==tree
 assert git('status','--porcelain','--untracked-files=no')==''
 blobs={p:git('rev-parse','HEAD:'+p) for p in ['scripts/network/prediction/predicted_item_interaction_journal.gd','tests/runtime/test_v0_mvp_6_prediction_rollback.gd']}
 subjects[label]={'head':sha,'tree':tree,'tracked_clean':True,'blobs':blobs}
assert subjects['feature']['blobs']==subjects['main']['blobs']
logchecks=[]
for folder in ['native-exact','main-focused','linux/unpacked/journal-linux','nx-serial/baseline-main-plus-approved-repair-plus-nx','nx-serial/candidate-plus-mvp6-m4','linux/unpacked/journal-nx-linux/baseline-main-plus-approved-repair-plus-nx','linux/unpacked/journal-nx-linux/candidate-plus-mvp6-m4']:
 for p in (evidence/folder).glob('*.log'):
  text=p.read_text(encoding='utf-8-sig',errors='replace')
  fatal=re.findall(r'(?im)^.*(?:SCRIPT ERROR:|Parse Error:|^ERROR:|: FAIL\s*\().*$',text)
  assert not fatal,(p,fatal)
  markers=re.findall(r'PASS\s*\((\d+) assertions',text) or re.findall(r'assertions=(\d+) failures=0[^\r\n]*passed=true',text)
  if p.name!='import.log': assert len(markers)==1,(p,markers)
  logchecks.append({'path':str(p.relative_to(evidence)),'pass_assertions':markers,'fatal':fatal})
for path in ['nx-serial/summary.json','linux/unpacked/journal-nx-linux/summary.json']:
 s=json.loads((evidence/path).read_bytes())
 assert s['repair_composition_revalidated'] and not s['dependency_revalidated'] and not s['unmodified_canonical_baseline']
 assert [r['assertions'] for r in s['baseline_tests'][1:]]==[44,31,37,25,940]
 assert [r['assertions'] for r in s['candidate_tests'][1:]]==[44,31,37,25,940]
assert hashlib.sha256((evidence/'linux/artifact.zip').read_bytes()).hexdigest()=='afd5aeac91fd73e893fb569cc11a46a49c15673244c79c0a1dcd2e661160c1cd'
engine=pathlib.Path('C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe')
assert hashlib.sha256(engine.read_bytes()).hexdigest()=='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
env=dict(os.environ,BREAKPOINT_RUNTIME_DISABLED='1',PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default')
runs=[]
cwd=root/'worktrees/mvp6-journal-exact-73b88181'
for name,path,n in [('rollback','tests/runtime/test_v0_mvp_6_prediction_rollback.gd',77),('nx6','tests/network/test_nx6_predicted_item_interactions.gd',940),('bridge','tests/network/test_nx6_predicted_item_interactions_integration.gd',66)]:
 argv=[str(engine),'--headless','--path',str(cwd),'--script','res://'+path]
 r=subprocess.run(argv,cwd=cwd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
 (out/(name+'.log')).write_bytes(r.stdout)
 t=r.stdout.decode('utf-8',errors='replace')
 assert r.returncode==0 and re.findall(r'PASS\s*\((\d+) assertions',t)==[str(n)] and not re.search(r'(?im)SCRIPT ERROR:|Parse Error:|^ERROR:|: FAIL\s*\(',t),(name,t)
 runs.append({'argv':argv,'exit_code':r.returncode,'assertions':n,'log_sha256':hashlib.sha256(r.stdout).hexdigest()})
assert subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=cwd).strip()==b''
result={'verified_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'manifest_sha256':hashlib.sha256(mraw).hexdigest(),'manifest_files_verified':len(checks),'git_files_verified':len(checks),'subjects':subjects,'raw_logs':logchecks,'independent_runs':runs,'mvp6_accepted':False,'merge_ready':False,'full_world_core':'PENDING_SEPARATE_ADDENDUM'}
(out/'audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'manifest_files':len(checks),'git_files':len(checks),'raw_logs':len(logchecks),'independent_assertions':[r['assertions'] for r in runs],'subjects':subjects},indent=2))
