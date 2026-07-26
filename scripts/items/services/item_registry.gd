extends RefCounted

const ItemDefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemInstanceScript = preload("res://scripts/items/domain/item_instance.gd")
const ItemIdGeneratorScript = preload("res://scripts/items/services/item_id_generator.gd")
const ItemRelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const SCHEMA: String = "planet_simulator.item_registry.v2"
const SCHEMA_VERSION: int = 2
const LEGACY_SCHEMA_VERSION: int = 1

var definitions: Dictionary = {}
var items: Dictionary = {}
var id_generator = ItemIdGeneratorScript.new()


func setup_id_generator(generator) -> void:
	assert(generator != null and generator.has_method("generate"))
	id_generator = generator


func register_definition(definition) -> void:
	assert(definition != null)
	assert(not String(definition.id).is_empty())
	definitions[definition.id] = definition


func create_item(
	definition_id: String,
	quantity: int = 1,
	components: Dictionary = {},
	relation: Dictionary = {},
	display_name: String = ""
) -> Variant:
	var definition = get_definition(definition_id)
	if definition == null:
		return null
	if quantity < 1 or quantity > definition.max_stack:
		return null
	var item_id: String = ""
	for _attempt in range(4):
		var candidate: String = String(id_generator.generate(definition_id))
		if ItemIdGeneratorScript.is_global_id(candidate) and not items.has(candidate):
			item_id = candidate
			break
	if item_id.is_empty():
		return null
	var resolved_name: String = display_name.strip_edges()
	if resolved_name.is_empty():
		resolved_name = String(definition.display_name)
	var item = ItemInstanceScript.new({
		"instance_id": item_id,
		"definition_id": definition_id,
		"display_name": resolved_name,
		"quantity": quantity,
		"components": components,
		"relation": relation,
	})
	items[item_id] = item
	return item


func add_item(item) -> bool:
	if item == null or not ItemIdGeneratorScript.is_global_id(String(item.instance_id)):
		return false
	if items.has(item.instance_id):
		return false
	var definition = get_definition(item.definition_id)
	if definition == null:
		return false
	if int(item.quantity) < 1 or int(item.quantity) > int(definition.max_stack):
		return false
	items[item.instance_id] = item
	return true


func remove_item(item_id: String) -> bool:
	return items.erase(item_id)


func get_item(item_id: String) -> Variant:
	return items.get(item_id)


func get_definition(definition_id: String) -> Variant:
	return definitions.get(definition_id)


func all_items() -> Array:
	return items.values()


func to_dict() -> Dictionary:
	var definition_rows: Array = []
	var definition_ids: Array = definitions.keys()
	definition_ids.sort()
	for definition_id in definition_ids:
		definition_rows.append(definitions[definition_id].to_dict())

	var item_rows: Array = []
	var item_ids: Array = items.keys()
	item_ids.sort()
	for item_id in item_ids:
		item_rows.append(items[item_id].to_dict())

	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"definitions": definition_rows,
		"items": item_rows,
	}


func load_dict(data: Dictionary) -> Dictionary:
	var source_version_result: Dictionary = _resolve_source_version(data)
	if not bool(source_version_result.get("success", false)):
		return source_version_result
	var source_version: int = int(source_version_result.get("version", 0))

	var definition_rows = data.get("definitions", [])
	var item_rows = data.get("items", [])
	if not definition_rows is Array or not item_rows is Array:
		return _failure("INVALID_REGISTRY_ROWS")

	var next_definitions: Dictionary = {}
	for definition_value in definition_rows:
		if not definition_value is Dictionary:
			return _failure("INVALID_DEFINITION_ROW")
		var definition_data: Dictionary = Dictionary(definition_value)
		var definition_validation: Dictionary = _validate_definition_data(definition_data)
		if not bool(definition_validation.get("success", false)):
			return definition_validation
		var definition = ItemDefinitionScript.new(definition_data)
		if next_definitions.has(definition.id):
			return _failure("DUPLICATE_DEFINITION_ID", {"definition_id": definition.id})
		next_definitions[definition.id] = definition

	var next_items: Dictionary = {}
	var legacy_item_ids: Array[String] = []
	for item_value in item_rows:
		if not item_value is Dictionary:
			return _failure("INVALID_ITEM_ROW")
		var item_data: Dictionary = Dictionary(item_value)
		if source_version >= SCHEMA_VERSION:
			if String(item_data.get("schema", "")) != ItemInstanceScript.SCHEMA:
				return _failure("UNSUPPORTED_ITEM_SCHEMA", {
					"schema": String(item_data.get("schema", "")),
				})
			if int(item_data.get("schema_version", 0)) != ItemInstanceScript.SCHEMA_VERSION:
				return _failure("UNSUPPORTED_ITEM_VERSION", {
					"schema_version": int(item_data.get("schema_version", 0)),
				})
		if not item_data.get("relation", {}) is Dictionary:
			return _failure("INVALID_ITEM_RELATION")
		var relation_data: Dictionary = Dictionary(item_data.get("relation", {}))
		if (
			source_version >= SCHEMA_VERSION
			and ItemRelationsScript.kind_of(relation_data) == ItemRelationsScript.WORLD
		):
			var spatial_ref_value = relation_data.get("spatial_ref", {})
			if not spatial_ref_value is Dictionary or not SpatialRefScript.is_valid(spatial_ref_value):
				return _failure("INVALID_ITEM_SPATIAL_REF", {
					"item_id": String(item_data.get("instance_id", "")),
				})
		if not item_data.get("components", {}) is Dictionary:
			return _failure("INVALID_ITEM_COMPONENTS")
		var raw_quantity: int = int(item_data.get("quantity", 1))
		if raw_quantity < 1:
			return _failure("INVALID_ITEM_QUANTITY", {
				"item_id": String(item_data.get("instance_id", "")),
				"quantity": raw_quantity,
			})
		var raw_revision: int = int(item_data.get("revision", 0))
		if raw_revision < 0:
			return _failure("INVALID_ITEM_REVISION", {
				"item_id": String(item_data.get("instance_id", "")),
				"revision": raw_revision,
			})
		var item = ItemInstanceScript.new(item_data)
		if String(item.instance_id).is_empty():
			return _failure("ITEM_ID_REQUIRED")
		if next_items.has(item.instance_id):
			return _failure("DUPLICATE_ITEM_ID", {"item_id": item.instance_id})
		if not next_definitions.has(item.definition_id):
			return _failure("UNKNOWN_DEFINITION", {
				"item_id": item.instance_id,
				"definition_id": item.definition_id,
			})
		var definition = next_definitions[item.definition_id]
		if item.quantity < 1 or item.quantity > definition.max_stack:
			return _failure("INVALID_ITEM_QUANTITY", {"item_id": item.instance_id})
		if source_version >= SCHEMA_VERSION:
			if not ItemIdGeneratorScript.is_global_id(item.instance_id):
				return _failure("INVALID_GLOBAL_ITEM_ID", {"item_id": item.instance_id})
		elif not ItemIdGeneratorScript.is_global_id(item.instance_id):
			legacy_item_ids.append(item.instance_id)
		if item.display_name.strip_edges().is_empty():
			item.display_name = String(definition.display_name)
		next_items[item.instance_id] = item

	definitions = next_definitions
	items = next_items
	return {
		"success": true,
		"source_schema_version": source_version,
		"schema_version": SCHEMA_VERSION,
		"legacy_item_ids": legacy_item_ids,
		"legacy_item_count": legacy_item_ids.size(),
	}


func _validate_definition_data(data: Dictionary) -> Dictionary:
	var definition_id: String = String(data.get("id", ""))
	if definition_id.is_empty():
		return _failure("DEFINITION_ID_REQUIRED")
	var max_stack: int = int(data.get("max_stack", 1))
	if max_stack < 1:
		return _failure("INVALID_DEFINITION_MAX_STACK", {
			"definition_id": definition_id,
			"max_stack": max_stack,
		})
	var unit_mass_kg: float = float(data.get("unit_mass_kg", 0.0))
	if not is_finite(unit_mass_kg) or unit_mass_kg < 0.0:
		return _failure("INVALID_DEFINITION_MASS", {
			"definition_id": definition_id,
		})
	var external_volume_l: float = float(data.get("external_volume_l", 0.0))
	if not is_finite(external_volume_l) or external_volume_l < 0.0:
		return _failure("INVALID_DEFINITION_VOLUME", {
			"definition_id": definition_id,
		})
	var tags_value = data.get("tags", [])
	if not tags_value is Array and not tags_value is PackedStringArray:
		return _failure("INVALID_DEFINITION_TAGS", {
			"definition_id": definition_id,
		})
	if not data.get("metadata", {}) is Dictionary:
		return _failure("INVALID_DEFINITION_METADATA", {
			"definition_id": definition_id,
		})
	return {"success": true}


func _resolve_source_version(data: Dictionary) -> Dictionary:
	var schema: String = String(data.get("schema", ""))
	if schema.is_empty():
		return {"success": true, "version": LEGACY_SCHEMA_VERSION}
	if schema != SCHEMA:
		return _failure("UNSUPPORTED_REGISTRY_SCHEMA", {"schema": schema})
	var version: int = int(data.get("schema_version", 0))
	if version != SCHEMA_VERSION:
		return _failure("UNSUPPORTED_REGISTRY_VERSION", {"schema_version": version})
	return {"success": true, "version": version}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
