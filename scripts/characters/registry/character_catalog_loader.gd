class_name CharacterCatalogLoader
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const Definition = preload("res://scripts/characters/contracts/character_definition.gd")
const Registry = preload("res://scripts/characters/registry/character_registry.gd")

func load_registry(path: String) -> Dictionary:
	if not path.begins_with("res://") or not path.ends_with(".json") or path.contains(".."):
		return Utils.failure("INVALID_CHARACTER_CATALOG_PATH")
	if not FileAccess.file_exists(path):
		return Utils.failure("CHARACTER_CATALOG_NOT_FOUND", {"path": path})
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not Utils.is_json_safe(parsed):
		return Utils.failure("INVALID_CHARACTER_CATALOG_JSON")
	if String(parsed.get("schema", "")) != "planet_simulator.character_catalog.v1":
		return Utils.failure("UNSUPPORTED_CHARACTER_CATALOG_SCHEMA")
	var raw_definitions = parsed.get("definitions", [])
	if not raw_definitions is Array or raw_definitions.is_empty() or raw_definitions.size() > 128:
		return Utils.failure("INVALID_CHARACTER_CATALOG_SIZE")
	var registry := Registry.new()
	var fallback_id := Utils.normalized_id(parsed.get("fallback_character_id", ""))
	for raw_definition in raw_definitions:
		if not raw_definition is Dictionary:
			return Utils.failure("INVALID_CHARACTER_CATALOG_ENTRY")
		var definition := Definition.new()
		var setup_result: Dictionary = definition.setup(raw_definition)
		if not setup_result.success:
			return setup_result
		var register_result: Dictionary = registry.register_definition(definition, definition.character_id == fallback_id)
		if not register_result.success:
			return register_result
	var seal_result: Dictionary = registry.seal()
	if not seal_result.success:
		return seal_result
	return Utils.success({"registry": registry, "report": registry.create_report()})
