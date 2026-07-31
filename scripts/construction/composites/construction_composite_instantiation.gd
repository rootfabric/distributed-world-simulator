extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const ParameterScript = preload("res://scripts/construction/composites/composite_parameter_definition.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")

const SCHEMA: String = "planet_simulator.construction_composite_instantiation.v1"
const FIELDS: Array[String] = [
	"schema",
	"instantiation_id",
	"composite_definition_id",
	"definition_version",
	"definition_checksum",
	"build_plan_id",
	"build_plan_checksum",
	"construct_id",
	"root_item_instance_id",
	"parameter_values",
	"part_bindings",
	"material_bindings",
	"checksum",
]
const PART_BINDING_FIELDS: Array[String] = ["slot_id", "item_instance_id", "part_id"]
const MATERIAL_BINDING_FIELDS: Array[String] = [
	"stage_template_id",
	"definition_id",
	"item_instance_id",
	"quantity",
]


static func create(
	instantiation_id: String,
	definition: Dictionary,
	build_plan: Dictionary,
	part_bindings: Array,
	material_bindings: Array,
	parameter_values: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"instantiation_id": instantiation_id,
		"composite_definition_id": String(definition.get("composite_definition_id", "")),
		"definition_version": int(definition.get("definition_version", 0)),
		"definition_checksum": String(definition.get("checksum", "")),
		"build_plan_id": String(build_plan.get("build_plan_id", "")),
		"build_plan_checksum": String(build_plan.get("checksum", "")),
		"construct_id": String(build_plan.get("construct_id", "")),
		"root_item_instance_id": String(build_plan.get("root_item_instance_id", "")),
		"parameter_values": parameter_values.duplicate(true),
		"part_bindings": _sorted_part_bindings(part_bindings),
		"material_bindings": _sorted_material_bindings(material_bindings),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_COMPOSITE_INSTANTIATION_SCHEMA")
	for pair in [
		["instantiation_id", "composite-instantiation/"],
		["composite_definition_id", "composite-definition/"],
		["build_plan_id", "build-plan/"],
		["construct_id", "construct/"],
		["root_item_instance_id", "item/"],
	]:
		if not _is_identifier(String(value.get(pair[0], "")), String(pair[1])):
			return _failure("INVALID_COMPOSITE_INSTANTIATION_IDENTITY")
	if not UtilsScript.is_json_integer(value.get("definition_version")) or int(value["definition_version"]) < 1:
		return _failure("INVALID_COMPOSITE_INSTANTIATION_DEFINITION_VERSION")
	for field in ["definition_checksum", "build_plan_checksum", "checksum"]:
		if not _is_lower_hex_64(String(value.get(field, ""))):
			return _failure("INVALID_COMPOSITE_INSTANTIATION_CHECKSUM")
	if typeof(value.get("parameter_values")) != TYPE_DICTIONARY:
		return _failure("INVALID_COMPOSITE_INSTANTIATION_PARAMETER_VALUES")
	for raw_parameter_id in value["parameter_values"].keys():
		if not _is_identifier(String(raw_parameter_id), "parameter/"):
			return _failure("INVALID_COMPOSITE_INSTANTIATION_PARAMETER_ID")
		if not bool(UtilsScript.canonicalize(value["parameter_values"][raw_parameter_id]).get("success", false)):
			return _failure("COMPOSITE_INSTANTIATION_PARAMETER_VALUE_NOT_JSON_SAFE")
	if typeof(value.get("part_bindings")) != TYPE_ARRAY or value["part_bindings"].is_empty():
		return _failure("COMPOSITE_INSTANTIATION_PART_BINDINGS_REQUIRED")
	var slots: Dictionary = {}
	var items: Dictionary = {}
	var parts: Dictionary = {}
	var previous_slot: String = ""
	for raw in value["part_bindings"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_COMPOSITE_PART_BINDING")
		var binding: Dictionary = raw
		var binding_exact: Dictionary = UtilsScript.validate_exact_fields(binding, PART_BINDING_FIELDS)
		if not bool(binding_exact.get("success", false)):
			return binding_exact
		if not _is_identifier(String(binding.get("slot_id", "")), "slot/") or not _is_identifier(String(binding.get("item_instance_id", "")), "item/") or not _is_identifier(String(binding.get("part_id", "")), "part/"):
			return _failure("INVALID_COMPOSITE_PART_BINDING_IDENTITY")
		var slot_id: String = String(binding["slot_id"])
		var item_id: String = String(binding["item_instance_id"])
		var part_id: String = String(binding["part_id"])
		if slots.has(slot_id) or items.has(item_id) or parts.has(part_id):
			return _failure("DUPLICATE_COMPOSITE_PART_BINDING")
		if not previous_slot.is_empty() and slot_id < previous_slot:
			return _failure("COMPOSITE_PART_BINDINGS_NOT_SORTED")
		slots[slot_id] = true
		items[item_id] = true
		parts[part_id] = true
		previous_slot = slot_id
	if typeof(value.get("material_bindings")) != TYPE_ARRAY:
		return _failure("INVALID_COMPOSITE_MATERIAL_BINDINGS")
	var previous_key: String = ""
	var seen_material_rows: Dictionary = {}
	for raw in value["material_bindings"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_COMPOSITE_MATERIAL_BINDING")
		var binding: Dictionary = raw
		var binding_exact: Dictionary = UtilsScript.validate_exact_fields(binding, MATERIAL_BINDING_FIELDS)
		if not bool(binding_exact.get("success", false)):
			return binding_exact
		if not _is_identifier(String(binding.get("stage_template_id", "")), "stage-template/") or not _is_plain_identifier(String(binding.get("definition_id", ""))) or not _is_identifier(String(binding.get("item_instance_id", "")), "item/"):
			return _failure("INVALID_COMPOSITE_MATERIAL_BINDING_IDENTITY")
		if not UtilsScript.is_json_integer(binding.get("quantity")) or int(binding["quantity"]) < 1:
			return _failure("INVALID_COMPOSITE_MATERIAL_BINDING_QUANTITY")
		var key: String = _material_key(binding)
		if seen_material_rows.has(key):
			return _failure("DUPLICATE_COMPOSITE_MATERIAL_BINDING")
		if not previous_key.is_empty() and key < previous_key:
			return _failure("COMPOSITE_MATERIAL_BINDINGS_NOT_SORTED")
		seen_material_rows[key] = true
		previous_key = key
	if String(value["checksum"]) != compute_checksum(value):
		return _failure("COMPOSITE_INSTANTIATION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("COMPOSITE_INSTANTIATION_NOT_JSON_SAFE")
	return _success()


static func validate_against_definition(value: Dictionary, definition: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var definition_validation: Dictionary = DefinitionScript.validate(definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	if (
		String(value["composite_definition_id"]) != String(definition["composite_definition_id"])
		or int(value["definition_version"]) != int(definition["definition_version"])
		or String(value["definition_checksum"]) != String(definition["checksum"])
	):
		return _failure("COMPOSITE_INSTANTIATION_DEFINITION_MISMATCH")
	var parameter_definitions: Dictionary = DefinitionScript.parameter_map(definition)
	if _set_from_array(value["parameter_values"].keys()) != _set_from_array(parameter_definitions.keys()):
		return _failure("COMPOSITE_INSTANTIATION_PARAMETER_SET_MISMATCH")
	for parameter_id in parameter_definitions:
		var parameter: Dictionary = parameter_definitions[parameter_id]
		var parameter_validation: Dictionary = ParameterScript.validate_value(parameter, value["parameter_values"][parameter_id])
		if not bool(parameter_validation.get("success", false)):
			return parameter_validation
		if not _canonical_equal(
			ParameterScript.normalize_value(parameter, value["parameter_values"][parameter_id]),
			value["parameter_values"][parameter_id]
		):
			return _failure("COMPOSITE_INSTANTIATION_PARAMETER_NOT_NORMALIZED")
	return _success()


static func validate_against(value: Dictionary, definition: Dictionary, build_plan: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var definition_validation: Dictionary = DefinitionScript.validate(definition)
	if not bool(definition_validation.get("success", false)):
		return definition_validation
	var plan_validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	if (
		String(value["composite_definition_id"]) != String(definition["composite_definition_id"])
		or int(value["definition_version"]) != int(definition["definition_version"])
		or String(value["definition_checksum"]) != String(definition["checksum"])
	):
		return _failure("COMPOSITE_INSTANTIATION_DEFINITION_MISMATCH")
	if (
		String(value["build_plan_id"]) != String(build_plan["build_plan_id"])
		or String(value["build_plan_checksum"]) != String(build_plan["checksum"])
		or String(value["construct_id"]) != String(build_plan["construct_id"])
		or String(value["root_item_instance_id"]) != String(build_plan["root_item_instance_id"])
	):
		return _failure("COMPOSITE_INSTANTIATION_BUILD_PLAN_MISMATCH")
	var parameter_definitions: Dictionary = DefinitionScript.parameter_map(definition)
	if _set_from_array(value["parameter_values"].keys()) != _set_from_array(parameter_definitions.keys()):
		return _failure("COMPOSITE_INSTANTIATION_PARAMETER_SET_MISMATCH")
	for parameter_id in parameter_definitions:
		var parameter: Dictionary = parameter_definitions[parameter_id]
		var parameter_validation: Dictionary = ParameterScript.validate_value(parameter, value["parameter_values"][parameter_id])
		if not bool(parameter_validation.get("success", false)):
			return parameter_validation
		if not _canonical_equal(
			ParameterScript.normalize_value(parameter, value["parameter_values"][parameter_id]),
			value["parameter_values"][parameter_id]
		):
			return _failure("COMPOSITE_INSTANTIATION_PARAMETER_NOT_NORMALIZED")
	var compiled_facets: Dictionary = build_plan["target_snapshot"].get("compiled_facets", {})
	if not _canonical_equal(compiled_facets.get("composite_parameters", {}), value["parameter_values"]):
		return _failure("COMPOSITE_INSTANTIATION_PARAMETER_PROVENANCE_MISMATCH")
	var definition_slots: Dictionary = DefinitionScript.part_slot_map(definition)
	var binding_by_slot: Dictionary = {}
	for binding in value["part_bindings"]:
		binding_by_slot[String(binding["slot_id"])] = binding
	if _set_from_array(binding_by_slot.keys()) != _set_from_array(definition_slots.keys()):
		return _failure("COMPOSITE_INSTANTIATION_PART_BINDING_SET_MISMATCH")
	var target_part_by_id: Dictionary = {}
	for part in build_plan["target_snapshot"]["parts"]:
		target_part_by_id[String(part["part_id"])] = part
	var sources: Dictionary = BuildPlanScript.source_projection_map(build_plan)
	for slot_id in binding_by_slot:
		var binding: Dictionary = binding_by_slot[slot_id]
		var item_id: String = String(binding["item_instance_id"])
		if not target_part_by_id.has(String(binding["part_id"])):
			return _failure("COMPOSITE_INSTANTIATION_BOUND_PART_MISSING")
		if String(target_part_by_id[String(binding["part_id"])]["item_instance_id"]) != item_id:
			return _failure("COMPOSITE_INSTANTIATION_BOUND_ITEM_MISMATCH")
		if not sources.has(item_id):
			return _failure("COMPOSITE_INSTANTIATION_BOUND_SOURCE_MISSING")
		if String(sources[item_id]["definition_id"]) != String(definition_slots[slot_id]["definition_id"]):
			return _failure("COMPOSITE_INSTANTIATION_BOUND_SOURCE_DEFINITION_MISMATCH")
	var expected_material_bindings: Array = []
	for stage_template in definition["stage_templates"]:
		var sequence_index: int = int(stage_template["sequence_index"])
		var stage: Dictionary = build_plan["stages"][sequence_index]
		for allocation in stage["material_allocations"]:
			expected_material_bindings.append({
				"stage_template_id": String(stage_template["stage_template_id"]),
				"definition_id": String(allocation["definition_id"]),
				"item_instance_id": String(allocation["item_instance_id"]),
				"quantity": int(allocation["quantity"]),
			})
	expected_material_bindings = _sorted_material_bindings(expected_material_bindings)
	if not _canonical_equal(expected_material_bindings, value["material_bindings"]):
		return _failure("COMPOSITE_INSTANTIATION_MATERIAL_BINDING_PLAN_MISMATCH")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _sorted_part_bindings(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return String(left.get("slot_id", "")) < String(right.get("slot_id", ""))
	)
	return result


static func _sorted_material_bindings(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return _material_key(left) < _material_key(right)
	)
	return result


static func _material_key(value: Dictionary) -> String:
	return "%s|%s|%s" % [
		String(value.get("stage_template_id", "")),
		String(value.get("definition_id", "")),
		String(value.get("item_instance_id", "")),
	]


static func _set_from_array(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[String(value)] = true
	return result


static func _canonical_equal(left, right) -> bool:
	var left_json: String = UtilsScript.canonical_json(left)
	return not left_json.is_empty() and left_json == UtilsScript.canonical_json(right)


static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()


static func _is_plain_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_.:":
			return false
	return true


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
