extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const LocalPlan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")

const READY := "STRUCTURAL_LOCAL_UNBAKE_PLAN_READY"
const REQUEST_FIELDS: Array[String] = [
	"plan_id", "source_frontier_hash", "structural_descriptor", "reconstruction_mapping", "guard_field",
	"parts", "bonds", "boundary_anchors", "target_region_id", "max_full_parts",
	"minimum_retained_component_parts", "continuity_tolerance", "conservation_tolerance", "transition_version",
]
const PART_FIELDS: Array[String] = [
	"part_id", "region_id", "mass", "position", "orientation", "inertia_tensor", "support_points",
]
const BOND_FIELDS: Array[String] = ["bond_id", "part_a", "part_b", "rigid"]
const ANCHOR_FIELDS: Array[String] = ["anchor_id", "part_id", "position_local", "orientation_local"]

static func compile(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(request.get("plan_id"), 2) or not Utils.is_canonical_id(request.get("target_region_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COMPILE_ID")
	if not Utils.is_lower_hex_64(request.get("source_frontier_hash")):
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_SOURCE_FRONTIER")
	if not Utils.is_json_integer(request.get("max_full_parts")) or int(request["max_full_parts"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_BOUND")
	if not Utils.is_json_integer(request.get("minimum_retained_component_parts")) or int(request["minimum_retained_component_parts"]) < 100:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_RETAINED_MINIMUM")
	if not Utils.is_positive_number(request.get("continuity_tolerance")) or not Utils.is_positive_number(request.get("conservation_tolerance")):
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_TOLERANCE")
	if typeof(request.get("transition_version")) != TYPE_STRING or String(request["transition_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_VERSION")
	for field in ["parts", "bonds", "boundary_anchors"]:
		if typeof(request.get(field)) != TYPE_ARRAY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_COLLECTION", {"field": field})
	if typeof(request.get("structural_descriptor")) != TYPE_DICTIONARY or typeof(request.get("reconstruction_mapping")) != TYPE_DICTIONARY or typeof(request.get("guard_field")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_BINDING")

	var descriptor: Dictionary = request["structural_descriptor"]
	var mapping: Dictionary = request["reconstruction_mapping"]
	var guard_field: Dictionary = request["guard_field"]
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = Reconstruction.validate(mapping)
	if not bool(checked.get("success", false)):
		return checked
	checked = GuardField.validate(guard_field)
	if not bool(checked.get("success", false)):
		return checked
	if String(descriptor["source_frontier_hash"]) != String(request["source_frontier_hash"]) or String(mapping["source_frontier_hash"]) != String(request["source_frontier_hash"]) or String(guard_field["source_frontier_hash"]) != String(request["source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_SOURCE_BINDING_MISMATCH")
	if String(descriptor["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_PARENT_MAPPING_MISMATCH")
	if String(guard_field["structural_descriptor_hash"]) != String(descriptor["checksum"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_DESCRIPTOR_MISMATCH")
	if String(guard_field["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_MAPPING_MISMATCH")
	if String(descriptor["construct_id"]) != String(mapping["construct_id"]) or String(descriptor["construct_id"]) != String(guard_field["construct_id"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_CONSTRUCT_BINDING_MISMATCH")

	# Recompile the canonical source into the exact parent descriptor/mapping. This gives D a
	# fail-closed proof that the supplied canonical part/bond/anchor inventory is the same source
	# that produced B0.2-A/B rather than a second mutable representation.
	var parent_recompile := AggregateCompiler.compile({
		"descriptor_id": String(descriptor["descriptor_id"]),
		"mapping_id": String(mapping["mapping_id"]),
		"source_frontier_hash": String(request["source_frontier_hash"]),
		"construct_id": String(descriptor["construct_id"]),
		"parts": request["parts"].duplicate(true),
		"bonds": request["bonds"].duplicate(true),
		"boundary_anchors": request["boundary_anchors"].duplicate(true),
		"reconstruction_version": String(mapping["reconstruction_version"]),
		"minimum_part_count": 100,
	})
	if not bool(parent_recompile.get("success", false)):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_PARENT_RECOMPILE_FAILED", parent_recompile)
	if String(parent_recompile["descriptor"]["checksum"]) != String(descriptor["checksum"]) or String(parent_recompile["reconstruction_mapping"]["checksum"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_CANONICAL_SOURCE_MISMATCH")

	var parts := Utils.sorted_dicts(request["parts"], "part_id")
	var bonds := Utils.sorted_dicts(request["bonds"], "bond_id")
	var anchors := Utils.sorted_dicts(request["boundary_anchors"], "anchor_id")
	if parts.size() != int(descriptor["part_count"]) or bonds.size() != int(descriptor["bond_count"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_CANONICAL_COUNT_MISMATCH")
	var part_by_id: Dictionary = {}
	for raw in parts:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_PART")
		var part: Dictionary = raw
		checked = Utils.validate_exact_fields(part, PART_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		part_by_id[String(part["part_id"])] = part
	var bond_by_id: Dictionary = {}
	var adjacency: Dictionary = {}
	for part_id in part_by_id.keys():
		adjacency[part_id] = []
	for raw in bonds:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_BOND")
		var bond: Dictionary = raw
		checked = Utils.validate_exact_fields(bond, BOND_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if typeof(bond.get("rigid")) != TYPE_BOOL or not bool(bond["rigid"]):
			return Utils.failure("NO_SAFE_BOUNDED_LOCAL_UNBAKE_NON_RIGID_BOND", {"bond_id": bond.get("bond_id", "")})
		var bond_id := String(bond["bond_id"])
		var a := String(bond["part_a"])
		var b := String(bond["part_b"])
		if bond_by_id.has(bond_id) or a == b or not part_by_id.has(a) or not part_by_id.has(b):
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_BOND", {"bond_id": bond_id})
		bond_by_id[bond_id] = bond
		adjacency[a].append({"neighbor": b, "bond_id": bond_id})
		adjacency[b].append({"neighbor": a, "bond_id": bond_id})

	# The C guard field is the certified tree topology D is allowed to refine. Require exact
	# bond identity/endpoints; otherwise a stale guard cannot drive a new topology transition.
	if guard_field["bond_models"].size() != bonds.size():
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_TOPOLOGY_MISMATCH")
	for model in guard_field["bond_models"]:
		var bond_id := String(model["bond_id"])
		if not bond_by_id.has(bond_id):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_BOND_MISSING", {"bond_id": bond_id})
		var bond: Dictionary = bond_by_id[bond_id]
		var endpoints := [String(bond["part_a"]), String(bond["part_b"])]
		var certified := [String(model["parent_part_id"]), String(model["child_part_id"])]
		endpoints.sort(); certified.sort()
		if endpoints != certified:
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_BOND_ENDPOINT_MISMATCH", {"bond_id": bond_id})

	var target_region_id := String(request["target_region_id"])
	var target_part_ids: Array = []
	for region in mapping["region_mappings"]:
		if String(region["region_id"]) == target_region_id:
			target_part_ids = region["part_ids"].duplicate()
			break
	if target_part_ids.is_empty():
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_TARGET_REGION_MISSING", {"region_id": target_region_id})
	target_part_ids.sort()
	if target_part_ids.size() > int(request["max_full_parts"]):
		return Utils.failure("NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT", {
			"target_region_id": target_region_id,
			"full_parts": target_part_ids.size(),
			"max_full_parts": int(request["max_full_parts"]),
		})
	var target_set: Dictionary = {}
	var target_models: Array = []
	for part_id in target_part_ids:
		target_set[String(part_id)] = true
		var part: Dictionary = part_by_id[String(part_id)]
		target_models.append({
			"part_id": String(part_id),
			"mass": float(part["mass"]),
			"inertia_tensor": part["inertia_tensor"].duplicate(true),
		})

	var target_internal_bond_ids: Array = []
	var residual_internal_bonds: Array = []
	var cut_bonds: Array = []
	for bond in bonds:
		var a_target := target_set.has(String(bond["part_a"]))
		var b_target := target_set.has(String(bond["part_b"]))
		if a_target and b_target:
			target_internal_bond_ids.append(String(bond["bond_id"]))
		elif a_target or b_target:
			cut_bonds.append(bond)
		else:
			residual_internal_bonds.append(bond)
	if cut_bonds.is_empty():
		return Utils.failure("NO_SAFE_BOUNDED_LOCAL_UNBAKE_NO_CUT_INTERFACE")

	# Connected components of the retained graph after removing the target region.
	var residual_set: Dictionary = {}
	for part_id in part_by_id.keys():
		if not target_set.has(String(part_id)):
			residual_set[String(part_id)] = true
	var component_parts_list: Array = []
	var visited: Dictionary = {}
	var residual_ids: Array = residual_set.keys(); residual_ids.sort()
	for seed_raw in residual_ids:
		var seed := String(seed_raw)
		if visited.has(seed):
			continue
		var queue: Array = [seed]
		visited[seed] = true
		var component_parts: Array = []
		while not queue.is_empty():
			var current := String(queue.pop_front())
			component_parts.append(current)
			for edge in adjacency[current]:
				var neighbor := String(edge["neighbor"])
				if target_set.has(neighbor) or visited.has(neighbor):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		component_parts.sort()
		if component_parts.size() < int(request["minimum_retained_component_parts"]):
			return Utils.failure("NO_SAFE_BOUNDED_LOCAL_UNBAKE_RESIDUAL_TOO_SMALL", {
				"part_count": component_parts.size(),
				"minimum": int(request["minimum_retained_component_parts"]),
			})
		component_parts_list.append(component_parts)
	if visited.size() != residual_set.size():
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_RESIDUAL_COVERAGE_FAILED")

	var guard_bond_by_id: Dictionary = {}
	for model in guard_field["bond_models"]:
		guard_bond_by_id[String(model["bond_id"])] = model
	var original_anchor_by_id: Dictionary = {}
	for raw in anchors:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_LOCAL_UNBAKE_ANCHOR")
		var anchor: Dictionary = raw
		checked = Utils.validate_exact_fields(anchor, ANCHOR_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		original_anchor_by_id[String(anchor["anchor_id"])] = anchor

	var component_id_by_part: Dictionary = {}
	for index in range(component_parts_list.size()):
		var component_id := "component/b0-2-d-%03d" % index
		for part_id in component_parts_list[index]:
			component_id_by_part[String(part_id)] = component_id

	var cut_interfaces: Array = []
	var synthetic_anchors_by_component: Dictionary = {}
	for index in range(component_parts_list.size()):
		synthetic_anchors_by_component["component/b0-2-d-%03d" % index] = []
	var parent_com := _vec3(descriptor["center_of_mass"])
	var sorted_cut_bonds := Utils.sorted_dicts(cut_bonds, "bond_id")
	for index in range(sorted_cut_bonds.size()):
		var bond: Dictionary = sorted_cut_bonds[index]
		var a := String(bond["part_a"])
		var b := String(bond["part_b"])
		var full_part_id := a if target_set.has(a) else b
		var residual_part_id := b if target_set.has(a) else a
		var component_id := String(component_id_by_part[residual_part_id])
		var bond_id := String(bond["bond_id"])
		if not guard_bond_by_id.has(bond_id):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_CUT_BOND_NOT_GUARDED", {"bond_id": bond_id})
		var point_from_parent_com := _vec3(guard_bond_by_id[bond_id]["point_from_com"])
		var point_absolute := parent_com + point_from_parent_com
		var full_part: Dictionary = part_by_id[full_part_id]
		var residual_part: Dictionary = part_by_id[residual_part_id]
		var full_local := _quat(full_part["orientation"]).inverse() * (point_absolute - _vec3(full_part["position"]))
		var residual_local := _quat(residual_part["orientation"]).inverse() * (point_absolute - _vec3(residual_part["position"]))
		var anchor_id := "anchor/b0-2-d-%03d" % index
		(synthetic_anchors_by_component[component_id] as Array).append({
			"anchor_id": anchor_id,
			"part_id": residual_part_id,
			"position_local": _arr3(residual_local),
			"orientation_local": [0.0, 0.0, 0.0, 1.0],
		})
		cut_interfaces.append({
			"interface_id": "interface/b0-2-d-%03d" % index,
			"bond_id": bond_id,
			"full_part_id": full_part_id,
			"residual_part_id": residual_part_id,
			"residual_component_id": component_id,
			"full_position_local": _arr3(full_local),
			"residual_anchor_id": anchor_id,
			"point_from_parent_com": _arr3(point_from_parent_com),
		})

	var residual_components: Array = []
	for index in range(component_parts_list.size()):
		var component_id := "component/b0-2-d-%03d" % index
		var component_part_ids: Array = component_parts_list[index]
		var component_set: Dictionary = {}
		var component_parts: Array = []
		for part_id in component_part_ids:
			component_set[String(part_id)] = true
			component_parts.append(part_by_id[String(part_id)].duplicate(true))
		var component_bonds: Array = []
		var component_bond_ids: Array = []
		for bond in residual_internal_bonds:
			if component_set.has(String(bond["part_a"])) and component_set.has(String(bond["part_b"])):
				component_bonds.append(bond.duplicate(true))
				component_bond_ids.append(String(bond["bond_id"]))
		var component_anchors: Array = []
		for anchor in anchors:
			if component_set.has(String(anchor["part_id"])):
				component_anchors.append(anchor.duplicate(true))
		component_anchors.append_array((synthetic_anchors_by_component[component_id] as Array).duplicate(true))
		component_anchors = Utils.sorted_dicts(component_anchors, "anchor_id")
		var compiled := AggregateCompiler.compile({
			"descriptor_id": "aggregate/b0-2-d-residual-%03d" % index,
			"mapping_id": "mapping/b0-2-d-residual-%03d" % index,
			"source_frontier_hash": String(request["source_frontier_hash"]),
			"construct_id": String(descriptor["construct_id"]),
			"parts": component_parts,
			"bonds": component_bonds,
			"boundary_anchors": component_anchors,
			"reconstruction_version": String(request["transition_version"]),
			"minimum_part_count": int(request["minimum_retained_component_parts"]),
		})
		if not bool(compiled.get("success", false)):
			return Utils.failure("NO_SAFE_BOUNDED_LOCAL_UNBAKE_RESIDUAL_COMPILE_FAILED", {
				"component_id": component_id,
				"cause": compiled,
			})
		component_bond_ids.sort()
		var anchor_ids: Array = []
		for anchor in component_anchors:
			anchor_ids.append(String(anchor["anchor_id"]))
		anchor_ids.sort()
		residual_components.append({
			"component_id": component_id,
			"descriptor": compiled["descriptor"],
			"reconstruction_mapping": compiled["reconstruction_mapping"],
			"part_ids": component_part_ids.duplicate(),
			"bond_ids": component_bond_ids,
			"anchor_ids": anchor_ids,
		})

	var plan := LocalPlan.create(
		String(request["plan_id"]), String(request["source_frontier_hash"]), String(descriptor["construct_id"]),
		String(descriptor["checksum"]), String(mapping["checksum"]), String(guard_field["checksum"]),
		target_region_id, target_part_ids, target_models, target_internal_bond_ids, residual_components,
		cut_interfaces, parts.size(), bonds.size(), int(request["max_full_parts"]),
		int(request["minimum_retained_component_parts"]), float(request["continuity_tolerance"]),
		float(request["conservation_tolerance"]), String(request["transition_version"])
	)
	if plan.is_empty():
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_PLAN_ASSEMBLY_FAILED")
	var full_dof: int = parts.size() * 13
	var mixed_dof: int = target_part_ids.size() * 13 + residual_components.size() * 13
	return {
		"success": true,
		"status": READY,
		"plan": plan,
		"diagnostics": {
			"target_region_id": target_region_id,
			"full_part_count": target_part_ids.size(),
			"retained_component_count": residual_components.size(),
			"retained_part_count": parts.size() - target_part_ids.size(),
			"cut_interface_count": cut_interfaces.size(),
			"full_dof": full_dof,
			"mixed_dof": mixed_dof,
			"preserved_reduction_ratio": float(full_dof) / float(mixed_dof),
			"unbaked_fraction": float(target_part_ids.size()) / float(parts.size()),
			"physical_bake_artifact_emitted": false,
			"next_required_stage": "B0.2-E_TOPOLOGY_SPLIT_REBAKE",
		},
	}

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
