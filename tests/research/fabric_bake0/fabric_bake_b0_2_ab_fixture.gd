extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")

const PART_COUNT := 500
const REGION_SIZE := 20
const MINIMUM_PART_COUNT := 100

static func h(value) -> String:
	return Utils.canonical_hash(value)

static func build(mutation_revision: int = 0, reverse_input: bool = false) -> Dictionary:
	var source_dependency_hash := h({"dependency": "b0.2-ab-canonical-source"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/b0-2-structural", 9, 30 + mutation_revision,
		h({"construction": "b0.2-structural", "mutation_revision": mutation_revision}),
		source_dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/b0-2-structural", 9, 8,
		h({"matter": "b0.2-structural"}), source_dependency_hash
	)
	var frontier := Frontier.create([matter, construction])
	var parts := make_parts(PART_COUNT, mutation_revision)
	var bonds := make_bonds(PART_COUNT)
	var anchors := make_anchors(PART_COUNT)
	if reverse_input:
		parts.reverse()
		bonds.reverse()
		anchors.reverse()
	var request := {
		"descriptor_id": "aggregate/b0-2-structural",
		"mapping_id": "mapping/b0-2-structural",
		"source_frontier_hash": String(frontier["frontier_hash"]),
		"construct_id": "construct/b0-2-structural",
		"parts": parts,
		"bonds": bonds,
		"boundary_anchors": anchors,
		"reconstruction_version": "FABRIC_BAKE_B0_2_AB_R1",
		"minimum_part_count": MINIMUM_PART_COUNT,
	}
	return {
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"parts": parts,
		"bonds": bonds,
		"anchors": anchors,
		"request": request,
	}

static func make_parts(count: int, mutation_revision: int = 0) -> Array:
	var parts: Array = []
	for index in range(count):
		var x := index % 10
		var y := (index / 10) % 10
		var z := index / 100
		var mass := 1.0 + 0.025 * float(index % 11)
		if mutation_revision > 0 and index == 237:
			mass += 0.375 * float(mutation_revision)
		var half_extents := Vector3(
			0.35 + 0.015 * float(index % 3),
			0.28 + 0.010 * float(index % 5),
			0.22 + 0.012 * float(index % 7)
		)
		var position := Vector3(
			(float(x) - 4.5) * 1.25,
			(float(y) - 4.5) * 1.10,
			(float(z) - 2.0) * 0.95
		)
		var angle := float(index % 8) * PI / 16.0
		var axis := Vector3(0.3 + 0.1 * float(index % 2), 1.0, 0.2).normalized()
		var orientation := Quaternion(axis, angle).normalized()
		var size := half_extents * 2.0
		var inertia := [
			[mass * (size.y * size.y + size.z * size.z) / 12.0, 0.0, 0.0],
			[0.0, mass * (size.x * size.x + size.z * size.z) / 12.0, 0.0],
			[0.0, 0.0, mass * (size.x * size.x + size.y * size.y) / 12.0],
		]
		parts.append({
			"part_id": "part/b0-2-%04d" % index,
			"region_id": "region/b0-2-%03d" % (index / REGION_SIZE),
			"mass": mass,
			"position": arr3(position),
			"orientation": arr4(orientation),
			"inertia_tensor": inertia,
			"support_points": box_support_points(half_extents),
		})
	return parts

static func make_bonds(count: int) -> Array:
	var bonds: Array = []
	for index in range(1, count):
		bonds.append({
			"bond_id": "bond/b0-2-%04d" % index,
			"part_a": "part/b0-2-%04d" % (index - 1),
			"part_b": "part/b0-2-%04d" % index,
			"rigid": true,
		})
	return bonds

static func make_anchors(count: int) -> Array:
	return [
		{"anchor_id": "anchor/b0-2-a", "part_id": "part/b0-2-0000", "position_local": [-0.35, 0.0, 0.0], "orientation_local": [0.0, 0.0, 0.0, 1.0]},
		{"anchor_id": "anchor/b0-2-b", "part_id": "part/b0-2-0009", "position_local": [0.35, 0.0, 0.0], "orientation_local": [0.0, 0.0, 0.0, 1.0]},
		{"anchor_id": "anchor/b0-2-c", "part_id": "part/b0-2-%04d" % (count - 10), "position_local": [0.0, -0.28, 0.0], "orientation_local": [0.0, 0.0, 0.0, 1.0]},
		{"anchor_id": "anchor/b0-2-d", "part_id": "part/b0-2-%04d" % (count - 1), "position_local": [0.0, 0.28, 0.0], "orientation_local": [0.0, 0.0, 0.0, 1.0]},
	]

static func reduced_state() -> Dictionary:
	var q := Quaternion(Vector3(0.2, 1.0, -0.3).normalized(), 0.63).normalized()
	return {
		"position": [104.25, -87.5, 32.125],
		"orientation": arr4(q),
		"linear_velocity": [4.75, -1.25, 0.625],
		"angular_velocity": [0.35, -0.17, 0.22],
	}

static func box_support_points(half_extents: Vector3) -> Array:
	var points: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				points.append([sx * half_extents.x, sy * half_extents.y, sz * half_extents.z])
	return points

static func arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func arr4(value: Quaternion) -> Array:
	var q := value.normalized()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	return [q.x, q.y, q.z, q.w]
