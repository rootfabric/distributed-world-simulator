extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")

const DEFAULT_TOLERANCE_M: float = 0.000001


static func shared_face(fine_mesh: Dictionary, coarse_mesh: Dictionary, tolerance_m: float = DEFAULT_TOLERANCE_M) -> Dictionary:
	if not bool(MeshData.validate(fine_mesh).get("success", false)) \
		or not bool(MeshData.validate(coarse_mesh).get("success", false)) \
		or tolerance_m <= 0.0 or not is_finite(tolerance_m):
		return {}
	var fine_bounds: Array = fine_mesh["bounds_m"]
	var coarse_bounds: Array = coarse_mesh["bounds_m"]
	for axis in range(3):
		var tangent_a: int = (axis + 1) % 3
		var tangent_b: int = (axis + 2) % 3
		var overlaps_a: bool = minf(float(fine_bounds[tangent_a + 3]), float(coarse_bounds[tangent_a + 3])) \
			- maxf(float(fine_bounds[tangent_a]), float(coarse_bounds[tangent_a])) > tolerance_m
		var overlaps_b: bool = minf(float(fine_bounds[tangent_b + 3]), float(coarse_bounds[tangent_b + 3])) \
			- maxf(float(fine_bounds[tangent_b]), float(coarse_bounds[tangent_b])) > tolerance_m
		if not overlaps_a or not overlaps_b:
			continue
		if absf(float(fine_bounds[axis + 3]) - float(coarse_bounds[axis])) <= tolerance_m:
			return {"axis": axis, "direction": 1, "plane_coordinate_m": float(fine_bounds[axis + 3])}
		if absf(float(fine_bounds[axis]) - float(coarse_bounds[axis + 3])) <= tolerance_m:
			return {"axis": axis, "direction": -1, "plane_coordinate_m": float(fine_bounds[axis])}
	return {}


static func segments(
	mesh_data: Dictionary,
	axis: int,
	plane_coordinate_m: float,
	tolerance_m: float = DEFAULT_TOLERANCE_M
) -> Array:
	if not bool(MeshData.validate(mesh_data).get("success", false)) \
		or axis < 0 or axis > 2 or tolerance_m <= 0.0:
		return []
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var normals: PackedVector3Array = mesh_data["normals"]
	var colors: PackedColorArray = mesh_data["colors"]
	var indices: PackedInt32Array = mesh_data["indices"]
	var origin: Vector3 = mesh_data["origin_body_local_m"]
	var segments_by_key: Dictionary = {}
	for triangle_offset in range(0, indices.size(), 3):
		var boundary: Array = []
		for corner_offset in range(3):
			var vertex_index: int = int(indices[triangle_offset + corner_offset])
			var point: Vector3 = origin + vertices[vertex_index]
			if absf(point[axis] - plane_coordinate_m) <= tolerance_m:
				boundary.append({
					"point": point,
					"normal": normals[vertex_index],
					"color": colors[vertex_index],
				})
		if boundary.size() < 2:
			continue
		for first in range(boundary.size() - 1):
			for second in range(first + 1, boundary.size()):
				var a: Dictionary = boundary[first]
				var b: Dictionary = boundary[second]
				var key_a: String = _point_key(a["point"], tolerance_m)
				var key_b: String = _point_key(b["point"], tolerance_m)
				if key_a == key_b:
					continue
				var ordered_a: Dictionary = a if key_a < key_b else b
				var ordered_b: Dictionary = b if key_a < key_b else a
				var segment_key: String = "%s|%s" % [key_a, key_b] if key_a < key_b else "%s|%s" % [key_b, key_a]
				segments_by_key[segment_key] = {
					"key": segment_key,
					"point_a": ordered_a["point"],
					"point_b": ordered_b["point"],
					"normal_a": ordered_a["normal"],
					"normal_b": ordered_b["normal"],
					"color_a": ordered_a["color"],
					"color_b": ordered_b["color"],
				}
	var keys: Array = segments_by_key.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(segments_by_key[key])
	return result


static func segment_signature(segments_value: Array, tolerance_m: float = DEFAULT_TOLERANCE_M) -> Array:
	var result: Array = []
	for raw_segment in segments_value:
		var segment: Dictionary = raw_segment
		result.append([
			_quantized_point(segment["point_a"], tolerance_m),
			_quantized_point(segment["point_b"], tolerance_m),
		])
	return result


static func segment_hash(segments_value: Array, tolerance_m: float = DEFAULT_TOLERANCE_M) -> String:
	return RepresentationUtils.payload_hash(segment_signature(segments_value, tolerance_m))


static func _point_key(point: Vector3, tolerance_m: float) -> String:
	var signature: Array = _quantized_point(point, tolerance_m)
	return "%d:%d:%d" % [int(signature[0]), int(signature[1]), int(signature[2])]


static func _quantized_point(point: Vector3, tolerance_m: float) -> Array:
	return [
		int(round(point.x / tolerance_m)),
		int(round(point.y / tolerance_m)),
		int(round(point.z / tolerance_m)),
	]
