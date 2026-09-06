#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, re, sys
from pathlib import Path

LABELS = [
    'BRIDGE3_A_HASH','BRIDGE3_B_HASH','BRIDGE3_C_HASH','BRIDGE3_D_HASH',
    'BRIDGE3_E_HASH','BRIDGE3_F_HASH','BRIDGE3_F_CAPSULE_HASH','BRIDGE3_G_HASH',
    'B06A_SAFETY_HASH','B06A_ENVELOPE_CHECKSUM','B06B_SELECTION_HASH',
    'B06C_TRANSITION_HASH','B06D_RECOVERY_HASH','B06D_DISK_RECOVERY_HASH',
    'B06E_FINAL_STATE_HASH','B06E_TRANSITION_HASH','B06E_WORK_HASH',
]
FATAL = re.compile(r'SCRIPT ERROR|Parse Error|Invalid call|Assertion failed|^ERROR:|Segmentation fault', re.M)
HEX = re.compile(r'^[0-9a-f]{64}$')

def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit('usage: validate_bridge3_closure.py LOG_DIR')
    root=Path(sys.argv[1])
    logs=sorted(root.glob('*.log'))
    if not logs:
        raise SystemExit('no closure logs')
    corpus='\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in logs)
    if FATAL.search(corpus):
        raise SystemExit('fatal runtime marker in closure logs')
    values={}
    for label in LABELS:
        found=re.findall(rf'^{re.escape(label)}=([^\s]+)$', corpus, re.M)
        unique=sorted(set(found))
        if len(unique) != 1 or not HEX.fullmatch(unique[0]):
            raise SystemExit(f'{label}: expected one stable sha256, got {unique}')
        values[label]=unique[0]
    required_sentinels=[
        'FABRIC BRIDGE-3-A: PASS','FABRIC BRIDGE-3-B: PASS','FABRIC BRIDGE-3-C: PASS',
        'FABRIC BRIDGE-3-D: PASS','FABRIC BRIDGE-3-E: PASS','FABRIC BRIDGE-3-F: PASS',
        'FABRIC BRIDGE-3-G: PASS',
    ]
    for sentinel in required_sentinels:
        if sentinel not in corpus:
            raise SystemExit('missing sentinel: '+sentinel)
    payload={'schema':'dws.fabric.bridge3.closure_hash.v1','hashes':values}
    canonical=json.dumps(payload,sort_keys=True,separators=(',',':')).encode()
    digest=hashlib.sha256(canonical).hexdigest()
    (root/'deterministic.json').write_text(json.dumps(payload,indent=2,sort_keys=True)+'\n')
    print('BRIDGE3_CLOSURE_HASH='+digest)
    print('FABRIC BRIDGE-3 deterministic closure: PASS')
    return 0
if __name__=='__main__':
    raise SystemExit(main())
