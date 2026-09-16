import json, hashlib, subprocess
from pathlib import Path
root=Path('C:/distributed-world-simulator/worktrees/mvp6-journal-act0-control')
out=Path(__file__).parent
run=lambda *a:subprocess.check_output(['git','--no-replace-objects',*a],cwd=root)
sha=lambda b:hashlib.sha256(b).hexdigest()
head='a7c711c4b09fe52e52a206abc13ce8b427c19cf9'; tree='cc48a2446198a49c78ee46af601e2e56d3807bfd'
assert run('rev-parse','HEAD').decode().strip()==head
assert run('rev-parse','HEAD^{tree}').decode().strip()==tree
assert not run('status','--porcelain','--untracked-files=no').strip()
assert not run('diff','3b82145ae946bb51aebf67f048a28420368b40be','HEAD','--','scripts','scenes','project.godot').strip()
auth='docs/control/mvp-act0-r1/act0-journal-fence-r1/'
recordbytes=run('show','HEAD:'+auth+'authorization.json'); record=json.loads(recordbytes)
assert sha(recordbytes)=='111dd670e3e45ad79dc874d4e1df38080c9f41b4f5ca5fe07533a7954de4036c'
for name, f in record['files'].items():
 payload=run('show','HEAD:'+auth+name)
 assert sha(payload)==f['sha256']
 assert payload==run('show',record['source_commit']+':'+f['source_path'])
wo=json.loads(run('show','HEAD:'+auth+'work-order.json'))
assert wo['risk_class']=='CRITICAL' and wo['work_order_type']=='CONTROL'
assert not run('diff','3b82145ae946bb51aebf67f048a28420368b40be','9fdba029','--','tests/harness/test_v0_mvp_act0.py').strip()
changed=run('diff','--name-only','3b82145ae946bb51aebf67f048a28420368b40be','HEAD').decode().splitlines()
assert all(p=='tests/harness/test_v0_mvp_act0.py' or p.startswith(auth) for p in changed)
(out/'source-audit.json').write_text(json.dumps(dict(head=head,tree=tree,runtime_delta_from_3b=False,tracked_clean=True,authorization_source_bytes_verified=True,work_order_precedes_code=True,changed_paths=changed,source_findings=[],limits=['This source audit alone is not a validation or acceptance verdict.']),indent=2)+'\n')
print('Source audit PASS')
