extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Plan=preload("res://scripts/construction/distributed/construction_authority_migration_plan.gd")
const SCHEMA="planet_simulator.construction_authority_handoff.v1"
const FIELDS:Array[String]=["schema","transfer_id","migration_plan","construct_state","terminal_operations","created_tick","checksum"]
static func create(transfer_id:String,plan:Dictionary,construct_state:Dictionary,terminal_operations:Array,created_tick:int)->Dictionary:
 var ops=terminal_operations.duplicate(true);ops.sort_custom(func(a,b):return String(a.get("operation_id",""))<String(b.get("operation_id","")))
 var v={"schema":SCHEMA,"transfer_id":transfer_id,"migration_plan":plan.duplicate(true),"construct_state":construct_state.duplicate(true),"terminal_operations":ops,"created_tick":created_tick,"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not P.path_id(String(v.get("transfer_id","")),"authority-transfer/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_HANDOFF_IDENTITY")
 if typeof(v.get("migration_plan"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_HANDOFF_PLAN")
 x=Plan.validate(v.migration_plan);if not bool(x.success):return x
 if typeof(v.get("construct_state"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.construct_state).get("success",false)):return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_HANDOFF_STATE")
 if String(v.construct_state.get("construct_id",""))!=String(v.migration_plan.construct_id) or String(v.construct_state.get("checksum",""))!=String(v.migration_plan.construct_checksum):return P.failure("CONSTRUCTION_AUTHORITY_HANDOFF_STATE_MISMATCH")
 if typeof(v.get("terminal_operations"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_HANDOFF_OPERATIONS")
 var prev=""
 for op in v.terminal_operations:
  if typeof(op)!=TYPE_DICTIONARY or not P.path_id(String(op.get("operation_id","")),"operation/") or typeof(op.get("result"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_HANDOFF_OPERATION")
  var oid=String(op.operation_id);if not prev.is_empty() and oid<=prev:return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_HANDOFF_OPERATIONS")
  prev=oid
 if not Utils.is_json_integer(v.get("created_tick")) or int(v.created_tick)<0:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_HANDOFF_TICK")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AUTHORITY_HANDOFF_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
