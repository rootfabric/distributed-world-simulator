class_name CharacterActionState
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_action_state.v1"

var action_id := "action/none"
var action_sequence := 0
var action_started_tick := 0
var equipment_pose := "pose/empty"
var active := false

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("ACTION_STATE_NOT_JSON_SAFE")
	action_id = Utils.normalized_id(data.get("action_id", action_id))
	action_sequence = int(data.get("action_sequence", action_sequence))
	action_started_tick = int(data.get("action_started_tick", action_started_tick))
	equipment_pose = Utils.normalized_id(data.get("equipment_pose", equipment_pose))
	active = bool(data.get("active", active))
	return validate()

func validate() -> Dictionary:
	if not Utils.is_valid_id(action_id) or not Utils.is_valid_id(equipment_pose):
		return Utils.failure("INVALID_ACTION_ID")
	if action_sequence < 0 or action_started_tick < 0:
		return Utils.failure("INVALID_ACTION_SEQUENCE")
	return Utils.success()

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "action_id": action_id, "action_sequence": action_sequence, "action_started_tick": action_started_tick, "equipment_pose": equipment_pose, "active": active}
