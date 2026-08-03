extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_authority_migration_plan.v1"
const FIELDS:Array[String]=["schema","migration_id","construct_id","source_server_id","target_server_id","source_cell_id","target_cell_id","source_authority_epoch","target_authority_epoch","source_record_checksum","construct_checksum","replica_server_ids","metadata","checksum"]
static func create(migration_id:String,construct_id:String,source_server:String,target_server:String,source_cell:String,target_cell:String,source_epoch:int,source_record_checksum:String,construct_checksum:String,replicas:Array=[],metadata:Dictionary={})->Dictionary:
 var v={"schema":SCHEMA,"migration_id":migration_id,"construct_id":construct_id,"source_server_id":source_server,"target_server_id":target_server,"source_cell_id":source_cell,"target_cell_id":target_cell,"source_authority_epoch":source_epoch,"target_authority_epoch":source_epoch+1,"source_record_checksum":source_record_checksum,"construct_checksum":construct_checksum,"replica_server_ids":P.sorted_strings(replicas),"metadata":metadata.duplicate(true),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA:return P.failure("UNSUPPORTED_CONSTRUCTION_AUTHORITY_MIGRATION_SCHEMA")
 if not P.path_id(String(v.get("migration_id","")),"authority-migration/") or not P.path_id(String(v.get("construct_id","")),"construct/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_IDENTITY")
 for f in ["source_server_id","target_server_id"]:
  if not P.path_id(String(v.get(f,"")),"server/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_SERVER")
 if String(v.source_server_id)==String(v.target_server_id):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_OWNER_UNCHANGED")
 for f in ["source_cell_id","target_cell_id"]:
  if not P.path_id(String(v.get(f,"")),"cell/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_CELL")
 if not Utils.is_json_integer(v.get("source_authority_epoch")) or int(v.source_authority_epoch)<1 or not Utils.is_json_integer(v.get("target_authority_epoch")) or int(v.target_authority_epoch)!=int(v.source_authority_epoch)+1:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_EPOCH")
 for f in ["source_record_checksum","construct_checksum"]:
  if String(v.get(f,"")).length()!=64:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_CHECKSUM")
 if typeof(v.get("replica_server_ids"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_MIGRATION_REPLICAS")
 var prev=""
 for raw in v.replica_server_ids:
  var s=String(raw);if not P.path_id(s,"server/") or s==String(v.target_server_id) or (not prev.is_empty() and s<=prev):return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_MIGRATION_REPLICAS")
  prev=s
 if typeof(v.get("metadata"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.metadata).get("success",false)):return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_MIGRATION_METADATA")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_PLAN_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
