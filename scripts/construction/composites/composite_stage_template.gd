extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BuildStageScript = preload("res://scripts/construction/build/construction_build_stage.gd")

const SCHEMA: String = "planet_simulator.composite_stage_template.v1"
const FIELDS: Array[String] = [
	"schema",
	"stage_template_id",
	"sequence_index",
	"display_name",
	"semantic_state",
	"included_part_slot_ids",
	"included_bond_template_ids",
	"material_requirements",
	"required_capabilities",
]
const MATERIAL_FIELDS: Array[String] = ["definition_id", "quantity"]


static func create(
	stage_template_id: String,
	sequence_index: int,
	display_name: String,
	semantic_state: String,
	included_part_slot_ids: Array,
	included_bond_template_ids: Array,
	material_requirements: Array = [],
	required_capabilities: Array = []
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"stage_template_id": stage_template_id,
		"sequence_index": sequence_index,
		"display_name": display_name,
		"semantic_state": semantic_state,
		"included_part_slot_ids": _sorted_strings(included_part_slot_ids),
		"included_bond_template_ids": _sorted_strings(included_bond_template_ids),
		"material_requirements": _sorted_requirements(material_requirements),
		"required_capabilities": _sorted_strings(required_capabilities),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_COMPOSITE_STAGE_TEMPLATE_SCHEMA")
	if not _is_path_id(String(value.get("stage_template_id", "")), "stage-template/"):
		return _failure("INVALID_COMPOSITE_STAGE_TEMPLATE_ID")
	if not UtilsScript.is_json_integer(value.get("sequence_index")) or int(value["sequence_index"]) < 0:
		return _failure("INVALID_COMPOSITE_STAGE_TEMPLATE_INDEX")
	if typeof(value.get("display_name")) != TYPE_STRING or String(value["display_name"]).strip_edges().is_empty():
		return _failure("COMPOSITE_STAGE_TEMPLATE_NAME_REQUIRED")
	if not BuildStageScript.SEMANTIC_STATES.has(String(value.get("semantic_state", ""))):
		return _failure("INVALID_COMPOSITE_STAGE_SEMANTIC_STATE")
	var slots: Dictionary = _validate_sorted_ids(value.get("included_part_slot_ids"), "slot/")
	if not bool(slots.get("success", false)):
		return _failure("INVALID_COMPOSITE_STAGE_PART_SLOTS")
	var bonds: Dictionary = _validate_sorted_ids(value.get("included_bond_template_ids"), "bond-template/")
	if not bool(bonds.get("success", false)):
		return _failure("INVALID_COMPOSITE_STAGE_BOND_TEMPLATES")
	if typeof(value.get("material_requirements")) != TYPE_ARRAY:
		return _failure("INVALID_COMPOSITE_STAGE_MATERIAL_REQUIREMENTS")
	var previous_definition_id: String = ""
	var seen: Dictionary = {}
	for raw in value["material_requirements"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_COMPOSITE_STAGE_MATERIAL_REQUIREMENT")
		var requirement: Dictionary = raw
		var requirement_exact: Dictionary = UtilsScript.validate_exact_fields(requirement, MATERIAL_FIELDS)
		if not bool(requirement_exact.get("success", false)):
			return requirement_exact
		var definition_id: String = String(requirement.get("definition_id", ""))
		if not _is_plain_identifier(definition_id):
			return _failure("INVALID_COMPOSITE_STAGE_MATERIAL_DEFINITION")
		if not UtilsScript.is_json_integer(requirement.get("quantity")) or int(requirement["quantity"]) < 1:
			return _failure("INVALID_COMPOSITE_STAGE_MATERIAL_QUANTITY")
		if seen.has(definition_id):
			return _failure("DUPLICATE_COMPOSITE_STAGE_MATERIAL_DEFINITION")
		if not previous_definition_id.is_empty() and definition_id < previous_definition_id:
			return _failure("COMPOSITE_STAGE_MATERIAL_REQUIREMENTS_NOT_SORTED")
		seen[definition_id] = true
		previous_definition_id = definition_id
	var capabilities: Dictionary = _validate_capabilities(value.get("required_capabilities"))
	if not bool(capabilities.get("success", false)):
		return capabilities
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("COMPOSITE_STAGE_TEMPLATE_NOT_JSON_SAFE")
	return _success()


static func _validate_sorted_ids(value, prefix: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_COMPOSITE_STAGE_ID_COLLECTION")
	var seen: Dictionary = {}
	var previous: String = ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_COMPOSITE_STAGE_ID_COLLECTION")
		var identifier: String = String(raw)
		if not _is_path_id(identifier, prefix) or seen.has(identifier):
			return _failure("INVALID_COMPOSITE_STAGE_ID_COLLECTION")
		if not previous.is_empty() and identifier < previous:
			return _failure("COMPOSITE_STAGE_IDS_NOT_SORTED")
		seen[identifier] = true
		previous = identifier
	return _success()


static func _validate_capabilities(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_COMPOSITE_STAGE_REQUIRED_CAPABILITIES")
	var seen: Dictionary = {}
	var previous: String = ""
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_COMPOSITE_STAGE_REQUIRED_CAPABILITY")
		var capability: String = String(raw)
		if not _is_upper_kind(capability) or seen.has(capability):
			return _failure("INVALID_COMPOSITE_STAGE_REQUIRED_CAPABILITY")
		if not previous.is_empty() and capability < previous:
			return _failure("COMPOSITE_STAGE_REQUIRED_CAPABILITIES_NOT_SORTED")
		seen[capability] = true
		previous = capability
	return _success()


static func _sorted_requirements(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return String(left.get("definition_id", "")) < String(right.get("definition_id", ""))
	)
	return result


static func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_plain_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_.:":
			return false
	return true


static func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
