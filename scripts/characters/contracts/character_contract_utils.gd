class_name CharacterContractUtils
extends RefCounted

const MAX_ID_LENGTH := 96
const MAX_TEXT_LENGTH := 160
const ALLOWED_ID_CHARACTERS := "abcdefghijklmnopqrstuvwxyz0123456789_-/.:"

static func normalized_id(value: Variant) -> String:
	return String(value).strip_edges().to_lower()

static func is_valid_id(value: Variant) -> bool:
	var text := normalized_id(value)
	if text.is_empty() or text.length() > MAX_ID_LENGTH:
		return false
	if text.begins_with("/") or text.ends_with("/") or text.contains("//"):
		return false
	for character in text:
		if ALLOWED_ID_CHARACTERS.find(character) < 0:
			return false
	return true

static func is_valid_text(value: Variant, allow_empty: bool = false) -> bool:
	var text := String(value).strip_edges()
	return (allow_empty or not text.is_empty()) and text.length() <= MAX_TEXT_LENGTH

static func is_json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for child in value:
				if not is_json_safe(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING:
					return false
				if not is_json_safe(value[key], depth + 1):
					return false
			return true
		_:
			return false

static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

static func finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)
