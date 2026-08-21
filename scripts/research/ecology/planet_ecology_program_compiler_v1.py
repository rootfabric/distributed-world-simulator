from __future__ import annotations
import argparse, copy, hashlib, json
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping

SCHEMA="distributed_world_simulator.ecology.evo3_e3_7_planet_ecology_program.v1"
CHECKPOINT="ECO.EVO3/E3.7"
COMPILER_STAGE="PLANET_COMPILATION"
AUTHORITY="RESEARCH_DERIVED_NON_AUTHORITATIVE"
HASH_ALGORITHM="SHA256_CANONICAL_JSON_SORTED_KEYS_V1"
ROOT=Path(__file__).resolve().parents[3]
DEFAULT_CONTRACT=ROOT/"config/ecology/eco-evo3-e3-7-planet-compilation-contract.v1.json"
DEFAULT_BINDING=ROOT/"config/ecology/eco-evo3-e3-7-inputs.binding.v1.json"
EXPECTED_CONTRACT_HASH="c2d0eec22d554cd6ec202a99c38c19609ad8d33ecb388bf598fe0d82b28483a1"
EXPECTED_BINDING_HASH="a2b53bd002120a5dc4367b4550193d2cd6282f5e68154c0479b3ac1ab7fac263"
EXPECTED_CONTROL_HEAD="c9f0b0becb3d2494097d946202788b9d1aa292f4"
EXPECTED_E3_6_MERGE="b7c279ec60a335b91924b3f1f6a0df6ac4f61d1d"
EXPECTED_PLANET="eco-evo3-fixture/planet-alpha-01"
EXPECTED_TIME_KEY="tf-fixture/planet-alpha/t000180"
EXPECTED_CATALOG_HASH="5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
EXPECTED_E3_3_HASH="9736ec70f844c930f8e160a4f08ae8e0aae1cce6f73fbf106499bea15b15a51a"
EXPECTED_E3_4_HASH="6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"
EXPECTED_E3_5_HASH="b8f30e129c0f714ebc937cdac6869e63223d8d72172cecb68dd049f604557ff5"
ROOT_SELF_HASH_FIELDS={"e3_1":"snapshot_hash","e3_2":"opportunity_field_hash","e3_3":"decomposition_hash","e3_4":"colonization_program_hash","e3_5":"population_workset_hash","e3_6":"temporal_program_hash"}
FORBIDDEN_TRUE_KEYS={"canonical_binding_resolved","production_binding_authorized","canonical_species_declared","canonical_time_ownership","canonical_environment_ownership","history_write_allowed","forecast_authorized","network_authority","persistence_authority","production_persistence_authority","world_transaction_authority","transaction_authority","asset_scatter_truth","xfer1_authority"}

def canonical_bytes(v:Any)->bytes:
    return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def sha256_hex(raw:bytes)->str: return hashlib.sha256(raw).hexdigest()
def git_blob_hex(raw:bytes)->str:
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()
def object_hash(v:Dict[str,Any],field:str)->str:
    x=copy.deepcopy(v); x.pop(field,None); return sha256_hex(canonical_bytes(x))
def _require(ok:bool,msg:str)->None:
    if not ok: raise ValueError(msg)
def _parse_object(raw:bytes,where:str)->Dict[str,Any]:
    v=json.loads(raw.decode("utf-8")); _require(isinstance(v,dict),f"{where}: root must be object"); return v
def _exact_keys(v:Dict[str,Any],expected:Iterable[str],where:str)->None:
    e=set(expected); a=set(v); _require(a==e,f"{where}: keys mismatch missing={sorted(e-a)} extra={sorted(a-e)}")
def _contains_scalar(v:Any,key:str,expected:Any)->bool:
    if isinstance(v,dict): return v.get(key)==expected or any(_contains_scalar(x,key,expected) for x in v.values())
    if isinstance(v,list): return any(_contains_scalar(x,key,expected) for x in v)
    return False
def _reject_true_authority(v:Any,where:str)->None:
    if isinstance(v,dict):
        for k,x in v.items():
            if k in FORBIDDEN_TRUE_KEYS: _require(x is False,f"{where}: forbidden authority promotion {k}={x!r}")
            _reject_true_authority(x,where)
    elif isinstance(v,list):
        for x in v: _reject_true_authority(x,where)

class _VerifiedInputs:
    __slots__=("contract","binding","values","raw")
    def __init__(self,*,contract,binding,values,raw):
        self.contract=copy.deepcopy(contract); self.binding=copy.deepcopy(binding); self.values=copy.deepcopy(values); self.raw={k:bytes(v) for k,v in raw.items()}
class _VerifiedPlanetEcologyProgram(dict):
    def __init__(self,value,inputs):
        super().__init__(copy.deepcopy(value)); self._raw={k:bytes(v) for k,v in inputs.raw.items()}

def _validate_contract(c):
    _require(c.get("schema")=="distributed_world_simulator.ecology.evo3_e3_7_planet_compilation_contract.v1","contract schema")
    _require(c.get("checkpoint")==CHECKPOINT and c.get("compiler_stage")==COMPILER_STAGE,"contract stage")
    _require(c.get("authority")==AUTHORITY and c.get("canonical_binding_resolved") is False and c.get("production_binding_authorized") is False,"contract authority")
    _require(c.get("contract_hash")==EXPECTED_CONTRACT_HASH==object_hash(c,"contract_hash"),"contract hash")
    p=c.get("input_policy",{})
    _require(p.get("immediate_ecology_predecessor")=="EXACT_ACCEPTED_E3_6_TEMPORAL_PROGRAM","E3.6 predecessor")
    _require(p.get("accepted_chain_required")==["E3.1","E3.2","E3.3","E3.4","E3.5","E3.6"],"accepted chain")
    for k in ("persisted_evo2_species_catalog_required","raw_bytes_required","git_blob_required","artifact_sha256_required","semantic_identity_recompute_required_where_defined","plain_parsed_json_authority_forbidden","candidate_alias_authority_forbidden","stage_rebake_or_retuning_forbidden"): _require(p.get(k) is True,f"contract input policy {k}")
    o=c.get("output_policy",{}); _require(o.get("program_type")=="PlanetEcologyProgram" and o.get("research_derived_non_authoritative") is True,"program type")
    for k in ("canonical_foundation_ownership","canonical_species_taxonomy","individual_entity_truth","production_persistence_authority","world_transaction_authority","network_authority","asset_scatter_truth","xfer1_authority"): _require(o.get(k) is False,f"contract output authority {k}")
    d=c.get("determinism",{}); _require(d.get("canonical_json")=="SORTED_KEYS_COMPACT_UTF8_NEWLINE_V1","canonical JSON")
    _require(d.get("global_rng_allowed") is False and d.get("local_clock_allowed") is False and d.get("ambient_environment_allowed") is False,"external nondeterminism")
    for k in ("same_exact_inputs_same_program_bytes_required","same_exact_inputs_same_program_hash_required","fresh_process_replay_required"): _require(d.get(k) is True,f"determinism {k}")

def _validate_binding(b,c):
    _require(b.get("schema")=="distributed_world_simulator.ecology.evo3_e3_7_inputs_binding.v1","binding schema")
    _require(b.get("binding_state")=="EXACT_ACCEPTED_EVO3_CHAIN_PLUS_PERSISTED_EVO2_CATALOG","binding state")
    _require(b.get("authority")==AUTHORITY and b.get("canonical_binding_resolved") is False and b.get("production_binding_authorized") is False,"binding authority")
    _require(b.get("accepted_control_head")==EXPECTED_CONTROL_HEAD and b.get("accepted_e3_6_merge_commit")==EXPECTED_E3_6_MERGE,"binding accepted base")
    _require(b.get("contract_hash")==c["contract_hash"],"binding contract hash")
    _require(b.get("binding_hash")==EXPECTED_BINDING_HASH==object_hash(b,"binding_hash"),"binding hash")
    _require(set(b.get("inputs",{}))=={"e3_1","e3_2","e3_3","e3_4","catalog","e3_5","e3_6"},"binding exact input set")

def _verify_raw(name,raw,spec):
    _require(git_blob_hex(raw)==spec["git_blob"],f"{name}: Git blob mismatch"); _require(sha256_hex(raw)==spec["sha256"],f"{name}: SHA-256 mismatch")
    v=_parse_object(raw,name)
    for f,e in spec.get("semantic_fields",{}).items(): _require(v.get(f)==e,f"{name}: semantic identity {f}")
    h=ROOT_SELF_HASH_FIELDS.get(name)
    if h: _require(object_hash(v,h)==v[h],f"{name}: recomputed {h}")
    _reject_true_authority(v,name); return v

def _validate_catalog(c):
    _require(c.get("schema")=="distributed_world_simulator.ecology.evo2_species_catalog.v1" and c.get("catalog_hash")==EXPECTED_CATALOG_HASH,"catalog identity")
    _require(c.get("canonical_species_declared") is False,"catalog canonical promotion")
    entries=c.get("entries"); _require(isinstance(entries,list) and len(entries)==2,"catalog exact entry count")
    seen=set()
    for e in entries:
        sid=str(e.get("research_species_id","")); _require(sid.startswith("eco-research-species/") and sid not in seen,"catalog research species identity"); seen.add(sid)
        _require(e.get("canonical_species_declared") is False,"catalog entry canonical promotion")
        _require(e.get("genome_checksum")==e.get("genome",{}).get("checksum"),"catalog genome checksum")
        _require(e.get("recruitment_traits_checksum")==e.get("recruitment_traits",{}).get("checksum"),"catalog recruitment checksum")

def _validate_cross_stage(v:Mapping[str,Dict[str,Any]]):
    s,o,d,c,cat,w,t=(v[k] for k in ("e3_1","e3_2","e3_3","e3_4","catalog","e3_5","e3_6")); _validate_catalog(cat)
    planet,time_key=s.get("stable_planet_identity"),s.get("stable_time_key"); _require((planet,time_key)==(EXPECTED_PLANET,EXPECTED_TIME_KEY),"E3.1 stable identities")
    _require(o.get("stable_planet_identity")==planet and o.get("stable_time_key")==time_key,"E3.2 stable identity linkage")
    _require(o.get("source_snapshot_hash")==s.get("snapshot_hash") and o.get("source_field_provenance_hash")==s.get("field_provenance_hash"),"E3.2 snapshot linkage")
    ob={x["stable_spatial_key"]:x for x in o.get("samples",[])}; db={x["stable_spatial_key"]:x for x in d.get("patches",[])}
    _require(len(ob)==len(o.get("samples",[])) and len(db)==len(d.get("patches",[])) and set(ob)==set(db),"E3.2/E3.3 spatial coverage")
    for k in sorted(ob):
        _require(db[k].get("source_opportunity_id")==ob[k].get("opportunity_id") and db[k].get("source_opportunity_sample_hash")==ob[k].get("opportunity_sample_hash"),f"E3.3 opportunity linkage {k}")
    _require(_contains_scalar(c,"decomposition_hash",EXPECTED_E3_3_HASH),"E3.4 decomposition linkage")
    _require(_contains_scalar(c,"catalog_hash",EXPECTED_CATALOG_HASH),"E3.4 catalog linkage")
    _require(_contains_scalar(w,"colonization_program_hash",EXPECTED_E3_4_HASH),"E3.5 colonization linkage")
    _require(_contains_scalar(t,"population_workset_hash",EXPECTED_E3_5_HASH),"E3.6 workset linkage")
    _require(t.get("source_population_workset",{}).get("stable_planet_identity")==planet and t.get("source_population_workset",{}).get("stable_time_key")==time_key,"E3.6 stable identity linkage")
    _require(t.get("source_tf_env_snapshot",{}).get("snapshot_hash")==s.get("snapshot_hash"),"E3.6 snapshot linkage")
    _require(t.get("refresh_contract",{}).get("seasonality_evidence_state")=="UNRESOLVED_SINGLE_SNAPSHOT","E3.6 single snapshot semantics")

def _verified_inputs_from_raw(raw):
    _require(set(raw)=={"contract","binding","e3_1","e3_2","e3_3","e3_4","catalog","e3_5","e3_6"},"exact raw input set")
    c=_parse_object(raw["contract"],"contract"); b=_parse_object(raw["binding"],"binding"); _validate_contract(c); _validate_binding(b,c)
    values={n:_verify_raw(n,raw[n],spec) for n,spec in b["inputs"].items()}; _validate_cross_stage(values)
    return _VerifiedInputs(contract=c,binding=b,values=values,raw=raw)

def load_verified_inputs(contract_path:Path=DEFAULT_CONTRACT,binding_path:Path=DEFAULT_BINDING):
    cr=Path(contract_path).read_bytes(); br=Path(binding_path).read_bytes(); b=_parse_object(br,"binding preflight"); raw={"contract":cr,"binding":br}
    for n,s in b.get("inputs",{}).items(): raw[n]=(ROOT/s["path"]).read_bytes()
    return _verified_inputs_from_raw(raw)

def _chain_manifest(b):
    out=[]
    for n in ("e3_1","e3_2","e3_3","e3_4","catalog","e3_5","e3_6"):
        s=b["inputs"][n]; out.append({"input":n,"path":s["path"],"git_blob":s["git_blob"],"sha256":s["sha256"],"semantic_fields":copy.deepcopy(s.get("semantic_fields",{}))})
    return out
def _region_manifest(w):
    out=[]
    for u in w.get("population_work_units",[]):
        if u.get("scale")=="REGION":
            out.append({"scheduling_region_id":u["scheduling_region_id"],"work_unit_id":u["work_unit_id"],"stable_spatial_keys":sorted(u.get("stable_spatial_keys",[])),"basis_keys":sorted(u.get("basis_keys",[])),"aggregate_member_count":int(u.get("aggregate_member_count",0)),"authority":"RESEARCH_SCHEDULING_IDENTITY_NON_CANONICAL"})
    return sorted(out,key=lambda x:(x["scheduling_region_id"],x["work_unit_id"]))
def _species_manifest(cat):
    return sorted([{"research_species_id":e["research_species_id"],"entry_hash":e["entry_hash"],"genome_checksum":e["genome_checksum"],"recruitment_traits_checksum":e["recruitment_traits_checksum"],"canonical_species_declared":False} for e in cat["entries"]],key=lambda x:x["research_species_id"])

def _build_program(i):
    v=i.values; s,o,d,c,cat,w,t=(v[k] for k in ("e3_1","e3_2","e3_3","e3_4","catalog","e3_5","e3_6"))
    regions=_region_manifest(w); species=_species_manifest(cat); spatial=sorted({e["stable_spatial_key"] for e in t.get("temporal_envelopes",[])}); basis=sorted({k for e in t.get("temporal_envelopes",[]) for k in e.get("basis_keys",[])})
    foundation={"stable_planet_identity":s["stable_planet_identity"],"stable_time_key":s["stable_time_key"],"snapshot_hash":s["snapshot_hash"],"field_provenance_hash":s["field_provenance_hash"],"reference_frame_identity":s.get("reference_frame_identity"),"tf_semantic_reference":t["source_tf_env_snapshot"]["tf_semantic_reference"],"env_semantic_reference":t["source_tf_env_snapshot"]["env_semantic_reference"],"ownership":"EXTERNAL_OWNER_SNAPSHOT_CONTEXT"}
    projection={"authority":"RESEARCH_PROJECTION_NON_CANONICAL","stable_planet_identity":s["stable_planet_identity"],"stable_time_key":s["stable_time_key"],"catalog_entry_count":len(cat["entries"]),"opportunity_sample_count":len(o.get("samples",[])),"research_patch_count":len(d.get("patches",[])),"research_edge_count":len(d.get("edges",[])),"research_region_count":len(regions),"active_spatial_key_count":len(spatial),"active_basis_count":len(basis),"temporal_envelope_count":len(t.get("temporal_envelopes",[])),"individual_entity_count":0}
    evidence={"accepted_control_head":EXPECTED_CONTROL_HEAD,"accepted_e3_6_merge_commit":EXPECTED_E3_6_MERGE,"immediate_ecology_predecessor":"E3.6","accepted_chain_exact":True,"persisted_evo2_catalog_exact":True,"external_nondeterminism_snapshot_bound":True,"global_rng_used":False,"local_clock_used":False,"ambient_environment_used":False,"input_manifest":_chain_manifest(i.binding)}
    provenance={"contract_hash":i.contract["contract_hash"],"binding_hash":i.binding["binding_hash"],"accepted_control_head":EXPECTED_CONTROL_HEAD,"accepted_e3_6_merge_commit":EXPECTED_E3_6_MERGE,"input_verification":"EXACT_RAW_GIT_BLOB_SHA256_AND_ACCEPTED_SEMANTIC_IDENTITIES","e3_1_snapshot_hash":s["snapshot_hash"],"e3_2_opportunity_field_hash":o["opportunity_field_hash"],"e3_3_decomposition_hash":d["decomposition_hash"],"e3_4_colonization_program_hash":c["colonization_program_hash"],"evo2_species_catalog_hash":cat["catalog_hash"],"e3_5_population_workset_hash":w["population_workset_hash"],"e3_6_temporal_program_hash":t["temporal_program_hash"]}
    p={"schema":SCHEMA,"version":"1.0.0","checkpoint":CHECKPOINT,"compiler_stage":COMPILER_STAGE,"program_type":"PlanetEcologyProgram","authority":AUTHORITY,"canonical_binding_resolved":False,"production_binding_authorized":False,"stable_planet_identity":s["stable_planet_identity"],"stable_time_key":s["stable_time_key"],"foundation_manifest":foundation,"species_manifest":species,"accepted_chain_manifest":_chain_manifest(i.binding),"regions":regions,"opportunity_field":copy.deepcopy(o),"ecology_decomposition":copy.deepcopy(d),"colonization_program":copy.deepcopy(c),"population_workset":copy.deepcopy(w),"temporal_program":copy.deepcopy(t),"execution_budget_hints":copy.deepcopy(w.get("execution_budget_hints",[])),"projection":projection,"evidence_package":evidence,"provenance":provenance,"provenance_hash":sha256_hex(canonical_bytes(provenance)),"planet_ecology_program_hash_algorithm":HASH_ALGORITHM}
    p["planet_ecology_program_hash"]=object_hash(p,"planet_ecology_program_hash"); return p

def build_planet_ecology_program(inputs):
    _require(type(inputs) is _VerifiedInputs,"build requires exact _VerifiedInputs capability"); v=_verified_inputs_from_raw(inputs.raw); p=_build_program(v); validate_output_structure(p); return _VerifiedPlanetEcologyProgram(p,v)

def validate_output_structure(p):
    _exact_keys(p,("schema","version","checkpoint","compiler_stage","program_type","authority","canonical_binding_resolved","production_binding_authorized","stable_planet_identity","stable_time_key","foundation_manifest","species_manifest","accepted_chain_manifest","regions","opportunity_field","ecology_decomposition","colonization_program","population_workset","temporal_program","execution_budget_hints","projection","evidence_package","provenance","provenance_hash","planet_ecology_program_hash_algorithm","planet_ecology_program_hash"),"PlanetEcologyProgram")
    _require(p["schema"]==SCHEMA and p["checkpoint"]==CHECKPOINT and p["compiler_stage"]==COMPILER_STAGE and p["program_type"]=="PlanetEcologyProgram","output identity")
    _require(p["authority"]==AUTHORITY and p["canonical_binding_resolved"] is False and p["production_binding_authorized"] is False,"output authority")
    _require((p["stable_planet_identity"],p["stable_time_key"])==(EXPECTED_PLANET,EXPECTED_TIME_KEY),"output stable identity")
    _require(p["planet_ecology_program_hash_algorithm"]==HASH_ALGORITHM and p["planet_ecology_program_hash"]==object_hash(p,"planet_ecology_program_hash"),"output program hash")
    _require(p["provenance_hash"]==sha256_hex(canonical_bytes(p["provenance"])),"output provenance hash")
    _require(p["projection"].get("individual_entity_count")==0,"individual entity truth forbidden")
    _require(p["evidence_package"].get("accepted_chain_exact") is True and p["evidence_package"].get("persisted_evo2_catalog_exact") is True,"evidence package")
    _require(p["evidence_package"].get("global_rng_used") is False and p["evidence_package"].get("local_clock_used") is False and p["evidence_package"].get("ambient_environment_used") is False,"nondeterminism evidence")
    _require(len(p["accepted_chain_manifest"])==7 and len(p["species_manifest"])==2 and len(p["regions"])>=1,"manifest cardinality"); _reject_true_authority(p,"PlanetEcologyProgram")

def validate_output_integrity(program):
    _require(type(program) is _VerifiedPlanetEcologyProgram,"serialization requires _VerifiedPlanetEcologyProgram capability"); inputs=_verified_inputs_from_raw(program._raw); expected=_build_program(inputs); validate_output_structure(expected); _require(canonical_bytes(dict(program))==canonical_bytes(expected),"PlanetEcologyProgram differs from independent exact-input rebuild")
def serialize_planet_ecology_program(program): validate_output_integrity(program); return canonical_bytes(dict(program))+b"\n"
def write_planet_ecology_program(program,output): Path(output).write_bytes(serialize_planet_ecology_program(program))
def build_from_paths(contract_path:Path=DEFAULT_CONTRACT,binding_path:Path=DEFAULT_BINDING): return build_planet_ecology_program(load_verified_inputs(contract_path,binding_path))
def main():
    p=argparse.ArgumentParser(description="ECO EVO3 E3.7 deterministic PlanetEcologyProgram compiler"); p.add_argument("--contract",type=Path,default=DEFAULT_CONTRACT); p.add_argument("--binding",type=Path,default=DEFAULT_BINDING); p.add_argument("--output",type=Path,required=True); p.add_argument("--quiet",action="store_true"); a=p.parse_args()
    program=build_from_paths(a.contract,a.binding); write_planet_ecology_program(program,a.output)
    if not a.quiet: print(f"E3.7 PlanetEcologyProgram: {a.output}\nplanet_ecology_program_hash={program['planet_ecology_program_hash']}\nprovenance_hash={program['provenance_hash']}\nregions={len(program['regions'])}\nspecies={len(program['species_manifest'])}")
    return 0
if __name__=="__main__": raise SystemExit(main())
