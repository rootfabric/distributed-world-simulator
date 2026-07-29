extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")

const SCHEMA: String = "planet_simulator.aggregate_delta_envelope.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"delta_id",
	"aggregate_id",
	"aggregate_kind",
	"state_schema",
	"authority_owner_id",
	"authority_epoch",
	"base_revision",
	"result_revision",
	"server_tick",
	"changed_fields",
	"removed_fields",
	"checksum",
]


static func create(
	delta_id: String,
	aggregate_id: String,
	aggregate_kind: String,
	state_schema: String,
	authority_owner_id: String,
	authority_epoch: int,
	base_revision: int,
	result_revision: int,
	server_tick: int,
	changed_fields: Dictionary,
	removed_fields: Array = []
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"delta_id": delta_id,
		"aggregate_id": aggregate_id,
		"aggregate_kind": aggregate_kind,
		"state_schema": state_schema,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"base_revision": base_revision,
		"result_revision": result_revision,
		"server_tick": server_tick,
		"changed_fields": changed_fields.duplicate(true),
		"removed_fields": removed_fields.duplicate(),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_DELTA_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return _failure("UNSUPPORTED_AGGREGATE_DELTA_PROTOCOL")
	for field in ["delta_id", "aggregate_id", "aggregate_kind", "state_schema", "authority_owner_id", "checksum"]:
		var check: Dictionary = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	for field in ["authority_epoch", "base_revision", "result_revision", "server_tick"]:
		var integer_check: Dictionary = UtilsScript.require_json_integer(value, field)
		if not bool(integer_check.get("success", false)):
			return integer_check
	if int(value["authority_epoch"]) < 1 or int(value["base_revision"]) < 0 or int(value["result_revision"]) <= int(value["base_revision"]) or int(value["server_tick"]) < 0:
		return _failure("INVALID_AGGREGATE_DELTA_COUNTERS")
	if typeof(value.get("changed_fields")) != TYPE_DICTIONARY or typeof(value.get("removed_fields")) != TYPE_ARRAY:
		return _failure("INVALID_AGGREGATE_DELTA_PATCH")
	var seen_paths: Dictionary = {}
	for raw_path in value["changed_fields"].keys():
		if typeof(raw_path) != TYPE_STRING or not _valid_path(String(raw_path)):
			return _failure("INVALID_AGGREGATE_DELTA_PATH")
		seen_paths[String(raw_path)] = true
	for raw_path in value["removed_fields"]:
		if typeof(raw_path) != TYPE_STRING or not _valid_path(String(raw_path)) or seen_paths.has(String(raw_path)):
			return _failure("INVALID_AGGREGATE_DELTA_PATH")
		seen_paths[String(raw_path)] = true
	var paths: Array = seen_paths.keys()
	for first_index in range(paths.size()):
		for second_index in range(first_index + 1, paths.size()):
			if _overlap(String(paths[first_index]), String(paths[second_index])):
				return _failure("OVERLAPPING_AGGREGATE_DELTA_PATHS")
	var safe: Dictionary = UtilsScript.canonicalize(value, "$.aggregate_delta")
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_AGGREGATE_DELTA")
	if not _is_lower_hex_64(String(value["checksum"])) or String(value["checksum"]) != compute_checksum(value):
		return _failure("AGGREGATE_DELTA_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()


static func apply_to_snapshot(snapshot_value: Dictionary, delta_value: Dictionary) -> Dictionary:
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot_value)
	if not bool(snapshot_validation.get("success", false)):
		return _failure_result("INVALID_BASE_AGGREGATE_SNAPSHOT")
	var delta_validation: Dictionary = validate(delta_value)
	if not bool(delta_validation.get("success", false)):
		return _failure_result(String(delta_validation.get("error_code", "INVALID_AGGREGATE_DELTA")))
	var descriptor: Dictionary = snapshot_value["descriptor"]
	var identity: Dictionary = descriptor["identity"]
	var authority: Dictionary = descriptor["authority"]
	if String(delta_value["aggregate_id"]) != String(identity["aggregate_id"]):
		return _failure_result("AGGREGATE_ID_MISMATCH")
	if String(delta_value["aggregate_kind"]) != String(identity["aggregate_kind"]):
		return _failure_result("AGGREGATE_KIND_MISMATCH")
	if String(delta_value["state_schema"]) != String(identity["state_schema"]):
		return _failure_result("AGGREGATE_STATE_SCHEMA_MISMATCH")
	if String(delta_value["authority_owner_id"]) != String(authority["authority_owner_id"]):
		return _failure_result("AGGREGATE_AUTHORITY_OWNER_MISMATCH")
	if int(delta_value["authority_epoch"]) != int(authority["authority_epoch"]):
		return _failure_result("STALE_AGGREGATE_AUTHORITY_EPOCH")
	if int(delta_value["base_revision"]) != int(authority["state_revision"]):
		return _failure_result("AGGREGATE_REVISION_CONFLICT")
	if int(delta_value["server_tick"]) < int(authority["server_tick"]):
		return _failure_result("STALE_AGGREGATE_SERVER_TICK")
	var output: Dictionary = snapshot_value.duplicate(true)
	var state: Dictionary = output["state"]
	for path_value in delta_value["removed_fields"]:
		if not _erase_path(state, String(path_value)):
			return _failure_result("AGGREGATE_DELTA_REMOVE_FAILED")
	for path_value in delta_value["changed_fields"].keys():
		if not _set_path(state, String(path_value), delta_value["changed_fields"][path_value]):
			return _failure_result("AGGREGATE_DELTA_SET_FAILED")
	output["descriptor"]["authority"]["state_revision"] = int(delta_value["result_revision"])
	output["descriptor"]["authority"]["server_tick"] = int(delta_value["server_tick"])
	output["checksum"] = SnapshotScript.compute_checksum(output)
	if not bool(DescriptorScript.validate(output["descriptor"]).get("success", false)):
		return _failure_result("INVALID_RESULT_AGGREGATE_DESCRIPTOR")
	var result_validation: Dictionary = SnapshotScript.validate(output)
	if not bool(result_validation.get("success", false)):
		return _failure_result("INVALID_RESULT_AGGREGATE_SNAPSHOT")
	return {"success": true, "error_code": "", "snapshot": SnapshotScript.normalize(output)}


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _valid_path(path: String) -> bool:
	if path.is_empty() or path != path.strip_edges() or path.begins_with(".") or path.ends_with("."):
		return false
	for segment in path.split(".", true):
		if segment.strip_edges().is_empty() or segment != segment.strip_edges():
			return false
	return true


static func _overlap(first: String, second: String) -> bool:
	return first == second or first.begins_with(second + ".") or second.begins_with(first + ".")


static func _erase_path(target: Dictionary, path: String) -> bool:
	var parts: PackedStringArray = path.split(".", true)
	var current: Dictionary = target
	for index in range(parts.size() - 1):
		if typeof(current.get(parts[index])) != TYPE_DICTIONARY:
			return false
		current = current[parts[index]]
	var leaf: String = parts[parts.size() - 1]
	if not current.has(leaf):
		return false
	current.erase(leaf)
	return true


static func _set_path(target: Dictionary, path: String, value) -> bool:
	var parts: PackedStringArray = path.split(".", true)
	var current: Dictionary = target
	for index in range(parts.size() - 1):
		var segment: String = parts[index]
		if not current.has(segment):
			current[segment] = {}
		if typeof(current[segment]) != TYPE_DICTIONARY:
			return false
		current = current[segment]
	current[parts[parts.size() - 1]] = value
	return true


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)


static func _failure_result(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "snapshot": {}}
