extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_agent_reservation.v1"
const FIELDS:Array[String]=["schema","reservation_id","operation_id","agent_id","goal_id","resource_kind","resource_id","quantity","exclusive","created_tick","lease_expires_tick","status","checksum"]
const KINDS=["ITEM","TOOL","WORKSPACE","BUDGET","MACHINE"]
const STATUSES=["ACTIVE","CONSUMED","RELEASED","EXPIRED"]
static func create(reservation_id:String,operation_id:String,agent_id:String,goal_id:String,resource_kind:String,resource_id:String,quantity:float,exclusive:bool,created_tick:int,lease_expires_tick:int,status:String="ACTIVE")->Dictionary:
 var v={"schema":SCHEMA,"reservation_id":reservation_id,"operation_id":operation_id,"agent_id":agent_id,"goal_id":goal_id,"resource_kind":resource_kind,"resource_id":resource_id,"quantity":P.metric(quantity),"exclusive":exclusive,"created_tick":created_tick,"lease_expires_tick":lease_expires_tick,"status":status,"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not P.path_id(String(v.get("reservation_id","")),"agent-reservation/") or not P.path_id(String(v.get("operation_id","")),"operation/") or not P.path_id(String(v.get("agent_id","")),"agent/") or not P.path_id(String(v.get("goal_id","")),"agent-goal/"):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_IDENTITY")
 if not KINDS.has(String(v.get("resource_kind",""))) or String(v.get("resource_id","" )).is_empty():return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_RESOURCE")
 if not P.positive_number(v.get("quantity")) or typeof(v.get("exclusive"))!=TYPE_BOOL:return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_QUANTITY")
 for f in ["created_tick","lease_expires_tick"]:
  if not Utils.is_json_integer(v.get(f)) or int(v[f])<0:return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_TICK")
 if int(v.lease_expires_tick)<=int(v.created_tick):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_LEASE")
 if not STATUSES.has(String(v.get("status",""))):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_STATUS")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_RESERVATION_CHECKSUM_MISMATCH")
 return P.success()
static func with_status(v:Dictionary,status:String)->Dictionary:var n=v.duplicate(true);n.status=status;n.checksum=compute_checksum(n);return n
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
