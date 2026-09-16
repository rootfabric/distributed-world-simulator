#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, math, re, struct
from datetime import datetime
from fractions import Fraction
from pathlib import Path

DOMAIN = b'DWS/FABRIC/HOLDOUT-R4/POST-G2/UNSEEN/V1\0'
SCHEMA = 'distributed_world_simulator.fabric_holdout_r4_post_g2_unseen_cases.v1'
SUBJECT_HEAD='e6228a39b6b3006a3d14ad0884c09266570fcd00'
SUBJECT_TREE='1b84960369868aa6d5ec23c1eae3019250ff9a8f'
FREEZE='649af4ef16de00c797b4d63be70426abb3c75d68'
TARGET_MS=1789562700000
EXPECTED_CASES_SHA='3e14d528a33f4ecb95c4d7fd1f3f55394fcb4b3e624e0bf728698acef99f576d'
EXPECTED_OUTPUT_BYTES_SHA='3ca9faa0fe13e6530aa4053e91ee40123749caa3ce64537bba88da36a80852b6'
EXPECTED_RAW_PULSE_SHA='8a5e684b4fe2a0193dcea7560ad47531bfbc510100e9e670189f50210022a4af'
EXPECTED_URI='https://beacon.nist.gov/beacon/2.0/chain/2/pulse/1943920'
EXPECTED_TS='2026-09-16T12:46:00.000Z'
ASSERTIONS=0

def check(cond: bool, label: str):
    global ASSERTIONS
    ASSERTIONS += 1
    if not cond: raise AssertionError(label)

class SpecStream:
    def __init__(self, seed: bytes, label: str):
        self.seed=seed; self.label=label.encode(); self.counter=0; self.buf=b''
    def take(self,n):
        while len(self.buf)<n:
            self.buf += hashlib.sha256(DOMAIN+self.seed+b'\0'+self.label+b'\0'+self.counter.to_bytes(8,'big')).digest(); self.counter += 1
        r,self.buf=self.buf[:n],self.buf[n:]; return r
    def u64(self): return int.from_bytes(self.take(8),'big')
    def integer(self,lo,hi): return lo + self.u64() % (hi-lo+1)
    def choice(self,seq): return seq[self.u64()%len(seq)]

def fstr(v:Fraction): return f'{v.numerator}/{v.denominator}'

def solve(A,b):
    n=len(b); M=[list(r)+[b[i]] for i,r in enumerate(A)]
    for c in range(n):
        p=next((r for r in range(c,n) if M[r][c]),None); check(p is not None, f'non-singular column {c}')
        if p!=c: M[c],M[p]=M[p],M[c]
        q=M[c][c]; M[c]=[x/q for x in M[c]]
        for r in range(n):
            if r==c: continue
            q=M[r][c]
            if q: M[r]=[M[r][j]-q*M[c][j] for j in range(n+1)]
    return [M[i][-1] for i in range(n)]

def pmul(a,b):
    out=[Fraction(0)]*(len(a)+len(b)-1)
    for i,x in enumerate(a):
        for j,y in enumerate(b): out[i+j]+=x*y
    return out

def build_transport(seed):
    s=SpecStream(seed,'transport'); hs=[]
    for i in range(10):
        sign=s.integer(0,1); unbiased=s.integer(-900,40); exp=unbiased+1023; mant=s.u64()&((1<<52)-1); mant=mant or 1
        h=struct.pack('<Q',(sign<<63)|(exp<<52)|mant).hex(); hs.append(h)
        x=struct.unpack('<d',bytes.fromhex(h))[0]
        check(math.isfinite(x),f'transport finite {i}'); check(struct.pack('<d',x).hex()==h,f'transport bits {i}')
    sign=s.integer(0,1); mant=(s.u64()&((1<<52)-1)) or 1; h=struct.pack('<Q',(sign<<63)|mant).hex(); hs.append(h)
    x=struct.unpack('<d',bytes.fromhex(h))[0]; check(math.isfinite(x) and x!=0.0,'transport finite subnormal')
    return {'float64_le_hex':hs,'nested_key':'unseen_'+s.take(6).hex(),'tamper_replacement_hex':'000000000000f03f','required_checks':['exact_float_type','exact_float_bits','lossless_payload_hash','dictionary_order_canonical','checksum_tamper_rejected']}

def build_graph(seed):
    s=SpecStream(seed,'graph'); nodes=[f'g{i}' for i in range(6)]
    pairs=[('g0','g1'),('g1','g2'),('g2','g3'),('g3','g4'),('g4','g5'),('g1','g4'),('g2','g5'),('g0','g3'),('g2','g4')]
    edges=[{'element_id':f'ge{i}','node_a':a,'node_b':b,'resistance_ohm':s.integer(2,29),'active':True} for i,(a,b) in enumerate(pairs)]
    raw=[s.integer(-32,32) for _ in range(3)]; raw[1]=raw[0]+(raw[1]%13)+3; raw[2]=raw[0]-(raw[2]%11)-2
    bounds={'g0':Fraction(raw[0],4),'g3':Fraction(raw[1],4),'g5':Fraction(raw[2],4)}
    unknown=[n for n in nodes if n not in bounds]; idx={n:i for i,n in enumerate(unknown)}
    A=[[Fraction(0) for _ in unknown] for _ in unknown]; b=[Fraction(0) for _ in unknown]
    for n in unknown:
        i=idx[n]
        for e in edges:
            if n not in (e['node_a'],e['node_b']): continue
            other=e['node_b'] if e['node_a']==n else e['node_a']; g=Fraction(1,e['resistance_ohm']); A[i][i]+=g
            if other in idx: A[i][idx[other]]-=g
            else: b[i]+=g*bounds[other]
    x=solve(A,b); pot=dict(bounds); pot.update(zip(unknown,x))
    edgecur={e['element_id']:(pot[e['node_a']]-pot[e['node_b']])/e['resistance_ohm'] for e in edges}; ports={n:Fraction(0) for n in bounds}
    for e in edges:
        cur=edgecur[e['element_id']]
        if e['node_a'] in ports: ports[e['node_a']]+=cur
        if e['node_b'] in ports: ports[e['node_b']]-=cur
    check(sum(ports.values(),Fraction(0))==0,'graph exact port conservation')
    for n in unknown:
        residual=Fraction(0)
        for e in edges:
            if n==e['node_a']: residual += edgecur[e['element_id']]
            elif n==e['node_b']: residual -= edgecur[e['element_id']]
        check(residual==0,f'graph exact KCL {n}')
    return {'model':{'nodes':[{'node_id':n} for n in nodes],'elements':edges},'boundaries_v':{k:float(v) for k,v in bounds.items()},'oracle':{'potentials_v':{k:float(pot[k]) for k in nodes},'potentials_rational':{k:fstr(pot[k]) for k in nodes},'edge_currents_a':{k:float(v) for k,v in edgecur.items()},'port_currents_a':{k:float(v) for k,v in ports.items()}},'floating_negative':{'nodes':['gf0','gf1'],'resistance_ohm':s.integer(3,19),'expected_error':'R3_GENERAL_FLOATING_COMPONENT'},'tolerance':1e-9}

def build_mechanics(seed):
    s=SpecStream(seed,'mechanics')
    axes=[(Fraction(1,3),Fraction(2,3),Fraction(2,3)),(Fraction(2,3),Fraction(1,3),Fraction(2,3)),(Fraction(2,3),Fraction(2,3),Fraction(1,3)),(Fraction(-1,3),Fraction(2,3),Fraction(2,3))]
    axis=s.choice(axes); check(sum(a*a for a in axis)==1,'mechanics unit axis')
    masses=[Fraction(1),Fraction(s.integer(4,12),4),Fraction(s.integer(5,14),4),Fraction(s.integer(4,13),4),Fraction(1)]
    nodes=[{'node_id':f'm{i}','local_position_m':[float(Fraction(i)*v) for v in axis],'mass_kg':float(masses[i]),'anchored':i in (0,4)} for i in range(5)]
    ks=[s.integer(60,240) for _ in range(4)]; ds=[Fraction(s.integer(10,90),100) for _ in range(4)]
    edges=[{'element_id':f'me{i}','node_a':f'm{i}','node_b':f'm{i+1}','stiffness_n_per_m':float(ks[i]),'damping_ns_per_m':float(ds[i]),'capacity_n':500.0,'active':True} for i in range(4)]
    mobile=['m1','m2','m3']; mi={n:i for i,n in enumerate(mobile)}; K=[[Fraction(0) for _ in mobile] for _ in mobile]
    for i,e in enumerate(edges):
        k=Fraction(ks[i]); a,b=e['node_a'],e['node_b']
        if a in mi: K[mi[a]][mi[a]]+=k
        if b in mi: K[mi[b]][mi[b]]+=k
        if a in mi and b in mi: K[mi[a]][mi[b]]-=k; K[mi[b]][mi[a]]-=k
    coupler=s.choice(mobile); disp=solve(K,[Fraction(int(n==coupler)) for n in mobile])
    for v in ([Fraction(1),0,0],[0,Fraction(1),0],[0,0,Fraction(1)],[Fraction(1),Fraction(-1),Fraction(1)]):
        check(sum(v[i]*K[i][j]*v[j] for i in range(3) for j in range(3))>0,'mechanics stiffness positive definite')
    return {'model':{'nodes':nodes,'elements':edges},'coupler_node_id':coupler,'expected_mobile_nodes':mobile,'axis':[float(v) for v in axis],'oracle':{'displacement_per_newton':{n:float(v) for n,v in zip(mobile,disp)},'displacement_rational':{n:fstr(v) for n,v in zip(mobile,disp)}},'tiny_mass_kg':1e-15,'tiny_mass_expected_error':'R3_MASS_INVALID','tolerance':1e-10}

def build_events(seed):
    s=SpecStream(seed,'events'); grid=list(range(2,15)); picks=[]
    while len(picks)<3:
        v=s.choice(grid)
        if v not in picks: picks.append(v)
    picks.sort(); roots=[Fraction(v,16) for v in picks]; tangent=roots[1]; coeff=[Fraction(1)]
    for r in (roots[0],tangent,tangent,roots[2]): coeff=pmul(coeff,[-r,Fraction(1)])
    for r in roots: check(sum(c*(r**i) for i,c in enumerate(coeff))==0,f'event exact root {r}')
    deriv=[Fraction(i)*coeff[i] for i in range(1,len(coeff))]; check(sum(c*(tangent**i) for i,c in enumerate(deriv))==0,'event tangent derivative')
    bond=f"bond/unseen|{s.take(4).hex()}|segment|{s.take(3).hex()}"; sign=s.choice([-1,1])
    return {'polynomial_coefficients':[float(v) for v in coeff],'polynomial_coefficients_rational':[fstr(v) for v in coeff],'expected_roots':[float(v) for v in roots],'tangent_root':float(tangent),'transition_token':f'failure|{bond}|{float(sign):.1f}','expected_element_id':bond,'expected_sign':float(sign),'malformed_token':f'failure|{bond}|0.5','root_tolerance':5e-8}

def canonical(obj): return (json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n').encode()

def derive(pulse_doc):
    p=pulse_doc['pulse']; ov=p['outputValue'].upper(); seed=bytes.fromhex(ov)
    return {'schema':SCHEMA,'generator_version':'v1','subject':{'head':SUBJECT_HEAD,'tree':SUBJECT_TREE},'production_freeze_commit':FREEZE,'beacon':{'source':'NIST Randomness Beacon 2.0','selection_rule':'first pulse returned by /beacon/2.0/pulse/time/next/<target_ms>','target_time_utc':'2026-09-16T12:45:00.000Z','target_time_unix_ms':TARGET_MS,'pulse_uri':p['uri'],'pulse_timestamp':p['timeStamp'],'output_value':ov,'seed_commit_sha256':hashlib.sha256(DOMAIN+seed).hexdigest()},'families':{'transport':build_transport(seed),'graph':build_graph(seed),'mechanics':build_mechanics(seed),'events':build_events(seed)},'acceptance':{'all_families_required':True,'product_mutation_allowed':False,'threshold_relaxation_allowed':False,'historical_g1_reuse_allowed':False}}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--pulse',type=Path,required=True); ap.add_argument('--cases',type=Path,required=True); ap.add_argument('--out',type=Path,required=True); a=ap.parse_args()
    pulse=json.loads(a.pulse.read_text()); actual_bytes=a.cases.read_bytes(); actual=json.loads(actual_bytes)
    check(pulse['schema']=='distributed_world_simulator.fabric_holdout_r4_post_g2_nist_pulse_selection.v1','pulse schema')
    check(pulse['selection_rule']=='first pulse returned by https://beacon.nist.gov/beacon/2.0/pulse/time/next/1789562700000','pulse selection rule')
    check(pulse['source_run']==35108952760 and pulse['source_artifact']==10451362354,'pulse source evidence')
    check(pulse['source_raw_sha256']==EXPECTED_RAW_PULSE_SHA,'pulse raw sha')
    p=pulse['pulse']; check(p['uri']==EXPECTED_URI,'pulse uri'); check(p['timeStamp']==EXPECTED_TS,'pulse timestamp')
    check(p['chainIndex']==2 and p['pulseIndex']==1943920 and p['period']==60000 and p['statusCode']==0,'pulse coordinates')
    ts=int(datetime.fromisoformat(p['timeStamp'].replace('Z','+00:00')).timestamp()*1000); check(ts==1789562760000 and ts>TARGET_MS,'pulse after cut')
    ov=p['outputValue'].upper(); check(bool(re.fullmatch(r'[0-9A-F]{128}',ov)),'pulse output shape'); check(hashlib.sha256(bytes.fromhex(ov)).hexdigest()==EXPECTED_OUTPUT_BYTES_SHA,'pulse output sha')
    expected=derive(pulse); expected_bytes=canonical(expected); expected_sha=hashlib.sha256(expected_bytes).hexdigest()
    check(expected_sha==EXPECTED_CASES_SHA,'independent cases sha'); check(hashlib.sha256(actual_bytes).hexdigest()==EXPECTED_CASES_SHA,'revealed cases sha'); check(actual_bytes==expected_bytes,'byte-identical independent derivation'); check(actual==expected,'structural equality')
    check(actual['subject']=={'head':SUBJECT_HEAD,'tree':SUBJECT_TREE},'subject binding'); check(actual['production_freeze_commit']==FREEZE,'freeze binding')
    check(actual['acceptance']=={'all_families_required':True,'product_mutation_allowed':False,'threshold_relaxation_allowed':False,'historical_g1_reuse_allowed':False},'acceptance policy')
    t=actual['families']['transport']; check(len(t['float64_le_hex'])==11,'transport count'); check(len(set(t['float64_le_hex']))==11,'transport unique'); check(t['tamper_replacement_hex']=='000000000000f03f','transport tamper sentinel')
    g=actual['families']['graph']; check(len(g['model']['nodes'])==6 and len(g['model']['elements'])==9 and len(g['boundaries_v'])==3,'graph shape'); check(g['floating_negative']['expected_error']=='R3_GENERAL_FLOATING_COMPONENT','graph negative')
    m=actual['families']['mechanics']; check(m['expected_mobile_nodes']==['m1','m2','m3'],'mechanics mobile order'); check(m['tiny_mass_kg']==1e-15 and m['tiny_mass_expected_error']=='R3_MASS_INVALID','mechanics mass floor')
    e=actual['families']['events']; check(e['expected_element_id'] in e['transition_token'],'event delimiter id'); check(e['transition_token'].endswith('|1.0') or e['transition_token'].endswith('|-1.0'),'event legal sign'); check(e['malformed_token'].endswith('|0.5'),'event invalid sign control')
    a.out.write_bytes(expected_bytes)
    print(f'FABRIC_R4_POST_G2_UNSEEN_INDEPENDENT_ASSERTIONS={ASSERTIONS}')
    print('FABRIC-R4-POST-G2-UNSEEN-INDEPENDENT-ORACLE: PASS')
    print('INDEPENDENT_CASES_SHA256='+expected_sha)
if __name__=='__main__': main()
