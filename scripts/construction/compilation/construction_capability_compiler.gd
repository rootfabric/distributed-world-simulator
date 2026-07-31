extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")

static func compile(parts: Array, bonds: Array) -> Dictionary:
	var part_by_id: Dictionary = {}
	var total_mass_kg: float = 0.0
	var weighted_position := Vector3.ZERO
	var support_points: Array[Vector2] = []
	var surface_count: int = 0
	for raw_part in parts:
		if typeof(raw_part) != TYPE_DICTIONARY:
			return _failure("INVALID_PART_RECORD")
		var part: Dictionary = raw_part
		var validation: Dictionary = PartScript.validate(part)
		if not bool(validation.get("success", false)):
			return validation
		var part_id: String = String(part["part_id"])
		if part_by_id.has(part_id):
			return _failure("DUPLICATE_PART_ID")
		part_by_id[part_id] = part
		var mass: float = float(part["mass_kg"])
		var position := Vector3(float(part["local_position_m"][0]), float(part["local_position_m"][1]), float(part["local_position_m"][2]))
		total_mass_kg += mass
		weighted_position += position * mass
		match String(part["role"]):
			"support":
				support_points.append(Vector2(position.x, position.z))
			"surface":
				surface_count += 1

	var intact_adjacency: Dictionary = {}
	for part_id in part_by_id.keys():
		intact_adjacency[part_id] = []
	var seen_bonds: Dictionary = {}
	for raw_bond in bonds:
		if typeof(raw_bond) != TYPE_DICTIONARY:
			return _failure("INVALID_BOND_RECORD")
		var bond: Dictionary = raw_bond
		var validation: Dictionary = BondScript.validate(bond)
		if not bool(validation.get("success", false)):
			return validation
		var bond_id: String = String(bond["bond_id"])
		if seen_bonds.has(bond_id):
			return _failure("DUPLICATE_BOND_ID")
		seen_bonds[bond_id] = true
		var part_a: String = String(bond["part_a_id"])
		var part_b: String = String(bond["part_b_id"])
		if not part_by_id.has(part_a) or not part_by_id.has(part_b):
			return _failure("BOND_REFERENCES_UNKNOWN_PART")
		if String(bond["state"]) != "BROKEN":
			intact_adjacency[part_a].append(part_b)
			intact_adjacency[part_b].append(part_a)

	var connected: bool = _is_connected(intact_adjacency)
	var center_of_mass := Vector3.ZERO if total_mass_kg <= 0.0 else weighted_position / total_mass_kg
	var stable: bool = connected and support_points.size() >= 3 and _point_in_convex_hull(Vector2(center_of_mass.x, center_of_mass.z), support_points)
	var capabilities: Array[String] = []
	if stable and surface_count > 0:
		capabilities.append("PLACE_ITEMS")
		capabilities.append("SUPPORT_SURFACE")
		capabilities.append("WORK_SURFACE")
	capabilities.sort()
	return {
		"success": true,
		"error_code": "",
		"message": "",
		"compiled": {
			"total_mass_kg": total_mass_kg,
			"center_of_mass_m": [center_of_mass.x, center_of_mass.y, center_of_mass.z],
			"connected": connected,
			"stable": stable,
			"rigid_island_count": _count_components(intact_adjacency),
			"capabilities": capabilities,
		},
	}

static func _is_connected(adjacency: Dictionary) -> bool:
	return adjacency.is_empty() or _count_components(adjacency) == 1

static func _count_components(adjacency: Dictionary) -> int:
	var visited: Dictionary = {}
	var count: int = 0
	var keys: Array = adjacency.keys()
	keys.sort()
	for start in keys:
		if visited.has(start):
			continue
		count += 1
		var queue: Array = [start]
		visited[start] = true
		while not queue.is_empty():
			var current = queue.pop_front()
			var neighbours: Array = adjacency[current].duplicate()
			neighbours.sort()
			for neighbour in neighbours:
				if not visited.has(neighbour):
					visited[neighbour] = true
					queue.append(neighbour)
	return count

static func _point_in_convex_hull(point: Vector2, points: Array[Vector2]) -> bool:
	var hull: PackedVector2Array = Geometry2D.convex_hull(PackedVector2Array(points))
	if hull.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, hull)

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
