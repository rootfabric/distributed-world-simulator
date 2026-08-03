extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
var _balances:Dictionary={};var _escrows:Dictionary={};var _operations:Dictionary={};var _generation:=0
func setup(balances:Dictionary)->Dictionary:
	if not U.canonical_dict(balances):return P.failure("INVALID_CONSTRUCTION_ECONOMY_LEDGER_BALANCES")
	_balances={};for id in balances.keys():
		if typeof(id)!=TYPE_STRING or not U.money(balances[id]):return P.failure("INVALID_CONSTRUCTION_ECONOMY_LEDGER_BALANCE")
		_balances[String(id)]=P.metric(float(balances[id]))
	_escrows={};_operations={};_generation=0;return P.success()
func hold(operation_id:String,escrow_id:String,payer_id:String,payee_id:String,amount:float,currency:String,metadata:Dictionary={})->Dictionary:
	var payload={"kind":"HOLD","escrow_id":escrow_id,"payer_id":payer_id,"payee_id":payee_id,"amount":P.metric(amount),"currency":currency,"metadata":metadata.duplicate(true)};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not P.path_id(operation_id,"operation/") or not P.path_id(escrow_id,"escrow/") or payer_id.is_empty() or payee_id.is_empty() or not U.money(amount) or amount<=0.0:return _store_failure(operation_id,payload,"INVALID_CONSTRUCTION_ECONOMY_ESCROW_HOLD")
	if _escrows.has(escrow_id):return _store_failure(operation_id,payload,"CONSTRUCTION_ECONOMY_ESCROW_ALREADY_EXISTS")
	if float(_balances.get(payer_id,0.0))+0.000001<amount:return _store_failure(operation_id,payload,"CONSTRUCTION_ECONOMY_INSUFFICIENT_FUNDS")
	_balances[payer_id]=P.metric(float(_balances.get(payer_id,0.0))-amount);_escrows[escrow_id]={"escrow_id":escrow_id,"payer_id":payer_id,"payee_id":payee_id,"amount":P.metric(amount),"currency":currency,"status":"HELD","metadata":metadata.duplicate(true)};_generation+=1
	return _store(operation_id,payload,P.success({"escrow":Dictionary(_escrows[escrow_id]).duplicate(true),"generation":_generation,"replay":false}))
func settle(operation_id:String,escrow_id:String)->Dictionary:
	var payload={"kind":"SETTLE","escrow_id":escrow_id};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _escrows.has(escrow_id) or String(_escrows[escrow_id].status)!="HELD":return _store_failure(operation_id,payload,"CONSTRUCTION_ECONOMY_ESCROW_NOT_HELD")
	var e:Dictionary=_escrows[escrow_id];_balances[String(e.payee_id)]=P.metric(float(_balances.get(String(e.payee_id),0.0))+float(e.amount));e.status="SETTLED";_escrows[escrow_id]=e;_generation+=1
	return _store(operation_id,payload,P.success({"escrow":e.duplicate(true),"generation":_generation,"replay":false}))
func refund(operation_id:String,escrow_id:String)->Dictionary:
	var payload={"kind":"REFUND","escrow_id":escrow_id};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _escrows.has(escrow_id) or String(_escrows[escrow_id].status)!="HELD":return _store_failure(operation_id,payload,"CONSTRUCTION_ECONOMY_ESCROW_NOT_HELD")
	var e:Dictionary=_escrows[escrow_id];_balances[String(e.payer_id)]=P.metric(float(_balances.get(String(e.payer_id),0.0))+float(e.amount));e.status="REFUNDED";_escrows[escrow_id]=e;_generation+=1
	return _store(operation_id,payload,P.success({"escrow":e.duplicate(true),"generation":_generation,"replay":false}))
func get_balance(id:String)->float:return float(_balances.get(id,0.0))
func get_escrow(id:String)->Dictionary:return Dictionary(_escrows.get(id,{})).duplicate(true)
func get_generation()->int:return _generation
func export_state()->Dictionary:
	var v={"balances":_balances.duplicate(true),"escrows":_escrows.duplicate(true),"operations":_operations.duplicate(true),"generation":_generation,"checksum":""};v.checksum=U.checksum(v);return v
func load_state(v:Dictionary)->Dictionary:
	if typeof(v.get("balances"))!=TYPE_DICTIONARY or typeof(v.get("escrows"))!=TYPE_DICTIONARY or typeof(v.get("operations"))!=TYPE_DICTIONARY or not Utils.is_json_integer(v.get("generation")):return P.failure("INVALID_CONSTRUCTION_ECONOMY_LEDGER_STATE")
	if String(v.get("checksum",""))!=U.checksum(v):return P.failure("CONSTRUCTION_ECONOMY_LEDGER_STATE_CHECKSUM_MISMATCH")
	_balances=Dictionary(v.balances).duplicate(true);_escrows=Dictionary(v.escrows).duplicate(true);_operations=Dictionary(v.operations).duplicate(true);_generation=int(v.generation);return P.success()
func _replay(id:String,payload:Dictionary)->Dictionary:
	if not _operations.has(id):return {}
	var checksum=Utils.payload_hash(payload);var stored:Dictionary=_operations[id]
	if String(stored.payload_checksum)!=checksum:return P.failure("CONSTRUCTION_ECONOMY_OPERATION_ID_CONFLICT")
	var r=Dictionary(stored.result).duplicate(true);r.replay=true;return r
func _store(id:String,payload:Dictionary,result:Dictionary)->Dictionary:_operations[id]={"payload_checksum":Utils.payload_hash(payload),"result":result.duplicate(true)};return result
func _store_failure(id:String,payload:Dictionary,code:String)->Dictionary:return _store(id,payload,P.failure(code,{"replay":false}))
