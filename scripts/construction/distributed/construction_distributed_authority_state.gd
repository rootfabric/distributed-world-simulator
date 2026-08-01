extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Registry=preload("res://scripts/construction/distributed/construction_authority_registry.gd")
const Replica=preload("res://scripts/construction/distributed/construction_authority_read_replica.gd")
const SCHEMA="planet_simulator.construction_distributed_authority_state.v1"
const FIELDS:Array[String]=["schema","registry","replicas","tick","checksum"]
static func create(registry_state:Dictionary,replicas:Array,tick:int)->Dictionary:
 var rows=replicas.duplicate(true);rows.sort_custom(func(a,b):return _key(a)<_key(b))
 var v={"schema":SCHEMA,"registry":registry_state.duplicate(true),"replicas":rows,"tick":tick,"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not Utils.is_json_integer(v.get("tick")) or int(v.tick)<0 or typeof(v.get("registry"))!=TYPE_DICTIONARY or typeof(v.get("replicas"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_AUTHORITY_STATE")
 x=Registry.validate_state(v.registry);if not bool(x.success):return x
 var prev=""
 for row in v.replicas:
  if typeof(row)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_AUTHORITY_REPLICA")
  x=Replica.validate_state(row);if not bool(x.success):return x
  var key=_key(row);if not prev.is_empty() and key<=prev:return P.failure("NON_CANONICAL_CONSTRUCTION_DISTRIBUTED_AUTHORITY_REPLICAS")
  prev=key
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_DISTRIBUTED_AUTHORITY_STATE_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
static func _key(v:Dictionary)->String:return "%s|%s"%[String(v.get("construct_id","")),String(v.get("replica_server_id",""))]
