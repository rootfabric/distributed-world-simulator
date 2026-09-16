#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, struct
from fractions import Fraction
from pathlib import Path

DOMAIN = b'DWS/FABRIC/HOLDOUT-R4/POST-G2/UNSEEN/V1\0'
SCHEMA = 'distributed_world_simulator.fabric_holdout_r4_post_g2_unseen_cases.v1'
SUBJECT_HEAD = 'e6228a39b6b3006a3d14ad0884c09266570fcd00'
SUBJECT_TREE = '1b84960369868aa6d5ec23c1eae3019250ff9a8f'
FREEZE_COMMIT = '649af4ef16de00c797b4d63be70426abb3c75d68'
TARGET_MS = 1789562700000
TARGET_UTC = '2026-09-16T12:45:00.000Z'

class Stream:
    def __init__(self, seed: bytes, label: str):
        self.seed = seed; self.label = label.encode('utf-8'); self.counter = 0; self.buf = b''
    def _refill(self):
        self.buf += hashlib.sha256(DOMAIN + self.seed + b'\0' + self.label + b'\0' + self.counter.to_bytes(8, 'big')).digest(); self.counter += 1
    def take(self, n: int) -> bytes:
        while len(self.buf) < n: self._refill()
        out, self.buf = self.buf[:n], self.buf[n:]; return out
    def u64(self) -> int: return int.from_bytes(self.take(8), 'big')
    def integer(self, lo: int, hi: int) -> int: return lo + self.u64() % (hi - lo + 1)
    def choice(self, seq): return seq[self.u64() % len(seq)]

def _fstr(x: Fraction) -> str: return f'{x.numerator}/{x.denominator}'

def _gauss_fraction(a: list[list[Fraction]], b: list[Fraction]) -> list[Fraction]:
    n=len(b); m=[row[:] + [b[i]] for i,row in enumerate(a)]
    for col in range(n):
        pivot=next((r for r in range(col,n) if m[r][col] != 0),None)
        if pivot is None: raise ValueError('singular matrix')
        if pivot != col: m[col],m[pivot]=m[pivot],m[col]
        scale=m[col][col]; m[col]=[v/scale for v in m[col]]
        for r in range(n):
            if r == col: continue
            factor=m[r][col]
            if factor: m[r]=[m[r][c]-factor*m[col][c] for c in range(n+1)]
    return [m[i][-1] for i in range(n)]

def _poly_mul(a,b):
    out=[Fraction(0) for _ in range(len(a)+len(b)-1)]
    for i,av in enumerate(a):
        for j,bv in enumerate(b): out[i+j]+=av*bv
    return out

def _transport(seed: bytes) -> dict:
    s=Stream(seed,'transport'); patterns=[]
    for _ in range(10):
        sign=s.integer(0,1); unbiased=s.integer(-900,40); exp=unbiased+1023; mant=s.u64() & ((1<<52)-1); mant=mant or 1
        patterns.append(struct.pack('<Q',(sign<<63)|(exp<<52)|mant).hex())
    sign=s.integer(0,1); mant=(s.u64() & ((1<<52)-1)) or 1; patterns.append(struct.pack('<Q',(sign<<63)|mant).hex())
    return {'float64_le_hex':patterns,'nested_key':'unseen_'+s.take(6).hex(),'tamper_replacement_hex':'000000000000f03f','required_checks':['exact_float_type','exact_float_bits','lossless_payload_hash','dictionary_order_canonical','checksum_tamper_rejected']}

def _graph(seed: bytes) -> dict:
    s=Stream(seed,'graph'); nodes=[f'g{i}' for i in range(6)]
    pairs=[('g0','g1'),('g1','g2'),('g2','g3'),('g3','g4'),('g4','g5'),('g1','g4'),('g2','g5'),('g0','g3'),('g2','g4')]
    edges=[{'element_id':f'ge{i}','node_a':a,'node_b':b,'resistance_ohm':s.integer(2,29),'active':True} for i,(a,b) in enumerate(pairs)]
    raw=[s.integer(-32,32) for _ in range(3)]; raw[1]=raw[0]+(raw[1]%13)+3; raw[2]=raw[0]-(raw[2]%11)-2
    boundaries={'g0':Fraction(raw[0],4),'g3':Fraction(raw[1],4),'g5':Fraction(raw[2],4)}; unknown=[n for n in nodes if n not in boundaries]; idx={n:i for i,n in enumerate(unknown)}
    A=[[Fraction(0) for _ in unknown] for _ in unknown]; B=[Fraction(0) for _ in unknown]
    for n in unknown:
        i=idx[n]
        for e in edges:
            if n not in (e['node_a'],e['node_b']): continue
            other=e['node_b'] if e['node_a']==n else e['node_a']; g=Fraction(1,int(e['resistance_ohm'])); A[i][i]+=g
            if other in idx: A[i][idx[other]]-=g
            else: B[i]+=g*boundaries[other]
    x=_gauss_fraction(A,B); pot=dict(boundaries)
    for n,v in zip(unknown,x): pot[n]=v
    edge_curr={e['element_id']:(pot[e['node_a']]-pot[e['node_b']])/int(e['resistance_ohm']) for e in edges}; port_curr={n:Fraction(0) for n in boundaries}
    for e in edges:
        a,b=e['node_a'],e['node_b']; cur=edge_curr[e['element_id']]
        if a in port_curr: port_curr[a]+=cur
        if b in port_curr: port_curr[b]-=cur
    return {'model':{'nodes':[{'node_id':n} for n in nodes],'elements':edges},'boundaries_v':{k:float(v) for k,v in boundaries.items()},'oracle':{'potentials_v':{k:float(pot[k]) for k in nodes},'potentials_rational':{k:_fstr(pot[k]) for k in nodes},'edge_currents_a':{k:float(v) for k,v in edge_curr.items()},'port_currents_a':{k:float(v) for k,v in port_curr.items()}},'floating_negative':{'nodes':['gf0','gf1'],'resistance_ohm':s.integer(3,19),'expected_error':'R3_GENERAL_FLOATING_COMPONENT'},'tolerance':1e-9}

def _mechanics(seed: bytes) -> dict:
    s=Stream(seed,'mechanics'); axes=[(Fraction(1,3),Fraction(2,3),Fraction(2,3)),(Fraction(2,3),Fraction(1,3),Fraction(2,3)),(Fraction(2,3),Fraction(2,3),Fraction(1,3)),(Fraction(-1,3),Fraction(2,3),Fraction(2,3))]; axis=s.choice(axes)
    masses=[Fraction(1),Fraction(s.integer(4,12),4),Fraction(s.integer(5,14),4),Fraction(s.integer(4,13),4),Fraction(1)]; nodes=[]
    for i in range(5): nodes.append({'node_id':f'm{i}','local_position_m':[float(Fraction(i)*v) for v in axis],'mass_kg':float(masses[i]),'anchored':i in (0,4)})
    stiffness=[s.integer(60,240) for _ in range(4)]; damping=[Fraction(s.integer(10,90),100) for _ in range(4)]
    edges=[{'element_id':f'me{i}','node_a':f'm{i}','node_b':f'm{i+1}','stiffness_n_per_m':float(stiffness[i]),'damping_ns_per_m':float(damping[i]),'capacity_n':500.0,'active':True} for i in range(4)]
    mobile=['m1','m2','m3']; mi={n:i for i,n in enumerate(mobile)}; K=[[Fraction(0) for _ in mobile] for _ in mobile]
    for i,e in enumerate(edges):
        k=Fraction(stiffness[i]); a,b=e['node_a'],e['node_b']
        if a in mi: K[mi[a]][mi[a]]+=k
        if b in mi: K[mi[b]][mi[b]]+=k
        if a in mi and b in mi: K[mi[a]][mi[b]]-=k; K[mi[b]][mi[a]]-=k
    coupler=s.choice(mobile); disp=_gauss_fraction(K,[Fraction(1) if n==coupler else Fraction(0) for n in mobile])
    return {'model':{'nodes':nodes,'elements':edges},'coupler_node_id':coupler,'expected_mobile_nodes':mobile,'axis':[float(v) for v in axis],'oracle':{'displacement_per_newton':{n:float(v) for n,v in zip(mobile,disp)},'displacement_rational':{n:_fstr(v) for n,v in zip(mobile,disp)}},'tiny_mass_kg':1e-15,'tiny_mass_expected_error':'R3_MASS_INVALID','tolerance':1e-10}

def _events(seed: bytes) -> dict:
    s=Stream(seed,'events'); grid=list(range(2,15)); picks=[]
    while len(picks)<3:
        v=s.choice(grid)
        if v not in picks: picks.append(v)
    picks.sort(); roots=[Fraction(v,16) for v in picks]; tangent=roots[1]; coeff=[Fraction(1)]
    for r in [roots[0],tangent,tangent,roots[2]]: coeff=_poly_mul(coeff,[-r,Fraction(1)])
    bond_id=f"bond/unseen|{s.take(4).hex()}|segment|{s.take(3).hex()}"; sign=s.choice([-1,1])
    return {'polynomial_coefficients':[float(v) for v in coeff],'polynomial_coefficients_rational':[_fstr(v) for v in coeff],'expected_roots':[float(v) for v in roots],'tangent_root':float(tangent),'transition_token':f"failure|{bond_id}|{float(sign):.1f}",'expected_element_id':bond_id,'expected_sign':float(sign),'malformed_token':f"failure|{bond_id}|0.5",'root_tolerance':5e-8}

def generate(output_value: str,pulse_uri: str,pulse_timestamp: str) -> dict:
    ov=output_value.strip().upper()
    if len(ov)!=128 or any(c not in '0123456789ABCDEF' for c in ov): raise ValueError('outputValue must be exactly 512 bits / 128 hex chars')
    seed=bytes.fromhex(ov)
    return {'schema':SCHEMA,'generator_version':'v1','subject':{'head':SUBJECT_HEAD,'tree':SUBJECT_TREE},'production_freeze_commit':FREEZE_COMMIT,'beacon':{'source':'NIST Randomness Beacon 2.0','selection_rule':'first pulse returned by /beacon/2.0/pulse/time/next/<target_ms>','target_time_utc':TARGET_UTC,'target_time_unix_ms':TARGET_MS,'pulse_uri':pulse_uri,'pulse_timestamp':pulse_timestamp,'output_value':ov,'seed_commit_sha256':hashlib.sha256(DOMAIN+seed).hexdigest()},'families':{'transport':_transport(seed),'graph':_graph(seed),'mechanics':_mechanics(seed),'events':_events(seed)},'acceptance':{'all_families_required':True,'product_mutation_allowed':False,'threshold_relaxation_allowed':False,'historical_g1_reuse_allowed':False}}

def canonical_bytes(obj: dict) -> bytes: return (json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n').encode('utf-8')

def self_test() -> None:
    fake='0123456789ABCDEF'*8; a=generate(fake,'selftest://pulse','2099-01-01T00:00:00.000Z'); b=generate(fake,'selftest://pulse','2099-01-01T00:00:00.000Z')
    assert canonical_bytes(a)==canonical_bytes(b); assert set(a['families'])=={'transport','graph','mechanics','events'}; assert len(a['families']['transport']['float64_le_hex'])==11; assert len(a['families']['graph']['model']['elements'])==9; assert len(a['families']['mechanics']['expected_mobile_nodes'])==3; assert len(a['families']['events']['expected_roots'])==3; assert abs(sum(a['families']['graph']['oracle']['port_currents_a'].values()))<1e-10
    print('FABRIC_R4_POST_G2_UNSEEN_GENERATOR_SELF_TEST=PASS'); print('SELF_TEST_CASES_SHA256='+hashlib.sha256(canonical_bytes(a)).hexdigest())

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--output-value'); ap.add_argument('--pulse-uri',default=''); ap.add_argument('--pulse-timestamp',default=''); ap.add_argument('--out',type=Path); ap.add_argument('--self-test',action='store_true'); args=ap.parse_args()
    if args.self_test: self_test(); return
    if not args.output_value or not args.out: ap.error('--output-value and --out are required unless --self-test')
    data=canonical_bytes(generate(args.output_value,args.pulse_uri,args.pulse_timestamp)); args.out.parent.mkdir(parents=True,exist_ok=True); args.out.write_bytes(data); print('UNSEEN_CASES_SHA256='+hashlib.sha256(data).hexdigest()); print('UNSEEN_CASES_PATH='+str(args.out))
if __name__=='__main__': main()
