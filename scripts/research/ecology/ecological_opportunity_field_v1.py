from __future__ import annotations
import argparse, copy, hashlib, json
from pathlib import Path
from typing import Any

CONTRACT_SCHEMA="distributed_world_simulator.ecology.evo3_ecological_opportunity_field_contract.v1"
SNAPSHOT_SCHEMA="distributed_world_simulator.ecology.evo3_planet_field_snapshot.v1"
OUTPUT_SCHEMA="distributed_world_simulator.ecology.evo3_ecological_opportunity_field.v1"
VERSION="1.0.0"; SCALE=1_000_000
EXPECTED_PARENT={"e3_1_code_under_test_head":"7a1f5f0dc29b0564c6d4b684826250fca6a9b711","e3_1_aggregate_hash":"0a412c5c6cb12264c93c92d502321b578ebb3d166ae90d80ab450e03478e8036","e3_1_contract_hash":"b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170","e3_1_fixture_hash":"3e22d87666b13a4bafcdd5dd3184097b53b221103fd2f9e9f2be452c8ab79978","e3_1_field_provenance_hash":"3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3","e3_1_snapshot_hash":"2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00","e3_1_snapshot_artifact_sha256":"5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790","e3_0_architecture_hash":"cbf50695b6db79d543c26168bcfa1bb9ac2e29b052f0eabeafb028ab618a3ac6"}
EXPECTED_INPUT={"mode":"EXACT_ACCEPTED_E3_1_SNAPSHOT_ONLY","materialized_snapshot_path":"config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json","raw_fixture_input_forbidden":True,"raw_owner_field_input_forbidden":True,"snapshot_hash_must_match_parent":True,"field_provenance_must_match_parent":True,"artifact_sha256_must_match_parent":True,"canonical_binding_must_remain_unresolved":True,"owner_state_write_forbidden":True}
EXPECTED_TRANSFORM={"numeric_encoding":"INTEGER_FIXED_UNITS_V1","fraction_scale_ppm":SCALE,"sample_order":"LEXICOGRAPHIC_STABLE_SPATIAL_KEY","water_opportunity_ppm":"soil_moisture_ppm","light_opportunity_ppm":"light_availability_ppm","nutrient_opportunity_ppm":"nutrient_availability_ppm","persistence_opportunity_ppm":"1000000-disturbance_pressure_ppm","limiting_resource_opportunity_ppm":"min(water_opportunity_ppm,light_opportunity_ppm,nutrient_opportunity_ppm)","establishment_opportunity_ppm":"floor(limiting_resource_opportunity_ppm*persistence_opportunity_ppm/1000000)","thermal_context":"temperature_milli_c_passthrough_only_not_a_target_or_fitness_optimum","interpolation":"NONE_E3_2_SAMPLE_FIELD_ONLY","global_rng_consumption_forbidden":True}
FORBIDDEN=("biome","species","population","fitness","assignment","canonical_sd","production_api","authority_route")
FORBIDDEN_OUTPUT_TOKENS=FORBIDDEN
SAMPLE_KEYS={"sample_id","stable_spatial_key","latitude_microdeg","longitude_microdeg","temperature_milli_c","soil_moisture_ppm","light_availability_ppm","nutrient_availability_ppm","disturbance_pressure_ppm","sample_hash","field_provenance_hash"}
SNAPSHOT_SAMPLE_KEYS=["sample_id","stable_spatial_key","latitude_microdeg","longitude_microdeg","temperature_milli_c","soil_moisture_ppm","light_availability_ppm","nutrient_availability_ppm","disturbance_pressure_ppm","sample_hash","field_provenance_hash"]
OUT_SAMPLE_KEYS={"opportunity_id","stable_spatial_key","latitude_microdeg","longitude_microdeg","thermal_context_milli_c","water_opportunity_ppm","light_opportunity_ppm","nutrient_opportunity_ppm","persistence_opportunity_ppm","limiting_resource_opportunity_ppm","establishment_opportunity_ppm","source_sample_hash","source_field_provenance_hash","opportunity_sample_hash"}

def canonical_bytes(v:Any)->bytes:return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def sha256_hex(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def object_hash(v:dict,field:str)->str:
 p=copy.deepcopy(v);p.pop(field,None);return sha256_hex(canonical_bytes(p))
def load_json(path)->dict:
 v=json.loads(Path(path).read_text());
 if not isinstance(v,dict):raise ValueError("root")
 return v
def _keys(v,expected,where):
 if set(v)!=set(expected):raise ValueError(where+" keys")
def _forbidden(v):
 if isinstance(v,dict):
  for k,x in v.items():
   if any(t in str(k).lower() for t in FORBIDDEN):raise ValueError("forbidden key")
   _forbidden(x)
 elif isinstance(v,list):
  for x in v:_forbidden(x)
 elif isinstance(v,str) and any(t in v.lower() for t in FORBIDDEN):raise ValueError("forbidden string")

def validate_contract(c:dict)->None:
 _keys(c,{"schema","version","revision","branch","checkpoint","name","status","research_only","parent","input_policy","transform_semantics","output_contract","acceptance_gates","forbidden_promotions","next_gate","contract_hash_algorithm","contract_hash"},"contract")
 if c["schema"]!=CONTRACT_SCHEMA or c["version"]!=VERSION or c["checkpoint"]!="ECO.EVO3/E3.2" or c["research_only"] is not True:raise ValueError("identity")
 if c["parent"]!=EXPECTED_PARENT or c["input_policy"]!=EXPECTED_INPUT or c["transform_semantics"]!=EXPECTED_TRANSFORM:raise ValueError("frozen contract")
 o=c["output_contract"]
 if o.get("schema")!=OUTPUT_SCHEMA or o.get("authority")!="RESEARCH_DERIVED_NON_AUTHORITATIVE" or o.get("canonical_binding_resolved") is not False or o.get("expected_sample_count")!=12:raise ValueError("output contract")
 for k in ("one_to_one_with_snapshot_samples","all_fraction_outputs_bounded_ppm","source_provenance_retained","species_assignment_forbidden","biome_label_forbidden","population_truth_forbidden","research_region_creation_forbidden"):
  if o.get(k) is not True:raise ValueError(k)
 if o.get("compiled_suitability_is_population_truth") is not False:raise ValueError("truth boundary")
 g=c["acceptance_gates"]
 if g.get("fresh_process_replay_count")!=2:raise ValueError("replay count")
 for k in ("exact_parent_snapshot_required","exact_formula_contract_required","same_input_same_bytes_required","fresh_process_bytes_must_match","all_12_samples_retained","semantic_tamper_after_rehash_must_fail","raw_fixture_cli_surface_must_be_absent","forbidden_semantic_injection_must_fail","production_authority_claim_forbidden"):
  if g.get(k) is not True:raise ValueError(k)
 n=c["next_gate"]
 if n!={"on_accept":"AUTHORIZE_E3_3_RESEARCH_ECOLOGY_DECOMPOSITION","e3_3_must_consume_accepted_opportunity_field":True,"e3_3_research_region_ids_must_be_namespaced":True,"e3_3_may_not_create_canonical_sd_domains":True,"production_binding_remains_blocked_on_xfer1":True}:raise ValueError("next gate")
 if c["contract_hash_algorithm"]!="SHA256_CANONICAL_JSON_SORTED_KEYS_V1" or c["contract_hash"]!=object_hash(c,"contract_hash"):raise ValueError("contract hash")

def validate_snapshot(s:dict,c:dict)->None:
 validate_contract(c);p=c["parent"]
 _keys(s,{"schema","version","snapshot_id","authority","canonical_binding_resolved","stable_planet_identity","stable_time_key","reference_frame_identity","foundation_manifest","samples","source_fixture_hash","field_provenance_hash","snapshot_hash_algorithm","snapshot_hash"},"snapshot")
 if s["schema"]!=SNAPSHOT_SCHEMA or s["version"]!=VERSION or s["authority"]!="RESEARCH_DERIVED_NON_AUTHORITATIVE" or s["canonical_binding_resolved"] is not False:raise ValueError("snapshot identity")
 if s["source_fixture_hash"]!=p["e3_1_fixture_hash"] or s["field_provenance_hash"]!=p["e3_1_field_provenance_hash"] or s["snapshot_hash"]!=p["e3_1_snapshot_hash"]:raise ValueError("snapshot parent lock")
 if s["snapshot_hash_algorithm"]!="SHA256_CANONICAL_JSON_SORTED_KEYS_V1" or s["snapshot_hash"]!=object_hash(s,"snapshot_hash"):raise ValueError("snapshot hash")
 if set(s["foundation_manifest"])!={"G","ENV","MAT","WQ","SD","TF"}:raise ValueError("foundations")
 for r in s["foundation_manifest"].values():
  if set(r)!={"semantic_reference","canonical_binding_resolved"} or not r["semantic_reference"] or r["canonical_binding_resolved"] is not False:raise ValueError("foundation binding")
 if len(s["samples"])!=12:raise ValueError("sample count")
 keys=[x.get("stable_spatial_key") for x in s["samples"]]
 if keys!=sorted(keys) or len(set(keys))!=12:raise ValueError("sample order")
 for x in s["samples"]:
  _keys(x,SAMPLE_KEYS,"sample")
  for k in ("soil_moisture_ppm","light_availability_ppm","nutrient_availability_ppm","disturbance_pressure_ppm"):
   if type(x[k]) is not int or not 0<=x[k]<=SCALE:raise ValueError("sample range")

def validate_accepted_snapshot(s:dict,c:dict)->None:validate_snapshot(s,c)

def load_accepted_snapshot(path,c:dict)->dict:
 validate_contract(c);raw=Path(path).read_bytes()
 if sha256_hex(raw)!=c["parent"]["e3_1_snapshot_artifact_sha256"]:raise ValueError("artifact sha")
 s=json.loads(raw.decode())
 if raw!=canonical_bytes(s)+b"\n":raise ValueError("canonical artifact")
 validate_snapshot(s,c);return s

def _build(c:dict,s:dict)->dict:
 out=[]
 for x in s["samples"]:
  w=x["soil_moisture_ppm"];l=x["light_availability_ppm"];n=x["nutrient_availability_ppm"];p=SCALE-x["disturbance_pressure_ppm"];m=min(w,l,n);e=m*p//SCALE
  ident=sha256_hex(canonical_bytes({"source_snapshot_hash":s["snapshot_hash"],"stable_spatial_key":x["stable_spatial_key"],"source_field_provenance_hash":x["field_provenance_hash"],"derivation_contract_hash":c["contract_hash"]}))
  y={"opportunity_id":"eco-evo3/e3.2/opportunity/"+ident[:24],"stable_spatial_key":x["stable_spatial_key"],"latitude_microdeg":x["latitude_microdeg"],"longitude_microdeg":x["longitude_microdeg"],"thermal_context_milli_c":x["temperature_milli_c"],"water_opportunity_ppm":w,"light_opportunity_ppm":l,"nutrient_opportunity_ppm":n,"persistence_opportunity_ppm":p,"limiting_resource_opportunity_ppm":m,"establishment_opportunity_ppm":e,"source_sample_hash":x["sample_hash"],"source_field_provenance_hash":x["field_provenance_hash"]}
  y["opportunity_sample_hash"]=object_hash(y,"opportunity_sample_hash");out.append(y)
 mv=[x["limiting_resource_opportunity_ppm"] for x in out];ev=[x["establishment_opportunity_ppm"] for x in out]
 summary={"sample_count":12,"limiting_resource_min_ppm":min(mv),"limiting_resource_max_ppm":max(mv),"limiting_resource_mean_ppm":sum(mv)//12,"establishment_min_ppm":min(ev),"establishment_max_ppm":max(ev),"establishment_mean_ppm":sum(ev)//12}
 prov=sha256_hex(canonical_bytes({"source_snapshot_hash":s["snapshot_hash"],"source_field_provenance_hash":s["field_provenance_hash"],"derivation_contract_hash":c["contract_hash"],"opportunity_sample_hashes":[x["opportunity_sample_hash"] for x in out]}))
 f={"schema":OUTPUT_SCHEMA,"version":VERSION,"field_id":"eco-evo3/e3.2/field/"+prov[:24],"authority":"RESEARCH_DERIVED_NON_AUTHORITATIVE","canonical_binding_resolved":False,"stable_planet_identity":s["stable_planet_identity"],"stable_time_key":s["stable_time_key"],"reference_frame_identity":s["reference_frame_identity"],"source_snapshot_hash":s["snapshot_hash"],"source_field_provenance_hash":s["field_provenance_hash"],"derivation_contract_hash":c["contract_hash"],"samples":out,"summary":summary,"field_provenance_hash":prov,"opportunity_field_hash_algorithm":"SHA256_CANONICAL_JSON_SORTED_KEYS_V1"}
 f["opportunity_field_hash"]=object_hash(f,"opportunity_field_hash");return f

def build_opportunity_field(c:dict,s:dict)->dict:
 validate_snapshot(s,c);f=_build(c,s);validate_opportunity_field(f,c,s);return f

def validate_opportunity_field(f:dict,c:dict,s:dict)->None:
 validate_snapshot(s,c)
 _keys(f,{"schema","version","field_id","authority","canonical_binding_resolved","stable_planet_identity","stable_time_key","reference_frame_identity","source_snapshot_hash","source_field_provenance_hash","derivation_contract_hash","samples","summary","field_provenance_hash","opportunity_field_hash_algorithm","opportunity_field_hash"},"field")
 if f["schema"]!=OUTPUT_SCHEMA or f["authority"]!="RESEARCH_DERIVED_NON_AUTHORITATIVE" or f["canonical_binding_resolved"] is not False:raise ValueError("field identity")
 if f["source_snapshot_hash"]!=s["snapshot_hash"] or f["source_field_provenance_hash"]!=s["field_provenance_hash"] or f["derivation_contract_hash"]!=c["contract_hash"]:raise ValueError("field source")
 if len(f["samples"])!=12 or [x["stable_spatial_key"] for x in f["samples"]]!=[x["stable_spatial_key"] for x in s["samples"]]:raise ValueError("field order")
 for x in f["samples"]:
  _keys(x,OUT_SAMPLE_KEYS,"out sample")
  for k in ("water_opportunity_ppm","light_opportunity_ppm","nutrient_opportunity_ppm","persistence_opportunity_ppm","limiting_resource_opportunity_ppm","establishment_opportunity_ppm"):
   if type(x[k]) is not int or not 0<=x[k]<=SCALE:raise ValueError("field range")
  if x["opportunity_sample_hash"]!=object_hash(x,"opportunity_sample_hash"):raise ValueError("sample hash")
 if f["opportunity_field_hash_algorithm"]!="SHA256_CANONICAL_JSON_SORTED_KEYS_V1" or f["opportunity_field_hash"]!=object_hash(f,"opportunity_field_hash"):raise ValueError("field hash")
 _forbidden(f)
 if f!=_build(c,s):raise ValueError("semantic derivation")

def write_field(path,f):Path(path).write_bytes(canonical_bytes(f)+b"\n")
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--contract",required=True);p.add_argument("--snapshot",required=True);p.add_argument("--output");p.add_argument("--quiet",action="store_true");a=p.parse_args()
 c=load_json(a.contract);s=load_accepted_snapshot(a.snapshot,c);f=build_opportunity_field(c,s)
 if a.output:write_field(a.output,f)
 if not a.quiet:
  print("ECO.EVO3 E3.2 Ecological Opportunity Field: PASS");print("samples=12");print(f"contract_hash={c['contract_hash']}");print(f"source_snapshot_hash={f['source_snapshot_hash']}");print(f"field_provenance_hash={f['field_provenance_hash']}");print(f"opportunity_field_hash={f['opportunity_field_hash']}");print(f"establishment_mean_ppm={f['summary']['establishment_mean_ppm']}")
 return 0
if __name__=="__main__":raise SystemExit(main())
