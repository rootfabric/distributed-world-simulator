extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.entity_registry_kernel_port.v1"
const REGISTRY_FIELDS: Array[String] = [
	"schema", "authority_owner_id", "authority_epoch", "entity_count",
	"migration_count", "chunk_transition_count", "zone_transition_count",
	"stale_write_rejection_count", "entities",
]
const ENTITY_FIELDS: Array[String] = [
	"schema", "entity_id", "entity_type", "spatial_ref", "partition_address",
	"zone_id", "chunk_id", "world_position", "components",
	"authority_owner_id", "authority_epoch", "state_revision", "revision",
	"last_simulation_tick", "created_at_utc", "updated_at_utc",
]

var registry_snapshot: Dictionary = {}
var configured: bool = false


func setup(snapshot_value: Dictionary) -> Dictionary:
	return refresh(snapshot_value)


func refresh(snapshot_value: Dictionary) -> Dictionary:
	var staged: Dictionary = snapshot_value.duplicate(true)
	var validation: Dictionary = _validate_registry_snapshot(staged)
	if not bool(validation.get("success", false)):
		return validation
	var safe: Dictionary = UtilsScript.canonicalize(staged)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_REGISTRY_SNAPSHOT", {"message": safe.get("error", "")})
	registry_snapshot = safe["value"]
	configured = true
	return {"success": true, "entity_count": int(registry_snapshot["entity_count"])}


func create_registry_snapshot() -> Dictionary:
	if not configured:
		return _failure("PORT_NOT_CONFIGURED")
	return {"success": true, "snapshot": registry_snapshot.duplicate(true)}


func get_entity_snapshot(entity_id: String) -> Dictionary:
	if not configured or entity_id.strip_edges().is_empty():
		return _failure("INVALID_ENTITY_ID")
	for value in registry_snapshot.get("entities", []):
		if value is Dictionary and String(value.get("entity_id", "")) == entity_id:
			return {"success": true, "snapshot": value.duplicate(true)}
	return _failure("ENTITY_NOT_FOUND")


func has_entity(entity_id: String) -> bool:
	return bool(get_entity_snapshot(entity_id).get("success", false))


func get_entity_count() -> int:
	return int(registry_snapshot.get("entity_count", -1)) if configured else -1


func create_descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": configured,
		"read_only": true,
		"entity_count": get_entity_count(),
		"authority_owner_id": String(registry_snapshot.get("authority_owner_id", "")),
		"authority_epoch": int(registry_snapshot.get("authority_epoch", 0)),
	}


func _validate_registry_snapshot(value: Dictionary) -> Dictionary:
	var fields: Dictionary = UtilsScript.validate_exact_fields(value, REGISTRY_FIELDS)
	if not bool(fields.get("success", false)):
		return fields
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != "planet_simulator.entity_registry.v2":
		return _failure("UNSUPPORTED_REGISTRY_SCHEMA")
	for counter_field in [
		"entity_count", "migration_count", "chunk_transition_count",
		"zone_transition_count", "stale_write_rejection_count",
	]:
		if not UtilsScript.is_json_integer(value.get(counter_field)) or int(value[counter_field]) < 0:
			return _failure("INVALID_REGISTRY_COUNTER", {"field": counter_field})
	if not UtilsScript.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1:
		return _failure("INVALID_AUTHORITY_EPOCH")
	if typeof(value.get("authority_owner_id")) != TYPE_STRING or String(value["authority_owner_id"]).is_empty():
		return _failure("INVALID_AUTHORITY_OWNER")
	var entities_value = value.get("entities")
	if typeof(entities_value) != TYPE_ARRAY or entities_value.size() != int(value["entity_count"]):
		return _failure("REGISTRY_COUNT_MISMATCH")
	var entity_ids: Dictionary = {}
	for entity_value in entities_value:
		if typeof(entity_value) != TYPE_DICTIONARY:
			return _failure("INVALID_ENTITY_SNAPSHOT")
		var entity_fields: Dictionary = UtilsScript.validate_exact_fields(entity_value, ENTITY_FIELDS)
		if not bool(entity_fields.get("success", false)):
			return _failure("INVALID_ENTITY_SNAPSHOT", {"validation": entity_fields})
		if typeof(entity_value.get("schema")) != TYPE_STRING or String(entity_value["schema"]) != "planet_simulator.entity.v2":
			return _failure("UNSUPPORTED_ENTITY_SCHEMA")
		if typeof(entity_value.get("entity_id")) != TYPE_STRING or String(entity_value["entity_id"]).is_empty():
			return _failure("INVALID_ENTITY_ID")
		if typeof(entity_value.get("entity_type")) != TYPE_STRING or String(entity_value["entity_type"]).is_empty():
			return _failure("INVALID_ENTITY_TYPE")
		for revision_field in ["authority_epoch", "state_revision", "revision", "last_simulation_tick"]:
			if not UtilsScript.is_json_integer(entity_value.get(revision_field)) or int(entity_value[revision_field]) < 0:
				return _failure("INVALID_ENTITY_REVISION", {"field": revision_field})
		var entity_id: String = String(entity_value["entity_id"])
		if entity_ids.has(entity_id):
			return _failure("DUPLICATE_ENTITY_ID")
		entity_ids[entity_id] = true
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_REGISTRY_SNAPSHOT", {"message": safe.get("error", "")})
	return {"success": true}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
