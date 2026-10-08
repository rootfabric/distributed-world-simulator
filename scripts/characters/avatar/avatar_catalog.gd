class_name AvatarCatalog
extends RefCounted

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var _definitions: Dictionary = {}
var _fallback_character_id := ""
var _sealed := false

func load_path(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return Contract.failure("AVATAR_CATALOG_READ_FAILED", {"path": path})
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return Contract.failure("AVATAR_CATALOG_JSON_INVALID", {"path": path})
	return setup(Dictionary(parsed))

func setup(data: Dictionary) -> Dictionary:
	if _sealed:
		return Contract.failure("AVATAR_CATALOG_SEALED")
	if String(data.get("schema", "")) != "planet_simulator.avatar_catalog.v1":
		return Contract.failure("AVATAR_CATALOG_SCHEMA_INVALID")
	var entries = data.get("characters", [])
	if not entries is Array or entries.is_empty():
		return Contract.failure("AVATAR_CATALOG_EMPTY")
	_definitions.clear()
	for entry_value in entries:
		if not entry_value is Dictionary:
			return Contract.failure("AVATAR_CATALOG_ENTRY_INVALID")
		var entry: Dictionary = Dictionary(entry_value).duplicate(true)
		entry["schema"] = Contract.DEFINITION_SCHEMA
		var check := Contract.validate_definition(entry)
		if not bool(check.get("success", false)):
			return check
		var character_id := Contract.normalized_id(entry.get("character_id", ""))
		if _definitions.has(character_id):
			return Contract.failure("AVATAR_DEFINITION_DUPLICATE", {"character_id": character_id})
		_definitions[character_id] = entry
	_fallback_character_id = Contract.normalized_id(data.get("fallback_character_id", ""))
	if not _definitions.has(_fallback_character_id):
		return Contract.failure("AVATAR_FALLBACK_UNKNOWN", {"character_id": _fallback_character_id})
	_sealed = true
	return Contract.success({"character_count": _definitions.size()})

func has_definition(character_id: StringName) -> bool:
	return _definitions.has(Contract.normalized_id(character_id))

func get_definition(character_id: StringName) -> Dictionary:
	var key := Contract.normalized_id(character_id)
	if not _definitions.has(key):
		key = _fallback_character_id
	return Dictionary(_definitions.get(key, {})).duplicate(true)

func get_definition_exact(character_id: StringName) -> Dictionary:
	return Dictionary(_definitions.get(Contract.normalized_id(character_id), {})).duplicate(true)

func get_fallback_character_id() -> String:
	return _fallback_character_id

func get_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _definitions.keys():
		ids.append(String(key))
	ids.sort()
	return ids

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.avatar_catalog_report.v1",
		"fallback_character_id": _fallback_character_id,
		"character_ids": get_character_ids(),
		"character_count": _definitions.size(),
		"sealed": _sealed,
	}
