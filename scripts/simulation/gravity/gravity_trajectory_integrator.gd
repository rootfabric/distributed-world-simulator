extends RefCounted

const SCHEMA: String = "planet_simulator.gravity_trajectory_state.v1"

var gravity_field


func setup(gravity_field_reference) -> bool:
	gravity_field = gravity_field_reference
	return gravity_field != null


func step(
	position_m: Vector3,
	velocity_mps: Vector3,
	delta_s: float,
	frame_id: String = "",
	sample_time_s: float = 0.0,
	reference_body_id: String = ""
) -> Dictionary:
	if gravity_field == null or delta_s <= 0.0:
		return {
			"success": false,
			"error_code": "INVALID_GRAVITY_STEP",
		}
	var acceleration_start_mps2: Vector3 = gravity_field.get_acceleration_at_position(
		position_m,
		frame_id,
		sample_time_s,
		reference_body_id
	)
	var next_position_m: Vector3 = (
		position_m
		+ velocity_mps * delta_s
		+ acceleration_start_mps2 * (0.5 * delta_s * delta_s)
	)
	var acceleration_end_mps2: Vector3 = gravity_field.get_acceleration_at_position(
		next_position_m,
		frame_id,
		sample_time_s + delta_s,
		reference_body_id
	)
	var next_velocity_mps: Vector3 = (
		velocity_mps
		+ (acceleration_start_mps2 + acceleration_end_mps2) * (0.5 * delta_s)
	)
	return {
		"success": true,
		"schema": SCHEMA,
		"frame_id": frame_id,
		"reference_body_id": reference_body_id,
		"sample_time_s": sample_time_s + delta_s,
		"position_m": _vector_to_array(next_position_m),
		"velocity_mps": _vector_to_array(next_velocity_mps),
		"acceleration_start_mps2": _vector_to_array(acceleration_start_mps2),
		"acceleration_end_mps2": _vector_to_array(acceleration_end_mps2),
	}


func propagate(
	position_m: Vector3,
	velocity_mps: Vector3,
	delta_s: float,
	step_count: int,
	frame_id: String = "",
	sample_time_s: float = 0.0,
	reference_body_id: String = ""
) -> Dictionary:
	if step_count <= 0:
		return {
			"success": false,
			"error_code": "INVALID_STEP_COUNT",
		}
	var current_position_m: Vector3 = position_m
	var current_velocity_mps: Vector3 = velocity_mps
	var current_time_s: float = sample_time_s
	for _step_index in range(step_count):
		var result: Dictionary = step(
			current_position_m,
			current_velocity_mps,
			delta_s,
			frame_id,
			current_time_s,
			reference_body_id
		)
		if not bool(result.get("success", false)):
			return result
		current_position_m = _array_to_vector(result.get("position_m", []))
		current_velocity_mps = _array_to_vector(result.get("velocity_mps", []))
		current_time_s = float(result.get("sample_time_s", current_time_s))
	return {
		"success": true,
		"schema": SCHEMA,
		"frame_id": frame_id,
		"reference_body_id": reference_body_id,
		"sample_time_s": current_time_s,
		"position_m": _vector_to_array(current_position_m),
		"velocity_mps": _vector_to_array(current_velocity_mps),
		"step_count": step_count,
		"delta_s": delta_s,
	}


func _array_to_vector(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
