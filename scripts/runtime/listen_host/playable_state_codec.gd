extends RefCounted

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const PLAYER_STATE_SCHEMA: String = "planet_simulator.playable_player_state.v1"
const TRANSFORM_SCHEMA: String = "planet_simulator.transform3d_dto.v1"
const PLAYER_STATE_FIELDS: Array[String] = [
	"schema",
	"spatial_ref",
	"interaction_position_m",
	"controller_id",
	"camera_mode",
	"flashlight_enabled",
	"last_input_sequence",
]
const TRANSFORM_FIELDS: Array[String] = ["schema", "position_m", "rotation_xyzw"]


static func create_player_state(
	position_m: Vector3,
	basis_value: Basis,
	linear_velocity_mps: Vector3,
	interaction_position_m: Vector3,
	controller_id: String,
	camera_mode: String,
	flashlight_enabled: bool,
	last_input_sequence: int,
	frame_id: String = "body/moon/fixed",
	universe_id: String = "main",
	space_id: String = "moon",
	instance_id: String = "persistent",
	sample_time_s: float = 0.0
) -> Dictionary:
	var value: Dictionary = {
		"schema": PLAYER_STATE_SCHEMA,
		"spatial_ref": SpatialRef.create(
			frame_id,
			position_m,
			basis_value,
			linear_velocity_mps,
			Vector3.ZERO,
			sample_time_s,
			universe_id,
			space_id,
			instance_id
		),
		"interaction_position_m": [
			interaction_position_m.x,
			interaction_position_m.y,
			interaction_position_m.z,
		],
		"controller_id": controller_id.strip_edges(),
		"camera_mode": camera_mode.strip_edges(),
		"flashlight_enabled": flashlight_enabled,
		"last_input_sequence": last_input_sequence,
	}
	return _json_stable_dictionary(value)


static func validate_player_state(value: Dictionary) -> Dictionary:
	var fields: Dictionary = NetworkUtils.validate_exact_fields(value, PLAYER_STATE_FIELDS)
	if not bool(fields.get("success", false)):
		return fields
	if String(value.get("schema", "")) != PLAYER_STATE_SCHEMA:
		return _failure("UNSUPPORTED_PLAYER_STATE_SCHEMA")
	if not value.get("spatial_ref", {}) is Dictionary or not SpatialRef.is_valid(Dictionary(value["spatial_ref"])):
		return _failure("INVALID_PLAYER_SPATIAL_REF")
	if not _finite_array(value.get("interaction_position_m"), 3):
		return _failure("INVALID_INTERACTION_POSITION")
	for field in ["controller_id", "camera_mode"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).strip_edges().is_empty():
			return _failure("INVALID_PLAYER_STATE_FIELD", {"field": field})
	if typeof(value.get("flashlight_enabled")) != TYPE_BOOL:
		return _failure("INVALID_PLAYER_STATE_FIELD", {"field": "flashlight_enabled"})
	if not NetworkUtils.is_json_integer(value.get("last_input_sequence")) or int(value["last_input_sequence"]) < 0:
		return _failure("INVALID_INPUT_SEQUENCE")
	var canonical: Dictionary = NetworkUtils.canonicalize(value)
	if not bool(canonical.get("success", false)):
		return _failure("NON_CANONICAL_PLAYER_STATE")
	return {"success": true, "error_code": ""}


static func normalize_player_state(value: Dictionary) -> Dictionary:
	if not bool(validate_player_state(value).get("success", false)):
		return {}
	var spatial: Dictionary = SpatialRef.normalize(Dictionary(value["spatial_ref"]))
	return _json_stable_dictionary({
		"schema": PLAYER_STATE_SCHEMA,
		"spatial_ref": spatial,
		"interaction_position_m": Array(value["interaction_position_m"]).duplicate(),
		"controller_id": String(value["controller_id"]),
		"camera_mode": String(value["camera_mode"]),
		"flashlight_enabled": bool(value["flashlight_enabled"]),
		"last_input_sequence": int(value["last_input_sequence"]),
	})


static func create_transform_dto(value: Transform3D) -> Dictionary:
	var basis_value: Basis = value.basis.orthonormalized()
	var rotation: Quaternion = basis_value.get_rotation_quaternion().normalized()
	return _json_stable_dictionary({
		"schema": TRANSFORM_SCHEMA,
		"position_m": [value.origin.x, value.origin.y, value.origin.z],
		"rotation_xyzw": [rotation.x, rotation.y, rotation.z, rotation.w],
	})


static func validate_transform_dto(value: Dictionary) -> Dictionary:
	var fields: Dictionary = NetworkUtils.validate_exact_fields(value, TRANSFORM_FIELDS)
	if not bool(fields.get("success", false)):
		return fields
	if String(value.get("schema", "")) != TRANSFORM_SCHEMA:
		return _failure("UNSUPPORTED_TRANSFORM_SCHEMA")
	if not _finite_array(value.get("position_m"), 3):
		return _failure("INVALID_TRANSFORM_POSITION")
	if not _finite_array(value.get("rotation_xyzw"), 4):
		return _failure("INVALID_TRANSFORM_ROTATION")
	var rotation_value: Array = value["rotation_xyzw"]
	var rotation := Quaternion(
		float(rotation_value[0]),
		float(rotation_value[1]),
		float(rotation_value[2]),
		float(rotation_value[3])
	)
	if rotation.length_squared() <= 0.0000001:
		return _failure("INVALID_TRANSFORM_ROTATION")
	var canonical: Dictionary = NetworkUtils.canonicalize(value)
	if not bool(canonical.get("success", false)):
		return _failure("NON_CANONICAL_TRANSFORM")
	return {"success": true, "error_code": ""}


static func transform_from_dto(value: Dictionary) -> Transform3D:
	if not bool(validate_transform_dto(value).get("success", false)):
		return Transform3D.IDENTITY
	var position: Array = value["position_m"]
	var rotation_value: Array = value["rotation_xyzw"]
	var rotation := Quaternion(
		float(rotation_value[0]),
		float(rotation_value[1]),
		float(rotation_value[2]),
		float(rotation_value[3])
	).normalized()
	return Transform3D(
		Basis(rotation).orthonormalized(),
		Vector3(float(position[0]), float(position[1]), float(position[2]))
	)


static func player_position(value: Dictionary) -> Vector3:
	return SpatialRef.get_position(Dictionary(value.get("spatial_ref", {})))


static func player_basis(value: Dictionary) -> Basis:
	return SpatialRef.get_basis(Dictionary(value.get("spatial_ref", {})))


static func player_velocity(value: Dictionary) -> Vector3:
	return SpatialRef.get_linear_velocity(Dictionary(value.get("spatial_ref", {})))


static func player_interaction_position(value: Dictionary) -> Vector3:
	var position_value = value.get("interaction_position_m", [0.0, 0.0, 0.0])
	if position_value is Array and position_value.size() == 3:
		return Vector3(
			float(position_value[0]),
			float(position_value[1]),
			float(position_value[2])
		)
	return Vector3.ZERO


static func _finite_array(value, expected_size: int) -> bool:
	if not value is Array or value.size() != expected_size:
		return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
	return true


static func _json_stable_dictionary(value: Dictionary) -> Dictionary:
	var round_trip: Dictionary = NetworkUtils.json_round_trip(value)
	return (
		Dictionary(round_trip.get("value", {})).duplicate(true)
		if bool(round_trip.get("success", false))
		else {}
	)


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
