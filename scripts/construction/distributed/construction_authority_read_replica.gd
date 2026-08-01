extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Record=preload("res://scripts/construction/distributed/construction_authority_record.gd")
const SCHEMA="planet_simulator.construction_authority_read_replica.v1"
const FIELDS:Array[String]=["schema","replica_server_id","construct_id","owner_server_id","authority_epoch","construct_checksum","state_bundle","last_update_tick","mode","checksum"]
const READ_ONLY="READ_ONLY"
var _state:Dictionary={}
func apply(record:Dictionary,state_bundle:Dictionary,tick:int)->Dictionary:
 var x=Record.validate(record);if not bool(x.success):return x
 if tick<0 or typeof(state_bundle)!=TYPE_DICTIONARY or not bool(Utils.canonicalize(state_bundle).get("success",false)):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICA_UPDATE")
 var server=String(_state.get("replica_server_id",""));if server.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_REPLICA_NOT_CONFIGURED")
 if not Array(record.replica_server_ids).has(server) and server!=String(record.owner_server_id):return P.failure("CONSTRUCTION_AUTHORITY_REPLICA_NOT_AUTHORIZED")
 if _state.has("schema"):
  if int(record.authority_epoch)<int(_state.authority_epoch):return P.failure("CONSTRUCTION_AUTHORITY_REPLICA_EPOCH_ROLLBACK")
  if int(record.authority_epoch)==int(_state.authority_epoch) and tick<int(_state.last_update_tick):return P.failure("CONSTRUCTION_AUTHORITY_REPLICA_TICK_ROLLBACK")
 var next={"schema":SCHEMA,"replica_server_id":server,"construct_id":String(record.construct_id),"owner_server_id":String(record.owner_server_id),"authority_epoch":int(record.authority_epoch),"construct_checksum":String(record.construct_checksum),"state_bundle":state_bundle.duplicate(true),"last_update_tick":tick,"mode":READ_ONLY,"checksum":""};next.checksum=compute_checksum(next)
 if _state.has("schema") and String(_state.checksum)==String(next.checksum):return P.success({"replay":true})
 _state=next;return P.success({"replay":false})
func configure(replica_server_id:String)->Dictionary:
 if not P.path_id(replica_server_id,"server/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICA_SERVER")
 _state={"replica_server_id":replica_server_id};return P.success()
func get_state()->Dictionary:return _state.duplicate(true)
func can_write()->bool:return false
func load_state(state:Dictionary)->Dictionary:
 var x=validate_state(state);if not bool(x.success):return x
 _state=state.duplicate(true);return P.success()
static func validate_state(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or v.get("mode")!=READ_ONLY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICA_STATE")
 for f in ["replica_server_id","owner_server_id"]:
  if not P.path_id(String(v.get(f,"")),"server/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICA_SERVER")
 if not P.path_id(String(v.get("construct_id","")),"construct/") or not Utils.is_json_integer(v.get("authority_epoch")) or int(v.authority_epoch)<1 or not Utils.is_json_integer(v.get("last_update_tick")) or int(v.last_update_tick)<0:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICA_SCOPE")
 if String(v.get("construct_checksum","")).length()!=64 or typeof(v.get("state_bundle"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.state_bundle).get("success",false)):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REPLICA_PAYLOAD")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AUTHORITY_REPLICA_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
