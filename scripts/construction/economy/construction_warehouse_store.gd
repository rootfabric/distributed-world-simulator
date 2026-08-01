extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const State=preload("res://scripts/construction/economy/construction_warehouse_state.gd")
var _states:Dictionary={};var _operations:Dictionary={};var _generation:=0
func setup(states:Array)->Dictionary:
	_states={};_operations={};_generation=0
	for s in states:
		var x=State.validate(s);if not bool(x.success):return x
		if _states.has(String(s.warehouse_id)):return P.failure("CONSTRUCTION_WAREHOUSE_DUPLICATE")
		_states[String(s.warehouse_id)]=s.duplicate(true)
	return P.success()
func reserve(operation_id:String,warehouse_id:String,item_ids:Array)->Dictionary:
	var payload={"kind":"RESERVE","warehouse_id":warehouse_id,"item_ids":P.sorted_strings(item_ids)};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _states.has(warehouse_id):return _store_failure(operation_id,payload,"CONSTRUCTION_WAREHOUSE_NOT_FOUND")
	var state:Dictionary=_states[warehouse_id].duplicate(true);var reserved:Dictionary=state.reserved_quantities.duplicate(true)
	for id in payload.item_ids:
		if State.available_quantity(state,String(id))<1.0:return _store_failure(operation_id,payload,"CONSTRUCTION_WAREHOUSE_ITEM_UNAVAILABLE")
		reserved[String(id)]=float(reserved.get(String(id),0.0))+1.0
	state.reserved_quantities=reserved;state.revision=int(state.revision)+1;state.checksum=U.checksum(state);_states[warehouse_id]=state;_generation+=1
	return _store(operation_id,payload,P.success({"warehouse":state.duplicate(true),"generation":_generation,"replay":false}))
func dispatch(operation_id:String,warehouse_id:String,item_ids:Array)->Dictionary:
	var payload={"kind":"DISPATCH","warehouse_id":warehouse_id,"item_ids":P.sorted_strings(item_ids)};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _states.has(warehouse_id):return _store_failure(operation_id,payload,"CONSTRUCTION_WAREHOUSE_NOT_FOUND")
	var state:Dictionary=_states[warehouse_id].duplicate(true);var items:Array=[];var remaining:Array=[];var reserved:Dictionary=state.reserved_quantities.duplicate(true)
	for projection in state.item_projections:
		var id=String(projection.item_instance_id)
		if payload.item_ids.has(id):
			if float(reserved.get(id,0.0))<1.0:return _store_failure(operation_id,payload,"CONSTRUCTION_WAREHOUSE_ITEM_NOT_RESERVED")
			items.append(Dictionary(projection).duplicate(true));reserved.erase(id)
		else:remaining.append(Dictionary(projection).duplicate(true))
	if items.size()!=payload.item_ids.size():return _store_failure(operation_id,payload,"CONSTRUCTION_WAREHOUSE_ITEM_NOT_FOUND")
	state.item_projections=remaining;state.reserved_quantities=reserved;state.revision=int(state.revision)+1;state.checksum=U.checksum(state);_states[warehouse_id]=state;_generation+=1
	return _store(operation_id,payload,P.success({"item_projections":items,"warehouse":state.duplicate(true),"generation":_generation,"replay":false}))
func receive(operation_id:String,warehouse_id:String,items:Array)->Dictionary:
	var payload={"kind":"RECEIVE","warehouse_id":warehouse_id,"item_checksums":[]};for p in items:payload.item_checksums.append(String(p.get("checksum","")));payload.item_checksums.sort()
	var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _states.has(warehouse_id):return _store_failure(operation_id,payload,"CONSTRUCTION_WAREHOUSE_NOT_FOUND")
	var state:Dictionary=_states[warehouse_id].duplicate(true);var merged:Array=state.item_projections.duplicate(true);for p in items:merged.append(p.duplicate(true));merged.sort_custom(func(a,b):return String(a.item_instance_id)<String(b.item_instance_id));state.item_projections=merged;state.revision=int(state.revision)+1;state.checksum=U.checksum(state)
	var checked=State.validate(state);if not bool(checked.success):return _store_failure(operation_id,payload,String(checked.error_code))
	_states[warehouse_id]=state;_generation+=1;return _store(operation_id,payload,P.success({"warehouse":state.duplicate(true),"generation":_generation,"replay":false}))
func get_state(id:String)->Dictionary:return Dictionary(_states.get(id,{})).duplicate(true)
func get_generation()->int:return _generation
func export_state()->Dictionary:var v={"states":_states.duplicate(true),"operations":_operations.duplicate(true),"generation":_generation,"checksum":""};v.checksum=U.checksum(v);return v
func load_state(v:Dictionary)->Dictionary:
	if typeof(v.get("states"))!=TYPE_DICTIONARY or typeof(v.get("operations"))!=TYPE_DICTIONARY or not Utils.is_json_integer(v.get("generation")) or String(v.get("checksum",""))!=U.checksum(v):return P.failure("INVALID_CONSTRUCTION_WAREHOUSE_STORE_STATE")
	for s in v.states.values():var x=State.validate(s);if not bool(x.success):return x
	_states=Dictionary(v.states).duplicate(true);_operations=Dictionary(v.operations).duplicate(true);_generation=int(v.generation);return P.success()
func _replay(id:String,payload:Dictionary)->Dictionary:
	if not _operations.has(id):return {}
	var stored:Dictionary=_operations[id];if String(stored.payload_checksum)!=Utils.payload_hash(payload):return P.failure("CONSTRUCTION_WAREHOUSE_OPERATION_ID_CONFLICT")
	var r=Dictionary(stored.result).duplicate(true);r.replay=true;return r
func _store(id:String,payload:Dictionary,result:Dictionary)->Dictionary:_operations[id]={"payload_checksum":Utils.payload_hash(payload),"result":result.duplicate(true)};return result
func _store_failure(id:String,payload:Dictionary,code:String)->Dictionary:return _store(id,payload,P.failure(code,{"replay":false}))
