extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.m6_durable_replay_outbox.v1"
const MAX_OUTBOX_RECORDS := 2048

var _service
var _next_sequence := 1
var _records: Array = []


func setup(service_reference) -> Dictionary:
	if service_reference == null:
		return _failure("M6_REPLAY_GAMEPLAY_SERVICE_REQUIRED")
	for method_name in [
		"export_replay_state", "restore_replay_state", "validate_replay_state",
		"has_durable_replay_operation", "get_report",
	]:
		if not service_reference.has_method(method_name):
			return _failure("M6_REPLAY_GAMEPLAY_METHOD_MISSING", {"method": method_name})
	_service = service_reference
	_next_sequence = 1
	_records.clear()
	return _success()


func stage_committed(operation_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	if _service == null:
		return _failure("M6_REPLAY_OUTBOX_NOT_CONFIGURED")
	var normalized_operation := operation_id.strip_edges()
	var normalized_type := command_type.strip_edges().to_upper()
	if not _is_canonical_id(normalized_operation) or normalized_type.is_empty():
		return _failure("INVALID_M6_OUTBOX_OPERATION")
	if not bool(_service.has_durable_replay_operation(normalized_operation)):
		return _failure("M6_OUTBOX_OPERATION_NOT_REPLAY_DURABLE", {"operation_id": normalized_operation})
	var safe := Utils.canonicalize(payload, "$.m6_outbox_payload")
	if not bool(safe.get("success", false)):
		return _failure("M6_OUTBOX_PAYLOAD_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	var payload_round_trip: Dictionary = Utils.json_round_trip(payload)
	if not bool(payload_round_trip.get("success", false)) or not payload_round_trip.get("value") is Dictionary:
		return _failure("M6_OUTBOX_PAYLOAD_NOT_JSON_SAFE", {"message": String(payload_round_trip.get("error", ""))})
	var stable_payload: Dictionary = Dictionary(payload_round_trip.get("value", {})).duplicate(true)
	for record_value in _records:
		if String(Dictionary(record_value).get("operation_id", "")) == normalized_operation:
			return _failure("M6_OUTBOX_OPERATION_ALREADY_STAGED", {"operation_id": normalized_operation})
	_prune_for_new_record()
	if _records.size() >= MAX_OUTBOX_RECORDS:
		return _failure("M6_OUTBOX_CAPACITY_EXCEEDED")
	var report: Dictionary = _service.get_report()
	var record: Dictionary = {
		"sequence": _next_sequence,
		"operation_id": normalized_operation,
		"command_type": normalized_type,
		"state": "COMMITTED",
		"committed_at_tick": int(report.get("server_tick", 0)),
		"service_revision": int(report.get("revision", 0)),
		"delivery_attempts": 0,
		"delivered": false,
		"payload": stable_payload,
		"payload_checksum": Utils.payload_hash(stable_payload),
	}
	_next_sequence += 1
	_records.append(record)
	_prune()
	return _success({"record": record.duplicate(true)})


func mark_delivered(sequence: int) -> Dictionary:
	for index in range(_records.size()):
		var record: Dictionary = _records[index]
		if int(record.get("sequence", 0)) != sequence:
			continue
		if bool(record.get("delivered", false)):
			return _success({"record": record.duplicate(true), "replay": true})
		record["delivery_attempts"] = int(record.get("delivery_attempts", 0)) + 1
		record["delivered"] = true
		record["state"] = "DELIVERED"
		_records[index] = record
		return _success({"record": record.duplicate(true)})
	return _failure("M6_OUTBOX_RECORD_NOT_FOUND", {"sequence": sequence})


func mark_delivery_attempt(sequence: int) -> Dictionary:
	for index in range(_records.size()):
		var record: Dictionary = _records[index]
		if int(record.get("sequence", 0)) != sequence:
			continue
		record["delivery_attempts"] = int(record.get("delivery_attempts", 0)) + 1
		_records[index] = record
		return _success({"record": record.duplicate(true)})
	return _failure("M6_OUTBOX_RECORD_NOT_FOUND", {"sequence": sequence})


func get_record(sequence: int) -> Dictionary:
	for record_value in _records:
		var record: Dictionary = record_value
		if int(record.get("sequence", 0)) == sequence:
			return record.duplicate(true)
	return {}


func get_records() -> Array:
	return _records.duplicate(true)


func get_record_for_operation(operation_id: String) -> Dictionary:
	for record_value in _records:
		var record: Dictionary = record_value
		if String(record.get("operation_id", "")) == operation_id:
			return record.duplicate(true)
	return {}


func get_pending_records() -> Array:
	var result: Array = []
	for record_value in _records:
		var record: Dictionary = record_value
		if not bool(record.get("delivered", false)):
			result.append(record.duplicate(true))
	return result


func to_dict() -> Dictionary:
	if _service == null:
		return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"next_sequence": _next_sequence,
		"gameplay_replay": _service.export_replay_state(),
		"committed_outbox": get_records(),
		"checksum": "",
	}
	return Utils.finalize_json_checksum(value)


func load_dict(value: Dictionary, _current_tick: int = -1) -> Dictionary:
	if _service == null:
		return _failure("M6_REPLAY_OUTBOX_NOT_CONFIGURED")
	var validation := validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var restored: Dictionary = _service.restore_replay_state(Dictionary(value.get("gameplay_replay", {})))
	if not bool(restored.get("success", false)):
		return _failure("M6_GAMEPLAY_REPLAY_RESTORE_FAILED", {"cause": restored})
	_next_sequence = int(value.get("next_sequence", 1))
	_records = Array(value.get("committed_outbox", [])).duplicate(true)
	return _success({
		"next_sequence": _next_sequence,
		"outbox_count": _records.size(),
		"pending_count": get_pending_records().size(),
		"gameplay_replay": restored.get("details", {}),
	})


func validate(value: Dictionary) -> Dictionary:
	if _service == null:
		return _failure("M6_REPLAY_OUTBOX_NOT_CONFIGURED")
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("INVALID_M6_REPLAY_OUTBOX_SCHEMA")
	if int(value.get("next_sequence", 0)) < 1 or typeof(value.get("committed_outbox")) != TYPE_ARRAY:
		return _failure("INVALID_M6_REPLAY_OUTBOX_STATE")
	if Array(value.get("committed_outbox", [])).size() > MAX_OUTBOX_RECORDS:
		return _failure("M6_OUTBOX_CAPACITY_EXCEEDED")
	if typeof(value.get("gameplay_replay")) != TYPE_DICTIONARY:
		return _failure("INVALID_M6_GAMEPLAY_REPLAY_SECTION")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _checksum(value):
		return _failure("M6_REPLAY_OUTBOX_CHECKSUM_MISMATCH")
	var gameplay_validation: Dictionary = _service.validate_replay_state(Dictionary(value.get("gameplay_replay", {})))
	if not bool(gameplay_validation.get("success", false)):
		return _failure("INVALID_M6_GAMEPLAY_REPLAY_SECTION", {"cause": gameplay_validation})
	var previous_sequence := 0
	var operation_ids: Dictionary = {}
	for record_value in value.get("committed_outbox", []):
		if not record_value is Dictionary:
			return _failure("INVALID_M6_OUTBOX_RECORD")
		var record: Dictionary = record_value
		var sequence := int(record.get("sequence", 0))
		if sequence <= previous_sequence or sequence >= int(value.get("next_sequence", 1)):
			return _failure("INVALID_M6_OUTBOX_SEQUENCE")
		var operation_id := String(record.get("operation_id", ""))
		var command_type := String(record.get("command_type", ""))
		if not _is_canonical_id(operation_id) or command_type.strip_edges().is_empty() or command_type != command_type.to_upper():
			return _failure("INVALID_M6_OUTBOX_RECORD")
		if operation_ids.has(operation_id):
			return _failure("DUPLICATE_M6_OUTBOX_OPERATION")
		if not _replay_state_has_operation(Dictionary(value.get("gameplay_replay", {})), operation_id):
			return _failure("M6_OUTBOX_OPERATION_NOT_REPLAY_DURABLE", {"operation_id": operation_id})
		operation_ids[operation_id] = true
		if int(record.get("committed_at_tick", -1)) < 0 or int(record.get("service_revision", -1)) < 0:
			return _failure("INVALID_M6_OUTBOX_REVISION")
		if String(record.get("state", "")) not in ["COMMITTED", "DELIVERED"]:
			return _failure("INVALID_M6_OUTBOX_STATE")
		if typeof(record.get("delivered")) != TYPE_BOOL or int(record.get("delivery_attempts", -1)) < 0:
			return _failure("INVALID_M6_OUTBOX_DELIVERY_STATE")
		if bool(record.get("delivered", false)) != (String(record.get("state", "")) == "DELIVERED"):
			return _failure("M6_OUTBOX_DELIVERY_STATE_MISMATCH")
		if bool(record.get("delivered", false)) and int(record.get("delivery_attempts", 0)) < 1:
			return _failure("M6_OUTBOX_DELIVERY_ATTEMPT_MISSING")
		if typeof(record.get("payload")) != TYPE_DICTIONARY:
			return _failure("INVALID_M6_OUTBOX_PAYLOAD")
		if String(record.get("payload_checksum", "")) != Utils.payload_hash(record.get("payload", {})):
			return _failure("M6_OUTBOX_PAYLOAD_CHECKSUM_MISMATCH")
		previous_sequence = sequence
	var safe := Utils.canonicalize(value, "$.m6_replay_outbox")
	if not bool(safe.get("success", false)):
		return _failure("M6_REPLAY_OUTBOX_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success({"outbox_count": value.get("committed_outbox", []).size()})


func get_report() -> Dictionary:
	var delivered := 0
	for record_value in _records:
		if bool(record_value.get("delivered", false)):
			delivered += 1
	return {
		"schema": SCHEMA,
		"next_sequence": _next_sequence,
		"outbox_count": _records.size(),
		"delivered_count": delivered,
		"pending_count": _records.size() - delivered,
		"checksum": String(to_dict().get("checksum", "")) if _service != null else "",
	}


func _replay_state_has_operation(replay_state: Dictionary, operation_id: String) -> bool:
	var service_ledger_value = replay_state.get("service_operation_ledger", {})
	if service_ledger_value is Dictionary and Dictionary(service_ledger_value).has(operation_id):
		return true
	var item_replay_value = replay_state.get("item_graph_replay", {})
	if not item_replay_value is Dictionary:
		return false
	var item_records_value = Dictionary(item_replay_value).get("records", {})
	return item_records_value is Dictionary and Dictionary(item_records_value).has(operation_id)


func _prune_for_new_record() -> void:
	while _records.size() >= MAX_OUTBOX_RECORDS:
		var removable_index := -1
		for index in range(_records.size()):
			if bool(_records[index].get("delivered", false)):
				removable_index = index
				break
		if removable_index < 0:
			break
		_records.remove_at(removable_index)


func _prune() -> void:
	while _records.size() > MAX_OUTBOX_RECORDS:
		var removable_index := -1
		for index in range(_records.size()):
			if bool(_records[index].get("delivered", false)):
				removable_index = index
				break
		if removable_index < 0:
			break
		_records.remove_at(removable_index)


func _is_canonical_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character in ["/", "_", ".", "-"]
		):
			return false
	return true


func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
