extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

const SCHEMA: String = "planet_simulator.entity_delta_envelope.v1"
const PROTOCOL_VERSION: int = 1
const PROTECTED_FIELDS: Array[String] = [
	"schema", "protocol_version", "snapshot_id", "delta_id", "entity_id",
	"entity_type", "authority_owner_id", "authority_epoch", "state_revision",
	"base_revision", "result_revision", "simulation_tick", "server_tick", "checksum",
]
const MUTABLE_ROOTS: Array[String] = [
	"spatial_ref", "partition_address", "physics_state", "domain_components",
]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"delta_id",
	"entity_id",
	"entity_type",
	"base_revision",
	"result_revision",
	"authority_owner_id",
	"authority_epoch",
	"server_tick",
	"changed_fields",
	"removed_fields",
	"checksum",
]


static func create(
	delta_id: String,
	entity_id: String,
	entity_type: String,
	base_revision: int,
	result_revision: int,
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int,
	changed_fields: Dictionary,
	removed_fields: Array[String] = []
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"delta_id": delta_id,
		"entity_id": entity_id,
		"entity_type": entity_type,
		"base_revision": base_revision,
		"result_revision": result_revision,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"server_tick": server_tick,
		"changed_fields": changed_fields.duplicate(true),
		"removed_fields": Array(removed_fields).duplicate(),
		"checksum": "",
	}
	value["removed_fields"].sort()
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	check = _validate_header(value)
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_dictionary(value, "changed_fields")
	if not bool(check.get("success", false)):
		return check
	check = _validate_removed_fields(value.get("removed_fields"))
	if not bool(check.get("success", false)):
		return check
	var changed: Dictionary = value["changed_fields"]
	var removed: Array = value["removed_fields"]
	if changed.is_empty() and removed.is_empty():
		return UtilsScript.validation_failure("EMPTY_DELTA", "Delta must change or remove at least one field")
	var changed_paths: Array[String] = []
	for field_value in changed.keys():
		if typeof(field_value) != TYPE_STRING or String(field_value).strip_edges().is_empty():
			return UtilsScript.validation_failure("INVALID_DELTA_FIELD", "changed_fields keys must be non-empty Strings")
		var changed_path: String = String(field_value)
		var path_validation: Dictionary = _validate_mutable_path(changed_path, false)
		if not bool(path_validation.get("success", false)):
			return path_validation
		changed_paths.append(changed_path)
	var removed_paths: Array[String] = []
	for field in removed:
		var removed_path: String = String(field)
		var path_validation: Dictionary = _validate_mutable_path(removed_path, true)
		if not bool(path_validation.get("success", false)):
			return path_validation
		removed_paths.append(removed_path)
	var all_paths: Array[String] = []
	all_paths.append_array(changed_paths)
	all_paths.append_array(removed_paths)
	for first_index in range(all_paths.size()):
		for second_index in range(first_index + 1, all_paths.size()):
			if _paths_overlap(all_paths[first_index], all_paths[second_index]):
				return UtilsScript.validation_failure("DELTA_FIELD_CONFLICT", "Delta paths cannot overlap")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	if not _is_lower_hex_64(String(value["checksum"])):
		return UtilsScript.validation_failure("INVALID_CHECKSUM", "checksum must be lowercase SHA-256")
	if String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Delta checksum does not match payload")
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var canonical: Dictionary = value.duplicate(true)
	canonical["removed_fields"] = Array(canonical["removed_fields"]).duplicate()
	canonical["removed_fields"].sort()
	canonical["checksum"] = compute_checksum(canonical)
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	var removed_value = payload.get("removed_fields", [])
	if removed_value is Array:
		payload["removed_fields"] = Array(removed_value).duplicate()
		payload["removed_fields"].sort()
	return UtilsScript.payload_hash(payload)


static func apply_to_snapshot(snapshot: Dictionary, delta: Dictionary) -> Dictionary:
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return {
			"success": false,
			"error_code": "INVALID_BASE_SNAPSHOT",
			"validation_error_code": String(snapshot_validation.get("error_code", "")),
			"snapshot": {},
		}
	var validation: Dictionary = validate(delta)
	if not bool(validation.get("success", false)):
		return {"success": false, "error_code": validation.get("error_code", "INVALID_DELTA"), "snapshot": {}}
	if String(snapshot.get("entity_id", "")) != String(delta["entity_id"]):
		return {"success": false, "error_code": "ENTITY_ID_MISMATCH", "snapshot": {}}
	if String(snapshot.get("entity_type", "")) != String(delta["entity_type"]):
		return {"success": false, "error_code": "ENTITY_TYPE_MISMATCH", "snapshot": {}}
	if not UtilsScript.is_json_integer(snapshot.get("state_revision")) or int(snapshot["state_revision"]) != int(delta["base_revision"]):
		return {"success": false, "error_code": "BASE_REVISION_MISMATCH", "snapshot": {}}
	if not UtilsScript.is_json_integer(snapshot.get("authority_epoch")) or int(snapshot["authority_epoch"]) != int(delta["authority_epoch"]):
		return {"success": false, "error_code": "STALE_AUTHORITY_EPOCH", "snapshot": {}}
	var output: Dictionary = snapshot.duplicate(true)
	var removals: Array = Array(delta["removed_fields"]).duplicate()
	removals.sort_custom(func(first, second): return String(first).count(".") > String(second).count("."))
	for field_value in removals:
		if not _erase_path(output, String(field_value)):
			return {"success": false, "error_code": "DELTA_PATH_NOT_FOUND", "snapshot": {}}
	var changes: Array = delta["changed_fields"].keys()
	changes.sort_custom(func(first, second): return String(first).count(".") < String(second).count("."))
	for field_value in changes:
		if not _set_path(output, String(field_value), delta["changed_fields"][field_value]):
			return {"success": false, "error_code": "INVALID_DELTA_PATH", "snapshot": {}}
	output["state_revision"] = int(delta["result_revision"])
	output["authority_owner_id"] = String(delta["authority_owner_id"])
	output["authority_epoch"] = int(delta["authority_epoch"])
	output["server_tick"] = int(delta["server_tick"])
	output["checksum"] = SnapshotScript.compute_checksum(output)
	var output_validation: Dictionary = SnapshotScript.validate(output)
	if not bool(output_validation.get("success", false)):
		return {
			"success": false,
			"error_code": "INVALID_RESULT_SNAPSHOT",
			"validation_error_code": String(output_validation.get("error_code", "")),
			"snapshot": {},
		}
	return {"success": true, "error_code": "", "snapshot": SnapshotScript.normalize(output)}


static func _validate_mutable_path(path: String, removal: bool) -> Dictionary:
	var parts: PackedStringArray = path.split(".", false)
	if parts.is_empty() or not MUTABLE_ROOTS.has(parts[0]):
		return UtilsScript.validation_failure("PROTECTED_DELTA_FIELD", "Delta path must start with a mutable snapshot field")
	if removal and parts.size() < 2:
		return UtilsScript.validation_failure("PROTECTED_DELTA_FIELD", "Required snapshot roots cannot be removed")
	for part in parts:
		if part.strip_edges().is_empty() or part != part.strip_edges():
			return UtilsScript.validation_failure("INVALID_DELTA_FIELD", "Delta path segments must be non-empty canonical Strings")
	return UtilsScript.validation_success()


static func _paths_overlap(first: String, second: String) -> bool:
	return first == second or first.begins_with(second + ".") or second.begins_with(first + ".")


static func _erase_path(target: Dictionary, path: String) -> bool:
	var parts: PackedStringArray = path.split(".", false)
	var current: Dictionary = target
	for index in range(parts.size() - 1):
		var segment: String = parts[index]
		if typeof(current.get(segment)) != TYPE_DICTIONARY:
			return false
		current = current[segment]
	var leaf: String = parts[parts.size() - 1]
	if not current.has(leaf):
		return false
	current.erase(leaf)
	return true


static func _set_path(target: Dictionary, path: String, value) -> bool:
	var parts: PackedStringArray = path.split(".", false)
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


static func _validate_header(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected entity delta schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	for field in ["delta_id", "entity_id", "entity_type", "authority_owner_id", "checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	for field in ["base_revision", "result_revision", "authority_epoch", "server_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["base_revision"]) < 0 or int(value["result_revision"]) <= int(value["base_revision"]):
		return UtilsScript.validation_failure("INVALID_REVISION_RANGE", "result_revision must be greater than base_revision")
	if int(value["authority_epoch"]) < 1 or int(value["server_tick"]) < 0:
		return UtilsScript.validation_failure("INVALID_COUNTER", "authority_epoch must be positive and server_tick non-negative")
	return UtilsScript.validation_success()


static func _validate_removed_fields(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "removed_fields must be an Array")
	var seen: Dictionary = {}
	for field_value in value:
		if typeof(field_value) != TYPE_STRING or String(field_value).strip_edges().is_empty():
			return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "removed_fields must contain non-empty Strings")
		if seen.has(field_value):
			return UtilsScript.validation_failure("DUPLICATE_FIELD", "removed_fields must be unique")
		seen[field_value] = true
	return UtilsScript.validation_success()


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true
