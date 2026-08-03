extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Reservation=preload("res://scripts/construction/agents/construction_agent_reservation.gd")
const SCHEMA="planet_simulator.construction_agent_reservation_store.v1"
const FIELDS:Array[String]=["schema","generation","capacities","reservations","terminal_operations","checksum"]
var _capacities:Dictionary={};var _reservations:Dictionary={};var _operations:Dictionary={};var _generation:=0
func setup(capacities:Dictionary={})->Dictionary:
 _capacities.clear();_reservations.clear();_operations.clear();_generation=0
 for id in capacities:
  if String(id).is_empty() or not P.non_negative_number(capacities[id]):return P.failure("INVALID_CONSTRUCTION_AGENT_RESOURCE_CAPACITY")
  _capacities[String(id)]=P.metric(float(capacities[id]))
 return P.success()
func set_capacity(resource_id:String,quantity:float)->Dictionary:
 if resource_id.is_empty() or not P.non_negative_number(quantity):return P.failure("INVALID_CONSTRUCTION_AGENT_RESOURCE_CAPACITY")
 _capacities[resource_id]=P.metric(quantity);_generation+=1;return P.success()
func acquire_batch(operation_id:String,agent_id:String,goal_id:String,requests:Array,current_tick:int,lease_expires_tick:int)->Dictionary:
 var payload={"operation_id":operation_id,"agent_id":agent_id,"goal_id":goal_id,"requests":_canonical_requests(requests),"current_tick":current_tick,"lease_expires_tick":lease_expires_tick};var checksum=Utils.payload_hash(payload)
 if _operations.has(operation_id):
  var old:Dictionary=_operations[operation_id]
  if String(old.checksum)!=checksum:return P.failure("CONSTRUCTION_AGENT_RESERVATION_OPERATION_ID_CONFLICT")
  var replay=Dictionary(old.result).duplicate(true);replay.replay=true;return replay
 if not P.path_id(operation_id,"operation/") or not P.path_id(agent_id,"agent/") or not P.path_id(goal_id,"agent-goal/") or current_tick<0 or lease_expires_tick<=current_tick:return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_REQUEST")
 expire(current_tick)
 var request_validation:=_validate_requests(requests);if not bool(request_validation.success):return request_validation
 var normalized:Array=request_validation.requests
 var active_by_resource:Dictionary={}
 for r in _reservations.values():
  if String(r.status)=="ACTIVE":active_by_resource[String(r.resource_id)]=float(active_by_resource.get(String(r.resource_id),0.0))+float(r.quantity)
 for req in normalized:
  var available:=float(_capacities.get(String(req.resource_id),0.0))-float(active_by_resource.get(String(req.resource_id),0.0))
  if bool(req.exclusive) and float(active_by_resource.get(String(req.resource_id),0.0))>0.0:return _terminal(operation_id,checksum,P.failure("CONSTRUCTION_AGENT_RESOURCE_CONTENTION",{"resource_id":String(req.resource_id)}))
  if available+0.00000001<float(req.quantity):return _terminal(operation_id,checksum,P.failure("CONSTRUCTION_AGENT_RESOURCE_CAPACITY_EXCEEDED",{"resource_id":String(req.resource_id),"available":available}))
 var created:Array=[];var index:=0
 for req in normalized:
  var id="agent-reservation/%s/%03d"%[operation_id.trim_prefix("operation/").replace("/",":"),index]
  var reservation=Reservation.create(id,operation_id,agent_id,goal_id,String(req.resource_kind),String(req.resource_id),float(req.quantity),bool(req.exclusive),current_tick,lease_expires_tick)
  _reservations[id]=reservation;created.append(reservation.duplicate(true));index+=1
 _generation+=1;return _terminal(operation_id,checksum,P.success({"reservations":created,"replay":false}))
func consume_operation(operation_id:String)->Dictionary:
 var changed:=0
 for id in _reservations:
  var r:Dictionary=_reservations[id]
  if String(r.operation_id)==operation_id and String(r.status)=="ACTIVE":_reservations[id]=Reservation.with_status(r,"CONSUMED");changed+=1
 if changed>0:_generation+=1
 return P.success({"changed":changed})
func release_operation(operation_id:String)->Dictionary:
 var changed:=0
 for id in _reservations:
  var r:Dictionary=_reservations[id]
  if String(r.operation_id)==operation_id and String(r.status)=="ACTIVE":_reservations[id]=Reservation.with_status(r,"RELEASED");changed+=1
 if changed>0:_generation+=1
 return P.success({"changed":changed})
func expire(tick:int)->Dictionary:
 var changed:=0
 for id in _reservations:
  var r:Dictionary=_reservations[id]
  if String(r.status)=="ACTIVE" and int(r.lease_expires_tick)<=tick:_reservations[id]=Reservation.with_status(r,"EXPIRED");changed+=1
 if changed>0:_generation+=1
 return P.success({"changed":changed})
func list_reservations()->Array:var a:Array=_reservations.values();a.sort_custom(func(x,y):return String(x.reservation_id)<String(y.reservation_id));return a.duplicate(true)
func get_generation()->int:return _generation
func to_dict()->Dictionary:
 var caps: Array = []
 var ids := _capacities.keys()
 ids.sort()
 for id in ids:
  caps.append({"resource_id": String(id), "quantity": float(_capacities[id])})
 var ops: Array = []
 ids = _operations.keys()
 ids.sort()
 for id in ids:
  ops.append(Dictionary(_operations[id]).duplicate(true))
 var v={"schema":SCHEMA,"generation":_generation,"capacities":caps,"reservations":list_reservations(),"terminal_operations":ops,"checksum":""};v.checksum=compute_checksum(v);return v
func load_dict(v:Dictionary)->Dictionary:
 var x=validate_state(v);if not bool(x.success):return x
 _capacities.clear()
 for row in v.capacities:
  _capacities[String(row.resource_id)] = float(row.quantity)
 _reservations.clear()
 for row in v.reservations:
  _reservations[String(row.reservation_id)] = row.duplicate(true)
 _operations.clear()
 for row in v.terminal_operations:
  _operations[String(row.operation_id)] = row.duplicate(true)
 _generation=int(v.generation);return P.success()
static func validate_state(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not Utils.is_json_integer(v.get("generation")) or int(v.generation)<0:return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_STORE")
 var prev:="";var seen:={}
 for row in v.capacities:
  var id=String(row.get("resource_id",""));if id.is_empty() or seen.has(id) or (not prev.is_empty() and id<prev) or not P.non_negative_number(row.get("quantity")):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_CAPACITY_STATE")
  seen[id]=true;prev=id
 prev="";seen={}
 for row in v.reservations:
  x=Reservation.validate(row);if not bool(x.success):return x
  var id=String(row.reservation_id);if seen.has(id) or (not prev.is_empty() and id<prev):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_RESERVATION_STATE")
  seen[id]=true;prev=id
 if typeof(v.get("terminal_operations"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_OPERATION_STATE")
 prev="";seen={}
 for row in v.terminal_operations:
  if typeof(row)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_OPERATION_STATE")
  x=Utils.validate_exact_fields(row,["operation_id","checksum","result"]);if not bool(x.success):return x
  var operation_id:=String(row.operation_id);if not P.path_id(operation_id,"operation/") or seen.has(operation_id) or (not prev.is_empty() and operation_id<prev):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_RESERVATION_OPERATION_STATE")
  if String(row.checksum).length()!=64 or typeof(row.result)!=TYPE_DICTIONARY or not bool(Utils.canonicalize(row.result).get("success",false)):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_OPERATION_STATE")
  seen[operation_id]=true;prev=operation_id
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_RESERVATION_STORE_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
func _terminal(id:String,checksum:String,result:Dictionary)->Dictionary:_operations[id]={"operation_id":id,"checksum":checksum,"result":result.duplicate(true)};return result
static func _validate_requests(requests:Array)->Dictionary:
 if requests.is_empty():return P.failure("CONSTRUCTION_AGENT_RESERVATION_REQUESTS_REQUIRED")
 var normalized:=_canonical_requests(requests);var seen:Dictionary={}
 for request in normalized:
  var kind:=String(request.resource_kind);var resource_id:=String(request.resource_id);var key:="%s|%s"%[kind,resource_id]
  if not kind in ["ITEM","TOOL","WORKSPACE","BUDGET"] or resource_id.is_empty() or seen.has(key):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_RESOURCE")
  if not P.positive_number(request.quantity):return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_QUANTITY")
  seen[key]=true
 return P.success({"requests":normalized})

static func _canonical_requests(requests:Array)->Array:
 var result:Array=[]
 for row in requests:result.append({"resource_kind":String(row.get("resource_kind","")),"resource_id":String(row.get("resource_id","")),"quantity":P.metric(float(row.get("quantity",0.0))),"exclusive":bool(row.get("exclusive",false))})
 result.sort_custom(func(a,b):return "%s|%s"%[a.resource_kind,a.resource_id]<"%s|%s"%[b.resource_kind,b.resource_id]);return result
