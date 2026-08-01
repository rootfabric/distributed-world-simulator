extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")

var _records_by_operation_id: Dictionary = {}


func resolve(request: Dictionary) -> Dictionary:
	if not bool(RequestScript.validate(request).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_JOURNAL_REQUEST")
	var operation_id: String = String(request["operation_id"])
	if not _records_by_operation_id.has(operation_id):
		return MatterUtilsScript.success({"status": "MISS"})
	var record: Dictionary = _records_by_operation_id[operation_id]
	if String(record["request_checksum"]) != String(request["checksum"]) \
		or record["request"] != request:
		return MatterUtilsScript.failure("MATTER_OPERATION_FINGERPRINT_CONFLICT")
	return MatterUtilsScript.success({
		"status": "REPLAY",
		"result": Dictionary(record["result"]).duplicate(true),
	})


func record(request: Dictionary, result: Dictionary) -> Dictionary:
	if not bool(RequestScript.validate(request).get("success", false)) \
		or not bool(ResultScript.validate(result).get("success", false)) \
		or String(request["operation_id"]) != String(result["operation_id"]):
		return MatterUtilsScript.failure("INVALID_MATTER_JOURNAL_RECORD")
	var operation_id: String = String(request["operation_id"])
	if _records_by_operation_id.has(operation_id):
		var resolved: Dictionary = resolve(request)
		if not bool(resolved.get("success", false)):
			return resolved
		if String(resolved.get("details", {}).get("status", "")) == "REPLAY" \
			and resolved["details"]["result"] == result:
			return MatterUtilsScript.success({"status": "IDEMPOTENT"})
		return MatterUtilsScript.failure("SAME_OPERATION_MATTER_RESULT_CONFLICT")
	_records_by_operation_id[operation_id] = {
		"request_checksum": String(request["checksum"]),
		"request": request.duplicate(true),
		"result": result.duplicate(true),
	}
	return MatterUtilsScript.success({"status": "RECORDED"})


func export_persistence_state() -> Dictionary:
	var operation_ids: Array = _records_by_operation_id.keys()
	operation_ids.sort()
	var records: Array = []
	for operation_id in operation_ids:
		var record: Dictionary = _records_by_operation_id[operation_id]
		records.append({
			"operation_id": String(operation_id),
			"request": Dictionary(record["request"]).duplicate(true),
			"result": Dictionary(record["result"]).duplicate(true),
		})
	var value: Dictionary = {
		"schema": "planet_simulator.matter_mutation_journal_state.v1",
		"records": records,
		"content_hash": content_hash(),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate_persistence_state(value: Dictionary) -> Dictionary:
	var fields: Array[String] = ["schema", "records", "content_hash", "checksum"]
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, fields)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != "planet_simulator.matter_mutation_journal_state.v1" \
		or typeof(value.get("records")) != TYPE_ARRAY \
		or not MatterUtilsScript.is_lower_hex_64(value.get("content_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_JOURNAL_STATE")
	var previous_operation_id: String = ""
	var entries: Array = []
	for index in range(value["records"].size()):
		var raw = value["records"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_PERSISTED_MATTER_JOURNAL_RECORD", {"index": index})
		var record: Dictionary = Dictionary(raw)
		var record_fields: Dictionary = MatterUtilsScript.validate_exact_fields(
			record, ["operation_id", "request", "result"]
		)
		if not bool(record_fields.get("success", false)):
			return record_fields
		var request: Dictionary = PersistenceCodecScript.rehydrate_request(Dictionary(record["request"]))
		var result: Dictionary = PersistenceCodecScript.rehydrate_result(Dictionary(record["result"]))
		var operation_id: String = String(record["operation_id"])
		if request.is_empty() or result.is_empty() \
			or operation_id != String(request["operation_id"]) \
			or operation_id != String(result["operation_id"]):
			return MatterUtilsScript.failure("INVALID_PERSISTED_MATTER_JOURNAL_RECORD", {"index": index})
		if index > 0 and operation_id <= previous_operation_id:
			return MatterUtilsScript.failure("PERSISTED_MATTER_JOURNAL_NOT_SORTED_UNIQUE")
		entries.append({
			"operation_id": operation_id,
			"request_checksum": String(request["checksum"]),
			"result_checksum": String(result["checksum"]),
		})
		previous_operation_id = operation_id
	if String(value["content_hash"]) != MatterUtilsScript.payload_hash(entries):
		return MatterUtilsScript.failure("MATTER_JOURNAL_STATE_CONTENT_HASH_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_mutation_journal_state")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


func validate_restore_state(value: Dictionary) -> Dictionary:
	return validate_persistence_state(value)


func restore_persistence_state(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_restore_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var staged: Dictionary = {}
	for raw in value["records"]:
		var record: Dictionary = raw
		var request: Dictionary = PersistenceCodecScript.rehydrate_request(Dictionary(record["request"]))
		var result: Dictionary = PersistenceCodecScript.rehydrate_result(Dictionary(record["result"]))
		staged[String(record["operation_id"])] = {
			"request_checksum": String(request["checksum"]),
			"request": request,
			"result": result,
		}
	_records_by_operation_id = staged
	if content_hash() != String(value["content_hash"]):
		_records_by_operation_id.clear()
		return MatterUtilsScript.failure("MATTER_JOURNAL_RESTORE_HASH_MISMATCH")
	return MatterUtilsScript.success({"restored_records": _records_by_operation_id.size()})


func has_operation(operation_id: String) -> bool:
	return _records_by_operation_id.has(operation_id.strip_edges().to_lower())


func result_for(operation_id: String) -> Dictionary:
	var normalized_id: String = operation_id.strip_edges().to_lower()
	if not _records_by_operation_id.has(normalized_id):
		return {}
	return Dictionary(_records_by_operation_id[normalized_id]["result"]).duplicate(true)


func size() -> int:
	return _records_by_operation_id.size()


func content_hash() -> String:
	var operation_ids: Array = _records_by_operation_id.keys()
	operation_ids.sort()
	var entries: Array = []
	for operation_id in operation_ids:
		var record: Dictionary = _records_by_operation_id[operation_id]
		entries.append({
			"operation_id": String(operation_id),
			"request_checksum": String(record["request_checksum"]),
			"result_checksum": String(record["result"]["checksum"]),
		})
	return MatterUtilsScript.payload_hash(entries)
