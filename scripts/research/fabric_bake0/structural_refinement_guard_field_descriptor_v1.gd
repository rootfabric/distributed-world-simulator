extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_structural_refinement_guard_field.v1"
const DYNAMICS_MODEL := "RIGID_TREE_INVERSE_DYNAMICS"
const FIELDS: Array[String] = [
	"schema", "field_id", "source_frontier_hash", "construct_id", "structural_descriptor_hash",
	"reconstruction_mapping_hash", "capacity_certificate_hash", "root_part_id", "dynamics_model",
	"trigger_ratio", "required_refinement_level", "residual_force_tolerance", "residual_moment_tolerance",
	"part_models", "bond_models", "region_guards", "evaluator_version", "checksum",
]
const PART_FIELDS: Array[String] = [
	"part_id", "region_id", "mass", "position_from_com", "inertia_tensor_body", "depth",
]
const BOND_FIELDS: Array[String] = [
	"bond_id", "parent_part_id", "child_part_id", "mapped_region_id", "point_from_com",
	"certified_force_capacity", "certified_moment_capacity", "uncertainty_ratio",
]
const MATRIX_TOLERANCE := 1.0e-10

static func create(
	field_id: String, source_frontier_hash: String, construct_id: String,
	structural_descriptor_hash: String, reconstruction_mapping_hash: String,
	capacity_certificate_hash: String, root_part_id: String, trigger_ratio: float,
	required_refinement_level: int, residual_force_tolerance: float,
	residual_moment_tolerance: float, part_models: Array, bond_models: Array,
	region_guards: Array, evaluator_version: String
) -> Dictionary:
	var parts := Utils.sorted_dicts(part_models, "part_id")
	var bonds := Utils.sorted_dicts(bond_models, "bond_id")
	var guards := Utils.sorted_dicts(region_guards, "guard_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"field_id": field_id,
		"source_frontier_hash": source_frontier_hash,
		"construct_id": construct_id,
		"structural_descriptor_hash": structural_descriptor_hash,
		"reconstruction_mapping_hash": reconstruction_mapping_hash,
		"capacity_certificate_hash": capacity_certificate_hash,
		"root_part_id": root_part_id,
		"dynamics_model": DYNAMICS_MODEL,
		"trigger_ratio": trigger_ratio,
		"required_refinement_level": required_refinement_level,
		"residual_force_tolerance": residual_force_tolerance,
		"residual_moment_tolerance": residual_moment_tolerance,
		"part_models": parts,
		"bond_models": bonds,
		"region_guards": guards,
		"evaluator_version": evaluator_version,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_STRUCTURAL_REFINEMENT_GUARD_FIELD_SCHEMA")
	for field in ["field_id", "construct_id", "root_part_id"]:
		if not Utils.is_canonical_id(value.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_GUARD_FIELD_ID", {"field": field})
	for field in ["source_frontier_hash", "structural_descriptor_hash", "reconstruction_mapping_hash", "capacity_certificate_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_GUARD_FIELD_HASH", {"field": field})
	if String(value.get("dynamics_model", "")) != DYNAMICS_MODEL:
		return Utils.failure("UNSUPPORTED_STRUCTURAL_REFINEMENT_DYNAMICS_MODEL")
	if not Utils.is_positive_number(value.get("trigger_ratio")) or float(value["trigger_ratio"]) >= 1.0:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_TRIGGER_RATIO")
	if not Utils.is_json_integer(value.get("required_refinement_level")) or int(value["required_refinement_level"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_LEVEL")
	if not Utils.is_positive_number(value.get("residual_force_tolerance")) or not Utils.is_positive_number(value.get("residual_moment_tolerance")):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_RESIDUAL_TOLERANCE")
	if typeof(value.get("evaluator_version")) != TYPE_STRING or String(value["evaluator_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_EVALUATOR_VERSION")
	if typeof(value.get("part_models")) != TYPE_ARRAY or value["part_models"].size() < 2:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_MODELS")
	if typeof(value.get("bond_models")) != TYPE_ARRAY or value["bond_models"].size() != value["part_models"].size() - 1:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_MODELS")
	if typeof(value.get("region_guards")) != TYPE_ARRAY or value["region_guards"].is_empty():
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_REGION_GUARDS")

	var part_ids: Dictionary = {}
	var region_ids: Dictionary = {}
	var previous_part := ""
	var root_count := 0
	for index in range(value["part_models"].size()):
		var raw = value["part_models"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_MODEL", {"index": index})
		var part: Dictionary = raw
		checked = Utils.validate_exact_fields(part, PART_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(part.get("part_id"), 2) or not Utils.is_canonical_id(part.get("region_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_MODEL_ID", {"index": index})
		if not Utils.is_positive_number(part.get("mass")):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_MASS", {"index": index})
		checked = _validate_vec3(part.get("position_from_com"))
		if not bool(checked.get("success", false)):
			return checked
		checked = _validate_spd_matrix3(part.get("inertia_tensor_body"))
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_json_integer(part.get("depth")) or int(part["depth"]) < 0:
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_DEPTH", {"index": index})
		var part_id := String(part["part_id"])
		if index > 0 and part_id <= previous_part:
			return Utils.failure("STRUCTURAL_REFINEMENT_PART_MODELS_NOT_SORTED_UNIQUE", {"index": index})
		previous_part = part_id
		part_ids[part_id] = true
		region_ids[String(part["region_id"])] = true
		if part_id == String(value["root_part_id"]):
			root_count += 1
			if int(part["depth"]) != 0:
				return Utils.failure("STRUCTURAL_REFINEMENT_ROOT_DEPTH_INVALID")
	if root_count != 1:
		return Utils.failure("STRUCTURAL_REFINEMENT_ROOT_PART_MISSING")

	var child_parts: Dictionary = {}
	var previous_bond := ""
	var max_uncertainty_by_region: Dictionary = {}
	for index in range(value["bond_models"].size()):
		var raw = value["bond_models"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_MODEL", {"index": index})
		var bond: Dictionary = raw
		checked = Utils.validate_exact_fields(bond, BOND_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		for field in ["bond_id", "parent_part_id", "child_part_id", "mapped_region_id"]:
			if not Utils.is_canonical_id(bond.get(field), 2):
				return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_ID", {"index": index, "field": field})
		var bond_id := String(bond["bond_id"])
		if index > 0 and bond_id <= previous_bond:
			return Utils.failure("STRUCTURAL_REFINEMENT_BONDS_NOT_SORTED_UNIQUE", {"index": index})
		previous_bond = bond_id
		var parent_id := String(bond["parent_part_id"])
		var child_id := String(bond["child_part_id"])
		if parent_id == child_id or not part_ids.has(parent_id) or not part_ids.has(child_id):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_ENDPOINT", {"bond_id": bond_id})
		if child_id == String(value["root_part_id"]) or child_parts.has(child_id):
			return Utils.failure("STRUCTURAL_REFINEMENT_TREE_CHILD_DUPLICATE", {"part_id": child_id})
		child_parts[child_id] = true
		if not region_ids.has(String(bond["mapped_region_id"])):
			return Utils.failure("STRUCTURAL_REFINEMENT_BOND_REGION_MISSING", {"bond_id": bond_id})
		checked = _validate_vec3(bond.get("point_from_com"))
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_positive_number(bond.get("certified_force_capacity")) or not Utils.is_positive_number(bond.get("certified_moment_capacity")):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_CAPACITY", {"bond_id": bond_id})
		if not Utils.is_non_negative_number(bond.get("uncertainty_ratio")) or float(bond["uncertainty_ratio"]) >= 1.0:
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_UNCERTAINTY", {"bond_id": bond_id})
		var region_id := String(bond["mapped_region_id"])
		max_uncertainty_by_region[region_id] = maxf(float(max_uncertainty_by_region.get(region_id, 0.0)), float(bond["uncertainty_ratio"]))
	if child_parts.size() != value["part_models"].size() - 1:
		return Utils.failure("STRUCTURAL_REFINEMENT_TREE_COVERAGE_INVALID")

	var guarded_regions: Dictionary = {}
	var previous_guard := ""
	for index in range(value["region_guards"].size()):
		var raw = value["region_guards"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_REGION_GUARD", {"index": index})
		var guard: Dictionary = raw
		checked = RefinementGuard.validate(guard)
		if not bool(checked.get("success", false)):
			return checked
		var guard_id := String(guard["guard_id"])
		if index > 0 and guard_id <= previous_guard:
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARDS_NOT_SORTED_UNIQUE", {"index": index})
		previous_guard = guard_id
		var region_id := String(guard["mapped_source_region"])
		if not region_ids.has(region_id) or guarded_regions.has(region_id):
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_REGION_INVALID", {"region_id": region_id})
		guarded_regions[region_id] = true
		if absf(float(guard["conservative_bound"]) - 1.0) > 1.0e-12:
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_BOUND_NOT_NORMALIZED", {"guard_id": guard_id})
		if absf(float(guard["trigger_threshold"]) - float(value["trigger_ratio"])) > 1.0e-12:
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_TRIGGER_MISMATCH", {"guard_id": guard_id})
		if int(guard["required_refinement_level"]) != int(value["required_refinement_level"]):
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_LEVEL_MISMATCH", {"guard_id": guard_id})
		var expected_uncertainty := float(max_uncertainty_by_region.get(region_id, 0.0))
		if absf(float(guard["uncertainty_margin"]) - expected_uncertainty) > 1.0e-12:
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_UNCERTAINTY_MISMATCH", {"guard_id": guard_id})
	if guarded_regions.size() != region_ids.size():
		return Utils.failure("STRUCTURAL_REFINEMENT_REGION_GUARD_COVERAGE_INVALID")
	return Utils.validate_checksum(value)

static func _validate_vec3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_VECTOR3")
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_VECTOR3")
	return Utils.success()

static func _validate_spd_matrix3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_INERTIA")
	for row in value:
		if typeof(row) != TYPE_ARRAY or row.size() != 3:
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_INERTIA")
		for component in row:
			if not Utils.is_finite_number(component):
				return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_INERTIA")
	for row in range(3):
		for column in range(3):
			if absf(float(value[row][column]) - float(value[column][row])) > MATRIX_TOLERANCE:
				return Utils.failure("NONSYMMETRIC_STRUCTURAL_REFINEMENT_INERTIA")
	var a := float(value[0][0])
	var det2 := a * float(value[1][1]) - float(value[0][1]) * float(value[1][0])
	var det3 := (
		float(value[0][0]) * (float(value[1][1]) * float(value[2][2]) - float(value[1][2]) * float(value[2][1]))
		- float(value[0][1]) * (float(value[1][0]) * float(value[2][2]) - float(value[1][2]) * float(value[2][0]))
		+ float(value[0][2]) * (float(value[1][0]) * float(value[2][1]) - float(value[1][1]) * float(value[2][0]))
	)
	if a <= 0.0 or det2 <= 0.0 or det3 <= 0.0:
		return Utils.failure("NONPOSITIVE_STRUCTURAL_REFINEMENT_INERTIA")
	return Utils.success()
