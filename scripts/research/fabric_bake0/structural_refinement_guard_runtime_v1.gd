extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")

const SAFE := "STRUCTURAL_GUARD_SAFE"
const REFINEMENT_REQUIRED := "STRUCTURAL_REFINEMENT_REQUIRED"
const CONTEXT_FIELDS: Array[String] = [
	"source_frontier_hash", "structural_descriptor_hash", "reconstruction_mapping_hash",
	"complete_external_wrench_set", "linear_acceleration_body", "angular_velocity_body",
	"angular_acceleration_body", "external_wrenches",
]
const WRENCH_FIELDS: Array[String] = [
	"wrench_id", "part_id", "point_from_com", "force_body", "torque_body_about_point",
]

static func evaluate(field: Dictionary, runtime_context: Dictionary) -> Dictionary:
	var checked := GuardField.validate(field)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_exact_fields(runtime_context, CONTEXT_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if String(runtime_context.get("source_frontier_hash", "")) != String(field["source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_GUARD_SOURCE_BINDING_MISMATCH")
	if String(runtime_context.get("structural_descriptor_hash", "")) != String(field["structural_descriptor_hash"]):
		return Utils.failure("STRUCTURAL_GUARD_DESCRIPTOR_BINDING_MISMATCH")
	if String(runtime_context.get("reconstruction_mapping_hash", "")) != String(field["reconstruction_mapping_hash"]):
		return Utils.failure("STRUCTURAL_GUARD_RECONSTRUCTION_BINDING_MISMATCH")
	if typeof(runtime_context.get("complete_external_wrench_set")) != TYPE_BOOL or not bool(runtime_context["complete_external_wrench_set"]):
		return Utils.failure("STRUCTURAL_GUARD_LOAD_COVERAGE_UNCERTIFIED")
	for field_name in ["linear_acceleration_body", "angular_velocity_body", "angular_acceleration_body"]:
		checked = _validate_vec3(runtime_context.get(field_name))
		if not bool(checked.get("success", false)):
			return checked
	if typeof(runtime_context.get("external_wrenches")) != TYPE_ARRAY:
		return Utils.failure("INVALID_STRUCTURAL_GUARD_EXTERNAL_WRENCHES")

	var part_by_id: Dictionary = {}
	for part in field["part_models"]:
		part_by_id[String(part["part_id"])] = part
	var external_force: Dictionary = {}
	var external_moment_com: Dictionary = {}
	for part_id in part_by_id.keys():
		external_force[part_id] = Vector3.ZERO
		external_moment_com[part_id] = Vector3.ZERO
	var wrench_ids: Dictionary = {}
	var wrenches := Utils.sorted_dicts(runtime_context["external_wrenches"], "wrench_id")
	for raw in wrenches:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_GUARD_EXTERNAL_WRENCH")
		var wrench: Dictionary = raw
		checked = Utils.validate_exact_fields(wrench, WRENCH_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(wrench.get("wrench_id"), 2) or not Utils.is_canonical_id(wrench.get("part_id"), 2):
			return Utils.failure("INVALID_STRUCTURAL_GUARD_WRENCH_ID")
		var wrench_id := String(wrench["wrench_id"])
		if wrench_ids.has(wrench_id):
			return Utils.failure("DUPLICATE_STRUCTURAL_GUARD_WRENCH", {"wrench_id": wrench_id})
		wrench_ids[wrench_id] = true
		var part_id := String(wrench["part_id"])
		if not part_by_id.has(part_id):
			return Utils.failure("STRUCTURAL_GUARD_WRENCH_PART_MISSING", {"part_id": part_id})
		for vector_field in ["point_from_com", "force_body", "torque_body_about_point"]:
			checked = _validate_vec3(wrench.get(vector_field))
			if not bool(checked.get("success", false)):
				return checked
		var force := _vec3(wrench["force_body"])
		var point := _vec3(wrench["point_from_com"])
		var torque := _vec3(wrench["torque_body_about_point"])
		external_force[part_id] = (external_force[part_id] as Vector3) + force
		external_moment_com[part_id] = (external_moment_com[part_id] as Vector3) + point.cross(force) + torque

	var a_com := _vec3(runtime_context["linear_acceleration_body"])
	var omega := _vec3(runtime_context["angular_velocity_body"])
	var alpha := _vec3(runtime_context["angular_acceleration_body"])
	var subtree_force: Dictionary = {}
	var subtree_moment_com: Dictionary = {}
	for part in field["part_models"]:
		var part_id := String(part["part_id"])
		var r := _vec3(part["position_from_com"])
		var mass := float(part["mass"])
		var point_acceleration := a_com + alpha.cross(r) + omega.cross(omega.cross(r))
		var required_force := point_acceleration * mass
		var inertia_omega := _mat_vec(part["inertia_tensor_body"], omega)
		var required_spin_moment := _mat_vec(part["inertia_tensor_body"], alpha) + omega.cross(inertia_omega)
		var required_moment_com := r.cross(required_force) + required_spin_moment
		subtree_force[part_id] = required_force - (external_force[part_id] as Vector3)
		subtree_moment_com[part_id] = required_moment_com - (external_moment_com[part_id] as Vector3)

	var bond_by_child: Dictionary = {}
	for bond in field["bond_models"]:
		bond_by_child[String(bond["child_part_id"])] = bond
	var ordered_parts: Array = field["part_models"].duplicate(true)
	ordered_parts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var ld := int(left["depth"])
		var rd := int(right["depth"])
		if ld == rd:
			return String(left["part_id"]) > String(right["part_id"])
		return ld > rd
	)

	var region_state: Dictionary = {}
	for guard in field["region_guards"]:
		var region_id := String(guard["mapped_source_region"])
		region_state[region_id] = {
			"guard_id": String(guard["guard_id"]),
			"mapped_source_region": region_id,
			"required_refinement_level": int(guard["required_refinement_level"]),
			"uncertainty_ratio": float(guard["uncertainty_margin"]),
			"trigger_ratio": float(guard["trigger_threshold"]),
			"max_utilization": 0.0,
			"peak_bond_id": "",
			"peak_force_norm": 0.0,
			"peak_moment_norm": 0.0,
			"capacity_envelope_crossed": false,
		}
	var global_peak_utilization := 0.0
	var global_peak_bond_id := ""
	var root_part_id := String(field["root_part_id"])
	for part in ordered_parts:
		var child_id := String(part["part_id"])
		if child_id == root_part_id:
			continue
		if not bond_by_child.has(child_id):
			return Utils.failure("STRUCTURAL_GUARD_TREE_BINDING_INCOMPLETE", {"part_id": child_id})
		var bond: Dictionary = bond_by_child[child_id]
		var force: Vector3 = subtree_force[child_id]
		var moment_com: Vector3 = subtree_moment_com[child_id]
		var bond_point := _vec3(bond["point_from_com"])
		var moment_at_bond := moment_com - bond_point.cross(force)
		var force_norm := force.length()
		var moment_norm := moment_at_bond.length()
		var utilization := (
			force_norm / float(bond["certified_force_capacity"])
			+ moment_norm / float(bond["certified_moment_capacity"])
		)
		var region_id := String(bond["mapped_region_id"])
		var region: Dictionary = region_state[region_id]
		if utilization > float(region["max_utilization"]):
			region["max_utilization"] = utilization
			region["peak_bond_id"] = String(bond["bond_id"])
			region["peak_force_norm"] = force_norm
			region["peak_moment_norm"] = moment_norm
		region["capacity_envelope_crossed"] = bool(region["capacity_envelope_crossed"]) or utilization >= 1.0
		region_state[region_id] = region
		if utilization > global_peak_utilization:
			global_peak_utilization = utilization
			global_peak_bond_id = String(bond["bond_id"])
		var parent_id := String(bond["parent_part_id"])
		subtree_force[parent_id] = (subtree_force[parent_id] as Vector3) + force
		subtree_moment_com[parent_id] = (subtree_moment_com[parent_id] as Vector3) + moment_com

	var residual_force: Vector3 = subtree_force[root_part_id]
	var residual_moment: Vector3 = subtree_moment_com[root_part_id]
	var residual_force_norm := residual_force.length()
	var residual_moment_norm := residual_moment.length()
	if residual_force_norm > float(field["residual_force_tolerance"]) or residual_moment_norm > float(field["residual_moment_tolerance"]):
		return Utils.failure("STRUCTURAL_GUARD_DYNAMICS_INCONSISTENT", {
			"residual_force_norm": residual_force_norm,
			"residual_moment_norm": residual_moment_norm,
			"force_tolerance": field["residual_force_tolerance"],
			"moment_tolerance": field["residual_moment_tolerance"],
		})

	var guard_by_region: Dictionary = {}
	for guard in field["region_guards"]:
		guard_by_region[String(guard["mapped_source_region"])] = guard
	var region_ids: Array = region_state.keys()
	region_ids.sort()
	var region_results: Array = []
	var refinement_requests: Array = []
	for region_id in region_ids:
		var region: Dictionary = region_state[region_id]
		var guard: Dictionary = guard_by_region[region_id]
		var guard_values := {String(guard["guard_id"]): float(region["max_utilization"])}
		var guard_result := RefinementGuard.evaluate(guard, guard_values)
		var remaining_margin := float(guard["trigger_threshold"]) - float(region["max_utilization"]) - float(guard["uncertainty_margin"])
		var triggered := not bool(guard_result.get("success", false)) and String(guard_result.get("error_code", "")) == "BAKE_REFINEMENT_REQUIRED"
		if not bool(guard_result.get("success", false)) and not triggered:
			return guard_result
		region["remaining_guard_margin"] = remaining_margin
		region["refinement_required"] = triggered
		region_results.append(region)
		if triggered:
			refinement_requests.append({
				"guard_id": String(guard["guard_id"]),
				"mapped_source_region": String(region_id),
				"required_refinement_level": int(guard["required_refinement_level"]),
				"peak_bond_id": String(region["peak_bond_id"]),
				"utilization": float(region["max_utilization"]),
				"remaining_guard_margin": remaining_margin,
				"reason": "STRUCTURAL_BOND_CAPACITY_GUARD",
			})
	if global_peak_utilization >= 1.0 and refinement_requests.is_empty():
		return Utils.failure("STRUCTURAL_GUARD_FALSE_NEGATIVE", {
			"peak_bond_id": global_peak_bond_id,
			"peak_utilization": global_peak_utilization,
		})
	return {
		"success": true,
		"status": REFINEMENT_REQUIRED if not refinement_requests.is_empty() else SAFE,
		"region_results": region_results,
		"refinement_requests": refinement_requests,
		"diagnostics": {
			"global_peak_utilization": global_peak_utilization,
			"global_peak_bond_id": global_peak_bond_id,
			"residual_force_norm": residual_force_norm,
			"residual_moment_norm": residual_moment_norm,
			"evaluated_bonds": field["bond_models"].size(),
			"evaluated_regions": field["region_guards"].size(),
		},
	}

static func _validate_vec3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_GUARD_VECTOR3")
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_GUARD_VECTOR3")
	return Utils.success()

static func _mat_vec(matrix: Array, vector: Vector3) -> Vector3:
	return Vector3(
		float(matrix[0][0]) * vector.x + float(matrix[0][1]) * vector.y + float(matrix[0][2]) * vector.z,
		float(matrix[1][0]) * vector.x + float(matrix[1][1]) * vector.y + float(matrix[1][2]) * vector.z,
		float(matrix[2][0]) * vector.x + float(matrix[2][1]) * vector.y + float(matrix[2][2]) * vector.z
	)

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
