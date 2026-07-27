extends RefCounted

const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const PartitionAddressScript = preload("res://scripts/simulation/partition/partition_address.gd")
const EntityLifecycle = preload("res://scripts/simulation/lifecycle/entity_lifecycle.gd")

const SCHEMA: String = "planet_simulator.world_entity_aggregate.v1"
const ENTITY_TYPE_WORLD_ITEM: String = "world_item"
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const QUATERNION_EPSILON: float = 0.000000000001
const QUATERNION_NORM_TOLERANCE: float = 0.00001
const SNAPSHOT_FIELDS: Array[String] = [
	"schema",
	"entity_id",
	"entity_type",
	"item_instance_id",
	"spatial_ref",
	"partition_address",
	"physics_state",
	"domain_components",
	"authority_owner_id",
	"authority_epoch",
	"state_revision",
	"last_simulation_tick",
	"lifecycle_state",
	"created_at_utc",
	"updated_at_utc",
]
const SPATIAL_REF_FIELDS: Array[String] = [
	"schema",
	"universe_id",
	"instance_id",
	"space_id",
	"frame_id",
	"position_m",
	"rotation_xyzw",
	"linear_velocity_mps",
	"angular_velocity_rps",
	"sample_time_s",
]

var entity_id: String = ""
var entity_type: String = ENTITY_TYPE_WORLD_ITEM
var item_instance_id: String = ""
var spatial_ref: Dictionary = {}
var partition_address: Dictionary = {}
var physics_state: Dictionary = {}
var domain_components: Dictionary = {}
var authority_owner_id: String = "local-process"
var authority_epoch: int = 1
var state_revision: int = 0
var last_simulation_tick: int = 0
var lifecycle_state: String = EntityLifecycle.ACTIVE
var created_at_utc: String = ""
var updated_at_utc: String = ""


func setup(
	entity_id_value: String,
	item_instance_id_value: String,
	spatial_ref_value: Dictionary,
	context: Dictionary = {}
) -> bool:
	if (
		entity_id_value.is_empty()
		or item_instance_id_value.is_empty()
		or not SpatialRefScript.is_valid(spatial_ref_value)
	):
		return false
	entity_id = entity_id_value
	item_instance_id = item_instance_id_value
	entity_type = String(context.get("entity_type", ENTITY_TYPE_WORLD_ITEM))
	# Persist the exact representation produced by Godot's JSON boundary once.
	# This prevents one-bit quaternion drift on save/load while avoiding repeated
	# Basis/Quaternion reconstruction.
	spatial_ref = _canonicalize_transport_dictionary(spatial_ref_value)
	var partition_value = context.get("partition_address", {})
	partition_address = _normalize_optional_partition(partition_value)
	physics_state = _normalize_json_dictionary(context.get("physics_state", {}))
	domain_components = _normalize_json_dictionary(context.get("domain_components", {}))
	authority_owner_id = String(context.get("authority_owner_id", "local-process"))
	authority_epoch = maxi(1, int(context.get("authority_epoch", 1)))
	state_revision = maxi(0, int(context.get("state_revision", 0)))
	last_simulation_tick = maxi(0, int(context.get("last_simulation_tick", 0)))
	lifecycle_state = String(context.get("lifecycle_state", EntityLifecycle.ACTIVE))
	if not EntityLifecycle.is_valid(lifecycle_state):
		return false
	created_at_utc = String(context.get("created_at_utc", Time.get_datetime_string_from_system(true, true)))
	updated_at_utc = String(context.get("updated_at_utc", created_at_utc))
	return validate().get("success", false)


func setup_from_snapshot(snapshot: Dictionary) -> bool:
	var validation: Dictionary = validate_snapshot_payload(snapshot)
	if not bool(validation.get("success", false)):
		return false
	return setup(
		String(snapshot.get("entity_id", "")),
		String(snapshot.get("item_instance_id", "")),
		Dictionary(snapshot.get("spatial_ref", {})),
		{
			"entity_type": snapshot.get("entity_type", ENTITY_TYPE_WORLD_ITEM),
			"partition_address": snapshot.get("partition_address", {}),
			"physics_state": snapshot.get("physics_state", {}),
			"domain_components": snapshot.get("domain_components", {}),
			"authority_owner_id": snapshot.get("authority_owner_id", "local-process"),
			"authority_epoch": snapshot.get("authority_epoch", 1),
			"state_revision": snapshot.get("state_revision", 0),
			"last_simulation_tick": snapshot.get("last_simulation_tick", 0),
			"lifecycle_state": snapshot.get("lifecycle_state", EntityLifecycle.ACTIVE),
			"created_at_utc": snapshot.get("created_at_utc", ""),
			"updated_at_utc": snapshot.get("updated_at_utc", ""),
		}
	)


func validate_snapshot_payload(snapshot: Dictionary) -> Dictionary:
	var fields_result: Dictionary = _validate_exact_fields(snapshot, SNAPSHOT_FIELDS)
	if not bool(fields_result.get("success", false)):
		return fields_result
	if typeof(snapshot["schema"]) != TYPE_STRING or snapshot["schema"] != SCHEMA:
		return _failure("UNSUPPORTED_WORLD_ENTITY_SCHEMA")
	for field in ["entity_id", "entity_type", "item_instance_id", "authority_owner_id", "lifecycle_state", "created_at_utc", "updated_at_utc"]:
		if typeof(snapshot[field]) != TYPE_STRING:
			return _failure("INVALID_WORLD_ENTITY_FIELD_TYPE", {"field": field})
	for field in ["entity_id", "entity_type", "item_instance_id", "authority_owner_id", "lifecycle_state"]:
		if String(snapshot[field]).strip_edges().is_empty():
			return _failure("EMPTY_WORLD_ENTITY_FIELD", {"field": field})
	if snapshot["entity_type"] != ENTITY_TYPE_WORLD_ITEM:
		return _failure("UNSUPPORTED_WORLD_ENTITY_TYPE")
	for field in ["spatial_ref", "partition_address", "physics_state", "domain_components"]:
		if typeof(snapshot[field]) != TYPE_DICTIONARY:
			return _failure("INVALID_WORLD_ENTITY_FIELD_TYPE", {"field": field})
	for field in ["authority_epoch", "state_revision", "last_simulation_tick"]:
		if not _is_json_integer(snapshot[field]):
			return _failure("INVALID_WORLD_ENTITY_INTEGER", {"field": field})
	if int(snapshot["authority_epoch"]) <= 0:
		return _failure("INVALID_AUTHORITY")
	if int(snapshot["state_revision"]) < 0 or int(snapshot["last_simulation_tick"]) < 0:
		return _failure("INVALID_REVISION")
	if not EntityLifecycle.is_valid(String(snapshot["lifecycle_state"])):
		return _failure("INVALID_LIFECYCLE_STATE")
	var spatial_result: Dictionary = _validate_spatial_ref_payload(Dictionary(snapshot["spatial_ref"]))
	if not bool(spatial_result.get("success", false)):
		return spatial_result
	var partition: Dictionary = Dictionary(snapshot["partition_address"])
	if not partition.is_empty() and not PartitionAddressScript.is_valid(partition):
		return _failure("INVALID_PARTITION_ADDRESS")
	if not _is_json_safe(snapshot["physics_state"]) or not _is_json_safe(snapshot["domain_components"]):
		return _failure("NON_SERIALIZABLE_COMPONENTS")
	return {"success": true}


func validate() -> Dictionary:
	if entity_id.is_empty():
		return _failure("EMPTY_ENTITY_ID")
	if item_instance_id.is_empty():
		return _failure("EMPTY_ITEM_INSTANCE_ID")
	if entity_type != ENTITY_TYPE_WORLD_ITEM:
		return _failure("UNSUPPORTED_WORLD_ENTITY_TYPE")
	if not SpatialRefScript.is_valid(spatial_ref):
		return _failure("INVALID_SPATIAL_REF")
	if not partition_address.is_empty() and not PartitionAddressScript.is_valid(partition_address):
		return _failure("INVALID_PARTITION_ADDRESS")
	if authority_owner_id.is_empty() or authority_epoch <= 0:
		return _failure("INVALID_AUTHORITY")
	if state_revision < 0 or last_simulation_tick < 0:
		return _failure("INVALID_REVISION")
	if not EntityLifecycle.is_valid(lifecycle_state):
		return _failure("INVALID_LIFECYCLE_STATE")
	if not _is_json_safe(physics_state) or not _is_json_safe(domain_components):
		return _failure("NON_SERIALIZABLE_COMPONENTS")
	return {"success": true}


func apply_spatial_state(
	spatial_ref_value: Dictionary,
	physics_state_value: Dictionary = {},
	partition_value: Dictionary = {},
	expected_revision: int = -1,
	expected_authority_epoch: int = -1,
	simulation_tick: int = -1
) -> Dictionary:
	if expected_revision >= 0 and expected_revision != state_revision:
		return _failure("REVISION_CONFLICT", {
			"expected_revision": expected_revision,
			"actual_revision": state_revision,
		})
	if expected_authority_epoch >= 0 and expected_authority_epoch != authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH", {
			"expected_authority_epoch": authority_epoch,
			"received_authority_epoch": expected_authority_epoch,
		})
	if lifecycle_state != EntityLifecycle.ACTIVE:
		return _failure("ENTITY_NOT_ACTIVE", {"lifecycle_state": lifecycle_state})
	if not SpatialRefScript.is_valid(spatial_ref_value):
		return _failure("INVALID_SPATIAL_REF")
	var next_partition: Dictionary = _normalize_optional_partition(partition_value)
	if not partition_value.is_empty() and next_partition.is_empty():
		return _failure("INVALID_PARTITION_ADDRESS")
	var next_physics: Dictionary = _normalize_json_dictionary(physics_state_value)
	if not _is_json_safe(next_physics):
		return _failure("NON_SERIALIZABLE_PHYSICS_STATE")
	var normalized_ref: Dictionary = _canonicalize_transport_dictionary(spatial_ref_value)
	var changed: bool = (
		normalized_ref != spatial_ref
		or next_physics != physics_state
		or (not partition_value.is_empty() and next_partition != partition_address)
	)
	if not changed:
		return {
			"success": true,
			"changed": false,
			"state_revision": state_revision,
		}
	spatial_ref = normalized_ref
	physics_state = next_physics
	if not partition_value.is_empty():
		partition_address = next_partition
	if simulation_tick >= 0:
		last_simulation_tick = simulation_tick
	_touch_revision()
	return {
		"success": true,
		"changed": true,
		"state_revision": state_revision,
	}


func apply_domain_components(
	component_patch: Dictionary,
	expected_revision: int = -1,
	expected_authority_epoch: int = -1
) -> Dictionary:
	if expected_revision >= 0 and expected_revision != state_revision:
		return _failure("REVISION_CONFLICT")
	if expected_authority_epoch >= 0 and expected_authority_epoch != authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	if not _is_json_safe(component_patch):
		return _failure("NON_SERIALIZABLE_COMPONENTS")
	var next_components: Dictionary = domain_components.duplicate(true)
	for key_value in component_patch.keys():
		var key: String = String(key_value)
		var value = component_patch[key_value]
		if value == null:
			next_components.erase(key)
		else:
			next_components[key] = _normalize_json_value(value)
	if next_components == domain_components:
		return {"success": true, "changed": false, "state_revision": state_revision}
	domain_components = next_components
	_touch_revision()
	return {"success": true, "changed": true, "state_revision": state_revision}


func transition_lifecycle(next_state: String) -> Dictionary:
	var result: Dictionary = EntityLifecycle.transition(lifecycle_state, next_state)
	if not bool(result.get("success", false)):
		return result
	if bool(result.get("changed", false)):
		lifecycle_state = next_state
		_touch_revision()
	result["state_revision"] = state_revision
	return result


func transfer_authority(next_owner_id: String, next_epoch: int) -> Dictionary:
	if next_owner_id.is_empty():
		return _failure("EMPTY_AUTHORITY_OWNER")
	if next_epoch <= authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	authority_owner_id = next_owner_id
	authority_epoch = next_epoch
	_touch_revision()
	return {
		"success": true,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"state_revision": state_revision,
	}


func to_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"entity_id": entity_id,
		"entity_type": entity_type,
		"item_instance_id": item_instance_id,
		"spatial_ref": spatial_ref.duplicate(true),
		"partition_address": partition_address.duplicate(true),
		"physics_state": physics_state.duplicate(true),
		"domain_components": domain_components.duplicate(true),
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"state_revision": state_revision,
		"last_simulation_tick": last_simulation_tick,
		"lifecycle_state": lifecycle_state,
		"created_at_utc": created_at_utc,
		"updated_at_utc": updated_at_utc,
	}


func _touch_revision() -> void:
	state_revision += 1
	updated_at_utc = Time.get_datetime_string_from_system(true, true)


func _canonicalize_transport_dictionary(value: Dictionary) -> Dictionary:
	var canonical: Dictionary = value.duplicate(true)
	var rotation_value = canonical.get("rotation_xyzw", [])
	if rotation_value is Array and rotation_value.size() == 4:
		var rotation: Array = Array(rotation_value).duplicate()
		var length_squared: float = 0.0
		for component in rotation:
			length_squared += float(component) * float(component)
		if length_squared > QUATERNION_EPSILON and absf(length_squared - 1.0) > QUATERNION_EPSILON:
			var inverse_length: float = 1.0 / sqrt(length_squared)
			for index in range(rotation.size()):
				rotation[index] = float(rotation[index]) * inverse_length
		for index in range(rotation.size()):
			if absf(float(rotation[index])) <= QUATERNION_EPSILON:
				rotation[index] = 0.0
		if _quaternion_requires_sign_flip(rotation):
			for index in range(rotation.size()):
				rotation[index] = -float(rotation[index])
		canonical["rotation_xyzw"] = rotation
	var encoded: String = JSON.stringify(canonical, "", true, true)
	var parsed = JSON.parse_string(encoded)
	return Dictionary(parsed) if parsed is Dictionary else {}


func _normalize_optional_partition(value) -> Dictionary:
	if not value is Dictionary or value.is_empty():
		return {}
	return PartitionAddressScript.normalize(Dictionary(value))


func _normalize_json_dictionary(value) -> Dictionary:
	if not value is Dictionary:
		return {}
	var normalized = _normalize_json_value(value)
	return Dictionary(normalized) if normalized is Dictionary else {}


func _normalize_json_value(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[String(key)] = _normalize_json_value(value[key])
		return result
	if value is Array:
		var result_array: Array = []
		for child in value:
			result_array.append(_normalize_json_value(child))
		return result_array
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


func _is_json_safe(value) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return abs(int(value)) <= MAX_SAFE_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)
		TYPE_ARRAY:
			for child in value:
				if not _is_json_safe(child):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value.keys():
				if typeof(key) != TYPE_STRING or not _is_json_safe(value[key]):
					return false
			return true
	return false


func _validate_exact_fields(value: Dictionary, fields: Array[String]) -> Dictionary:
	for field in fields:
		if not value.has(field):
			return _failure("MISSING_WORLD_ENTITY_FIELD", {"field": field})
	for key_value in value.keys():
		if typeof(key_value) != TYPE_STRING or not fields.has(String(key_value)):
			return _failure("UNEXPECTED_WORLD_ENTITY_FIELD", {"field": str(key_value)})
	return {"success": true}


func _validate_spatial_ref_payload(value: Dictionary) -> Dictionary:
	var fields_result: Dictionary = _validate_exact_fields(value, SPATIAL_REF_FIELDS)
	if not bool(fields_result.get("success", false)):
		return _failure("INVALID_SPATIAL_REF", {"cause": fields_result})
	for field in ["schema", "universe_id", "instance_id", "space_id", "frame_id"]:
		if typeof(value[field]) != TYPE_STRING or String(value[field]).strip_edges().is_empty():
			return _failure("INVALID_SPATIAL_REF", {"field": field})
	if value["schema"] != SpatialRefScript.SCHEMA:
		return _failure("INVALID_SPATIAL_REF", {"field": "schema"})
	for field in ["position_m", "linear_velocity_mps", "angular_velocity_rps"]:
		if not _is_number_array(value[field], 3):
			return _failure("INVALID_SPATIAL_REF", {"field": field})
	if not _is_number_array(value["rotation_xyzw"], 4):
		return _failure("INVALID_SPATIAL_REF", {"field": "rotation_xyzw"})
	var norm_squared: float = 0.0
	for component in value["rotation_xyzw"]:
		norm_squared += float(component) * float(component)
	if norm_squared <= QUATERNION_EPSILON or absf(norm_squared - 1.0) > QUATERNION_NORM_TOLERANCE:
		return _failure("INVALID_SPATIAL_REF", {"field": "rotation_xyzw"})
	if not _is_finite_json_number(value["sample_time_s"]):
		return _failure("INVALID_SPATIAL_REF", {"field": "sample_time_s"})
	return {"success": true}


func _is_number_array(value, expected_size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != expected_size:
		return false
	for component in value:
		if not _is_finite_json_number(component):
			return false
	return true


func _is_finite_json_number(value) -> bool:
	if typeof(value) == TYPE_INT:
		return abs(int(value)) <= MAX_SAFE_JSON_INTEGER
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)


func _is_json_integer(value) -> bool:
	if typeof(value) == TYPE_INT:
		return abs(int(value)) <= MAX_SAFE_JSON_INTEGER
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER) and float(value) == floor(float(value))


func _quaternion_requires_sign_flip(rotation: Array) -> bool:
	for index in [3, 0, 1, 2]:
		var component: float = float(rotation[index])
		if absf(component) > QUATERNION_EPSILON:
			return component < 0.0
	return false


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}
