class_name CharacterRegistry
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_registry.v1"

var _definitions: Dictionary = {}
var _fallback_character_id := ""
var _sealed := false

func register_definition(definition, make_fallback: bool = false) -> Dictionary:
	if _sealed:
		return Utils.failure("CHARACTER_REGISTRY_SEALED")
	if definition == null:
		return Utils.failure("MISSING_CHARACTER_DEFINITION")
	var validation: Dictionary = definition.validate()
	if not validation.success:
		return validation
	var character_id: String = definition.character_id
	if _definitions.has(character_id):
		return Utils.failure("DUPLICATE_CHARACTER_DEFINITION", {"character_id": character_id})
	_definitions[character_id] = definition
	if make_fallback or _fallback_character_id.is_empty():
		_fallback_character_id = character_id
	return Utils.success({"character_id": character_id})

func set_fallback(character_id: StringName) -> Dictionary:
	if _sealed:
		return Utils.failure("CHARACTER_REGISTRY_SEALED")
	var key := Utils.normalized_id(character_id)
	if not _definitions.has(key):
		return Utils.failure("UNKNOWN_FALLBACK_CHARACTER", {"character_id": key})
	_fallback_character_id = key
	return Utils.success()

func seal() -> Dictionary:
	if _definitions.is_empty() or _fallback_character_id.is_empty():
		return Utils.failure("INCOMPLETE_CHARACTER_REGISTRY")
	_sealed = true
	return Utils.success({"definition_count": _definitions.size()})

func has_definition(character_id: StringName) -> bool:
	return _definitions.has(Utils.normalized_id(character_id))

func get_definition(character_id: StringName):
	return _definitions.get(Utils.normalized_id(character_id), _definitions.get(_fallback_character_id))

func get_fallback_definition():
	return _definitions.get(_fallback_character_id)

func get_character_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _definitions.keys():
		result.append(String(key))
	result.sort()
	return result

func create_report() -> Dictionary:
	return {"schema": SCHEMA, "definition_count": _definitions.size(), "character_ids": get_character_ids(), "fallback_character_id": _fallback_character_id, "sealed": _sealed}
