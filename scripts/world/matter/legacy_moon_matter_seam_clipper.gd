extends RefCounted

const POSITION_EPSILON_M: float = 0.000000001
const AREA_EPSILON_SQUARED: float = 0.000000000000000001


static func clip_mesh_arrays(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	surface_anchor_world: Vector3,
	exclusion_bounds: Dictionary
) -> Dictionary:
	if indices.size() % 3 != 0 or vertices.is_empty() \
		or not _valid_bounds(exclusion_bounds):
		return {}
	var minimum_m := _vector3(exclusion_bounds["minimum_m"])
	var maximum_m := _vector3(exclusion_bounds["maximum_m"])
	var clearance_m := float(exclusion_bounds.get("clearance_m", 0.0))
	var expanded_minimum := minimum_m - Vector3.ONE * clearance_m
	var expanded_maximum := maximum_m + Vector3.ONE * clearance_m
	var has_uvs := uvs.size() == vertices.size()
	var output_vertices := vertices.duplicate()
	var output_uvs := uvs.duplicate() if has_uvs else PackedVector2Array()
	var output_indices := PackedInt32Array()
	var untouched_triangles := 0
	var clipped_triangles := 0
	var removed_triangles := 0
	var boundary_vertices := 0
	var planes: Array = [
		[0, expanded_minimum.x, true],
		[0, expanded_maximum.x, false],
		[1, expanded_minimum.y, true],
		[1, expanded_maximum.y, false],
		[2, expanded_minimum.z, true],
		[2, expanded_maximum.z, false],
	]

	for triangle_offset in range(0, indices.size(), 3):
		var ia: int = indices[triangle_offset]
		var ib: int = indices[triangle_offset + 1]
		var ic: int = indices[triangle_offset + 2]
		if ia < 0 or ib < 0 or ic < 0 \
			or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
			return {}
		var body_a := surface_anchor_world + vertices[ia]
		var body_b := surface_anchor_world + vertices[ib]
		var body_c := surface_anchor_world + vertices[ic]
		if _triangle_aabb_outside(body_a, body_b, body_c, expanded_minimum, expanded_maximum):
			output_indices.append_array(PackedInt32Array([ia, ib, ic]))
			untouched_triangles += 1
			continue

		var original_normal := (body_b - body_a).cross(body_c - body_a)
		var remaining: Array = [
			_vertex(body_a, uvs[ia] if has_uvs else Vector2.ZERO),
			_vertex(body_b, uvs[ib] if has_uvs else Vector2.ZERO),
			_vertex(body_c, uvs[ic] if has_uvs else Vector2.ZERO),
		]
		var outside_pieces: Array = []
		for plane_value in planes:
			if remaining.size() < 3:
				break
			var plane: Array = plane_value
			var split := _split_polygon(
				remaining,
				int(plane[0]),
				float(plane[1]),
				bool(plane[2])
			)
			var outside: Array = split["outside"]
			if outside.size() >= 3:
				outside_pieces.append(outside)
			remaining = split["inside"]

		if outside_pieces.is_empty():
			removed_triangles += 1
			continue
		clipped_triangles += 1
		for polygon_value in outside_pieces:
			var polygon: Array = polygon_value
			if polygon.size() < 3:
				continue
			var base_index := output_vertices.size()
			for vertex_value in polygon:
				var clipped_vertex: Dictionary = vertex_value
				var body_position: Vector3 = clipped_vertex["position_m"]
				output_vertices.append(body_position - surface_anchor_world)
				if has_uvs:
					output_uvs.append(clipped_vertex["uv"])
				boundary_vertices += 1
			for polygon_index in range(1, polygon.size() - 1):
				var i0 := base_index
				var i1 := base_index + polygon_index
				var i2 := base_index + polygon_index + 1
				var p0: Vector3 = output_vertices[i0]
				var p1: Vector3 = output_vertices[i1]
				var p2: Vector3 = output_vertices[i2]
				var triangle_normal := (p1 - p0).cross(p2 - p0)
				if triangle_normal.length_squared() <= AREA_EPSILON_SQUARED:
					continue
				if triangle_normal.dot(original_normal) < 0.0:
					var swap := i1
					i1 = i2
					i2 = swap
				output_indices.append_array(PackedInt32Array([i0, i1, i2]))

	return {
		"vertices": output_vertices,
		"uvs": output_uvs,
		"indices": output_indices,
		"untouched_triangle_count": untouched_triangles,
		"clipped_source_triangle_count": clipped_triangles,
		"removed_source_triangle_count": removed_triangles,
		"boundary_vertex_count": boundary_vertices,
		"expanded_minimum_m": expanded_minimum,
		"expanded_maximum_m": expanded_maximum,
	}


static func triangle_fully_outside_exclusion(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	exclusion_bounds: Dictionary
) -> bool:
	if not _valid_bounds(exclusion_bounds):
		return false
	var clearance_m := float(exclusion_bounds.get("clearance_m", 0.0))
	var minimum_m := _vector3(exclusion_bounds["minimum_m"]) - Vector3.ONE * clearance_m
	var maximum_m := _vector3(exclusion_bounds["maximum_m"]) + Vector3.ONE * clearance_m
	return _triangle_aabb_outside(a, b, c, minimum_m, maximum_m)


static func _split_polygon(
	polygon: Array,
	axis: int,
	boundary: float,
	keep_greater: bool
) -> Dictionary:
	var inside: Array = []
	var outside: Array = []
	for index in range(polygon.size()):
		var current: Dictionary = polygon[index]
		var next: Dictionary = polygon[(index + 1) % polygon.size()]
		var current_coordinate := _axis_value(current["position_m"], axis)
		var next_coordinate := _axis_value(next["position_m"], axis)
		var current_inside := (
			current_coordinate >= boundary - POSITION_EPSILON_M
			if keep_greater
			else current_coordinate <= boundary + POSITION_EPSILON_M
		)
		var next_inside := (
			next_coordinate >= boundary - POSITION_EPSILON_M
			if keep_greater
			else next_coordinate <= boundary + POSITION_EPSILON_M
		)
		if current_inside:
			inside.append(current)
		else:
			outside.append(current)
		if current_inside == next_inside:
			continue
		var denominator := next_coordinate - current_coordinate
		if absf(denominator) <= POSITION_EPSILON_M:
			continue
		var t := clampf((boundary - current_coordinate) / denominator, 0.0, 1.0)
		var intersection := _vertex(
			Vector3(current["position_m"]).lerp(Vector3(next["position_m"]), t),
			Vector2(current["uv"]).lerp(Vector2(next["uv"]), t)
		)
		inside.append(intersection)
		outside.append(intersection)
	return {"inside": _deduplicate_polygon(inside), "outside": _deduplicate_polygon(outside)}


static func _deduplicate_polygon(polygon: Array) -> Array:
	var result: Array = []
	for vertex_value in polygon:
		var vertex: Dictionary = vertex_value
		if not result.is_empty():
			var previous: Dictionary = result[result.size() - 1]
			if Vector3(previous["position_m"]).distance_squared_to(
				Vector3(vertex["position_m"])
			) <= POSITION_EPSILON_M * POSITION_EPSILON_M:
				continue
		result.append(vertex)
	if result.size() >= 2:
		var first: Dictionary = result[0]
		var last: Dictionary = result[result.size() - 1]
		if Vector3(first["position_m"]).distance_squared_to(
			Vector3(last["position_m"])
		) <= POSITION_EPSILON_M * POSITION_EPSILON_M:
			result.pop_back()
	return result


static func _triangle_aabb_outside(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	minimum_m: Vector3,
	maximum_m: Vector3
) -> bool:
	var triangle_min := Vector3(
		minf(a.x, minf(b.x, c.x)),
		minf(a.y, minf(b.y, c.y)),
		minf(a.z, minf(b.z, c.z))
	)
	var triangle_max := Vector3(
		maxf(a.x, maxf(b.x, c.x)),
		maxf(a.y, maxf(b.y, c.y)),
		maxf(a.z, maxf(b.z, c.z))
	)
	return triangle_max.x <= minimum_m.x \
		or triangle_min.x >= maximum_m.x \
		or triangle_max.y <= minimum_m.y \
		or triangle_min.y >= maximum_m.y \
		or triangle_max.z <= minimum_m.z \
		or triangle_min.z >= maximum_m.z


static func _vertex(position_m: Vector3, uv: Vector2) -> Dictionary:
	return {"position_m": position_m, "uv": uv}


static func _axis_value(value: Vector3, axis: int) -> float:
	match axis:
		0:
			return value.x
		1:
			return value.y
		_:
			return value.z


static func _valid_bounds(value: Dictionary) -> bool:
	if typeof(value.get("minimum_m")) != TYPE_ARRAY \
		or typeof(value.get("maximum_m")) != TYPE_ARRAY \
		or Array(value["minimum_m"]).size() != 3 \
		or Array(value["maximum_m"]).size() != 3:
		return false
	var minimum_m := _vector3(value["minimum_m"])
	var maximum_m := _vector3(value["maximum_m"])
	var clearance_m := float(value.get("clearance_m", 0.0))
	return is_finite(minimum_m.x) and is_finite(minimum_m.y) and is_finite(minimum_m.z) \
		and is_finite(maximum_m.x) and is_finite(maximum_m.y) and is_finite(maximum_m.z) \
		and minimum_m.x < maximum_m.x \
		and minimum_m.y < maximum_m.y \
		and minimum_m.z < maximum_m.z \
		and is_finite(clearance_m) and clearance_m >= 0.0


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
