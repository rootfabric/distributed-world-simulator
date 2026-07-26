extends RefCounted

const SCHEMA: String = "planet_simulator.spatial_ref.v1"
const DEFAULT_UNIVERSE_ID: String = "main"
const DEFAULT_INSTANCE_ID: String = "persistent"
const DEFAULT_SPACE_ID: String = "sol"
const DEFAULT_FRAME_ID: String = "sol.barycentric"


static func create(
	frame_id: String,
	position_m: Vector3,
	basis_value: Basis = Basis.IDENTITY,
	linear_velocity_mps: Vector3 = Vector3.ZERO,
	angular_velocity_rps: Vector3 = Vector3.ZERO,
	sample_time_s: float = 0.0,
	universe_id: String = DEFAULT_UNIVERSE_ID,
	space_id: String = DEFAULT_SPACE_ID,
	instance_id: String = DEFAULT_INSTANCE_ID
) -> Dictionary:
	var normalized_basis: Basis = basis_value.orthonormalized()
	var rotation: Quaternion = normalized_basis.get_rotation_quaternion().normalized()
	return {
		"schema": SCHEMA,
		"universe_id": universe_id.strip_edges().to_lower(),
		"instance_id": instance_id.strip_edges().to_lower(),
		"space_id": space_id.strip_edges().to_lower(),
		"frame_id": frame_id.strip_edges(),
		"position_m": _vector_to_array(position_m),
		"rotation_xyzw": _quaternion_to_array(rotation),
		"linear_velocity_mps": _vector_to_array(linear_velocity_mps),
		"angular_velocity_rps": _vector_to_array(angular_velocity_rps),
		"sample_time_s": sample_time_s,
	}


static func normalize(value: Dictionary, defaults: Dictionary = {}) -> Dictionary:
	var frame_id: String = String(value.get(
		"frame_id",
		defaults.get("frame_id", DEFAULT_FRAME_ID)
	))
	return create(
		frame_id,
		get_position(value),
		get_basis(value),
		get_linear_velocity(value),
		get_angular_velocity(value),
		float(value.get("sample_time_s", defaults.get("sample_time_s", 0.0))),
		String(value.get(
			"universe_id",
			defaults.get("universe_id", DEFAULT_UNIVERSE_ID)
		)),
		String(value.get(
			"space_id",
			defaults.get("space_id", DEFAULT_SPACE_ID)
		)),
		String(value.get(
			"instance_id",
			defaults.get("instance_id", DEFAULT_INSTANCE_ID)
		))
	)


static func is_valid(value: Dictionary) -> bool:
	var position_value = value.get("position_m", [])
	var rotation_value = value.get("rotation_xyzw", [])
	var linear_velocity_value = value.get("linear_velocity_mps", [])
	var angular_velocity_value = value.get("angular_velocity_rps", [])
	if (
		String(value.get("schema", "")) != SCHEMA
		or not _is_namespace_identifier(String(value.get("universe_id", "")))
		or not _is_namespace_identifier(String(value.get("instance_id", "")))
		or not _is_namespace_identifier(String(value.get("space_id", "")))
		or String(value.get("frame_id", "")).is_empty()
		or not _array_is_finite(position_value, 3)
		or not _array_is_finite(rotation_value, 4)
		or not _array_is_finite(linear_velocity_value, 3)
		or not _array_is_finite(angular_velocity_value, 3)
		or not _is_finite_number(value.get("sample_time_s", 0.0))
	):
		return false
	var rotation := Quaternion(
		float(rotation_value[0]),
		float(rotation_value[1]),
		float(rotation_value[2]),
		float(rotation_value[3])
	)
	return rotation.length_squared() > 0.0000001


static func get_position(value: Dictionary) -> Vector3:
	return _array_to_vector3(value.get("position_m", [0.0, 0.0, 0.0]))


static func get_basis(value: Dictionary) -> Basis:
	var rotation_value = value.get("rotation_xyzw", [0.0, 0.0, 0.0, 1.0])
	if rotation_value is Array and rotation_value.size() >= 4:
		var rotation := Quaternion(
			float(rotation_value[0]),
			float(rotation_value[1]),
			float(rotation_value[2]),
			float(rotation_value[3])
		)
		if rotation.length_squared() > 0.0000001:
			return Basis(rotation.normalized()).orthonormalized()
	return Basis.IDENTITY


static func get_linear_velocity(value: Dictionary) -> Vector3:
	return _array_to_vector3(value.get("linear_velocity_mps", [0.0, 0.0, 0.0]))


static func get_angular_velocity(value: Dictionary) -> Vector3:
	return _array_to_vector3(value.get("angular_velocity_rps", [0.0, 0.0, 0.0]))


static func with_sample_time(value: Dictionary, sample_time_s: float) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	result["sample_time_s"] = sample_time_s
	return result


static func _array_is_finite(value, minimum_size: int) -> bool:
	if not value is Array or value.size() < minimum_size:
		return false
	for index in range(minimum_size):
		if not _is_finite_number(value[index]):
			return false
	return true


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


# Persistence payloads must use untyped Arrays. JSON.parse_string() returns
# untyped Arrays, so retaining Array[float] metadata here would make an otherwise
# identical Dictionary compare unequal after a JSON round-trip.
static func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _quaternion_to_array(value: Quaternion) -> Array:
	return [value.x, value.y, value.z, value.w]


static func _array_to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
