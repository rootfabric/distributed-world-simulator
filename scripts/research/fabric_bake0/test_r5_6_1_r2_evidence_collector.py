#!/usr/bin/env python3
"""Eleven independent tamper fixtures must be rejected by the R2 exact collector."""
from __future__ import annotations
import argparse
from pathlib import Path
import shutil
import tempfile
from collect_r5_6_1_r2_evidence import collect

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',required=True,type=Path)
    args=ap.parse_args()
    def edit(path,old,new):
        raw=path.read_text(encoding='utf-8')
        if old not in raw:
            raise AssertionError('test fixture marker missing: '+old)
        path.write_text(raw.replace(old,new,1),encoding='utf-8')
    tamper=[
        ('checks',lambda p:edit(p/'r2-acceptance-2.log','"checks":626','"checks":625')),
        ('remove-scale',lambda p:(p/'r2-scale.log').unlink()),
        ('duplicate-marker',lambda p:(p/'r2-acceptance-3.log').write_text((p/'r2-acceptance-3.log').read_text()+ '\n' + [x for x in (p/'r2-acceptance-3.log').read_text().splitlines() if x.startswith('FABRIC_R56_R2_RESULT=')][0]+'\n')),
        ('duplicate-json-key',lambda p:edit(p/'r2-scale.log','"checks":255','"checks":255,"checks":255')),
        ('scale-case-forgery',lambda p:edit(p/'r2-scale.log','"n":100000','"n":99999')),
        ('engine-drift',lambda p:edit(p/'identity-after.txt','bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7','f'*64) if 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7' in (p/'identity-after.txt').read_text() else edit(p/'identity-after.txt','3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5','f'*64)),
        ('bridge-marker',lambda p:edit(p/'bridge4-regression.log','FABRIC BRIDGE-4 Canonical World: PASS (49 assertions)','FABRIC BRIDGE-4 Canonical World: FAIL (49 assertions)')),
        ('source-binding',lambda p:edit(p/'r1-narrow-admission.log','"duck_store_start_accepted":false','"duck_store_start_accepted":true')),
        ('numeric-assertion',lambda p:edit(p/'r2-numeric.log','"checks":54','"checks":53')),
        ('numeric-missing',lambda p:(p/'r2-numeric.log').unlink()),
        ('numeric-unsafe-admitted',lambda p:edit(p/'r2-numeric.log','"unsafe_ranges_rejected":1','"unsafe_ranges_rejected":0')),
    ]
    good=collect(args.root)
    assert good['verdict']=='IMPLEMENTER_EXACT_PASS'
    with tempfile.TemporaryDirectory(prefix='r56r2-collector-') as tmp:
        for i,(name,mutation) in enumerate(tamper):
            candidate=Path(tmp)/('campaign-'+str(i))
            shutil.copytree(args.root,candidate)
            mutation(candidate)
            try:
                collect(candidate)
            except (ValueError,FileNotFoundError,KeyError,TypeError) as err:
                print('R56_R2_EVIDENCE_TAMPER_REJECTED='+name+':'+type(err).__name__)
            else:
                raise AssertionError('collector accepted bad evidence: '+name)
    print('R56_R2_EVIDENCE_TAMPER_MATRIX=PASS 11/11')
if __name__=='__main__':main()
