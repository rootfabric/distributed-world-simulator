class_name CharacterAppearance
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_appearance.v1"

var appearance_id := "appearance/default"
var appearance_revision := 1
var parameters: Dictionary = {}

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("APPEARANCE_NOT_JSON_SAFE")
	appearance_id = Utils.normalized_id(data.get("appearance_id", appearance_id))
	appearance_revision = int(data.get("appearance_revision", appearance_revision))
	var raw_parameters = data.get("parameters", {})
	if not raw_parameters is Dictionary:
		return Utils.failure("INVALID_APPEARANCE_PARAMETERS")
	parameters = Dictionary(raw_parameters).duplicate(true)
	return validate()

func validate() -> Dictionary:
	if not Utils.is_valid_id(appearance_id):
		return Utils.failure("INVALID_APPEARANCE_ID")
	if appearance_revision < 1:
		return Utils.failure("INVALID_APPEARANCE_REVISION")
	if not Utils.is_json_safe(parameters):
		return Utils.failure("APPEARANCE_PARAMETERS_NOT_JSON_SAFE")
	if JSON.stringify(parameters).length() > 8192:
		return Utils.failure("APPEARANCE_PARAMETERS_TOO_LARGE")
	return Utils.success()

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "appearance_id": appearance_id, "appearance_revision": appearance_revision, "parameters": parameters.duplicate(true)}
