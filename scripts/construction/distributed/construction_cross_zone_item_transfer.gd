extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_cross_zone_item_transfer.v1"
const FIELDS:Array[String]=["schema","transfer_id","operation_id","item_instance_ids","source_server_id","target_server_id","source_cell_id","target_cell_id","source_construct_id","target_construct_id","authority_epoch","metadata","checksum"]
static func create(transfer_id:String,operation_id:String,item_ids:Array,source_server:String,target_server:String,source_cell:String,target_cell:String,source_construct:String,target_construct:String,authority_epoch:int,metadata:Dictionary={})->Dictionary:
 var v={"schema":SCHEMA,"transfer_id":transfer_id,"operation_id":operation_id,"item_instance_ids":P.sorted_strings(item_ids),"source_server_id":source_server,"target_server_id":target_server,"source_cell_id":source_cell,"target_cell_id":target_cell,"source_construct_id":source_construct,"target_construct_id":target_construct,"authority_epoch":authority_epoch,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not P.path_id(String(v.get("transfer_id","")),"cross-zone-transfer/") or not P.path_id(String(v.get("operation_id","")),"operation/"):return P.failure("INVALID_CONSTRUCTION_CROSS_ZONE_TRANSFER_IDENTITY")
 for f in ["source_server_id","target_server_id"]:
  if not P.path_id(String(v.get(f,"")),"server/"):return P.failure("INVALID_CONSTRUCTION_CROSS_ZONE_TRANSFER_SERVER")
 if String(v.source_server_id)==String(v.target_server_id):return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_SERVER_UNCHANGED")
 for f in ["source_cell_id","target_cell_id"]:
  if not P.path_id(String(v.get(f,"")),"cell/"):return P.failure("INVALID_CONSTRUCTION_CROSS_ZONE_TRANSFER_CELL")
 for f in ["source_construct_id","target_construct_id"]:
  if not P.path_id(String(v.get(f,"")),"construct/"):return P.failure("INVALID_CONSTRUCTION_CROSS_ZONE_TRANSFER_CONSTRUCT")
 if not Utils.is_json_integer(v.get("authority_epoch")) or int(v.authority_epoch)<1:return P.failure("INVALID_CONSTRUCTION_CROSS_ZONE_TRANSFER_EPOCH")
 if typeof(v.get("item_instance_ids"))!=TYPE_ARRAY or v.item_instance_ids.is_empty():return P.failure("INVALID_CONSTRUCTION_CROSS_ZONE_TRANSFER_ITEMS")
 var prev=""
 for raw in v.item_instance_ids:
  var id=String(raw);if not P.path_id(id,"item-instance/") or (not prev.is_empty() and id<=prev):return P.failure("NON_CANONICAL_CONSTRUCTION_CROSS_ZONE_TRANSFER_ITEMS")
  prev=id
 if typeof(v.get("metadata"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.metadata).get("success",false)):return P.failure("NON_CANONICAL_CONSTRUCTION_CROSS_ZONE_TRANSFER_METADATA")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
