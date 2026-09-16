import json,hashlib
from pathlib import Path
root=Path('C:/distributed-world-simulator/artifacts/mvp6-journal-73b88181/act0-full-harness-linux')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
s=json.loads((root/'unpacked/summary.json').read_text()); log=root/'unpacked/tests.log'
assert sha(log)==s['log_sha256']
assert sha(root/'artifact.zip')=='8628d1323d58d76df9de3b062dbd90b76b4b466c5389f46cb7ef54fa5b14551a'
assert s['head']=='a7c711c4b09fe52e52a206abc13ce8b427c19cf9' and s['exit_code']==1
text=log.read_text(); assert 'Ran 329 tests in 151.757s' in text and 'FAILED (failures=1, errors=10)' in text
assert text.count('OSError: [Errno 39] Directory not empty: \'repo\'')==10
r=dict(role='REVIEWER',verdict='FAIL',scope='Full Linux Harness addendum; prior Windows focused PASS remains historical and narrower',head=s['head'],tree=s['tree'],run_id=s['run_id'],artifact_id=10448743149,artifact_sha256=sha(root/'artifact.zip'),log_sha256=sha(log),tests=329,failures=1,errors=10,required_fixes=['Resolve deterministic temporary Git fixture cleanup errors without weakening strict cleanup or negative assertions, freeze new subject and rerun exact focused plus full Linux Harness.'],known_failure='Existing live proposed R3 directional PC0 RED; not waived',finding='10 new ACT0 negative-case teardown errors: tempfile strict rmtree reports repo directory not empty. Git background maintenance is a hypothesis, not yet proven by this log.',rank_up_moves=[],evidence_gaps=['Fixed replacement subject and fresh validation required.'],mvp6_verified=False,main_acceptance=False)
(Path(__file__).parent/'linux-full-harness-fail-a7.json').write_text(json.dumps(r,indent=2)+'\n')
print(sha(Path(__file__).parent/'linux-full-harness-fail-a7.json'))
