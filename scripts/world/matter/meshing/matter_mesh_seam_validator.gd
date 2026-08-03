extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")

const DEFAULT_TOLERANCE_M: float = 0.000001
const DEFAULT_NORMAL_TOLERANCE: float = 0.000001


static func compare_shared_plane(
	left_mesh: Dictionary,
	right_mesh: Dictionary,
	axis: int,
	plane_coordinate_m: float,
	tolerance_m: float = DEFAULT_TOLERANCE_M
) -> Dictionary:
	if not bool(MeshDataScript.validate(left_mesh).get("success", false)) \
		or not bool(MeshDataScript.validate(right_mesh).get("success", false)) \
		or axis < 0 or axis > 2 or not is_finite(plane_coordinate_m) \
		or not is_finite(tolerance_m) or tolerance_m <= 0.0:
		return MatterUtilsScript.failure("INVALID_MATTER_MESH_SEAM_INPUT")
	var left_points: Array = _boundary_vertex_signature(
		left_mesh, axis, plane_coordinate_m, tolerance_m
	)
	var right_points: Array = _boundary_vertex_signature(
		right_mesh, axis, plane_coordinate_m, tolerance_m
	)
	if left_points != right_points:
		return MatterUtilsScript.failure("MATTER_MESH_SEAM_VERTEX_MISMATCH", {
			"left_count": left_points.size(),
			"right_count": right_points.size(),
			"left_hash": MatterUtilsScript.payload_hash(left_points),
			"right_hash": MatterUtilsScript.payload_hash(right_points),
		})
	var left_normals: Array = _boundary_normal_signature(
		left_mesh, axis, plane_coordinate_m, tolerance_m
	)
	var right_normals: Array = _boundary_normal_signature(
		right_mesh, axis, plane_coordinate_m, tolerance_m
	)
	if left_normals != right_normals:
		return MatterUtilsScript.failure("MATTER_MESH_SEAM_NORMAL_MISMATCH", {
			"left_count": left_normals.size(),
			"right_count": right_normals.size(),
			"left_hash": MatterUtilsScript.payload_hash(left_normals),
			"right_hash": MatterUtilsScript.payload_hash(right_normals),
		})
	var left_segments: Array = _boundary_segment_signature(
		left_mesh, axis, plane_coordinate_m, tolerance_m
	)
	var right_segments: Array = _boundary_segment_signature(
		right_mesh, axis, plane_coordinate_m, tolerance_m
	)
	if left_points.is_empty() or right_points.is_empty() \
		or left_normals.is_empty() or right_normals.is_empty() \
		or left_segments.is_empty() or right_segments.is_empty():
		return MatterUtilsScript.failure("MATTER_MESH_SEAM_INTERSECTION_MISSING", {
			"left_vertex_count": left_points.size(),
			"right_vertex_count": right_points.size(),
			"left_normal_count": left_normals.size(),
			"right_normal_count": right_normals.size(),
			"left_segment_count": left_segments.size(),
			"right_segment_count": right_segments.size(),
		})
	if left_segments != right_segments:
		return MatterUtilsScript.failure("MATTER_MESH_SEAM_SEGMENT_MISMATCH", {
			"left_count": left_segments.size(),
			"right_count": right_segments.size(),
			"left_hash": MatterUtilsScript.payload_hash(left_segments),
			"right_hash": MatterUtilsScript.payload_hash(right_segments),
		})
	return MatterUtilsScript.success({
		"boundary_vertex_count": left_points.size(),
		"boundary_normal_count": left_normals.size(),
		"boundary_segment_count": left_segments.size(),
		"boundary_vertex_hash": MatterUtilsScript.payload_hash(left_points),
		"boundary_normal_hash": MatterUtilsScript.payload_hash(left_normals),
		"boundary_segment_hash": MatterUtilsScript.payload_hash(left_segments),
	})


static func _boundary_vertex_signature(
	mesh_data: Dictionary,
	axis: int,
	plane_coordinate_m: float,
	tolerance_m: float
) -> Array:
	var result_by_key: Dictionary = {}
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var origin: Vector3 = mesh_data["origin_body_local_m"]
	for vertex in vertices:
		var world_vertex: Vector3 = origin + vertex
		if absf(world_vertex[axis] - plane_coordinate_m) > tolerance_m:
			continue
		var signature: Array = _quantized_point(world_vertex, tolerance_m)
		result_by_key[_signature_key(signature)] = signature
	var keys: Array = result_by_key.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(result_by_key[key])
	return result


static func _boundary_normal_signature(
	mesh_data: Dictionary,
	axis: int,
	plane_coordinate_m: float,
	tolerance_m: float
) -> Array:
	var result_by_key: Dictionary = {}
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var normals: PackedVector3Array = mesh_data["normals"]
	var origin: Vector3 = mesh_data["origin_body_local_m"]
	for index in range(vertices.size()):
		var world_vertex: Vector3 = origin + vertices[index]
		if absf(world_vertex[axis] - plane_coordinate_m) > tolerance_m:
			continue
		var point_signature: Array = _quantized_point(world_vertex, tolerance_m)
		var normal_signature: Array = _quantized_normal(normals[index])
		var key: String = "%s|%s" % [
			_signature_key(point_signature), _signature_key(normal_signature)
		]
		result_by_key[key] = [point_signature, normal_signature]
	var keys: Array = result_by_key.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(result_by_key[key])
	return result


static func _boundary_segment_signature(
	mesh_data: Dictionary,
	axis: int,
	plane_coordinate_m: float,
	tolerance_m: float
) -> Array:
	var result_by_key: Dictionary = {}
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var indices: PackedInt32Array = mesh_data["indices"]
	var origin: Vector3 = mesh_data["origin_body_local_m"]
	for triangle_offset in range(0, indices.size(), 3):
		var boundary_points: Array = []
		for corner_offset in range(3):
			var world_vertex: Vector3 = origin + vertices[indices[triangle_offset + corner_offset]]
			if absf(world_vertex[axis] - plane_coordinate_m) <= tolerance_m:
				boundary_points.append(_quantized_point(world_vertex, tolerance_m))
		if boundary_points.size() < 2:
			continue
		for first in range(boundary_points.size() - 1):
			for second in range(first + 1, boundary_points.size()):
				var point_a: Array = boundary_points[first]
				var point_b: Array = boundary_points[second]
				var key_a: String = _signature_key(point_a)
				var key_b: String = _signature_key(point_b)
				if key_a == key_b:
					continue
				var segment: Array = [point_a, point_b] if key_a < key_b else [point_b, point_a]
				result_by_key["%s|%s" % [
					_signature_key(segment[0]), _signature_key(segment[1])
				]] = segment
	var keys: Array = result_by_key.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(result_by_key[key])
	return result


static func _quantized_point(value: Vector3, tolerance_m: float) -> Array:
	return [
		int(round(value.x / tolerance_m)),
		int(round(value.y / tolerance_m)),
		int(round(value.z / tolerance_m)),
	]


static func _quantized_normal(value: Vector3) -> Array:
	return [
		int(round(value.x / DEFAULT_NORMAL_TOLERANCE)),
		int(round(value.y / DEFAULT_NORMAL_TOLERANCE)),
		int(round(value.z / DEFAULT_NORMAL_TOLERANCE)),
	]


static func _signature_key(signature: Array) -> String:
	return "%d:%d:%d" % [int(signature[0]), int(signature[1]), int(signature[2])]
