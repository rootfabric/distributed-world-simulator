extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_authority_section_projection.v1"
const FIELDS:Array[String]=["schema","section_id","construct_id","coordinator_server_id","projection_server_id","spatial_cell_id","authority_epoch","construct_checksum","mode","metadata","checksum"]
const READ_ONLY="READ_ONLY"
static func create(section_id:String,construct_id:String,coordinator:String,projection_server:String,cell_id:String,epoch:int,construct_checksum:String,metadata:Dictionary={})->Dictionary:
 var v={"schema":SCHEMA,"section_id":section_id,"construct_id":construct_id,"coordinator_server_id":coordinator,"projection_server_id":projection_server,"spatial_cell_id":cell_id,"authority_epoch":epoch,"construct_checksum":construct_checksum,"mode":READ_ONLY,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA:return P.failure("UNSUPPORTED_CONSTRUCTION_AUTHORITY_SECTION_SCHEMA")
 if not P.path_id(String(v.get("section_id","")),"section/") or not P.path_id(String(v.get("construct_id","")),"construct/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_SECTION_IDENTITY")
 for f in ["coordinator_server_id","projection_server_id"]:
  if not P.path_id(String(v.get(f,"")),"server/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_SECTION_SERVER")
 if not P.path_id(String(v.get("spatial_cell_id","")),"cell/") or not Utils.is_json_integer(v.get("authority_epoch")) or int(v.authority_epoch)<1:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_SECTION_SCOPE")
 if String(v.get("construct_checksum","")).length()!=64 or v.get("mode")!=READ_ONLY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_SECTION_MODE")
 if typeof(v.get("metadata"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.metadata).get("success",false)):return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_SECTION_METADATA")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AUTHORITY_SECTION_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
