extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")

const ISO_EPSILON_M: float = 0.000000001
const NORMAL_EPSILON_SQUARED: float = 0.000000000001
const EDGE_VERTICES: Array = [
	[0, 1], [1, 2], [2, 0], [0, 3], [1, 3], [2, 3],
]
const TETRAHEDRA: Array = [
	[0, 1, 3, 7],
	[0, 1, 5, 7],
	[0, 2, 3, 7],
	[0, 2, 6, 7],
	[0, 4, 5, 7],
	[0, 4, 6, 7],
]
const TETRA_TRIANGLE_EDGES: Array = [
	[],
	[0, 3, 2],
	[0, 1, 4],
	[1, 4, 2, 2, 4, 3],
	[1, 2, 5],
	[0, 3, 5, 0, 5, 1],
	[0, 2, 5, 0, 5, 4],
	[5, 4, 3],
	[3, 4, 5],
	[4, 5, 0, 5, 2, 0],
	[1, 5, 0, 5, 3, 0],
	[5, 2, 1],
	[3, 4, 2, 2, 4, 1],
	[4, 1, 0],
	[2, 3, 0],
	[],
]
const CUBE_CORNERS: Array = [
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(0, 0, 1),
	Vector3i(1, 0, 1),
	Vector3i(0, 1, 1),
	Vector3i(1, 1, 1),
]


static func build_mesh_data(
	snapshot: Dictionary,
	grid_profile: Dictionary,
	iso_level_m: float = 0.0
) -> Dictionary:
	if not bool(SnapshotScript.validate(snapshot).get("success", false)) \
		or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or not bool(BrickLayoutScript.validate_brick_address(
			grid_profile, snapshot["address"]
		).get("success", false)) \
		or int(snapshot["sample_count"]) != BrickLayoutScript.sample_count(grid_profile) \
		or not is_finite(iso_level_m):
		return {}
	var cell_address: Dictionary = snapshot["address"]["cell_address"]
	var cell_bounds: Dictionary = CellGridScript.bounds(grid_profile, cell_address)
	if cell_bounds.is_empty():
		return {}
	var origin_body_local_m := Vector3(
		float(cell_bounds["center_m"][0]),
		float(cell_bounds["center_m"][1]),
		float(cell_bounds["center_m"][2])
	)
	var resolution: int = int(grid_profile["brick_interior_resolution"])
	var ghost: int = int(grid_profile["ghost_border_samples"])
	var spacing_m: float = float(cell_bounds["edge_length_m"]) / float(resolution)
	var signed_distance: Array = snapshot["geometry_channel"]["signed_distance_m"]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var edge_vertex_by_key: Dictionary = {}
	for cube_z in range(resolution):
		for cube_y in range(resolution):
			for cube_x in range(resolution):
				var lattice_x: int = cube_x + ghost
				var lattice_y: int = cube_y + ghost
				var lattice_z: int = cube_z + ghost
				var corner_indices: Array = []
				var corner_positions: Array = []
				var corner_distances: Array = []
				var corner_gradients: Array = []
				var corner_colors: Array = []
				for corner_offset_value in CUBE_CORNERS:
					var corner_offset: Vector3i = corner_offset_value
					var x: int = lattice_x + corner_offset.x
					var y: int = lattice_y + corner_offset.y
					var z: int = lattice_z + corner_offset.z
					var flat_index: int = BrickLayoutScript.flat_index(grid_profile, x, y, z)
					corner_indices.append(flat_index)
					corner_positions.append(
						BrickLayoutScript.sample_position_validated(
							grid_profile, cell_bounds, x, y, z
						) - origin_body_local_m
					)
					corner_distances.append(float(signed_distance[flat_index]))
					corner_gradients.append(_gradient(
						grid_profile, signed_distance, x, y, z, spacing_m
					))
					corner_colors.append(_sample_color(snapshot, flat_index))
				for tetra_value in TETRAHEDRA:
					var tetra: Array = tetra_value
					_polygonize_tetra(
						tetra,
						corner_indices,
						corner_positions,
						corner_distances,
						corner_gradients,
						corner_colors,
						iso_level_m,
						edge_vertex_by_key,
						vertices,
						normals,
						colors,
						indices
					)
	var compacted: Dictionary = _compact_mesh_arrays(vertices, normals, colors, indices)
	vertices = compacted["vertices"]
	normals = compacted["normals"]
	colors = compacted["colors"]
	indices = compacted["indices"]
	return MeshDataScript.create(
		String(snapshot["checksum"]),
		int(snapshot["state_revision"]),
		snapshot["address"],
		origin_body_local_m,
		iso_level_m,
		vertices,
		normals,
		colors,
		indices
	)


static func _compact_mesh_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> Dictionary:
	var compact_vertices := PackedVector3Array()
	var compact_normals := PackedVector3Array()
	var compact_colors := PackedColorArray()
	var compact_indices := PackedInt32Array()
	var remap: Dictionary = {}
	for source_index in indices:
		if not remap.has(source_index):
			var target_index: int = compact_vertices.size()
			remap[source_index] = target_index
			compact_vertices.append(vertices[source_index])
			compact_normals.append(normals[source_index])
			compact_colors.append(colors[source_index])
		compact_indices.append(int(remap[source_index]))
	return {
		"vertices": compact_vertices,
		"normals": compact_normals,
		"colors": compact_colors,
		"indices": compact_indices,
	}


static func _polygonize_tetra(
	tetra: Array,
	cube_sample_indices: Array,
	cube_positions: Array,
	cube_distances: Array,
	cube_gradients: Array,
	cube_colors: Array,
	iso_level_m: float,
	edge_vertex_by_key: Dictionary,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> void:
	var case_index: int = 0
	for tetra_corner in range(4):
		if float(cube_distances[int(tetra[tetra_corner])]) <= iso_level_m:
			case_index |= 1 << tetra_corner
	var triangle_edges: Array = TETRA_TRIANGLE_EDGES[case_index]
	for triangle_offset in range(0, triangle_edges.size(), 3):
		var triangle_indices: Array = []
		for edge_offset in range(3):
			var tetra_edge: Array = EDGE_VERTICES[int(triangle_edges[triangle_offset + edge_offset])]
			var cube_corner_a: int = int(tetra[int(tetra_edge[0])])
			var cube_corner_b: int = int(tetra[int(tetra_edge[1])])
			triangle_indices.append(_edge_vertex(
				cube_corner_a,
				cube_corner_b,
				cube_sample_indices,
				cube_positions,
				cube_distances,
				cube_gradients,
				cube_colors,
				iso_level_m,
				edge_vertex_by_key,
				vertices,
				normals,
				colors
			))
		if triangle_indices.has(-1):
			continue
		var index_a: int = int(triangle_indices[0])
		var index_b: int = int(triangle_indices[1])
		var index_c: int = int(triangle_indices[2])
		if index_a == index_b or index_b == index_c or index_c == index_a:
			continue
		var face_normal: Vector3 = (
			vertices[index_b] - vertices[index_a]
		).cross(vertices[index_c] - vertices[index_a])
		if face_normal.length_squared() <= NORMAL_EPSILON_SQUARED:
			continue
		var expected_normal: Vector3 = (
			normals[index_a] + normals[index_b] + normals[index_c]
		).normalized()
		if face_normal.dot(expected_normal) > 0.0:
			var swap: int = index_b
			index_b = index_c
			index_c = swap
		indices.append(index_a)
		indices.append(index_b)
		indices.append(index_c)


static func _edge_vertex(
	cube_corner_a: int,
	cube_corner_b: int,
	cube_sample_indices: Array,
	cube_positions: Array,
	cube_distances: Array,
	cube_gradients: Array,
	cube_colors: Array,
	iso_level_m: float,
	edge_vertex_by_key: Dictionary,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray
) -> int:
	var sample_index_a: int = int(cube_sample_indices[cube_corner_a])
	var sample_index_b: int = int(cube_sample_indices[cube_corner_b])
	var low: int = mini(sample_index_a, sample_index_b)
	var high: int = maxi(sample_index_a, sample_index_b)
	var edge_key: String = "%d:%d" % [low, high]
	if edge_vertex_by_key.has(edge_key):
		return int(edge_vertex_by_key[edge_key])
	var distance_a: float = float(cube_distances[cube_corner_a])
	var distance_b: float = float(cube_distances[cube_corner_b])
	var denominator: float = distance_b - distance_a
	var interpolation: float = 0.5
	if absf(denominator) > ISO_EPSILON_M:
		interpolation = clampf((iso_level_m - distance_a) / denominator, 0.0, 1.0)
	if absf(distance_a - iso_level_m) <= ISO_EPSILON_M:
		interpolation = 0.0
	elif absf(distance_b - iso_level_m) <= ISO_EPSILON_M:
		interpolation = 1.0
	var position_a: Vector3 = cube_positions[cube_corner_a]
	var position_b: Vector3 = cube_positions[cube_corner_b]
	var position: Vector3 = position_a.lerp(position_b, interpolation)
	var gradient_a: Vector3 = cube_gradients[cube_corner_a]
	var gradient_b: Vector3 = cube_gradients[cube_corner_b]
	var normal: Vector3 = gradient_a.lerp(gradient_b, interpolation)
	if normal.length_squared() <= NORMAL_EPSILON_SQUARED:
		normal = position.normalized()
	if normal.length_squared() <= NORMAL_EPSILON_SQUARED:
		normal = Vector3.UP
	normal = normal.normalized()
	var color_a: Color = cube_colors[cube_corner_a]
	var color_b: Color = cube_colors[cube_corner_b]
	var color: Color = color_a.lerp(color_b, interpolation)
	var vertex_index: int = vertices.size()
	vertices.append(position)
	normals.append(normal)
	colors.append(color)
	edge_vertex_by_key[edge_key] = vertex_index
	return vertex_index


static func _gradient(
	grid_profile: Dictionary,
	signed_distance: Array,
	x: int,
	y: int,
	z: int,
	spacing_m: float
) -> Vector3:
	var dx: float = float(signed_distance[BrickLayoutScript.flat_index(
		grid_profile, x + 1, y, z
	)]) - float(signed_distance[BrickLayoutScript.flat_index(
		grid_profile, x - 1, y, z
	)])
	var dy: float = float(signed_distance[BrickLayoutScript.flat_index(
		grid_profile, x, y + 1, z
	)]) - float(signed_distance[BrickLayoutScript.flat_index(
		grid_profile, x, y - 1, z
	)])
	var dz: float = float(signed_distance[BrickLayoutScript.flat_index(
		grid_profile, x, y, z + 1
	)]) - float(signed_distance[BrickLayoutScript.flat_index(
		grid_profile, x, y, z - 1
	)])
	return Vector3(dx, dy, dz) / (2.0 * spacing_m)


static func _sample_color(snapshot: Dictionary, sample_index: int) -> Color:
	var composition_channel: Dictionary = snapshot["composition_channel"]
	var palette_index: int = int(composition_channel["palette_indices"][sample_index])
	var composition: Dictionary = composition_channel["palette"][palette_index]
	var components: Array = composition["components"]
	if components.is_empty():
		return Color(0.08, 0.09, 0.11, 1.0)
	var dominant_material_id: String = ""
	var dominant_fraction: float = -1.0
	for component in components:
		var fraction: float = float(component["mass_fraction"])
		if fraction > dominant_fraction:
			dominant_fraction = fraction
			dominant_material_id = String(component["material_id"])
	match dominant_material_id:
		"matter/regolith-compacted":
			return Color(0.48, 0.43, 0.38, 1.0)
		"matter/fractured-basalt":
			return Color(0.29, 0.31, 0.34, 1.0)
		"matter/iron-nickel-ore":
			return Color(0.36, 0.24, 0.18, 1.0)
		"matter/water-ice":
			return Color(0.58, 0.76, 0.88, 1.0)
		"matter/basalt":
			return Color(0.19, 0.20, 0.22, 1.0)
		_:
			return Color(0.35, 0.35, 0.36, 1.0)
