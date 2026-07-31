extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const PartSlotScript = preload("res://scripts/construction/composites/composite_part_slot.gd")
const BondTemplateScript = preload("res://scripts/construction/composites/composite_bond_template.gd")
const StageTemplateScript = preload("res://scripts/construction/composites/composite_stage_template.gd")
const ParameterScript = preload("res://scripts/construction/composites/composite_parameter_definition.gd")
const ExposedPortScript = preload("res://scripts/construction/composites/composite_exposed_port.gd")
const BuildStageScript = preload("res://scripts/construction/build/construction_build_stage.gd")

const SCHEMA: String = "planet_simulator.construction_composite_definition.v1"
const FIELDS: Array[String] = [
	"schema",
	"composite_definition_id",
	"definition_version",
	"display_name",
	"root_definition_id",
	"root_display_name",
	"part_slots",
	"bond_templates",
	"stage_templates",
	"parameters",
	"exposed_ports",
	"provenance",
	"checksum",
]
const PROVENANCE_FIELDS: Array[String] = [
	"source_kind",
	"source_construct_checksum",
	"source_build_plan_checksum",
	"created_by",
]
const SOURCE_BUILD_PLAN_COMPLETION: String = "BUILD_PLAN_COMPLETION"
const SOURCE_MANUAL: String = "MANUAL"
const SOURCE_KINDS: Array[String] = [SOURCE_BUILD_PLAN_COMPLETION, SOURCE_MANUAL]


static func create(
	composite_definition_id: String,
	definition_version: int,
	display_name: String,
	root_definition_id: String,
	root_display_name: String,
	part_slots: Array,
	bond_templates: Array,
	stage_templates: Array,
	provenance: Dictionary,
	parameters: Array = [],
	exposed_ports: Array = []
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"composite_definition_id": composite_definition_id,
		"definition_version": definition_version,
		"display_name": display_name,
		"root_definition_id": root_definition_id,
		"root_display_name": root_display_name,
		"part_slots": _sorted_records(part_slots, "slot_id"),
		"bond_templates": _sorted_records(bond_templates, "bond_template_id"),
		"stage_templates": _sorted_stages(stage_templates),
		"parameters": _sorted_records(parameters, "parameter_id"),
		"exposed_ports": _sorted_records(exposed_ports, "port_id"),
		"provenance": provenance.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_COMPOSITE_DEFINITION_SCHEMA")
	if not _is_path_id(String(value.get("composite_definition_id", "")), "composite-definition/"):
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_DEFINITION_ID")
	if not UtilsScript.is_json_integer(value.get("definition_version")) or int(value["definition_version"]) < 1:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_DEFINITION_VERSION")
	for field in ["display_name", "root_display_name"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).strip_edges().is_empty():
			return _failure("CONSTRUCTION_COMPOSITE_%s_REQUIRED" % field.to_upper())
	if not _is_plain_identifier(String(value.get("root_definition_id", ""))):
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_ROOT_DEFINITION_ID")
	if String(value["root_definition_id"]) != "construct_root":
		return _failure("UNSUPPORTED_CONSTRUCTION_COMPOSITE_ROOT_DEFINITION")
	if typeof(value.get("part_slots")) != TYPE_ARRAY or value["part_slots"].is_empty():
		return _failure("CONSTRUCTION_COMPOSITE_PART_SLOTS_REQUIRED")
	var part_slots: Dictionary = {}
	var previous_slot_id: String = ""
	for raw in value["part_slots"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_PART_SLOT")
		var slot: Dictionary = raw
		var validation: Dictionary = PartSlotScript.validate(slot)
		if not bool(validation.get("success", false)):
			return validation
		var slot_id: String = String(slot["slot_id"])
		if part_slots.has(slot_id):
			return _failure("DUPLICATE_CONSTRUCTION_COMPOSITE_PART_SLOT")
		if not previous_slot_id.is_empty() and slot_id < previous_slot_id:
			return _failure("CONSTRUCTION_COMPOSITE_PART_SLOTS_NOT_SORTED")
		part_slots[slot_id] = slot
		previous_slot_id = slot_id
	if typeof(value.get("parameters")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_PARAMETERS")
	var parameter_ids: Dictionary = {}
	var previous_parameter_id: String = ""
	for raw in value["parameters"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_PARAMETER")
		var parameter: Dictionary = raw
		var parameter_validation: Dictionary = ParameterScript.validate(parameter)
		if not bool(parameter_validation.get("success", false)):
			return parameter_validation
		var parameter_id: String = String(parameter["parameter_id"])
		if parameter_ids.has(parameter_id):
			return _failure("DUPLICATE_CONSTRUCTION_COMPOSITE_PARAMETER")
		if not previous_parameter_id.is_empty() and parameter_id < previous_parameter_id:
			return _failure("CONSTRUCTION_COMPOSITE_PARAMETERS_NOT_SORTED")
		parameter_ids[parameter_id] = parameter
		previous_parameter_id = parameter_id
	if typeof(value.get("exposed_ports")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_EXPOSED_PORTS")
	var port_ids: Dictionary = {}
	var previous_port_id: String = ""
	for raw in value["exposed_ports"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_EXPOSED_PORT")
		var port: Dictionary = raw
		var port_validation: Dictionary = ExposedPortScript.validate(port)
		if not bool(port_validation.get("success", false)):
			return port_validation
		var port_id: String = String(port["port_id"])
		if port_ids.has(port_id):
			return _failure("DUPLICATE_CONSTRUCTION_COMPOSITE_EXPOSED_PORT")
		if not previous_port_id.is_empty() and port_id < previous_port_id:
			return _failure("CONSTRUCTION_COMPOSITE_EXPOSED_PORTS_NOT_SORTED")
		if not part_slots.has(String(port["slot_id"])):
			return _failure("CONSTRUCTION_COMPOSITE_EXPOSED_PORT_REFERENCES_UNKNOWN_SLOT")
		port_ids[port_id] = port
		previous_port_id = port_id
	if typeof(value.get("bond_templates")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_BOND_TEMPLATES")
	var bond_templates: Dictionary = {}
	var previous_bond_id: String = ""
	for raw in value["bond_templates"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_BOND_TEMPLATE")
		var bond: Dictionary = raw
		var validation: Dictionary = BondTemplateScript.validate(bond)
		if not bool(validation.get("success", false)):
			return validation
		var bond_id: String = String(bond["bond_template_id"])
		if bond_templates.has(bond_id):
			return _failure("DUPLICATE_CONSTRUCTION_COMPOSITE_BOND_TEMPLATE")
		if not previous_bond_id.is_empty() and bond_id < previous_bond_id:
			return _failure("CONSTRUCTION_COMPOSITE_BOND_TEMPLATES_NOT_SORTED")
		if not part_slots.has(String(bond["part_a_slot_id"])) or not part_slots.has(String(bond["part_b_slot_id"])):
			return _failure("CONSTRUCTION_COMPOSITE_BOND_REFERENCES_UNKNOWN_SLOT")
		bond_templates[bond_id] = bond
		previous_bond_id = bond_id
	if typeof(value.get("stage_templates")) != TYPE_ARRAY or value["stage_templates"].is_empty():
		return _failure("CONSTRUCTION_COMPOSITE_STAGE_TEMPLATES_REQUIRED")
	var stage_ids: Dictionary = {}
	var previous_parts: Dictionary = {}
	var previous_bonds: Dictionary = {}
	for index in range(value["stage_templates"].size()):
		var raw = value["stage_templates"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPOSITE_STAGE_TEMPLATE")
		var stage: Dictionary = raw
		var validation: Dictionary = StageTemplateScript.validate(stage)
		if not bool(validation.get("success", false)):
			return validation
		if int(stage["sequence_index"]) != index:
			return _failure("CONSTRUCTION_COMPOSITE_STAGE_INDEX_GAP")
		var stage_id: String = String(stage["stage_template_id"])
		if stage_ids.has(stage_id):
			return _failure("DUPLICATE_CONSTRUCTION_COMPOSITE_STAGE_TEMPLATE")
		stage_ids[stage_id] = true
		var current_parts: Dictionary = _set_from_array(stage["included_part_slot_ids"])
		var current_bonds: Dictionary = _set_from_array(stage["included_bond_template_ids"])
		if index == 0 and current_parts.is_empty():
			return _failure("CONSTRUCTION_COMPOSITE_FIRST_STAGE_MUST_INCLUDE_PART")
		if not _is_subset(previous_parts, current_parts) or not _is_subset(previous_bonds, current_bonds):
			return _failure("CONSTRUCTION_COMPOSITE_STAGE_CONTENT_REGRESSED")
		for slot_id in current_parts:
			if not part_slots.has(slot_id):
				return _failure("CONSTRUCTION_COMPOSITE_STAGE_REFERENCES_UNKNOWN_SLOT")
		for bond_id in current_bonds:
			if not bond_templates.has(bond_id):
				return _failure("CONSTRUCTION_COMPOSITE_STAGE_REFERENCES_UNKNOWN_BOND")
			var bond: Dictionary = bond_templates[bond_id]
			if not current_parts.has(String(bond["part_a_slot_id"])) or not current_parts.has(String(bond["part_b_slot_id"])):
				return _failure("CONSTRUCTION_COMPOSITE_STAGE_BOND_ENDPOINT_NOT_INCLUDED")
		if current_parts.size() == previous_parts.size() and stage["material_requirements"].is_empty():
			return _failure("CONSTRUCTION_COMPOSITE_STAGE_MAKES_NO_PROGRESS")
		previous_parts = current_parts
		previous_bonds = current_bonds
	var final_stage: Dictionary = value["stage_templates"][-1]
	if String(final_stage["semantic_state"]) != BuildStageScript.SEMANTIC_OPERATIONAL:
		return _failure("CONSTRUCTION_COMPOSITE_FINAL_STAGE_NOT_OPERATIONAL")
	if _set_from_array(final_stage["included_part_slot_ids"]) != _set_from_array(part_slots.keys()):
		return _failure("CONSTRUCTION_COMPOSITE_FINAL_STAGE_PART_SET_INCOMPLETE")
	if _set_from_array(final_stage["included_bond_template_ids"]) != _set_from_array(bond_templates.keys()):
		return _failure("CONSTRUCTION_COMPOSITE_FINAL_STAGE_BOND_SET_INCOMPLETE")
	var provenance_validation: Dictionary = _validate_provenance(value.get("provenance"))
	if not bool(provenance_validation.get("success", false)):
		return provenance_validation
	if _contains_instance_identifier(value):
		return _failure("CONSTRUCTION_COMPOSITE_DEFINITION_LEAKS_INSTANCE_ID")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_COMPOSITE_DEFINITION_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_COMPOSITE_DEFINITION_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func part_slot_map(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot in value.get("part_slots", []):
		result[String(slot.get("slot_id", ""))] = Dictionary(slot).duplicate(true)
	return result


static func bond_template_map(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for bond in value.get("bond_templates", []):
		result[String(bond.get("bond_template_id", ""))] = Dictionary(bond).duplicate(true)
	return result


static func parameter_map(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for parameter in value.get("parameters", []):
		result[String(parameter.get("parameter_id", ""))] = Dictionary(parameter).duplicate(true)
	return result


static func exposed_port_map(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for port in value.get("exposed_ports", []):
		result[String(port.get("port_id", ""))] = Dictionary(port).duplicate(true)
	return result


static func _validate_provenance(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_PROVENANCE")
	var provenance: Dictionary = value
	var exact: Dictionary = UtilsScript.validate_exact_fields(provenance, PROVENANCE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if not SOURCE_KINDS.has(String(provenance.get("source_kind", ""))):
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_SOURCE_KIND")
	for field in ["source_construct_checksum", "source_build_plan_checksum"]:
		var checksum: String = String(provenance.get(field, ""))
		if String(provenance["source_kind"]) == SOURCE_BUILD_PLAN_COMPLETION:
			if not _is_lower_hex_64(checksum):
				return _failure("INVALID_CONSTRUCTION_COMPOSITE_SOURCE_CHECKSUM")
		elif not checksum.is_empty():
			return _failure("MANUAL_COMPOSITE_SOURCE_CHECKSUM_MUST_BE_EMPTY")
	if not _is_path_id(String(provenance.get("created_by", "")), "actor/"):
		return _failure("INVALID_CONSTRUCTION_COMPOSITE_CREATOR")
	return _success()


static func _contains_instance_identifier(value) -> bool:
	if value is Dictionary:
		for key in value:
			if String(key) == "checksum":
				continue
			if _contains_instance_identifier(value[key]):
				return true
		return false
	if value is Array:
		for entry in value:
			if _contains_instance_identifier(entry):
				return true
		return false
	if typeof(value) == TYPE_STRING:
		var text: String = String(value)
		for prefix in ["item/", "construct/", "build-plan/", "operation/", "plan/"]:
			if text.begins_with(prefix):
				return true
	return false


static func _sorted_records(values: Array, id_field: String) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return String(left.get(id_field, "")) < String(right.get(id_field, ""))
	)
	return result


static func _sorted_stages(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(left, right):
		return int(left.get("sequence_index", -1)) < int(right.get("sequence_index", -1))
	)
	return result


static func _set_from_array(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[String(value)] = true
	return result


static func _is_subset(left: Dictionary, right: Dictionary) -> bool:
	for key in left:
		if not right.has(key):
			return false
	return true


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


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
