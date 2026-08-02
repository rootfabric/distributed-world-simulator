class_name CharacterDefinition
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const BodyProfile = preload("res://scripts/characters/contracts/character_body_profile.gd")
const AnimationProfile = preload("res://scripts/characters/contracts/character_animation_profile.gd")
const SocketProfile = preload("res://scripts/characters/contracts/character_socket_profile.gd")
const Appearance = preload("res://scripts/characters/contracts/character_appearance.gd")
const SCHEMA := "planet_simulator.character_definition.v1"

var character_id := ""
var display_name := ""
var presentation_scene_path := ""
var asset_revision := 1
var body_profile
var animation_profile
var socket_profile
var default_appearance

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("CHARACTER_DEFINITION_NOT_JSON_SAFE")
	character_id = Utils.normalized_id(data.get("character_id", ""))
	display_name = String(data.get("display_name", "")).strip_edges()
	presentation_scene_path = String(data.get("presentation_scene_path", "")).strip_edges()
	asset_revision = int(data.get("asset_revision", 1))
	body_profile = BodyProfile.new()
	var body_result: Dictionary = body_profile.setup(Dictionary(data.get("body_profile", {})))
	if not body_result.success:
		return body_result
	animation_profile = AnimationProfile.new()
	var animation_result: Dictionary = animation_profile.setup(Dictionary(data.get("animation_profile", {})))
	if not animation_result.success:
		return animation_result
	socket_profile = SocketProfile.new()
	var socket_result: Dictionary = socket_profile.setup(Dictionary(data.get("socket_profile", {})))
	if not socket_result.success:
		return socket_result
	default_appearance = Appearance.new()
	var appearance_result: Dictionary = default_appearance.setup(Dictionary(data.get("default_appearance", {})))
	if not appearance_result.success:
		return appearance_result
	return validate()

func validate() -> Dictionary:
	if not Utils.is_valid_id(character_id):
		return Utils.failure("INVALID_CHARACTER_ID")
	if not Utils.is_valid_text(display_name):
		return Utils.failure("INVALID_CHARACTER_DISPLAY_NAME")
	if not presentation_scene_path.begins_with("res://") or not presentation_scene_path.ends_with(".tscn"):
		return Utils.failure("INVALID_PRESENTATION_SCENE_PATH")
	if presentation_scene_path.contains("..") or presentation_scene_path.length() > 240:
		return Utils.failure("UNSAFE_PRESENTATION_SCENE_PATH")
	if asset_revision < 1:
		return Utils.failure("INVALID_CHARACTER_ASSET_REVISION")
	for profile in [body_profile, animation_profile, socket_profile, default_appearance]:
		if profile == null:
			return Utils.failure("MISSING_CHARACTER_PROFILE")
		var result: Dictionary = profile.validate()
		if not result.success:
			return result
	return Utils.success()

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "character_id": character_id, "display_name": display_name, "presentation_scene_path": presentation_scene_path, "asset_revision": asset_revision, "body_profile": body_profile.to_dict(), "animation_profile": animation_profile.to_dict(), "socket_profile": socket_profile.to_dict(), "default_appearance": default_appearance.to_dict()}
