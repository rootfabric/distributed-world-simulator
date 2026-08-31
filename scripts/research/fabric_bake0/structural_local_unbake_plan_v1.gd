extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_structural_local_unbake_plan.v1"
const FIELDS: Array[String] = [
	"schema", "plan_id", "source_frontier_hash", "construct_id",
	"parent_structural_descriptor_hash", "parent_reconstruction_mapping_hash", "guard_field_hash",
	"target_region_id", "target_part_ids", "target_part_models", "target_internal_bond_ids",
	"residual_components", "cut_interfaces", "canonical_part_count", "canonical_bond_count",
	"max_full_parts", "minimum_retained_component_parts", "continuity_tolerance",
	"conservation_tolerance", "transition_version", "checksum",
]
const TARGET_MODEL_FIELDS: Array[String] = ["part_id", "mass", "inertia_tensor"]
const COMPONENT_FIELDS: Array[String] = [
	"component_id", "descriptor", "reconstruction_mapping", "part_ids", "bond_ids", "anchor_ids",
]
const INTERFACE_FIELDS: Array[String] = [
	"interface_id", "bond_id", "full_part_id", "residual_part_id", "residual_component_id",
	"full_position_local", "residual_anchor_id", "point_from_parent_com",
]

static func create(
	plan_id: String, source_frontier_hash: String, construct_id: String,
	parent_structural_descriptor_hash: String, parent_reconstruction_mapping_hash: String,
	guard_field_hash: String, target_region_id: String, target_part_ids: Array,
	target_part_models: Array, target_internal_bond_ids: Array, residual_components: Array,
	cut_interfaces: Array, canonical_part_count: int, canonical_bond_count: int,
	max_full_parts: int, minimum_retained_component_parts: int, continuity_tolerance: float,
	conservation_tolerance: float, transition_version: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"plan_id": plan_id,
		"source_frontier_hash": source_frontier_hash,
		"construct_id": construct_id,
		"parent_structural_descriptor_hash": parent_structural_descriptor_hash,
		"parent_reconstruction_mapping_hash": parent_reconstruction_mapping_hash,
		"guard_field_hash": guard_field_hash,
		"target_region_id": target_region_id,
		"target_part_ids": target_part_ids.duplicate(),
		"target_part_models": Utils.sorted_dicts(target_part_models, "part_id"),
		"target_internal_bond_ids": target_internal_bond_ids.duplicate(),
		"residual_components": Utils.sorted_dicts(residual_components, "component_id"),
		"cut_interfaces": Utils.sorted_dicts(cut_interfaces, "interface_id"),
		"canonical_part_count": canonical_part_count,
		"canonical_bond_count": canonical_bond_count,
		"max_full_parts": max_full_parts,
		"minimum_retained_component_parts": minimum_retained_component_parts,
		"continuity_tolerance": continuity_tolerance,
		"conservation_tolerance": conservation_tolerance,
		"transition_version": transition_version,
		"checksum": "",
	}
	value["target_part_ids"].sort()
	value["target_internal_bond_ids"].sort()
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_STRUCTURAL_LOCAL_UNBAKE_PLAN_SCHEMA")
	for field in ["plan_id", "construct_id", "target_region_id"]:
		if not Utils.is_canonical_id(value.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_PLAN_ID", {"field": field})
	for field in ["source_frontier_hash", "parent_structural_descriptor_hash", "parent_reconstruction_mapping_hash", "guard_field_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_PLAN_HASH", {"field": field})
	if not Utils.is_json_integer(value.get("canonical_part_count")) or int(value["canonical_part_count"]) < 2:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_PART_COUNT")
	if not Utils.is_json_integer(value.get("canonical_bond_count")) or int(value["canonical_bond_count"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_BOND_COUNT")
	if not Utils.is_json_integer(value.get("max_full_parts")) or int(value["max_full_parts"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_BOUND")
	if not Utils.is_json_integer(value.get("minimum_retained_component_parts")) or int(value["minimum_retained_component_parts"]) < 100:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_RETAINED_MINIMUM")
	if not Utils.is_positive_number(value.get("continuity_tolerance")) or not Utils.is_positive_number(value.get("conservation_tolerance")):
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TOLERANCE")
	if typeof(value.get("transition_version")) != TYPE_STRING or String(value["transition_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_VERSION")

	checked = Utils.validate_sorted_unique_strings(value.get("target_part_ids"))
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TARGET_PART_IDS")
	if value["target_part_ids"].size() > int(value["max_full_parts"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_TARGET_EXCEEDS_BOUND")
	checked = Utils.validate_sorted_unique_strings(value.get("target_internal_bond_ids"), true)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TARGET_BOND_IDS")
	if typeof(value.get("target_part_models")) != TYPE_ARRAY or value["target_part_models"].size() != value["target_part_ids"].size():
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TARGET_MODELS")
	var target_parts: Dictionary = {}
	for index in range(value["target_part_models"].size()):
		var raw = value["target_part_models"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TARGET_MODEL", {"index": index})
		var model: Dictionary = raw
		checked = Utils.validate_exact_fields(model, TARGET_MODEL_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var part_id := String(model.get("part_id", ""))
		if not Utils.is_canonical_id(part_id, 2) or not value["target_part_ids"].has(part_id):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_TARGET_MODEL_ID_MISMATCH", {"part_id": part_id})
		if target_parts.has(part_id) or not Utils.is_positive_number(model.get("mass")):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TARGET_MODEL", {"part_id": part_id})
		checked = _validate_matrix3(model.get("inertia_tensor"))
		if not bool(checked.get("success", false)):
			return checked
		target_parts[part_id] = true

	if typeof(value.get("residual_components")) != TYPE_ARRAY or value["residual_components"].is_empty():
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_REQUIRES_RETAINED_COMPONENT")
	var covered_parts: Dictionary = target_parts.duplicate()
	var covered_bonds: Dictionary = {}
	for bond_id in value["target_internal_bond_ids"]:
		if covered_bonds.has(String(bond_id)):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_DUPLICATE_BOND_COVERAGE")
		covered_bonds[String(bond_id)] = true
	var component_parts: Dictionary = {}
	var component_ids: Dictionary = {}
	for index in range(value["residual_components"].size()):
		var raw = value["residual_components"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPONENT", {"index": index})
		var component: Dictionary = raw
		checked = Utils.validate_exact_fields(component, COMPONENT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var component_id := String(component.get("component_id", ""))
		if not Utils.is_canonical_id(component_id, 2) or component_ids.has(component_id):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPONENT_ID", {"component_id": component_id})
		component_ids[component_id] = true
		checked = Utils.validate_sorted_unique_strings(component.get("part_ids"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPONENT_PART_IDS", {"component_id": component_id})
		if component["part_ids"].size() < int(value["minimum_retained_component_parts"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_COMPONENT_BELOW_MINIMUM", {"component_id": component_id})
		checked = Utils.validate_sorted_unique_strings(component.get("bond_ids"), true)
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPONENT_BOND_IDS", {"component_id": component_id})
		checked = Utils.validate_sorted_unique_strings(component.get("anchor_ids"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPONENT_ANCHOR_IDS", {"component_id": component_id})
		if typeof(component.get("descriptor")) != TYPE_DICTIONARY or typeof(component.get("reconstruction_mapping")) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPONENT_ARTIFACT", {"component_id": component_id})
		checked = Descriptor.validate(component["descriptor"])
		if not bool(checked.get("success", false)):
			return checked
		checked = Reconstruction.validate(component["reconstruction_mapping"])
		if not bool(checked.get("success", false)):
			return checked
		var descriptor: Dictionary = component["descriptor"]
		var mapping: Dictionary = component["reconstruction_mapping"]
		if String(descriptor["source_frontier_hash"]) != String(value["source_frontier_hash"]) or String(mapping["source_frontier_hash"]) != String(value["source_frontier_hash"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_COMPONENT_FRONTIER_MISMATCH", {"component_id": component_id})
		if String(descriptor["construct_id"]) != String(value["construct_id"]) or String(mapping["construct_id"]) != String(value["construct_id"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_COMPONENT_CONSTRUCT_MISMATCH", {"component_id": component_id})
		if String(descriptor["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_COMPONENT_MAPPING_MISMATCH", {"component_id": component_id})
		if int(descriptor["part_count"]) != component["part_ids"].size() or int(descriptor["bond_count"]) != component["bond_ids"].size():
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_COMPONENT_COUNT_MISMATCH", {"component_id": component_id})
		for part_id in component["part_ids"]:
			var key := String(part_id)
			if covered_parts.has(key):
				return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_PART_OWNERSHIP_OVERLAP", {"part_id": key})
			covered_parts[key] = true
			component_parts[key] = component_id
		for bond_id in component["bond_ids"]:
			var key := String(bond_id)
			if covered_bonds.has(key):
				return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_DUPLICATE_BOND_COVERAGE", {"bond_id": key})
			covered_bonds[key] = true
	if covered_parts.size() != int(value["canonical_part_count"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_PART_COVERAGE_MISMATCH", {"covered": covered_parts.size()})

	if typeof(value.get("cut_interfaces")) != TYPE_ARRAY or value["cut_interfaces"].is_empty():
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_CUT_INTERFACE_REQUIRED")
	var interface_ids: Dictionary = {}
	for index in range(value["cut_interfaces"].size()):
		var raw = value["cut_interfaces"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_INTERFACE", {"index": index})
		var interface: Dictionary = raw
		checked = Utils.validate_exact_fields(interface, INTERFACE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		for field in ["interface_id", "bond_id", "full_part_id", "residual_part_id", "residual_component_id", "residual_anchor_id"]:
			if not Utils.is_canonical_id(interface.get(field), 2):
				return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_INTERFACE_ID", {"index": index, "field": field})
		var interface_id := String(interface["interface_id"])
		if interface_ids.has(interface_id):
			return Utils.failure("DUPLICATE_STRUCTURAL_LOCAL_UNBAKE_INTERFACE", {"interface_id": interface_id})
		interface_ids[interface_id] = true
		var bond_id := String(interface["bond_id"])
		if covered_bonds.has(bond_id):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_DUPLICATE_BOND_COVERAGE", {"bond_id": bond_id})
		covered_bonds[bond_id] = true
		if not target_parts.has(String(interface["full_part_id"])):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_INTERFACE_FULL_PART_MISMATCH", {"interface_id": interface_id})
		var residual_part_id := String(interface["residual_part_id"])
		if not component_parts.has(residual_part_id) or String(component_parts[residual_part_id]) != String(interface["residual_component_id"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_INTERFACE_RESIDUAL_PART_MISMATCH", {"interface_id": interface_id})
		checked = _validate_vec3(interface.get("full_position_local"))
		if not bool(checked.get("success", false)):
			return checked
		checked = _validate_vec3(interface.get("point_from_parent_com"))
		if not bool(checked.get("success", false)):
			return checked
		var found_anchor := false
		for component in value["residual_components"]:
			if String(component["component_id"]) != String(interface["residual_component_id"]):
				continue
			for anchor in component["descriptor"]["boundary_anchors"]:
				if String(anchor["anchor_id"]) == String(interface["residual_anchor_id"]) and String(anchor["part_id"]) == residual_part_id:
					found_anchor = true
					break
		if not found_anchor:
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_INTERFACE_ANCHOR_MISSING", {"interface_id": interface_id})
	if covered_bonds.size() != int(value["canonical_bond_count"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_BOND_COVERAGE_MISMATCH", {"covered": covered_bonds.size()})
	return Utils.validate_checksum(value)

static func _validate_vec3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_VECTOR3")
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_VECTOR3")
	return Utils.success()

static func _validate_matrix3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_INERTIA")
	for row in value:
		if typeof(row) != TYPE_ARRAY or row.size() != 3:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_INERTIA")
		for component in row:
			if not Utils.is_finite_number(component):
				return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_INERTIA")
	return Utils.success()
