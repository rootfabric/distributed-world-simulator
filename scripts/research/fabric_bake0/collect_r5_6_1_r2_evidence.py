#!/usr/bin/env python3
"""Strict FABRIC R5.6.1 R2 exact evidence; verifies source, payload and oracle campaigns."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
from collect_r5_6_1_evidence import sample as r1_sample, source_admission_evidence as r1_source, load_unique

VERSION = '4.7.1.stable.double.custom_build.a13da4feb'
ENGINES = {
    'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7',
    '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5',
}
FATAL = re.compile(r'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:', re.I)
HEX = re.compile(r'[0-9a-f]{40}\Z')

def need(value: bool, label: str):
    if not value:
        raise ValueError('R56_R2_EVIDENCE_' + label)

def read_log(path: Path) -> str:
    data = path.read_text(encoding='utf-8-sig')
    need(not FATAL.search(data), 'GODOT_FATAL_' + path.name)
    return data

def unique_payload(path: Path, marker: str) -> tuple[str,dict]:
    lines = [x[len(marker):] for x in read_log(path).splitlines() if x.startswith(marker)]
    need(len(lines) == 1, 'MISSING_OR_DUPLICATE_' + path.name)
    obj = load_unique(lines[0])
    need(type(obj) is dict, 'OBJECT_TYPE_' + path.name)
    return lines[0], obj

def identity(path: Path) -> tuple[str,str,str]:
    lines = path.read_text(encoding='utf-8-sig').splitlines()
    need(len(lines) == 4, 'IDENTITY_SHAPE')
    need(lines[0].startswith('HEAD=') and HEX.fullmatch(lines[0][5:]) is not None, 'HEAD_FORMAT')
    need(lines[1].startswith('TREE=') and HEX.fullmatch(lines[1][5:]) is not None, 'TREE_FORMAT')
    need(lines[2] == 'GODOT_VERSION='+VERSION, 'ENGINE_VERSION')
    engine = lines[3].removeprefix('GODOT_SHA256=')
    need(engine in ENGINES, 'ENGINE_SHA256')
    return lines[0][5:],lines[1][5:],engine

def collect(root: Path, expected_head: str='', expected_tree: str='') -> dict:
    before=identity(root/'identity-before.txt')
    after=identity(root/'identity-after.txt')
    need(before == after, 'IDENTITY_DRIFT')
    if expected_head: need(before[0]==expected_head, 'HEAD_DRIFT')
    if expected_tree: need(before[1]==expected_tree, 'TREE_DRIFT')
    results=[]
    for i in (1,2,3):
        row, obj=unique_payload(root/f'r2-acceptance-{i}.log','FABRIC_R56_R2_RESULT=')
        need(set(obj)=={'schema','checks','events','failures','full_oracle_queries','max_touched_nodes','rejected_cases','scenarios'},'R2_FIELDS')
        need(obj['schema']=='fabric.r56_r2.dynamic_aggregate.acceptance.v1','R2_SCHEMA')
        need(type(obj['checks']) is int and obj['checks']==626 and obj['failures']==[], 'R2_CHECKS')
        need(type(obj['events']) is int and obj['events']==8,'R2_EVENTS')
        need(type(obj['scenarios']) is int and obj['scenarios']==2,'R2_VARIANTS')
        need(type(obj['full_oracle_queries']) is int and obj['full_oracle_queries']==32,'R2_ORACLE')
        need(type(obj['rejected_cases']) is int and obj['rejected_cases']==44,'R2_REJECTS')
        need(type(obj['max_touched_nodes']) is int and 1<=obj['max_touched_nodes']<=18,'R2_NODES')
        results.append((row,obj))
    need(results[0][0]==results[1][0]==results[2][0], 'R2_NONDETERMINISTIC_PAYLOAD')
    scale_raw,scale=unique_payload(root/'r2-scale.log','FABRIC_R56_R2_SCALE=')
    need(set(scale)=={'schema','checks','failures','cases'},'SCALE_FIELDS')
    need(scale['schema']=='fabric.r56_r2.dynamic_index_scale.v1','SCALE_SCHEMA')
    need(type(scale['checks']) is int and scale['checks']==255 and scale['failures']==[], 'SCALE_CHECKS')
    need(len(scale['cases'])==3,'SCALE_CASES')
    for n,row in zip([5000,20000,100000],scale['cases']):
        need(row.get('n')==n and row.get('initial_parts_scanned')==n,'SCALE_BUILD')
        need(row.get('sparse_updated_parts')==3,'SCALE_CHANGED_PARTS')
        need(type(row.get('max_nodes_per_part_update')) is int and 1<=row['max_nodes_per_part_update']<=18,'SCALE_UPDATE_BOUND')
        need(type(row.get('total_fenwick_nodes_touched')) is int and row['total_fenwick_nodes_touched']<=3*18,'SCALE_NODE_COUNT')
    numeric_raw, numeric = unique_payload(root/'r2-numeric.log', 'FABRIC_R56_R2_NUMERIC=')
    need(set(numeric)=={'schema','checks','failures','stable_offsets',
        'sparse_update_ok','unsafe_ranges_rejected'}, 'NUMERIC_FIELDS')
    need(numeric.get('schema')=='fabric.r56_r2.numeric_conditioning.v1', 'NUMERIC_SCHEMA')
    need(type(numeric.get('checks')) is int and numeric['checks']==54
        and numeric.get('failures')==[], 'NUMERIC_CHECKS')
    need(numeric.get('stable_offsets')==[1.0,1.0e5,1.0e7,1.0e8,1.0e9], 'NUMERIC_OFFSETS')
    need(numeric.get('sparse_update_ok') is True, 'NUMERIC_SPARSE_UPDATE')
    need(type(numeric.get('unsafe_ranges_rejected')) is int
        and numeric['unsafe_ranges_rejected']==1, 'NUMERIC_FAIL_CLOSED')
    com_raw,com = unique_payload(root/'r2-com.log', 'FABRIC_R56_R2_COM_PRECISION=')
    need(set(com)=={'schema','checks','failures','center_budget_m',
        'unsafe_centers_rejected','safe_centers','multi_axis_rejections',
        'state_unchanged','cases'}, 'COM_FIELDS')
    need(com.get('schema')=='fabric.r56_r2.center_precision.v1','COM_SCHEMA')
    need(type(com.get('checks')) is int and com['checks']==52 and
        com.get('failures')==[], 'COM_ASSERTIONS')
    need(type(com.get('center_budget_m')) is float and
        com['center_budget_m']==1.0e-6, 'COM_PRECISION_BUDGET')
    need(type(com.get('unsafe_centers_rejected')) is int and
        com['unsafe_centers_rejected']==6, 'COM_FAIL_CLOSED')
    need(type(com.get('safe_centers')) is int and
        com['safe_centers']==2, 'COM_POSITIVE_CASES')
    need(type(com.get('multi_axis_rejections')) is int and
        com['multi_axis_rejections']==2 and com.get('state_unchanged') is True,
        'COM_AXES_AND_ROLLBACK')
    need(type(com.get('cases')) is list and len(com['cases'])==8, 'COM_CASES')
    cases=[('x-1e9',0,False),('x-1e12',0,True),('x-1e13',0,True),
        ('x-1e14',0,True),('x-1e15',0,True),('x-safe-1e12',0,False),
        ('y-negative-1e13',1,True),('z-positive-1e13',2,True)]
    for row,(label,axis,reject) in zip(com['cases'], cases):
        need(type(row) is dict and set(row)=={'label','axis','offset',
            'separation','expected_reject','accepted','error_code'},
            'COM_CASE_SHAPE')
        need(row['label']==label and type(row['axis']) is int and
            row['axis']==axis and type(row['expected_reject']) is bool and
            row['expected_reject'] is reject, 'COM_CASE_IDENTITY')
        need(type(row['accepted']) is bool and row['accepted'] is (not reject) and
            row['error_code']==('R56_R2_RANGE_CENTER_PRECISION_UNSAFE' if reject else ''),
            'COM_CASE_RESULT')
        need(type(row['separation']) is float and row['separation']>0.0,
            'COM_CASE_SEPARATION')
    recovery_raw,recovery=unique_payload(root/'r2-com-recovery.log','FABRIC_R56_R2_COM_RECOVERY=')
    need(set(recovery)=={'schema','checks','failures','observations'}, 'COM_RECOVERY_FIELDS')
    need(recovery.get('schema')=='fabric.r56_r2.com_recovery.v1', 'COM_RECOVERY_SCHEMA')
    need(type(recovery.get('checks')) is int and recovery['checks']==18
         and recovery.get('failures')==[], 'COM_RECOVERY_ASSERTIONS')
    observed=recovery.get('observations')
    need(type(observed) is dict and set(observed)=={
         'first_update_success','unsafe_query_success','unsafe_error',
         'incorrect_matter_refused','stale_source_refused','recovery_success',
         'recovery_error','final_status'}, 'COM_RECOVERY_OBSERVATIONS')
    need(observed['first_update_success'] is True and
         observed['unsafe_query_success'] is False and
         observed['unsafe_error']=='R56_R2_RANGE_CENTER_PRECISION_UNSAFE', 'COM_RECOVERY_INITIAL_FAIL_CLOSED')
    need(observed['incorrect_matter_refused'] is True and
         observed['stale_source_refused'] is True, 'COM_RECOVERY_MASS_SOURCE_SAFETY')
    need(observed['recovery_success'] is True and
         observed['recovery_error']=='', 'COM_RECOVERY_LIVENESS')
    stat=observed['final_status']
    need(type(stat) is dict and stat.get('schema')=='planet_simulator.fabric_r56_r2_dynamic_moments.v1', 'COM_RECOVERY_INDEX_SCHEMA')
    for key,expect in [('count',2),('build_scanned_parts',2),('revision',2),
                       ('accepted_updates',2),('updated_parts',2),
                       ('update_full_moment_scans',0)]:
        need(type(stat.get(key)) is int and stat[key]==expect, 'COM_RECOVERY_STATUS_'+key)
    need(type(stat.get('source_checksum')) is str and re.fullmatch(r'[0-9a-f]{64}',stat['source_checksum']) is not None,
         'COM_RECOVERY_SOURCE_CHECKSUM')
    original=r1_sample(root/'r1-acceptance.log')
    need(original[2]=='29defdc33cb1192b9e1577517561c6fcc0f5693daa889deebe585ab8816e043b','R1_HASH_DRIFT')
    narrow=r1_source(root/'r1-narrow-admission.log')
    for name in ('import','parse-r2','parse-scale','parse-numeric','parse-com','parse-com-recovery','parse-r1','parse-r1-narrow','bridge4-regression'):
        log=read_log(root/(name+'.log'))
        if name=='bridge4-regression':
            need('FABRIC BRIDGE-4 Canonical World: PASS (49 assertions)' in log, 'BRIDGE4_RESULT')
    deterministic_hash=hashlib.sha256(results[0][0].encode('utf-8')).hexdigest()
    result={
        'schema':'fabric.r56_r2.dynamic_aggregates.exact_evidence.v4',
        'verdict':'IMPLEMENTER_EXACT_PASS',
        'identity':{'head':before[0],'tree':before[1],'engine_sha256':before[2]},
        'r2_hash':deterministic_hash,
        'r2_acceptance':results[0][1],
        'r2_scale':scale,
        'r2_numeric':numeric,
        'r2_center_precision':com,
        'r2_com_recovery':recovery,
        'r1_baseline_hash':original[2],
        'r1_narrow':narrow,
        'logs':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob('*.log'))},
    }
    (root/'evidence.json').write_text(json.dumps(result,ensure_ascii=False,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    return result

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',required=True,type=Path)
    ap.add_argument('--expected-head',default='')
    ap.add_argument('--expected-tree',default='')
    p=ap.parse_args()
    evidence=collect(p.root,p.expected_head,p.expected_tree)
    print('FABRIC_R56_R2_HASH='+evidence['r2_hash'])
    print('FABRIC_R56_R2_EXACT_EVIDENCE=PASS')

if __name__=='__main__': main()
