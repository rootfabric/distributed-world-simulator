extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

const ROOT_PART_ID := "part/b0-2-0000"
const WEAK_BOND_ID := "bond/b0-2-0257"
const WEAK_REGION_ID := "region/b0-2-012"
const LOCAL_PAIR_A := "part/b0-2-0240"
const LOCAL_PAIR_B := "part/b0-2-0280"
const TRIGGER_RATIO := 0.80
const TARGET_UNCERTAINTY := 0.05
const DEFAULT_UNCERTAINTY := 0.02
const TARGET_FORCE_CAPACITY := 40.0
const DEFAULT_FORCE_CAPACITY := 1000.0
const MOMENT_CAPACITY := 1.0e9
const RESIDUAL_FORCE_TOLERANCE := 1.0e-8
const RESIDUAL_MOMENT_TOLERANCE := 1.0e-8

static func build(reverse_input: bool = false, add_cycle: bool = false) -> Dictionary:
	var ab := ABFixture.build(0, reverse_input)
	if add_cycle:
		var extra_bond := {
			"bond_id": "bond/b0-2-cycle",
			"part_a": "part/b0-2-0000",
			"part_b": "part/b0-2-0499",
			"rigid": true,
		}
		ab["bonds"].append(extra_bond)
		ab["request"]["bonds"] = ab["bonds"].duplicate(true)
	var aggregate := AggregateCompiler.compile(ab["request"])
	if not bool(aggregate.get("success", false)):
		return {"success": false, "aggregate": aggregate, "ab": ab}
	var capacities := make_capacity_specs(ab["bonds"], ab["parts"], aggregate["descriptor"])
	if reverse_input:
		capacities.reverse()
	var request := {
		"field_id": "guard-field/b0-2-c",
		"source_frontier_hash": String(ab["frontier"]["frontier_hash"]),
		"structural_descriptor": aggregate["descriptor"],
		"reconstruction_mapping": aggregate["reconstruction_mapping"],
		"parts": ab["parts"].duplicate(true),
		"bonds": ab["bonds"].duplicate(true),
		"root_part_id": ROOT_PART_ID,
		"bond_capacity_specs": capacities,
		"capacity_certificate_hash": capacity_hash(String(ab["frontier"]["frontier_hash"]), capacities),
		"trigger_ratio": TRIGGER_RATIO,
		"required_refinement_level": 2,
		"residual_force_tolerance": RESIDUAL_FORCE_TOLERANCE,
		"residual_moment_tolerance": RESIDUAL_MOMENT_TOLERANCE,
		"evaluator_version": "FABRIC_BAKE_B0_2_C_R1",
	}
	return {
		"success": true,
		"ab": ab,
		"aggregate": aggregate,
		"capacities": capacities,
		"request": request,
	}

static func capacity_hash(source_frontier_hash: String, capacities: Array) -> String:
	var sorted := Utils.sorted_dicts(capacities, "bond_id")
	return Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_capacity_set.v1",
		"source_frontier_hash": source_frontier_hash,
		"bond_capacity_specs": sorted,
	})

static func make_capacity_specs(bonds: Array, parts: Array, descriptor: Dictionary) -> Array:
	var part_positions: Dictionary = {}
	var com := vec3(descriptor["center_of_mass"])
	for part in parts:
		part_positions[String(part["part_id"])] = vec3(part["position"]) - com
	var specs: Array = []
	for bond in bonds:
		var bond_id := String(bond["bond_id"])
		var point := ((part_positions[String(bond["part_a"])] as Vector3) + (part_positions[String(bond["part_b"])] as Vector3)) * 0.5
		var weak := bond_id == WEAK_BOND_ID
		specs.append({
			"bond_id": bond_id,
			"point_from_com": arr3(point),
			"certified_force_capacity": TARGET_FORCE_CAPACITY if weak else DEFAULT_FORCE_CAPACITY,
			"certified_moment_capacity": MOMENT_CAPACITY,
			"uncertainty_ratio": TARGET_UNCERTAINTY if weak else DEFAULT_UNCERTAINTY,
		})
	return specs

static func dynamics() -> Dictionary:
	return {
		"linear_acceleration_body": [0.37, -0.19, 0.11],
		"angular_velocity_body": [0.21, -0.13, 0.17],
		"angular_acceleration_body": [0.031, -0.022, 0.014],
	}

static func runtime_context(fixture: Dictionary, load_magnitude: float, include_dynamic_base: bool = true) -> Dictionary:
	var d := dynamics()
	var wrenches: Array = []
	if include_dynamic_base:
		wrenches = rigid_inertial_wrenches(
			fixture["ab"]["parts"], fixture["aggregate"]["descriptor"],
			vec3(d["linear_acceleration_body"]), vec3(d["angular_velocity_body"]), vec3(d["angular_acceleration_body"])
		)
	else:
		d = {
			"linear_acceleration_body": [0.0, 0.0, 0.0],
			"angular_velocity_body": [0.0, 0.0, 0.0],
			"angular_acceleration_body": [0.0, 0.0, 0.0],
		}
	wrenches.append_array(local_balanced_pair_wrenches(fixture["aggregate"]["reconstruction_mapping"], load_magnitude))
	return {
		"source_frontier_hash": String(fixture["ab"]["frontier"]["frontier_hash"]),
		"structural_descriptor_hash": String(fixture["aggregate"]["descriptor"]["checksum"]),
		"reconstruction_mapping_hash": String(fixture["aggregate"]["reconstruction_mapping"]["checksum"]),
		"complete_external_wrench_set": true,
		"linear_acceleration_body": d["linear_acceleration_body"],
		"angular_velocity_body": d["angular_velocity_body"],
		"angular_acceleration_body": d["angular_acceleration_body"],
		"external_wrenches": wrenches,
	}

static func rigid_inertial_wrenches(parts: Array, descriptor: Dictionary, a_com: Vector3, omega: Vector3, alpha: Vector3) -> Array:
	var com := vec3(descriptor["center_of_mass"])
	var wrenches: Array = []
	for part in parts:
		var part_id := String(part["part_id"])
		var r := vec3(part["position"]) - com
		var mass := float(part["mass"])
		var q := quat(part["orientation"])
		var rotation := rotation_matrix(q)
		var inertia_body := mat_mul(mat_mul(rotation, part["inertia_tensor"]), mat_transpose(rotation))
		var point_acceleration := a_com + alpha.cross(r) + omega.cross(omega.cross(r))
		var force := point_acceleration * mass
		var spin_moment := mat_vec(inertia_body, alpha) + omega.cross(mat_vec(inertia_body, omega))
		wrenches.append({
			"wrench_id": "wrench/inertial-%s" % part_id.replace("/", "-"),
			"part_id": part_id,
			"point_from_com": arr3(r),
			"force_body": arr3(force),
			"torque_body_about_point": arr3(spin_moment),
		})
	return wrenches

static func local_balanced_pair_wrenches(mapping: Dictionary, load_magnitude: float) -> Array:
	var positions: Dictionary = {}
	for part in mapping["part_mappings"]:
		positions[String(part["part_id"])] = vec3(part["position_from_com"])
	var point_a: Vector3 = positions[LOCAL_PAIR_A]
	var point_b: Vector3 = positions[LOCAL_PAIR_B]
	var force := Vector3(load_magnitude, 0.0, 0.0)
	var balancing_torque := -(point_b - point_a).cross(force)
	return [
		{
			"wrench_id": "wrench/local-a",
			"part_id": LOCAL_PAIR_A,
			"point_from_com": arr3(point_a),
			"force_body": arr3(-force),
			"torque_body_about_point": arr3(balancing_torque),
		},
		{
			"wrench_id": "wrench/local-b",
			"part_id": LOCAL_PAIR_B,
			"point_from_com": arr3(point_b),
			"force_body": arr3(force),
			"torque_body_about_point": [0.0, 0.0, 0.0],
		},
	]

static func vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

static func arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func rotation_matrix(q: Quaternion) -> Array:
	var basis := Basis(q)
	return [
		[basis.x.x, basis.y.x, basis.z.x],
		[basis.x.y, basis.y.y, basis.z.y],
		[basis.x.z, basis.y.z, basis.z.z],
	]

static func mat_mul(a: Array, b: Array) -> Array:
	var output := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for r in range(3):
		for c in range(3):
			var value := 0.0
			for k in range(3):
				value += float(a[r][k]) * float(b[k][c])
			output[r][c] = value
	return output

static func mat_transpose(a: Array) -> Array:
	return [
		[float(a[0][0]), float(a[1][0]), float(a[2][0])],
		[float(a[0][1]), float(a[1][1]), float(a[2][1])],
		[float(a[0][2]), float(a[1][2]), float(a[2][2])],
	]

static func mat_vec(matrix: Array, vector: Vector3) -> Vector3:
	return Vector3(
		float(matrix[0][0]) * vector.x + float(matrix[0][1]) * vector.y + float(matrix[0][2]) * vector.z,
		float(matrix[1][0]) * vector.x + float(matrix[1][1]) * vector.y + float(matrix[1][2]) * vector.z,
		float(matrix[2][0]) * vector.x + float(matrix[2][1]) * vector.y + float(matrix[2][2]) * vector.z
	)
