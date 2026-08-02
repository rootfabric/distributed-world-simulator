class_name CharacterMotionState
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_motion_state.v1"

var velocity := Vector3.ZERO
var grounded := true
var stance := "stand"
var locomotion_mode := "grounded"
var facing_yaw := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
var state_revision := 0

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("MOTION_STATE_NOT_JSON_SAFE")
	var raw_velocity = data.get("velocity", {})
	if not raw_velocity is Dictionary:
		return Utils.failure("INVALID_MOTION_VELOCITY")
	velocity = Vector3(float(raw_velocity.get("x", 0.0)), float(raw_velocity.get("y", 0.0)), float(raw_velocity.get("z", 0.0)))
	grounded = bool(data.get("grounded", grounded))
	stance = Utils.normalized_id(data.get("stance", stance))
	locomotion_mode = Utils.normalized_id(data.get("locomotion_mode", locomotion_mode))
	facing_yaw = float(data.get("facing_yaw", facing_yaw))
	aim_yaw = float(data.get("aim_yaw", aim_yaw))
	aim_pitch = float(data.get("aim_pitch", aim_pitch))
	state_revision = int(data.get("state_revision", state_revision))
	return validate()

func validate() -> Dictionary:
	for number in [velocity.x, velocity.y, velocity.z, facing_yaw, aim_yaw, aim_pitch]:
		if not Utils.finite_number(number):
			return Utils.failure("INVALID_MOTION_NUMBER")
	if velocity.length() > 1000.0:
		return Utils.failure("MOTION_VELOCITY_OUT_OF_RANGE")
	if not Utils.is_valid_id(stance) or not Utils.is_valid_id(locomotion_mode):
		return Utils.failure("INVALID_MOTION_MODE")
	if absf(aim_pitch) > PI * 0.5 + 0.001:
		return Utils.failure("AIM_PITCH_OUT_OF_RANGE")
	if state_revision < 0:
		return Utils.failure("INVALID_MOTION_REVISION")
	return Utils.success()

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z}, "grounded": grounded, "stance": stance, "locomotion_mode": locomotion_mode, "facing_yaw": facing_yaw, "aim_yaw": aim_yaw, "aim_pitch": aim_pitch, "state_revision": state_revision}
