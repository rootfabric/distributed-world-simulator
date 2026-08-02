class_name CharacterAnimationProfile
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_animation_profile.v1"
const REQUIRED_SEMANTICS := ["locomotion/idle", "locomotion/walk", "locomotion/run", "locomotion/jump_start", "locomotion/fall", "locomotion/land"]

var animation_profile_id := ""
var semantic_map: Dictionary = {}
var fallback_semantic := "locomotion/idle"

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("ANIMATION_PROFILE_NOT_JSON_SAFE")
	animation_profile_id = Utils.normalized_id(data.get("animation_profile_id", ""))
	fallback_semantic = Utils.normalized_id(data.get("fallback_semantic", fallback_semantic))
	semantic_map.clear()
	var raw_map = data.get("semantic_map", {})
	if not raw_map is Dictionary:
		return Utils.failure("INVALID_ANIMATION_SEMANTIC_MAP")
	for semantic_value in raw_map:
		var semantic := Utils.normalized_id(semantic_value)
		var animation_name := String(raw_map[semantic_value]).strip_edges()
		if not Utils.is_valid_id(semantic) or not Utils.is_valid_text(animation_name):
			return Utils.failure("INVALID_ANIMATION_MAPPING", {"semantic": semantic})
		semantic_map[semantic] = animation_name
	return validate()

func validate() -> Dictionary:
	if not Utils.is_valid_id(animation_profile_id) or not Utils.is_valid_id(fallback_semantic):
		return Utils.failure("INVALID_ANIMATION_PROFILE_ID")
	if not semantic_map.has(fallback_semantic):
		return Utils.failure("MISSING_FALLBACK_ANIMATION")
	for semantic in REQUIRED_SEMANTICS:
		if not semantic_map.has(semantic):
			return Utils.failure("MISSING_REQUIRED_ANIMATION", {"semantic": semantic})
	return Utils.success()

func resolve(semantic: StringName) -> StringName:
	var key := Utils.normalized_id(semantic)
	return StringName(semantic_map.get(key, semantic_map.get(fallback_semantic, "")))

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "animation_profile_id": animation_profile_id, "fallback_semantic": fallback_semantic, "semantic_map": semantic_map.duplicate(true)}
