extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.world_repository_kernel_port.v1"
const DESCRIPTOR_FIELDS: Array[String] = [
	"schema", "configured", "world_id", "instance_id", "supports_flush_request",
]
const FLUSH_REQUEST_SCHEMA: String = "planet_simulator.repository_flush_request.v1"
const FLUSH_REQUEST_FIELDS: Array[String] = ["schema", "operation_id", "requested_at_tick", "world_id", "instance_id"]
const REPOSITORY_FIELDS: Array[String] = [
	"schema", "initialized", "world_id", "universe_id", "instance_id",
	"partition_space_id", "partition_scheme", "partition_scheme_revision",
	"partition_grid", "world_root", "manifest_path", "journal_path",
	"landmark_index_path", "landmark_count", "landmark_marker_node_count",
	"landmark_markers_enabled", "landmark_marker_max_distance_m",
	"landmark_index_rebuilt", "loaded_chunk_count", "runtime_node_count",
	"persistent_entity_count", "dirty_chunks", "chunk_load_count",
	"chunk_unload_count", "last_save_summary", "last_player_world_position",
]

var repository_snapshot: Dictionary = {}
var configured: bool = false


func setup(snapshot_value: Dictionary) -> Dictionary:
	return refresh(snapshot_value)


func refresh(snapshot_value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_repository_snapshot(snapshot_value)
	if not bool(validation.get("success", false)):
		return validation
	var safe: Dictionary = UtilsScript.canonicalize(snapshot_value)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_REPOSITORY_SNAPSHOT", {"message": safe.get("error", "")})
	repository_snapshot = safe["value"]
	configured = true
	return {"success": true}


static func validate_repository_snapshot(value: Dictionary) -> Dictionary:
	var fields: Dictionary = UtilsScript.validate_exact_fields(value, REPOSITORY_FIELDS)
	if not bool(fields.get("success", false)):
		return fields
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != "lunar.persistence_runtime.v1":
		return _static_failure("UNSUPPORTED_REPOSITORY_SCHEMA")
	if typeof(value.get("initialized")) != TYPE_BOOL:
		return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "initialized"})
	for field in [
		"world_id", "universe_id", "instance_id", "partition_space_id",
		"partition_scheme", "world_root", "manifest_path", "journal_path",
		"landmark_index_path", "last_save_summary",
	]:
		if typeof(value.get(field)) != TYPE_STRING:
			return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": field})
	for required_field in ["world_id", "universe_id", "instance_id", "partition_space_id", "partition_scheme"]:
		if String(value[required_field]).is_empty():
			return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": required_field})
	for counter_field in [
		"partition_scheme_revision", "landmark_count", "landmark_marker_node_count",
		"loaded_chunk_count", "runtime_node_count", "persistent_entity_count",
		"chunk_load_count", "chunk_unload_count",
	]:
		if not UtilsScript.is_json_integer(value.get(counter_field)) or int(value[counter_field]) < 0:
			return _static_failure("INVALID_REPOSITORY_COUNTER", {"field": counter_field})
	if int(value["partition_scheme_revision"]) < 1:
		return _static_failure("INVALID_REPOSITORY_COUNTER", {"field": "partition_scheme_revision"})
	for bool_field in ["landmark_markers_enabled", "landmark_index_rebuilt"]:
		if typeof(value.get(bool_field)) != TYPE_BOOL:
			return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": bool_field})
	if typeof(value.get("partition_grid")) != TYPE_DICTIONARY:
		return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "partition_grid"})
	var marker_distance = value.get("landmark_marker_max_distance_m")
	if typeof(marker_distance) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(marker_distance)) or float(marker_distance) < 0.0:
		return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "landmark_marker_max_distance_m"})
	if typeof(value.get("dirty_chunks")) != TYPE_ARRAY:
		return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "dirty_chunks"})
	var seen_chunks: Dictionary = {}
	for chunk_value in value["dirty_chunks"]:
		if typeof(chunk_value) != TYPE_STRING or String(chunk_value).is_empty():
			return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "dirty_chunks"})
		if seen_chunks.has(chunk_value):
			return _static_failure("DUPLICATE_DIRTY_CHUNK")
		seen_chunks[chunk_value] = true
	if typeof(value.get("last_player_world_position")) != TYPE_ARRAY or value["last_player_world_position"].size() != 3:
		return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "last_player_world_position"})
	for coordinate in value["last_player_world_position"]:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
			return _static_failure("INVALID_REPOSITORY_SNAPSHOT", {"field": "last_player_world_position"})
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return _static_failure("NON_CANONICAL_REPOSITORY_SNAPSHOT", {"message": safe.get("error", "")})
	return {"success": true}


func create_repository_snapshot() -> Dictionary:
	if not configured:
		return _failure("PORT_NOT_CONFIGURED")
	return {"success": true, "snapshot": repository_snapshot.duplicate(true)}


func create_flush_request(operation_id: String, requested_at_tick: int) -> Dictionary:
	if not configured:
		return _failure("PORT_NOT_CONFIGURED")
	var value: Dictionary = {
		"schema": FLUSH_REQUEST_SCHEMA,
		"operation_id": operation_id,
		"requested_at_tick": requested_at_tick,
		"world_id": String(repository_snapshot["world_id"]),
		"instance_id": String(repository_snapshot["instance_id"]),
	}
	var validation: Dictionary = validate_flush_request(value)
	if not bool(validation.get("success", false)):
		return validation
	return {"success": true, "request": value}


func validate_flush_request(value: Dictionary) -> Dictionary:
	var fields: Dictionary = UtilsScript.validate_exact_fields(value, FLUSH_REQUEST_FIELDS)
	if not bool(fields.get("success", false)):
		return fields
	if String(value.get("schema", "")) != FLUSH_REQUEST_SCHEMA:
		return _failure("UNSUPPORTED_FLUSH_REQUEST_SCHEMA")
	for field in ["operation_id", "world_id", "instance_id"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).is_empty():
			return _failure("INVALID_FLUSH_REQUEST", {"field": field})
	if not UtilsScript.is_json_integer(value.get("requested_at_tick")) or int(value["requested_at_tick"]) < 0:
		return _failure("INVALID_FLUSH_REQUEST_TICK")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_FLUSH_REQUEST")
	return {"success": true}


func create_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": configured,
		"world_id": String(repository_snapshot.get("world_id", "")),
		"instance_id": String(repository_snapshot.get("instance_id", "")),
		"supports_flush_request": configured,
	}


func validate_contract_state() -> Dictionary:
	var descriptor_validation: Dictionary = validate_descriptor(create_descriptor())
	if not bool(descriptor_validation.get("success", false)):
		return descriptor_validation
	if not configured:
		return _failure("PORT_NOT_CONFIGURED")
	var snapshot_validation: Dictionary = validate_repository_snapshot(repository_snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	return {"success": true}


static func validate_descriptor(value: Dictionary) -> Dictionary:
	var fields: Dictionary = UtilsScript.validate_exact_fields(value, DESCRIPTOR_FIELDS)
	if not bool(fields.get("success", false)):
		return fields
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _static_failure("UNSUPPORTED_PORT_SCHEMA")
	if typeof(value.get("configured")) != TYPE_BOOL:
		return _static_failure("INVALID_PORT_DESCRIPTOR", {"field": "configured"})
	if typeof(value.get("supports_flush_request")) != TYPE_BOOL:
		return _static_failure("INVALID_PORT_DESCRIPTOR", {"field": "supports_flush_request"})
	for field in ["world_id", "instance_id"]:
		if typeof(value.get(field)) != TYPE_STRING:
			return _static_failure("INVALID_PORT_DESCRIPTOR", {"field": field})
	if bool(value["configured"]):
		if not bool(value["supports_flush_request"]):
			return _static_failure("INVALID_PORT_DESCRIPTOR", {"field": "supports_flush_request"})
		if String(value["world_id"]).is_empty() or String(value["instance_id"]).is_empty():
			return _static_failure("INVALID_PORT_DESCRIPTOR", {"field": "identity"})
	else:
		if bool(value["supports_flush_request"]) or not String(value["world_id"]).is_empty() or not String(value["instance_id"]).is_empty():
			return _static_failure("INVALID_PORT_DESCRIPTOR", {"field": "unconfigured_state"})
	return {"success": true}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}


static func _static_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
