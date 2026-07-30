extends RefCounted

const StateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")
const SCHEMA := "planet_simulator.player_movement_service.v1"
const MAX_MOVEMENT_DELTA_SECONDS := 0.25
const MAX_PLAYER_SPEED_MPS := 250.0
const MOVEMENT_DISTANCE_ALLOWANCE_M := 2.0

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

func get_report() -> Dictionary: return {"schema": SCHEMA}
func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String) -> Dictionary: return {"success": false, "error_code": error_code, "details": {}}
