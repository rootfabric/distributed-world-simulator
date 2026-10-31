class_name AvatarContract
extends RefCounted

const DEFINITION_SCHEMA := "planet_simulator.avatar_definition.v1"
const MOTION_SCHEMA := "planet_simulator.avatar_motion_state.v1"
const ACTION_SCHEMA := "planet_simulator.avatar_action_state.v1"
const APPEARANCE_SCHEMA := "planet_simulator.avatar_appearance.v1"
const MAX_ID_LENGTH := 112
const MAX_TEXT_LENGTH := 160
const ALLOWED_ID_CHARACTERS := "abcdefghijklmnopqrstuvwxyz0123456789_-/.:"

static func normalized_id(value: Variant) -> String:
	return String(value).strip_edges().to_lower()

static func valid_id(value: Variant) -> bool:
	var text := normalized_id(value)
	if text.is_empty() or text.length() > MAX_ID_LENGTH:
		return false
	if text.begins_with("/") or text.ends_with("/") or text.contains("//"):
		return false
	for character in text:
		if ALLOWED_ID_CHARACTERS.find(character) < 0:
			return false
	return true

static func json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for child in value:
				if not json_safe(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not json_safe(value[key], depth + 1):
					return false
			return true
		_:
			return false

static func validate_definition(value: Dictionary) -> Dictionary:
	if String(value.get("schema", DEFINITION_SCHEMA)) != DEFINITION_SCHEMA:
		return failure("AVATAR_DEFINITION_SCHEMA")
	var character_id := normalized_id(value.get("character_id", ""))
	var provider_id := normalized_id(value.get("provider_id", ""))
	var display_name := String(value.get("display_name", "")).strip_edges()
	if not valid_id(character_id):
		return failure("AVATAR_CHARACTER_ID_INVALID")
	if not valid_id(provider_id):
		return failure("AVATAR_PROVIDER_ID_INVALID")
	if display_name.is_empty() or display_name.length() > MAX_TEXT_LENGTH:
		return failure("AVATAR_DISPLAY_NAME_INVALID")
	if int(value.get("asset_revision", 0)) < 1:
		return failure("AVATAR_ASSET_REVISION_INVALID")
	for forbidden in ["presentation_scene_path", "model_path", "animation_path"]:
		if value.has(forbidden):
			return failure("AVATAR_CORE_ASSET_COUPLING_FORBIDDEN", {"field": forbidden})
	for field in ["provider_options", "default_appearance", "animation_semantics", "sockets"]:
		var field_value = value.get(field, {})
		if not field_value is Dictionary or not json_safe(field_value):
			return failure("AVATAR_DEFINITION_FIELD_INVALID", {"field": field})
	var offset := float(value.get("visual_vertical_offset_m", -0.85))
	var eye_height := float(value.get("eye_height_m", 1.62))
	if is_nan(offset) or is_inf(offset) or is_nan(eye_height) or is_inf(eye_height):
		return failure("AVATAR_DEFINITION_NUMBER_INVALID")
	if eye_height <= 0.2 or eye_height > 4.0:
		return failure("AVATAR_EYE_HEIGHT_INVALID")
	return success()

static func validate_appearance(value: Dictionary) -> Dictionary:
	if not json_safe(value):
		return failure("AVATAR_APPEARANCE_NOT_JSON_SAFE")
	var appearance_id := normalized_id(value.get("appearance_id", "appearance/default"))
	if not valid_id(appearance_id):
		return failure("AVATAR_APPEARANCE_ID_INVALID")
	if int(value.get("appearance_revision", 1)) < 1:
		return failure("AVATAR_APPEARANCE_REVISION_INVALID")
	var parameters = value.get("parameters", {})
	if not parameters is Dictionary or JSON.stringify(parameters).length() > 8192:
		return failure("AVATAR_APPEARANCE_PARAMETERS_INVALID")
	return success()

static func validate_motion(value: Dictionary) -> Dictionary:
	var velocity = value.get("velocity", {})
	if not velocity is Dictionary:
		return failure("AVATAR_MOTION_VELOCITY_INVALID")
	for component in ["x", "y", "z"]:
		var number := float(velocity.get(component, 0.0))
		if is_nan(number) or is_inf(number) or absf(number) > 1000.0:
			return failure("AVATAR_MOTION_NUMBER_INVALID", {"field": component})
	var yaw := float(value.get("facing_yaw", 0.0))
	if is_nan(yaw) or is_inf(yaw):
		return failure("AVATAR_MOTION_YAW_INVALID")
	if int(value.get("state_revision", 0)) < 0:
		return failure("AVATAR_MOTION_REVISION_INVALID")
	return success()

static func validate_action(value: Dictionary) -> Dictionary:
	var action_id := normalized_id(value.get("action_id", "action/none"))
	if not valid_id(action_id):
		return failure("AVATAR_ACTION_ID_INVALID")
	if int(value.get("action_sequence", 0)) < 0:
		return failure("AVATAR_ACTION_SEQUENCE_INVALID")
	return success()

static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
