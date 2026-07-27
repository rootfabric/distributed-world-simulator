extends RefCounted

const Fingerprint = preload("res://scripts/items/services/item_operation_fingerprint.gd")

const SCHEMA: String = "planet_simulator.item_operation_ledger.v1"
const SCHEMA_VERSION: int = 1
const STATUS_SUCCEEDED: String = "SUCCEEDED"
const STATUS_REJECTED: String = "REJECTED"
const STATUS_RETRYABLE: String = "RETRYABLE"
const DEFAULT_MAXIMUM_ENTRIES: int = 2048

var records: Dictionary = {}
var next_sequence: int = 1
var maximum_entries: int = DEFAULT_MAXIMUM_ENTRIES
var content_generation: int = 0


func _init(configured_maximum_entries: int = DEFAULT_MAXIMUM_ENTRIES) -> void:
	maximum_entries = maxi(1, configured_maximum_entries)


func resolve(
	operation_id: String,
	command_type: String,
	payload_hash: String,
	aggregate_id: String,
	expected_revision: int
) -> Dictionary:
	if not records.has(operation_id):
		return {"found": false}
	var record: Dictionary = Dictionary(records[operation_id])
	if String(record.get("payload_hash", "")) == payload_hash:
		return {
			"found": true,
			"conflict": false,
			"record": record.duplicate(true),
			"result": Dictionary(record.get("result", {})).duplicate(true),
		}
	return {
		"found": true,
		"conflict": true,
		"record": record.duplicate(true),
		"result": decorate_result(
			{
				"success": false,
				"error_code": "OPERATION_ID_CONFLICT",
				"details": {
					"existing_command_type": String(record.get("command_type", "")),
					"incoming_command_type": command_type,
					"existing_payload_hash": String(record.get("payload_hash", "")),
					"incoming_payload_hash": payload_hash,
					"existing_aggregate_id": String(record.get("aggregate_id", "")),
					"incoming_aggregate_id": aggregate_id,
				},
			},
			operation_id,
			command_type,
			payload_hash,
			aggregate_id,
			expected_revision,
			-1,
			STATUS_REJECTED
		),
	}


func remember_terminal(
	operation_id: String,
	command_type: String,
	payload_hash: String,
	aggregate_id: String,
	expected_revision: int,
	result_revision: int,
	status: String,
	base_result: Dictionary
) -> Dictionary:
	assert(status == STATUS_SUCCEEDED or status == STATUS_REJECTED)
	var result: Dictionary = decorate_result(
		base_result,
		operation_id,
		command_type,
		payload_hash,
		aggregate_id,
		expected_revision,
		result_revision,
		status
	)
	var record: Dictionary = {
		"sequence": next_sequence,
		"operation_id": operation_id,
		"command_type": command_type,
		"payload_hash": payload_hash,
		"aggregate_id": aggregate_id,
		"expected_revision": expected_revision,
		"result_revision": result_revision,
		"status": status,
		"result": result.duplicate(true),
	}
	next_sequence += 1
	records[operation_id] = record
	_prune_oldest()
	_mark_content_changed()
	return result


func decorate_retryable(
	base_result: Dictionary,
	operation_id: String,
	command_type: String,
	payload_hash: String,
	aggregate_id: String,
	expected_revision: int,
	result_revision: int = -1
) -> Dictionary:
	return decorate_result(
		base_result,
		operation_id,
		command_type,
		payload_hash,
		aggregate_id,
		expected_revision,
		result_revision,
		STATUS_RETRYABLE
	)


func has_operation(operation_id: String) -> bool:
	return records.has(operation_id)


func get_record(operation_id: String) -> Dictionary:
	if not records.has(operation_id):
		return {}
	return Dictionary(records[operation_id]).duplicate(true)


func size() -> int:
	return records.size()


func get_content_generation() -> int:
	return content_generation


func clear() -> void:
	records.clear()
	next_sequence = 1
	_mark_content_changed()


func replace_from(other) -> void:
	assert(other != null)
	records = other.records.duplicate(true)
	next_sequence = int(other.next_sequence)
	maximum_entries = int(other.maximum_entries)
	_mark_content_changed()


func to_dict() -> Dictionary:
	var rows: Array = []
	var sorted_records: Array = records.values()
	sorted_records.sort_custom(func(left, right):
		return int(left.get("sequence", 0)) < int(right.get("sequence", 0))
	)
	for record_value in sorted_records:
		rows.append(Dictionary(record_value).duplicate(true))
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"maximum_entries": maximum_entries,
		"next_sequence": next_sequence,
		"records": rows,
	}


func load_dict(data: Dictionary) -> Dictionary:
	if String(data.get("schema", "")) != SCHEMA:
		return _failure("UNSUPPORTED_OPERATION_LEDGER_SCHEMA", {
			"schema": String(data.get("schema", "")),
		})
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return _failure("UNSUPPORTED_OPERATION_LEDGER_VERSION", {
			"schema_version": int(data.get("schema_version", 0)),
		})
	var raw_maximum_entries: int = int(data.get("maximum_entries", 0))
	if raw_maximum_entries < 1:
		return _failure("INVALID_OPERATION_LEDGER_LIMIT")
	var rows_value = data.get("records", [])
	if not rows_value is Array:
		return _failure("INVALID_OPERATION_LEDGER_ROWS")
	var rows: Array = rows_value
	if rows.size() > raw_maximum_entries:
		return _failure("OPERATION_LEDGER_LIMIT_EXCEEDED", {
			"record_count": rows.size(),
			"maximum_entries": raw_maximum_entries,
		})

	var next_records: Dictionary = {}
	var seen_sequences: Dictionary = {}
	var maximum_sequence: int = 0
	for row_value in rows:
		if not row_value is Dictionary:
			return _failure("INVALID_OPERATION_LEDGER_ROW")
		var canonical_value = Fingerprint.canonicalize(row_value)
		if not canonical_value is Dictionary:
			return _failure("INVALID_OPERATION_LEDGER_ROW")
		var record: Dictionary = Dictionary(canonical_value)
		var validation: Dictionary = _validate_record(record)
		if not bool(validation.get("success", false)):
			return validation
		record = _normalize_record_types(record)
		var operation_id: String = String(record.get("operation_id", ""))
		var sequence: int = int(record.get("sequence", 0))
		if next_records.has(operation_id):
			return _failure("DUPLICATE_OPERATION_ID", {
				"operation_id": operation_id,
			})
		if seen_sequences.has(sequence):
			return _failure("DUPLICATE_OPERATION_SEQUENCE", {
				"sequence": sequence,
			})
		next_records[operation_id] = record
		seen_sequences[sequence] = true
		maximum_sequence = maxi(maximum_sequence, sequence)

	var raw_next_sequence: int = int(data.get("next_sequence", 0))
	if raw_next_sequence <= maximum_sequence or raw_next_sequence < 1:
		return _failure("INVALID_NEXT_OPERATION_SEQUENCE", {
			"next_sequence": raw_next_sequence,
			"maximum_sequence": maximum_sequence,
		})

	records = next_records
	maximum_entries = raw_maximum_entries
	next_sequence = raw_next_sequence
	_mark_content_changed()
	return {
		"success": true,
		"record_count": records.size(),
		"next_sequence": next_sequence,
	}


func save_to_store(store, state_key: String = "item-operation-ledger") -> Dictionary:
	if store == null or not store.has_method("save_state"):
		return _failure("ITEM_STATE_STORE_REQUIRED")
	return store.save_state(state_key, to_dict())


func load_from_store(store, state_key: String = "item-operation-ledger") -> Dictionary:
	if store == null or not store.has_method("load_state"):
		return _failure("ITEM_STATE_STORE_REQUIRED")
	var loaded: Dictionary = store.load_state(state_key)
	if not bool(loaded.get("success", false)):
		return loaded
	var state_value = loaded.get("state", {})
	if not state_value is Dictionary:
		return _failure("INVALID_OPERATION_LEDGER_STATE")
	return load_dict(Dictionary(state_value))


static func decorate_result(
	base_result: Dictionary,
	operation_id: String,
	command_type: String,
	payload_hash: String,
	aggregate_id: String,
	expected_revision: int,
	result_revision: int,
	status: String
) -> Dictionary:
	var result: Dictionary = base_result.duplicate(true)
	result["operation_id"] = operation_id
	result["command_type"] = command_type
	result["payload_hash"] = payload_hash
	result["aggregate_id"] = aggregate_id
	result["expected_revision"] = expected_revision
	result["result_revision"] = result_revision
	result["status"] = status
	return result


func _validate_record(record: Dictionary) -> Dictionary:
	var operation_id: String = String(record.get("operation_id", ""))
	if operation_id.is_empty():
		return _failure("OPERATION_ID_REQUIRED")
	var command_type: String = String(record.get("command_type", ""))
	if command_type.is_empty():
		return _failure("COMMAND_TYPE_REQUIRED", {"operation_id": operation_id})
	var payload_hash: String = String(record.get("payload_hash", ""))
	if not Fingerprint.is_sha256_hex(payload_hash):
		return _failure("INVALID_OPERATION_PAYLOAD_HASH", {
			"operation_id": operation_id,
		})
	var aggregate_id: String = String(record.get("aggregate_id", ""))
	if aggregate_id.is_empty():
		return _failure("AGGREGATE_ID_REQUIRED", {"operation_id": operation_id})
	var expected_revision: int = int(record.get("expected_revision", -2))
	if expected_revision < -1:
		return _failure("INVALID_EXPECTED_REVISION", {
			"operation_id": operation_id,
		})
	var result_revision: int = int(record.get("result_revision", -2))
	if result_revision < -1:
		return _failure("INVALID_RESULT_REVISION", {
			"operation_id": operation_id,
		})
	var status: String = String(record.get("status", ""))
	if status != STATUS_SUCCEEDED and status != STATUS_REJECTED:
		return _failure("INVALID_OPERATION_STATUS", {
			"operation_id": operation_id,
			"status": status,
		})
	var sequence: int = int(record.get("sequence", 0))
	if sequence < 1:
		return _failure("INVALID_OPERATION_SEQUENCE", {
			"operation_id": operation_id,
		})
	var result_value = record.get("result", {})
	if not result_value is Dictionary:
		return _failure("INVALID_OPERATION_RESULT", {
			"operation_id": operation_id,
		})
	var result: Dictionary = Dictionary(result_value)
	if (
		String(result.get("operation_id", "")) != operation_id
		or String(result.get("command_type", "")) != command_type
		or String(result.get("payload_hash", "")) != payload_hash
		or String(result.get("aggregate_id", "")) != aggregate_id
		or int(result.get("expected_revision", -2)) != expected_revision
		or int(result.get("result_revision", -2)) != result_revision
		or String(result.get("status", "")) != status
	):
		return _failure("OPERATION_RESULT_METADATA_MISMATCH", {
			"operation_id": operation_id,
		})
	return {"success": true}


func _normalize_record_types(record: Dictionary) -> Dictionary:
	return Dictionary(_normalize_semantic_integers(record, ""))


func _normalize_semantic_integers(value, key_name: String):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			var name := String(key)
			result[key] = _normalize_semantic_integers(value[key], name)
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_normalize_semantic_integers(entry, key_name))
		return result
	if value is float and _is_integer_semantic_key(key_name):
		return int(value)
	return value


func _is_integer_semantic_key(key_name: String) -> bool:
	return (
		key_name == "sequence"
		or key_name == "quantity"
		or key_name.ends_with("_revision")
		or key_name.ends_with("_quantity")
		or key_name.ends_with("_count")
		or key_name.ends_with("_index")
	)


func _prune_oldest() -> void:
	while records.size() > maximum_entries:
		var oldest_id: String = ""
		var oldest_sequence: int = next_sequence
		for operation_id in records.keys():
			var sequence: int = int(Dictionary(records[operation_id]).get("sequence", 0))
			if sequence < oldest_sequence:
				oldest_sequence = sequence
				oldest_id = String(operation_id)
		if oldest_id.is_empty():
			break
		records.erase(oldest_id)


func _mark_content_changed() -> void:
	content_generation += 1


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
