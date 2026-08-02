class_name CharacterBodyProfile
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_body_profile.v1"

var body_profile_id := ""
var standing_height := 1.8
var crouching_height := 1.15
var capsule_radius := 0.35
var eye_height := 1.62
var step_height := 0.35
var mass := 80.0
var movement_profile_id := "movement/humanoid_standard"

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("BODY_PROFILE_NOT_JSON_SAFE")
	body_profile_id = Utils.normalized_id(data.get("body_profile_id", ""))
	standing_height = float(data.get("standing_height", standing_height))
	crouching_height = float(data.get("crouching_height", crouching_height))
	capsule_radius = float(data.get("capsule_radius", capsule_radius))
	eye_height = float(data.get("eye_height", eye_height))
	step_height = float(data.get("step_height", step_height))
	mass = float(data.get("mass", mass))
	movement_profile_id = Utils.normalized_id(data.get("movement_profile_id", movement_profile_id))
	return validate()

func validate() -> Dictionary:
	if not Utils.is_valid_id(body_profile_id) or not Utils.is_valid_id(movement_profile_id):
		return Utils.failure("INVALID_BODY_PROFILE_ID")
	for value in [standing_height, crouching_height, capsule_radius, eye_height, step_height, mass]:
		if not Utils.finite_number(value):
			return Utils.failure("INVALID_BODY_PROFILE_NUMBER")
	if standing_height < 0.5 or standing_height > 5.0:
		return Utils.failure("INVALID_STANDING_HEIGHT")
	if crouching_height < capsule_radius * 2.0 or crouching_height > standing_height:
		return Utils.failure("INVALID_CROUCHING_HEIGHT")
	if capsule_radius < 0.1 or capsule_radius > standing_height * 0.5:
		return Utils.failure("INVALID_CAPSULE_RADIUS")
	if eye_height <= 0.0 or eye_height > standing_height:
		return Utils.failure("INVALID_EYE_HEIGHT")
	if step_height < 0.0 or step_height > standing_height * 0.5:
		return Utils.failure("INVALID_STEP_HEIGHT")
	if mass < 1.0 or mass > 10000.0:
		return Utils.failure("INVALID_BODY_MASS")
	return Utils.success()

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "body_profile_id": body_profile_id, "standing_height": standing_height, "crouching_height": crouching_height, "capsule_radius": capsule_radius, "eye_height": eye_height, "step_height": step_height, "mass": mass, "movement_profile_id": movement_profile_id}
