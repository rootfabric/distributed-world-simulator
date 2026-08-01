extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")

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
