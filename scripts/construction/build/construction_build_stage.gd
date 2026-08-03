extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_build_stage.v1"
const SEMANTIC_FOUNDATION: String = "FOUNDATION"
const SEMANTIC_FRAME: String = "FRAME"
const SEMANTIC_STRUCTURE: String = "STRUCTURE"
const SEMANTIC_COMMISSIONING: String = "COMMISSIONING"
const SEMANTIC_OPERATIONAL: String = "OPERATIONAL"
const SEMANTIC_STATES: Array[String] = [
	SEMANTIC_FOUNDATION,
	SEMANTIC_FRAME,
	SEMANTIC_STRUCTURE,
	SEMANTIC_COMMISSIONING,
	SEMANTIC_OPERATIONAL,
]
const FIELDS: Array[String] = [
	"schema",
	"stage_id",
	"sequence_index",
	"display_name",
	"semantic_state",
	"included_part_ids",
	"included_bond_ids",
	"material_allocations",
	"required_capabilities",
]
const MATERIAL_FIELDS: Array[String] = ["item_instance_id", "definition_id", "quantity"]


static func create(
	stage_id: String,
	sequence_index: int,
	display_name: String,
	semantic_state: String,
	included_part_ids: Array,
	included_bond_ids: Array,
	material_allocations: Array = [],
	required_capabilities: Array = []
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"stage_id": stage_id,
		"sequence_index": sequence_index,
		"display_name": display_name,
		"semantic_state": semantic_state,
		"included_part_ids": _sorted_strings(included_part_ids),
		"included_bond_ids": _sorted_strings(included_bond_ids),
		"material_allocations": _sorted_allocations(material_allocations),
		"required_capabilities": _sorted_strings(required_capabilities),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_BUILD_STAGE_SCHEMA")
	if not _is_identifier(String(value.get("stage_id", "")), "stage/"):
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_ID")
	if not UtilsScript.is_json_integer(value.get("sequence_index")) or int(value["sequence_index"]) < 0:
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_INDEX")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty():
		return _failure("CONSTRUCTION_BUILD_STAGE_NAME_REQUIRED")
	if typeof(value.get("semantic_state")) != TYPE_STRING or not SEMANTIC_STATES.has(String(value["semantic_state"])):
		return _failure("INVALID_CONSTRUCTION_BUILD_STAGE_SEMANTIC_STATE")
	var parts_validation: Dictionary = _validate_identifier_array(value.get("included_part_ids"), "part/", "INVALID_BUILD_STAGE_PART_IDS")
	if not bool(parts_validation.get("success", false)):
		return parts_validation
	var bonds_validation: Dictionary = _validate_identifier_array(value.get("included_bond_ids"), "bond/", "INVALID_BUILD_STAGE_BOND_IDS")
	if not bool(bonds_validation.get("success", false)):
		return bonds_validation
	if typeof(value.get("material_allocations")) != TYPE_ARRAY:
		return _failure("INVALID_BUILD_STAGE_MATERIAL_ALLOCATIONS")
	var previous_item_id: String = ""
	var seen_material_items: Dictionary = {}
	for allocation_value in value["material_allocations"]:
		if typeof(allocation_value) != TYPE_DICTIONARY:
			return _failure("INVALID_BUILD_STAGE_MATERIAL_ALLOCATION")
		var allocation: Dictionary = allocation_value
		var allocation_exact: Dictionary = UtilsScript.validate_exact_fields(allocation, MATERIAL_FIELDS)
		if not bool(allocation_exact.get("success", false)):
			return allocation_exact
		var item_id: String = String(allocation.get("item_instance_id", ""))
		var definition_id: String = String(allocation.get("definition_id", ""))
		if not _is_identifier(item_id, "item/") or not _is_plain_identifier(definition_id):
			return _failure("INVALID_BUILD_STAGE_MATERIAL_IDENTITY")
		if not UtilsScript.is_json_integer(allocation.get("quantity")) or int(allocation["quantity"]) < 1:
			return _failure("INVALID_BUILD_STAGE_MATERIAL_QUANTITY")
		if seen_material_items.has(item_id):
			return _failure("DUPLICATE_BUILD_STAGE_MATERIAL_ITEM")
		if not previous_item_id.is_empty() and item_id < previous_item_id:
			return _failure("BUILD_STAGE_MATERIAL_ALLOCATIONS_NOT_SORTED")
		seen_material_items[item_id] = true
		previous_item_id = item_id
	var capabilities_validation: Dictionary = _validate_capabilities(value.get("required_capabilities"))
	if not bool(capabilities_validation.get("success", false)):
		return capabilities_validation
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_BUILD_STAGE_NOT_JSON_SAFE")
	return _success()


static func allocation_quantity_for(stage: Dictionary, item_instance_id: String) -> int:
	for allocation in stage.get("material_allocations", []):
		if String(allocation.get("item_instance_id", "")) == item_instance_id:
			return int(allocation.get("quantity", 0))
	return 0


static func _validate_identifier_array(value, prefix: String, error_code: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure(error_code)
	var previous: String = ""
	var seen: Dictionary = {}
	for raw_id in value:
		if typeof(raw_id) != TYPE_STRING:
			return _failure(error_code)
		var identifier: String = String(raw_id)
		if not _is_identifier(identifier, prefix) or seen.has(identifier):
			return _failure(error_code)
		if not previous.is_empty() and identifier < previous:
			return _failure(error_code)
		seen[identifier] = true
		previous = identifier
	return _success()


static func _validate_capabilities(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_BUILD_STAGE_REQUIRED_CAPABILITIES")
	var previous: String = ""
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_BUILD_STAGE_REQUIRED_CAPABILITY")
		var capability: String = String(raw)
		if not _is_upper_kind(capability) or seen.has(capability):
			return _failure("INVALID_BUILD_STAGE_REQUIRED_CAPABILITY")
		if not previous.is_empty() and capability < previous:
			return _failure("BUILD_STAGE_REQUIRED_CAPABILITIES_NOT_SORTED")
		seen[capability] = true
		previous = capability
	return _success()


static func _sorted_allocations(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return String(left.get("item_instance_id", "")) < String(right.get("item_instance_id", ""))
	)
	return result


static func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result


static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()


static func _is_plain_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not String(character) in [
			"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
			"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_", ".",
		]:
			return false
	return true


static func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_upper():
		return false
	for character in value:
		if not String(character) in [
			"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
			"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "_",
		]:
			return false
	return true


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
