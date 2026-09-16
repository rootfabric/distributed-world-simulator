import hashlib,json,subprocess
from pathlib import Path
import jsonschema
root=Path('C:/distributed-world-simulator/worktrees/mvp6-continuation'); out=Path(__file__).parent
path='config/control/harness/executions/E2026-09-09-V0-MVP-R1/human-attention/HA-V0-MVP6-JOURNAL-BASELINE-MERGE-R1.v1.json'
git=lambda *args:subprocess.check_output(['git','--no-replace-objects',*args],cwd=root)
sha=lambda b:hashlib.sha256(b).hexdigest()
commit=git('rev-parse','9a3c1fd0^{commit}').decode().strip(); tree=git('rev-parse',commit+'^{tree}').decode().strip()
payload=git('show',commit+':'+path); working=(root/path).read_bytes(); blob=git('rev-parse',commit+':'+path).decode().strip()
review=json.loads((out/'handoff-review.json').read_text())
for f in review['files']: f['path']=f['path'].replace(chr(92),'/')
original=next(f['sha256'] for f in review['files'] if f['path']==path)
assert sha(working)==original
assert working.replace(b'\r\n',b'\n')==payload
assert json.loads(working)==json.loads(payload)
jsonschema.validate(json.loads(payload),json.loads(git('show',commit+':config/control/harness/human-attention.schema.v1.json')))
assert sha(payload)=='e096bf4ad8c07c949141144a7dd5ae1627fd9aa14d442e61a3ff3862e81911aa'
checks=[]
for f in review['files']:
 if f['path']==path:continue
 b=git('show',commit+':'+f['path']); assert sha(b)==f['sha256']
 checks.append(dict(path=f['path'],sha256=sha(b),matches_original_review=True))
r=dict(role='INDEPENDENT_REVIEWER',verdict='PASS',scope='Evidence Git line-ending normalization audit only',evidence_commit=commit,evidence_tree=tree,path=path,git_blob=blob,reviewed_working_sha256=original,git_bytes_sha256=sha(payload),exact_crlf_to_lf_only=True,json_identical=True,schema_valid=True,other_reviewed_git_files=checks,original_review_file_sha256=sha((out/'handoff-review.json').read_bytes()),original_review_unchanged=True,policy_or_source_changes=False,merge_authorized=False)
(out/'git-byte-addendum.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(dict(commit=commit,blob=blob,addendum_sha256=sha((out/'git-byte-addendum.json').read_bytes()))))
