extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const StructuralDescriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")

const READY_FOR_LOCAL_UNBAKE := "STRUCTURAL_GUARD_FIELD_READY_FOR_LOCAL_UNBAKE"
const REQUEST_FIELDS: Array[String] = [
	"field_id", "source_frontier_hash", "structural_descriptor", "reconstruction_mapping",
	"parts", "bonds", "root_part_id", "bond_capacity_specs", "capacity_certificate_hash",
	"trigger_ratio", "required_refinement_level", "residual_force_tolerance",
	"residual_moment_tolerance", "evaluator_version",
]
const PART_FIELDS: Array[String] = [
	"part_id", "region_id", "mass", "position", "orientation", "inertia_tensor", "support_points",
]
const BOND_FIELDS: Array[String] = ["bond_id", "part_a", "part_b", "rigid"]
const CAPACITY_FIELDS: Array[String] = [
	"bond_id", "point_from_com", "certified_force_capacity", "certified_moment_capacity", "uncertainty_ratio",
]
const POSITION_TOLERANCE := 1.0e-10
const ORIENTATION_TOLERANCE := 1.0e-12

static func compile(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(request.get("field_id"), 2) or not Utils.is_canonical_id(request.get("root_part_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_COMPILE_ID")
	if not Utils.is_lower_hex_64(request.get("source_frontier_hash")) or not Utils.is_lower_hex_64(request.get("capacity_certificate_hash")):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_COMPILE_HASH")
	if not Utils.is_positive_number(request.get("trigger_ratio")) or float(request["trigger_ratio"]) >= 1.0:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_TRIGGER_RATIO")
	if not Utils.is_json_integer(request.get("required_refinement_level")) or int(request["required_refinement_level"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_LEVEL")
	if not Utils.is_positive_number(request.get("residual_force_tolerance")) or not Utils.is_positive_number(request.get("residual_moment_tolerance")):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_RESIDUAL_TOLERANCE")
	if typeof(request.get("evaluator_version")) != TYPE_STRING or String(request["evaluator_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_EVALUATOR_VERSION")
	if typeof(request.get("structural_descriptor")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_STRUCTURAL_DESCRIPTOR")
	checked = StructuralDescriptor.validate(request["structural_descriptor"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(request.get("reconstruction_mapping")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_RECONSTRUCTION_MAPPING")
	checked = Reconstruction.validate(request["reconstruction_mapping"])
	if not bool(checked.get("success", false)):
		return checked
	var descriptor: Dictionary = request["structural_descriptor"]
	var mapping: Dictionary = request["reconstruction_mapping"]
	if String(descriptor["source_frontier_hash"]) != String(request["source_frontier_hash"]) or String(mapping["source_frontier_hash"]) != String(request["source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_REFINEMENT_SOURCE_BINDING_MISMATCH")
	if String(descriptor["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_REFINEMENT_RECONSTRUCTION_BINDING_MISMATCH")
	if String(descriptor["construct_id"]) != String(mapping["construct_id"]):
		return Utils.failure("STRUCTURAL_REFINEMENT_CONSTRUCT_BINDING_MISMATCH")
	if typeof(request.get("parts")) != TYPE_ARRAY or typeof(request.get("bonds")) != TYPE_ARRAY or typeof(request.get("bond_capacity_specs")) != TYPE_ARRAY:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_COMPILE_COLLECTION")
	if request["parts"].size() != int(descriptor["part_count"]) or request["bonds"].size() != int(descriptor["bond_count"]):
		return Utils.failure("STRUCTURAL_REFINEMENT_SOURCE_COUNT_MISMATCH")
	if request["bonds"].size() != request["parts"].size() - 1:
		return Utils.failure("NO_SAFE_GUARD_CYCLIC_OR_REDUNDANT_STRUCTURAL_GRAPH", {
			"parts": request["parts"].size(), "bonds": request["bonds"].size(),
		})

	var parts := Utils.sorted_dicts(request["parts"], "part_id")
	var bonds := Utils.sorted_dicts(request["bonds"], "bond_id")
	var capacities := Utils.sorted_dicts(request["bond_capacity_specs"], "bond_id")
	var expected_capacity_hash := Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_capacity_set.v1",
		"source_frontier_hash": request["source_frontier_hash"],
		"bond_capacity_specs": capacities,
	})
	if String(request["capacity_certificate_hash"]) != expected_capacity_hash:
		return Utils.failure("NO_SAFE_GUARD_CAPACITY_CERTIFICATE_MISMATCH")
	if capacities.size() != bonds.size():
		return Utils.failure("NO_SAFE_GUARD_CAPACITY_COVERAGE_MISMATCH")
	var mapping_by_part: Dictionary = {}
	for part_mapping in mapping["part_mappings"]:
		mapping_by_part[String(part_mapping["part_id"])] = part_mapping
	var part_by_id: Dictionary = {}
	for part in parts:
		checked = _validate_part(part)
		if not bool(checked.get("success", false)):
			return checked
		var part_id := String(part["part_id"])
		if part_by_id.has(part_id):
			return Utils.failure("DUPLICATE_STRUCTURAL_REFINEMENT_PART", {"part_id": part_id})
		if not mapping_by_part.has(part_id):
			return Utils.failure("STRUCTURAL_REFINEMENT_PART_NOT_RECONSTRUCTABLE", {"part_id": part_id})
		var mapped: Dictionary = mapping_by_part[part_id]
		if String(mapped["region_id"]) != String(part["region_id"]):
			return Utils.failure("STRUCTURAL_REFINEMENT_PART_REGION_MISMATCH", {"part_id": part_id})
		var expected_position := _vec3(part["position"]) - _vec3(descriptor["center_of_mass"])
		if expected_position.distance_to(_vec3(mapped["position_from_com"])) > POSITION_TOLERANCE:
			return Utils.failure("STRUCTURAL_REFINEMENT_PART_POSITION_BINDING_MISMATCH", {"part_id": part_id})
		if _quat_distance(_quat(part["orientation"]), _quat(mapped["orientation_from_aggregate"])) > ORIENTATION_TOLERANCE:
			return Utils.failure("STRUCTURAL_REFINEMENT_PART_ORIENTATION_BINDING_MISMATCH", {"part_id": part_id})
		part_by_id[part_id] = part
	var root_part_id := String(request["root_part_id"])
	if not part_by_id.has(root_part_id):
		return Utils.failure("STRUCTURAL_REFINEMENT_ROOT_PART_MISSING")

	var bond_by_id: Dictionary = {}
	var adjacency: Dictionary = {}
	for part_id in part_by_id.keys():
		adjacency[part_id] = []
	for bond in bonds:
		checked = _validate_bond(bond, part_by_id)
		if not bool(checked.get("success", false)):
			return checked
		var bond_id := String(bond["bond_id"])
		if bond_by_id.has(bond_id):
			return Utils.failure("DUPLICATE_STRUCTURAL_REFINEMENT_BOND", {"bond_id": bond_id})
		bond_by_id[bond_id] = bond
		var a := String(bond["part_a"])
		var b := String(bond["part_b"])
		adjacency[a].append({"neighbor": b, "bond_id": bond_id})
		adjacency[b].append({"neighbor": a, "bond_id": bond_id})
	for part_id in adjacency.keys():
		adjacency[part_id].sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var ln := String(left["neighbor"])
			var rn := String(right["neighbor"])
			if ln == rn:
				return String(left["bond_id"]) < String(right["bond_id"])
			return ln < rn
		)

	var parent_by_part: Dictionary = {}
	var parent_bond_by_part: Dictionary = {}
	var depth_by_part: Dictionary = {root_part_id: 0}
	var queue: Array = [root_part_id]
	var visited: Dictionary = {root_part_id: true}
	while not queue.is_empty():
		var current := String(queue.pop_front())
		for edge in adjacency[current]:
			var neighbor := String(edge["neighbor"])
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			parent_by_part[neighbor] = current
			parent_bond_by_part[neighbor] = String(edge["bond_id"])
			depth_by_part[neighbor] = int(depth_by_part[current]) + 1
			queue.append(neighbor)
	if visited.size() != part_by_id.size():
		return Utils.failure("NO_SAFE_GUARD_DISCONNECTED_STRUCTURAL_GRAPH", {
			"visited": visited.size(), "parts": part_by_id.size(),
		})
	if parent_by_part.size() != part_by_id.size() - 1:
		return Utils.failure("NO_SAFE_GUARD_STRUCTURAL_TREE_ORIENTATION_FAILED")

	var capacity_by_bond: Dictionary = {}
	for spec in capacities:
		checked = _validate_capacity(spec)
		if not bool(checked.get("success", false)):
			return checked
		var bond_id := String(spec["bond_id"])
		if capacity_by_bond.has(bond_id) or not bond_by_id.has(bond_id):
			return Utils.failure("NO_SAFE_GUARD_CAPACITY_BOND_MISMATCH", {"bond_id": bond_id})
		capacity_by_bond[bond_id] = spec
	for bond_id in bond_by_id.keys():
		if not capacity_by_bond.has(bond_id):
			return Utils.failure("NO_SAFE_GUARD_CAPACITY_MISSING", {"bond_id": bond_id})

	var part_models: Array = []
	for part in parts:
		var part_id := String(part["part_id"])
		var rotation := _rotation_matrix(_quat(part["orientation"]))
		var inertia_body := _mat_mul(_mat_mul(rotation, part["inertia_tensor"]), _mat_transpose(rotation))
		part_models.append({
			"part_id": part_id,
			"region_id": String(part["region_id"]),
			"mass": float(part["mass"]),
			"position_from_com": mapping_by_part[part_id]["position_from_com"].duplicate(),
			"inertia_tensor_body": inertia_body,
			"depth": int(depth_by_part[part_id]),
		})

	var bond_models: Array = []
	var max_uncertainty_by_region: Dictionary = {}
	for child_id in parent_by_part.keys():
		var bond_id := String(parent_bond_by_part[child_id])
		var spec: Dictionary = capacity_by_bond[bond_id]
		var region_id := String(mapping_by_part[child_id]["region_id"])
		var uncertainty := float(spec["uncertainty_ratio"])
		max_uncertainty_by_region[region_id] = maxf(float(max_uncertainty_by_region.get(region_id, 0.0)), uncertainty)
		bond_models.append({
			"bond_id": bond_id,
			"parent_part_id": String(parent_by_part[child_id]),
			"child_part_id": String(child_id),
			"mapped_region_id": region_id,
			"point_from_com": spec["point_from_com"].duplicate(),
			"certified_force_capacity": float(spec["certified_force_capacity"]),
			"certified_moment_capacity": float(spec["certified_moment_capacity"]),
			"uncertainty_ratio": uncertainty,
		})
	bond_models = Utils.sorted_dicts(bond_models, "bond_id")

	var region_guards: Array = []
	var regions: Array = mapping["region_mappings"].duplicate(true)
	regions = Utils.sorted_dicts(regions, "region_id")
	for index in range(regions.size()):
		var region_id := String(regions[index]["region_id"])
		var uncertainty := float(max_uncertainty_by_region.get(region_id, 0.0))
		if float(request["trigger_ratio"]) + uncertainty > 1.0:
			return Utils.failure("NO_SAFE_GUARD_UNCERTIFIED_MARGIN", {
				"region_id": region_id,
				"trigger_ratio": request["trigger_ratio"],
				"uncertainty_ratio": uncertainty,
			})
		var guard := RefinementGuard.create(
			"guard/b0-2-c-%03d" % index,
			["quantity/force-demand", "quantity/moment-demand", "quantity/utilization"],
			1.0,
			float(request["trigger_ratio"]),
			region_id,
			int(request["required_refinement_level"]),
			uncertainty
		)
		if guard.is_empty():
			return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_ASSEMBLY_FAILED", {"region_id": region_id})
		region_guards.append(guard)

	var field := GuardField.create(
		String(request["field_id"]), String(request["source_frontier_hash"]), String(descriptor["construct_id"]),
		String(descriptor["checksum"]), String(mapping["checksum"]), String(request["capacity_certificate_hash"]),
		root_part_id, float(request["trigger_ratio"]), int(request["required_refinement_level"]),
		float(request["residual_force_tolerance"]), float(request["residual_moment_tolerance"]),
		part_models, bond_models, region_guards, String(request["evaluator_version"])
	)
	if field.is_empty():
		return Utils.failure("STRUCTURAL_REFINEMENT_GUARD_FIELD_ASSEMBLY_FAILED")
	return {
		"success": true,
		"status": READY_FOR_LOCAL_UNBAKE,
		"guard_field": field,
		"refinement_guards": field["region_guards"].duplicate(true),
		"diagnostics": {
			"part_count": part_models.size(),
			"bond_count": bond_models.size(),
			"region_guard_count": region_guards.size(),
			"dynamics_model": GuardField.DYNAMICS_MODEL,
			"physical_bake_artifact_emitted": false,
			"next_required_stage": "B0.2-D_BOUNDED_LOCAL_UNBAKE",
		},
	}

static func _validate_part(part: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(part, PART_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(part.get("part_id"), 2) or not Utils.is_canonical_id(part.get("region_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_ID")
	if not Utils.is_positive_number(part.get("mass")):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_PART_MASS")
	checked = _validate_vec3(part.get("position"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_quat(part.get("orientation"))
	if not bool(checked.get("success", false)):
		return checked
	return _validate_spd_matrix3(part.get("inertia_tensor"))

static func _validate_bond(bond: Dictionary, part_by_id: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(bond, BOND_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(bond.get("bond_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_ID")
	if typeof(bond.get("rigid")) != TYPE_BOOL or not bool(bond["rigid"]):
		return Utils.failure("NO_SAFE_GUARD_NON_RIGID_STRUCTURAL_BOND", {"bond_id": bond.get("bond_id", "")})
	var a := String(bond.get("part_a", ""))
	var b := String(bond.get("part_b", ""))
	if a == b or not part_by_id.has(a) or not part_by_id.has(b):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_ENDPOINT", {"bond_id": bond["bond_id"]})
	return Utils.success()

static func _validate_capacity(spec: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(spec, CAPACITY_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(spec.get("bond_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_CAPACITY_BOND_ID")
	checked = _validate_vec3(spec.get("point_from_com"))
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_positive_number(spec.get("certified_force_capacity")) or not Utils.is_positive_number(spec.get("certified_moment_capacity")):
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_CAPACITY", {"bond_id": spec["bond_id"]})
	if not Utils.is_non_negative_number(spec.get("uncertainty_ratio")) or float(spec["uncertainty_ratio"]) >= 1.0:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_BOND_UNCERTAINTY", {"bond_id": spec["bond_id"]})
	return Utils.success()

static func _validate_vec3(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_VECTOR3")
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_VECTOR3")
	return Utils.success()

static func _validate_quat(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 4:
		return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_QUATERNION")
	var norm_sq := 0.0
	for component in value:
		if not Utils.is_finite_number(component):
			return Utils.failure("INVALID_STRUCTURAL_REFINEMENT_QUATERNION")
		norm_sq += float(component) * float(component)
	if absf(norm_sq - 1.0) > 1.0e-9:
		return Utils.failure("NON_UNIT_STRUCTURAL_REFINEMENT_QUATERNION")
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
	for r in range(3):
		for c in range(3):
			if absf(float(value[r][c]) - float(value[c][r])) > 1.0e-10:
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

static func _rotation_matrix(q: Quaternion) -> Array:
	var basis := Basis(q)
	return [
		[basis.x.x, basis.y.x, basis.z.x],
		[basis.x.y, basis.y.y, basis.z.y],
		[basis.x.z, basis.y.z, basis.z.z],
	]

static func _mat_mul(a: Array, b: Array) -> Array:
	var output := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for r in range(3):
		for c in range(3):
			var value := 0.0
			for k in range(3):
				value += float(a[r][k]) * float(b[k][c])
			output[r][c] = value
	return output

static func _mat_transpose(a: Array) -> Array:
	return [
		[float(a[0][0]), float(a[1][0]), float(a[2][0])],
		[float(a[0][1]), float(a[1][1]), float(a[2][1])],
		[float(a[0][2]), float(a[1][2]), float(a[2][2])],
	]

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

static func _quat_distance(a: Quaternion, b: Quaternion) -> float:
	return 1.0 - absf(a.normalized().dot(b.normalized()))
