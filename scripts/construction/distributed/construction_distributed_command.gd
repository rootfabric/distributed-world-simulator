extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Command=preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const SCHEMA="planet_simulator.construction_distributed_command.v1"
const FIELDS:Array[String]=["schema","route_id","source_server_id","expected_owner_server_id","authority_epoch","command","metadata","checksum"]
static func create(route_id:String,source_server_id:String,expected_owner_server_id:String,authority_epoch:int,command:Dictionary,metadata:Dictionary={})->Dictionary:
 var v={"schema":SCHEMA,"route_id":route_id,"source_server_id":source_server_id,"expected_owner_server_id":expected_owner_server_id,"authority_epoch":authority_epoch,"command":command.duplicate(true),"metadata":metadata.duplicate(true),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA:return P.failure("UNSUPPORTED_CONSTRUCTION_DISTRIBUTED_COMMAND_SCHEMA")
 if not P.path_id(String(v.get("route_id","")),"authority-route/"):return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_ROUTE_ID")
 for f in ["source_server_id","expected_owner_server_id"]:
  if not P.path_id(String(v.get(f,"")),"server/"):return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_SERVER_ID")
 if not Utils.is_json_integer(v.get("authority_epoch")) or int(v.authority_epoch)<1:return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_AUTHORITY_EPOCH")
 if typeof(v.get("command"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_INNER_COMMAND")
 x=Command.validate(v.command);if not bool(x.success):return x
 if typeof(v.get("metadata"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.metadata).get("success",false)):return P.failure("NON_CANONICAL_CONSTRUCTION_DISTRIBUTED_METADATA")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_DISTRIBUTED_COMMAND_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
