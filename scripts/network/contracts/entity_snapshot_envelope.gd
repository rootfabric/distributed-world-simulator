extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SPATIAL_REF_SCHEMA: String = "planet_simulator.spatial_ref.v1"
const QUATERNION_NORM_SQUARED_TOLERANCE: float = 0.00001
const QUATERNION_CANONICAL_EPSILON: float = 0.000000000001
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

const SCHEMA: String = "planet_simulator.entity_snapshot_envelope.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"snapshot_id",
	"entity_id",
	"state_revision",
	"authority_owner_id",
	"authority_epoch",
	"simulation_tick",
	"spatial_ref",
	"physics_state",
	"domain_components",
]


static func create(
	snapshot_id: String,
	entity_id: String,
	state_revision: int,
	authority_owner_id: String,
	authority_epoch: int,
	simulation_tick: int,
	spatial_ref: Dictionary,
	physics_state: Dictionary = {},
	domain_components: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"snapshot_id": snapshot_id,
		"entity_id": entity_id,
		"state_revision": state_revision,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"simulation_tick": simulation_tick,
		"spatial_ref": spatial_ref.duplicate(true),
		"physics_state": physics_state.duplicate(true),
		"domain_components": domain_components.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var fields_validation: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(fields_validation.get("success", false)):
		return fields_validation
	var check: Dictionary = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if value["schema"] != SCHEMA:
		return _failure("UNSUPPORTED_SCHEMA", "Unexpected entity snapshot schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return _failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	for key in ["snapshot_id", "entity_id", "authority_owner_id"]:
		check = UtilsScript.require_string(value, key)
		if not bool(check.get("success", false)):
			return check
	for integer_field in ["state_revision", "authority_epoch", "simulation_tick"]:
		check = UtilsScript.require_json_integer(value, integer_field)
		if not bool(check.get("success", false)):
			return check
	if int(value["state_revision"]) < 0:
		return _failure("INVALID_REVISION", "state_revision cannot be negative")
	if int(value["authority_epoch"]) < 1:
		return _failure("INVALID_AUTHORITY_EPOCH", "authority_epoch must be positive")
	if int(value["simulation_tick"]) < 0:
		return _failure("INVALID_SIMULATION_TICK", "simulation_tick cannot be negative")
	var spatial_value = value["spatial_ref"]
	if not spatial_value is Dictionary:
		return _failure("INVALID_SPATIAL_REF", "spatial_ref must be an Object/Dictionary")
	var spatial_validation: Dictionary = _validate_spatial_ref_strict(spatial_value)
	if not bool(spatial_validation.get("success", false)):
		return _failure(
			"INVALID_SPATIAL_REF",
			String(spatial_validation.get("message", "spatial_ref is invalid"))
		)
	for key in ["physics_state", "domain_components"]:
		check = UtilsScript.require_dictionary(value, key)
		if not bool(check.get("success", false)):
			return _failure("INVALID_PAYLOAD", String(check.get("message", "%s must be a Dictionary" % key)))
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return _failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var canonical_value: Dictionary = value.duplicate(true)
	canonical_value["spatial_ref"] = _canonicalize_spatial_ref(value["spatial_ref"])
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical_value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func snapshot_hash(value: Dictionary) -> String:
	return UtilsScript.payload_hash(normalize(value))


static func _validate_spatial_ref_strict(value: Dictionary) -> Dictionary:
	var fields_validation: Dictionary = UtilsScript.validate_exact_fields(value, SPATIAL_REF_FIELDS)
	if not bool(fields_validation.get("success", false)):
		return fields_validation
	var check: Dictionary = UtilsScript.require_string(value, "schema")
	if not bool(check.get("success", false)):
		return check
	if value["schema"] != SPATIAL_REF_SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected spatial_ref schema")
	for namespace_field in ["universe_id", "instance_id", "space_id"]:
		check = UtilsScript.require_string(value, namespace_field)
		if not bool(check.get("success", false)):
			return check
		if not _is_namespace_identifier(String(value[namespace_field])):
			return UtilsScript.validation_failure(
				"INVALID_FIELD_VALUE",
				"%s is not a canonical namespace identifier" % namespace_field
			)
	check = UtilsScript.require_string(value, "frame_id")
	if not bool(check.get("success", false)):
		return check
	for vector_field in ["position_m", "linear_velocity_mps", "angular_velocity_rps"]:
		check = _validate_number_array(value, vector_field, 3)
		if not bool(check.get("success", false)):
			return check
	check = _validate_number_array(value, "rotation_xyzw", 4)
	if not bool(check.get("success", false)):
		return check
	var rotation: Array = value["rotation_xyzw"]
	var rotation_length_squared: float = 0.0
	for component in rotation:
		rotation_length_squared += float(component) * float(component)
	if rotation_length_squared <= 0.0000001:
		return UtilsScript.validation_failure("INVALID_FIELD_VALUE", "rotation_xyzw cannot be a zero quaternion")
	if absf(rotation_length_squared - 1.0) > QUATERNION_NORM_SQUARED_TOLERANCE:
		return UtilsScript.validation_failure(
			"INVALID_FIELD_VALUE",
			"rotation_xyzw must be a unit quaternion"
		)
	if not _is_finite_number(value["sample_time_s"]):
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "sample_time_s must be a finite JSON number")
	var safe: Dictionary = UtilsScript.canonicalize(value, "$.spatial_ref")
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func _canonicalize_spatial_ref(value: Dictionary) -> Dictionary:
	var normalized: Dictionary = value.duplicate(true)
	var rotation: Array = value["rotation_xyzw"]
	var length_squared: float = 0.0
	for component in rotation:
		length_squared += float(component) * float(component)
	var inverse_length: float = 1.0 / sqrt(length_squared)
	var canonical_rotation: Array = []
	for component in rotation:
		var normalized_component: float = float(component) * inverse_length
		canonical_rotation.append(0.0 if absf(normalized_component) <= QUATERNION_CANONICAL_EPSILON else normalized_component)
	if _quaternion_requires_sign_flip(canonical_rotation):
		for index in range(canonical_rotation.size()):
			canonical_rotation[index] = -float(canonical_rotation[index])
	normalized["rotation_xyzw"] = canonical_rotation
	return normalized


static func _quaternion_requires_sign_flip(rotation: Array) -> bool:
	# q and -q encode the same orientation. Prefer positive W and use XYZ as a
	# deterministic tie-breaker for 180-degree rotations where W is zero.
	for index in [3, 0, 1, 2]:
		var component: float = float(rotation[index])
		if absf(component) > QUATERNION_CANONICAL_EPSILON:
			return component < 0.0
	return false


static func _validate_number_array(value: Dictionary, field: String, expected_size: int) -> Dictionary:
	if typeof(value.get(field)) != TYPE_ARRAY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be an Array" % field)
	var components: Array = value[field]
	if components.size() != expected_size:
		return UtilsScript.validation_failure(
			"INVALID_FIELD_VALUE",
			"%s must contain exactly %d numbers" % [field, expected_size]
		)
	for component in components:
		if not _is_finite_number(component):
			return UtilsScript.validation_failure(
				"INVALID_FIELD_TYPE",
				"%s must contain only finite JSON numbers" % field
			)
	return UtilsScript.validation_success()


static func _is_namespace_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for forbidden in ["/", "\\", ":", " ", ".."]:
		if value.contains(forbidden):
			return false
	return true


static func _is_finite_number(value) -> bool:
	var value_type: int = typeof(value)
	return value_type in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _failure(error_code: String, message: String) -> Dictionary:
	return UtilsScript.validation_failure(error_code, message)
