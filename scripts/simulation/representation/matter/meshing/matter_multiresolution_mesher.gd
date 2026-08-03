extends RefCounted

const Field = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_field.gd")
const MeshData = preload("res://scripts/simulation/representation/matter/meshing/contracts/matter_multiresolution_mesh_data.gd")

const ISO_EPSILON_M: float = 0.000000001
const NORMAL_EPSILON_SQUARED: float = 0.000000000001
const EDGE_VERTICES: Array = [[0, 1], [1, 2], [2, 0], [0, 3], [1, 3], [2, 3]]
const TETRAHEDRA: Array = [
	[0, 1, 3, 7], [0, 1, 5, 7], [0, 2, 3, 7],
	[0, 2, 6, 7], [0, 4, 5, 7], [0, 4, 6, 7],
]
const TETRA_TRIANGLE_EDGES: Array = [
	[], [0, 3, 2], [0, 1, 4], [1, 4, 2, 2, 4, 3],
	[1, 2, 5], [0, 3, 5, 0, 5, 1], [0, 2, 5, 0, 5, 4], [5, 4, 3],
	[3, 4, 5], [4, 5, 0, 5, 2, 0], [1, 5, 0, 5, 3, 0], [5, 2, 1],
	[3, 4, 2, 2, 4, 1], [4, 1, 0], [2, 3, 0], [],
]
const CUBE_CORNERS: Array = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
]


static func build(field: Dictionary, grid_profile: Dictionary) -> Dictionary:
	if not bool(Field.validate(field, grid_profile).get("success", false)):
		return {}
	var resolution: int = int(field["resolution"])
	var spacing_m: float = float(field["sample_spacing_m"])
	var iso_level_m: float = float(field["iso_level_m"])
	var bounds_m: Array = field["bounds_m"]
	var minimum_m := Vector3(float(bounds_m[0]), float(bounds_m[1]), float(bounds_m[2]))
	var maximum_m := Vector3(float(bounds_m[3]), float(bounds_m[4]), float(bounds_m[5]))
	var origin_body_local_m: Vector3 = (minimum_m + maximum_m) * 0.5
	var signed_distance: Array = field["signed_distance_m"]
	var field_colors: Array = field["colors_rgba"]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var edge_vertex_by_key: Dictionary = {}
	for cube_z in range(resolution):
		for cube_y in range(resolution):
			for cube_x in range(resolution):
				var corner_indices: Array = []
				var corner_positions: Array = []
				var corner_distances: Array = []
				var corner_gradients: Array = []
				var corner_colors: Array = []
				for offset_value in CUBE_CORNERS:
					var offset: Vector3i = offset_value
					var x: int = cube_x + offset.x
					var y: int = cube_y + offset.y
					var z: int = cube_z + offset.z
					var flat_index: int = Field.flat_index(resolution, x, y, z)
					corner_indices.append(flat_index)
					corner_positions.append(Vector3(
						maximum_m.x if x == resolution else minimum_m.x + float(x) * spacing_m,
						maximum_m.y if y == resolution else minimum_m.y + float(y) * spacing_m,
						maximum_m.z if z == resolution else minimum_m.z + float(z) * spacing_m
					) - origin_body_local_m)
					corner_distances.append(float(signed_distance[flat_index]))
					corner_gradients.append(_gradient(resolution, signed_distance, x, y, z, spacing_m))
					var rgba: Array = field_colors[flat_index]
					corner_colors.append(Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3])))
				for tetra_value in TETRAHEDRA:
					_polygonize_tetra(
						tetra_value, corner_indices, corner_positions, corner_distances,
						corner_gradients, corner_colors, iso_level_m, edge_vertex_by_key,
						vertices, normals, colors, indices
					)
	var compacted: Dictionary = _compact(vertices, normals, colors, indices)
	return MeshData.create(
		field["representation_key"],
		String(field["field_hash"]),
		String(field["source_set"]["snapshot_set_hash"]),
		origin_body_local_m,
		bounds_m,
		iso_level_m,
		spacing_m,
		compacted["vertices"],
		compacted["normals"],
		compacted["colors"],
		compacted["indices"]
	)


static func _compact(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> Dictionary:
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_colors := PackedColorArray()
	var out_indices := PackedInt32Array()
	var remap: Dictionary = {}
	for source_index in indices:
		if not remap.has(source_index):
			remap[source_index] = out_vertices.size()
			out_vertices.append(vertices[source_index])
			out_normals.append(normals[source_index])
			out_colors.append(colors[source_index])
		out_indices.append(int(remap[source_index]))
	return {"vertices": out_vertices, "normals": out_normals, "colors": out_colors, "indices": out_indices}


static func _polygonize_tetra(
	tetra: Array,
	corner_indices: Array,
	corner_positions: Array,
	corner_distances: Array,
	corner_gradients: Array,
	corner_colors: Array,
	iso_level_m: float,
	edge_vertex_by_key: Dictionary,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> void:
	var case_index: int = 0
	for tetra_corner in range(4):
		if float(corner_distances[int(tetra[tetra_corner])]) <= iso_level_m:
			case_index |= 1 << tetra_corner
	var triangle_edges: Array = TETRA_TRIANGLE_EDGES[case_index]
	for triangle_offset in range(0, triangle_edges.size(), 3):
		var triangle: Array = []
		for edge_offset in range(3):
			var tetra_edge: Array = EDGE_VERTICES[int(triangle_edges[triangle_offset + edge_offset])]
			var corner_a: int = int(tetra[int(tetra_edge[0])])
			var corner_b: int = int(tetra[int(tetra_edge[1])])
			triangle.append(_edge_vertex(
				corner_a, corner_b, corner_indices, corner_positions, corner_distances,
				corner_gradients, corner_colors, iso_level_m, edge_vertex_by_key,
				vertices, normals, colors
			))
		if triangle.has(-1):
			continue
		var index_a: int = int(triangle[0])
		var index_b: int = int(triangle[1])
		var index_c: int = int(triangle[2])
		if index_a == index_b or index_b == index_c or index_c == index_a:
			continue
		var face_normal: Vector3 = (vertices[index_b] - vertices[index_a]).cross(vertices[index_c] - vertices[index_a])
		if face_normal.length_squared() <= NORMAL_EPSILON_SQUARED:
			continue
		var expected_normal: Vector3 = (normals[index_a] + normals[index_b] + normals[index_c]).normalized()
		if face_normal.dot(expected_normal) > 0.0:
			var swap: int = index_b
			index_b = index_c
			index_c = swap
		indices.append(index_a)
		indices.append(index_b)
		indices.append(index_c)


static func _edge_vertex(
	corner_a: int,
	corner_b: int,
	corner_indices: Array,
	corner_positions: Array,
	corner_distances: Array,
	corner_gradients: Array,
	corner_colors: Array,
	iso_level_m: float,
	edge_vertex_by_key: Dictionary,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray
) -> int:
	var sample_a: int = int(corner_indices[corner_a])
	var sample_b: int = int(corner_indices[corner_b])
	var edge_key: String = "%d:%d" % [mini(sample_a, sample_b), maxi(sample_a, sample_b)]
	if edge_vertex_by_key.has(edge_key):
		return int(edge_vertex_by_key[edge_key])
	var distance_a: float = float(corner_distances[corner_a])
	var distance_b: float = float(corner_distances[corner_b])
	var denominator: float = distance_b - distance_a
	var interpolation: float = 0.5
	if absf(denominator) > ISO_EPSILON_M:
		interpolation = clampf((iso_level_m - distance_a) / denominator, 0.0, 1.0)
	if absf(distance_a - iso_level_m) <= ISO_EPSILON_M:
		interpolation = 0.0
	elif absf(distance_b - iso_level_m) <= ISO_EPSILON_M:
		interpolation = 1.0
	var position: Vector3 = Vector3(corner_positions[corner_a]).lerp(corner_positions[corner_b], interpolation)
	var normal: Vector3 = Vector3(corner_gradients[corner_a]).lerp(corner_gradients[corner_b], interpolation)
	if normal.length_squared() <= NORMAL_EPSILON_SQUARED:
		normal = position.normalized()
	if normal.length_squared() <= NORMAL_EPSILON_SQUARED:
		normal = Vector3.UP
	normal = normal.normalized()
	var color: Color = Color(corner_colors[corner_a]).lerp(corner_colors[corner_b], interpolation)
	var vertex_index: int = vertices.size()
	vertices.append(position)
	normals.append(normal)
	colors.append(color)
	edge_vertex_by_key[edge_key] = vertex_index
	return vertex_index


static func _gradient(
	resolution: int,
	signed_distance: Array,
	x: int,
	y: int,
	z: int,
	spacing_m: float
) -> Vector3:
	var x0: int = maxi(0, x - 1)
	var x1: int = mini(resolution, x + 1)
	var y0: int = maxi(0, y - 1)
	var y1: int = mini(resolution, y + 1)
	var z0: int = maxi(0, z - 1)
	var z1: int = mini(resolution, z + 1)
	var dx_denominator: float = maxf(spacing_m, float(x1 - x0) * spacing_m)
	var dy_denominator: float = maxf(spacing_m, float(y1 - y0) * spacing_m)
	var dz_denominator: float = maxf(spacing_m, float(z1 - z0) * spacing_m)
	return Vector3(
		(float(signed_distance[Field.flat_index(resolution, x1, y, z)]) - float(signed_distance[Field.flat_index(resolution, x0, y, z)])) / dx_denominator,
		(float(signed_distance[Field.flat_index(resolution, x, y1, z)]) - float(signed_distance[Field.flat_index(resolution, x, y0, z)])) / dy_denominator,
		(float(signed_distance[Field.flat_index(resolution, x, y, z1)]) - float(signed_distance[Field.flat_index(resolution, x, y, z0)])) / dz_denominator
	)
