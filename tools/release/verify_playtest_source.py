#!/usr/bin/env python3
"""Verify the explicitly composed source snapshot; never waive failed tests."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
    lock=json.loads((ROOT/'config/release/playtest-composition.v1.json').read_text(encoding='utf-8'))
    errors=[]
    for path,sha in lock['files'].items():
        f=ROOT/path
        if not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest()!=sha: errors.append(path)
    if (ROOT/'.git').exists():
        base=lock['base_main']
        changed=set(subprocess.check_output(['git','diff','--name-only',base,'HEAD'],cwd=ROOT,text=True).splitlines())
        allowed=set(lock['changed_paths'])|{'config/release/playtest-composition.v1.json'}
        if changed!=allowed: errors.append('UNDECLARED_SCOPE:'+str(sorted(changed^allowed)))
    profile=json.loads((ROOT/'config/release/playtest-r1.json').read_text())
    assert profile['id']=='PLAYTEST_R1_SAFE60'
    assert profile['common_engine_args']==['--max-fps','60','--disable-vsync']
    if errors: raise SystemExit('PLAYTEST_SOURCE_FAIL '+str(errors))
    print('PLAYTEST_SOURCE_LOCK_PASS files='+str(len(lock['files'])))
if __name__=='__main__':main()
