extends RefCounted

const StateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")
const SCHEMA := "planet_simulator.player_movement_service.v1"
const MAX_MOVEMENT_DELTA_SECONDS := 0.25
const MAX_PLAYER_SPEED_MPS := 250.0
const MOVEMENT_DISTANCE_ALLOWANCE_M := 2.0
const PLAYGROUND_WALK_SPEED_MPS := 6.0
const PLAYGROUND_RUN_SPEED_MPS := 12.0
const PLAYGROUND_GRAVITY_MPS2 := 1.62
const PLAYGROUND_JUMP_SPEED_MPS := 3.6
const PLAYGROUND_GROUND_HEIGHT_M := 0.0
const PLAYGROUND_GROUND_EPSILON_M := 0.05
const MAX_LOOK_PITCH_RAD := 1.45

func apply_delta(record: Dictionary, input_sequence: int, delta_x: float, delta_z: float) -> Dictionary:
	if input_sequence < 1 or input_sequence <= int(record.get("last_input_sequence", 0)):
		return _failure("STALE_OR_DUPLICATE_INPUT_SEQUENCE")
	if is_nan(delta_x) or is_inf(delta_x) or is_nan(delta_z) or is_inf(delta_z) or absf(delta_x) > 10.0 or absf(delta_z) > 10.0:
		return _failure("INVALID_MOVEMENT_DELTA")
	var next := record.duplicate(true)
	var position: Dictionary = next.get("position", {}).duplicate(true)
	position["x"] = float(position.get("x", 0.0)) + delta_x
	position["z"] = float(position.get("z", 0.0)) + delta_z
	next["position"] = position
	next["velocity"] = {"x": delta_x, "y": 0.0, "z": delta_z}
	if absf(delta_x) + absf(delta_z) > 0.000001:
		next["orientation_yaw"] = atan2(delta_x, delta_z)
	next["last_input_sequence"] = input_sequence
	next["state_revision"] = int(next.get("state_revision", 0)) + 1
	return _success({"player": next})

func apply_movement_intent(record: Dictionary, input_sequence: int, payload: Dictionary) -> Dictionary:
	if input_sequence < 1 or input_sequence <= int(record.get("last_input_sequence", 0)):
		return _failure("STALE_OR_DUPLICATE_INPUT_SEQUENCE")
	var delta_seconds := float(payload.get("delta_seconds", 0.0))
	var move_x := float(payload.get("move_x", 0.0))
	var move_z := float(payload.get("move_z", 0.0))
	var look_yaw := float(payload.get("look_yaw", 0.0))
	var look_pitch := float(payload.get("look_pitch", 0.0))
	if (
		delta_seconds <= 0.0
		or delta_seconds > MAX_MOVEMENT_DELTA_SECONDS
		or not _finite(delta_seconds)
		or not _finite(move_x)
		or not _finite(move_z)
		or not _finite(look_yaw)
		or not _finite(look_pitch)
	):
		return _failure("INVALID_MOVEMENT_INTENT")
	var input_vector := Vector2(move_x, move_z)
	if input_vector.length() > 1.0001:
		return _failure("MOVEMENT_INTENT_OUT_OF_RANGE")
	if absf(look_yaw) > PI or absf(look_pitch) > MAX_LOOK_PITCH_RAD:
		return _failure("MOVEMENT_LOOK_OUT_OF_RANGE")
	if typeof(payload.get("jump_pressed")) != TYPE_BOOL or typeof(payload.get("sprint")) != TYPE_BOOL:
		return _failure("INVALID_MOVEMENT_INTENT_FLAGS")

	var next := record.duplicate(true)
	var position_value: Dictionary = Dictionary(next.get("position", {}))
	var velocity_value: Dictionary = Dictionary(next.get("velocity", {}))
	var position := Vector3(
		float(position_value.get("x", 0.0)),
		float(position_value.get("y", PLAYGROUND_GROUND_HEIGHT_M)),
		float(position_value.get("z", 0.0))
	)
	var velocity := Vector3(
		float(velocity_value.get("x", 0.0)),
		float(velocity_value.get("y", 0.0)),
		float(velocity_value.get("z", 0.0))
	)
	var basis := Basis(Vector3.UP, look_yaw)
	var right := basis.x.normalized()
	var forward := (-basis.z).normalized()
	var direction := right * move_x + forward * move_z
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var speed := PLAYGROUND_RUN_SPEED_MPS if bool(payload.get("sprint", false)) else PLAYGROUND_WALK_SPEED_MPS
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	var grounded := position.y <= PLAYGROUND_GROUND_HEIGHT_M + PLAYGROUND_GROUND_EPSILON_M and velocity.y <= 0.0
	if grounded:
		position.y = PLAYGROUND_GROUND_HEIGHT_M
		velocity.y = PLAYGROUND_JUMP_SPEED_MPS if bool(payload.get("jump_pressed", false)) else 0.0
	else:
		velocity.y -= PLAYGROUND_GRAVITY_MPS2 * delta_seconds
	position += velocity * delta_seconds
	if position.y < PLAYGROUND_GROUND_HEIGHT_M:
		position.y = PLAYGROUND_GROUND_HEIGHT_M
		velocity.y = 0.0

	next["position"] = {"x": position.x, "y": position.y, "z": position.z}
	next["velocity"] = {"x": velocity.x, "y": velocity.y, "z": velocity.z}
	next["orientation_yaw"] = look_yaw
	next["last_input_sequence"] = input_sequence
	next["state_revision"] = int(next.get("state_revision", 0)) + 1
	return _success({
		"player": next,
		"server_simulation": {
			"delta_seconds": delta_seconds,
			"look_pitch": look_pitch,
			"grounded": position.y <= PLAYGROUND_GROUND_HEIGHT_M + PLAYGROUND_GROUND_EPSILON_M,
		},
	})

func apply_authoritative_state(previous_state: Dictionary, candidate_state: Dictionary, delta_seconds: float) -> Dictionary:
	if delta_seconds <= 0.0 or delta_seconds > MAX_MOVEMENT_DELTA_SECONDS or is_nan(delta_seconds) or is_inf(delta_seconds):
		return _failure("INVALID_MOVEMENT_DELTA")
	var validation := StateCodec.validate_player_state(candidate_state)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_PLAYER_STATE")))
	var candidate := StateCodec.normalize_player_state(candidate_state)
	if int(candidate.get("last_input_sequence", 0)) <= int(previous_state.get("last_input_sequence", 0)):
		return _failure("DUPLICATE_INPUT_SEQUENCE")
	var velocity := StateCodec.player_velocity(candidate)
	if velocity.length() > MAX_PLAYER_SPEED_MPS:
		return _failure("PLAYER_SPEED_LIMIT_EXCEEDED")
	var maximum_displacement := MAX_PLAYER_SPEED_MPS * delta_seconds + MOVEMENT_DISTANCE_ALLOWANCE_M
	if StateCodec.player_position(candidate).distance_to(StateCodec.player_position(previous_state)) > maximum_displacement:
		return _failure("PLAYER_MOVEMENT_LIMIT_EXCEEDED")
	if StateCodec.player_interaction_position(candidate).distance_to(StateCodec.player_interaction_position(previous_state)) > maximum_displacement:
		return _failure("PLAYER_MOVEMENT_LIMIT_EXCEEDED")
	return _success({"player_state": candidate})

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"playground_authority": "SERVER_SIMULATED_INPUT_INTENT",
		"walk_speed_mps": PLAYGROUND_WALK_SPEED_MPS,
		"run_speed_mps": PLAYGROUND_RUN_SPEED_MPS,
		"gravity_mps2": PLAYGROUND_GRAVITY_MPS2,
		"jump_speed_mps": PLAYGROUND_JUMP_SPEED_MPS,
	}

func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
