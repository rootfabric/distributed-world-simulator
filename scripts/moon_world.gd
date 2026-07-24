extends Node3D

const MOON_RADIUS: float = 1_737_400.0
const MOON_GRAVITY: float = 1.62
const WORLD_SEED: int = 20260724

const GLOBAL_SEGMENTS: int = 128
const GLOBAL_RINGS: int = 64
const GLOBAL_SURFACE_OFFSET: float = -650.0

const LOCAL_CAP_RADIUS: float = 14_000.0
const LOCAL_CAP_RINGS: int = 72
const CAP_SEGMENTS: int = 128
const MEDIUM_CAP_RADIUS: float = 520_000.0
const MEDIUM_CAP_RINGS: int = 56

const LOCAL_LOD_EXIT_ALTITUDE: float = 3_500.0
const LOCAL_LOD_ENTER_ALTITUDE: float = 2_700.0
const MEDIUM_LOD_EXIT_ALTITUDE: float = 620_000.0
const MEDIUM_LOD_ENTER_ALTITUDE: float = 520_000.0

# The playable surface is a single radial mesh. The exact same ArrayMesh is
# used for rendering and ConcavePolygonShape3D collision.
const LOCAL_RADIAL_DISTRIBUTION_POWER: float = 2.0
const PLAYER_RECENTER_DISTANCE: float = 680.0
const SPECTATOR_CAP_RECENTER_DISTANCE: float = 75_000.0

const LARGE_CRATER_COUNT: int = 22
const MEDIUM_CRATER_COUNT: int = 70
const LOCAL_CRATER_COUNT: int = 180
const MOUNTAIN_MASSIF_COUNT: int = 44
const LOCAL_CRATER_CELL_SIZE: float = 6000.0
const LOCAL_CRATER_MAX_RADIUS: float = 5200.0
const ROCK_COUNT: int = 240
const ROCK_RADIUS: float = 6800.0
const SUN_DIRECTION := Vector3(-0.34, 0.58, -0.74)

var macro_noise := FastNoiseLite.new()
var middle_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var region_noise := FastNoiseLite.new()
var rugged_region_noise := FastNoiseLite.new()
var mountain_region_noise := FastNoiseLite.new()
var crater_region_noise := FastNoiseLite.new()
var local_shape_noise := FastNoiseLite.new()

var crater_centers := PackedVector3Array()
var crater_radii := PackedFloat64Array()
var crater_depths := PackedFloat64Array()
var crater_rims := PackedFloat64Array()
var crater_strengths := PackedFloat64Array()

var massif_centers := PackedVector3Array()
var massif_radii := PackedFloat64Array()
var massif_heights := PackedFloat64Array()
var massif_roughness := PackedFloat64Array()

var local_crater_centers := PackedVector3Array()
var local_crater_radii := PackedFloat64Array()
var local_crater_depths := PackedFloat64Array()
var local_crater_rims := PackedFloat64Array()

var global_moon: MeshInstance3D
var local_cap: MeshInstance3D
var medium_full_cap: MeshInstance3D
var medium_annulus_cap: MeshInstance3D
var rocks_instance: MultiMeshInstance3D
var collision_root: Node3D
var surface_root: Node3D

var surface_material: StandardMaterial3D
var rock_material: StandardMaterial3D
var rock_mesh: ArrayMesh

var render_origin_world: Vector3 = Vector3.ZERO
var surface_anchor_world: Vector3 = Vector3.ZERO
var surface_center_direction: Vector3 = Vector3.UP
var surface_east: Vector3 = Vector3.RIGHT
var surface_north: Vector3 = Vector3.FORWARD

var current_lod: int = 0
var initialized: bool = false
var spawn_rng := RandomNumberGenerator.new()
var last_spawn_region_name: String = "Не определён"


func setup() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if initialized:
		return

	initialized = true
	spawn_rng.randomize()
	_configure_noise()
	_generate_craters()
	_generate_mountain_massifs()
	_create_materials()
	_create_environment()

	surface_root = Node3D.new()
	surface_root.name = "SurfaceLOD"
	add_child(surface_root)

	collision_root = Node3D.new()
	collision_root.name = "LocalCollision"
	add_child(collision_root)

	rock_mesh = _create_rock_mesh(WORLD_SEED + 9001)
	_create_global_moon()


func _configure_noise() -> void:
	macro_noise.seed = WORLD_SEED
	macro_noise.frequency = 1.0
	middle_noise.seed = WORLD_SEED + 101
	middle_noise.frequency = 1.0
	detail_noise.seed = WORLD_SEED + 203
	detail_noise.frequency = 1.0
	ridge_noise.seed = WORLD_SEED + 307
	ridge_noise.frequency = 1.0
	region_noise.seed = WORLD_SEED + 409
	region_noise.frequency = 1.0
	rugged_region_noise.seed = WORLD_SEED + 503
	rugged_region_noise.frequency = 1.0
	mountain_region_noise.seed = WORLD_SEED + 601
	mountain_region_noise.frequency = 1.0
	crater_region_noise.seed = WORLD_SEED + 701
	crater_region_noise.frequency = 1.0
	local_shape_noise.seed = WORLD_SEED + 809
	local_shape_noise.frequency = 1.0


func _generate_craters() -> void:
	crater_centers.clear()
	crater_radii.clear()
	crater_depths.clear()
	crater_rims.clear()
	crater_strengths.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 404
	var total_count: int = (
		LARGE_CRATER_COUNT + MEDIUM_CRATER_COUNT + LOCAL_CRATER_COUNT
	)

	for crater_index in range(total_count):
		var category: int = 2
		if crater_index < LARGE_CRATER_COUNT:
			category = 0
		elif crater_index < LARGE_CRATER_COUNT + MEDIUM_CRATER_COUNT:
			category = 1

		var center := _select_crater_center(rng, category)
		var field_strength: float = _get_region_factors(center).w
		var radius_m: float
		var depth_ratio: float
		var rim_ratio: float

		match category:
			0:
				radius_m = rng.randf_range(70_000.0, 285_000.0)
				depth_ratio = rng.randf_range(0.030, 0.070)
				rim_ratio = rng.randf_range(0.10, 0.24)
			1:
				radius_m = rng.randf_range(8_000.0, 72_000.0)
				depth_ratio = rng.randf_range(0.055, 0.125)
				rim_ratio = rng.randf_range(0.14, 0.34)
			_:
				radius_m = rng.randf_range(450.0, 11_500.0)
				depth_ratio = rng.randf_range(0.085, 0.205)
				rim_ratio = rng.randf_range(0.18, 0.46)

		var strength: float = lerpf(0.72, 1.38, field_strength)
		crater_centers.append(center)
		crater_radii.append(radius_m)
		crater_depths.append(radius_m * depth_ratio)
		crater_rims.append(radius_m * depth_ratio * rim_ratio)
		crater_strengths.append(strength)


func _select_crater_center(rng: RandomNumberGenerator, category: int) -> Vector3:
	var best_direction := _random_unit_direction(rng)
	if category == 0:
		return best_direction

	var best_score: float = -INF
	var attempts: int = 5 if category == 1 else 9
	for _attempt in range(attempts):
		var candidate := _random_unit_direction(rng)
		var factors := _get_region_factors(candidate)
		var score: float = factors.w + rng.randf_range(-0.18, 0.18)
		if category == 1:
			score += factors.y * 0.12
		if score > best_score:
			best_score = score
			best_direction = candidate
	return best_direction


func _generate_mountain_massifs() -> void:
	massif_centers.clear()
	massif_radii.clear()
	massif_heights.clear()
	massif_roughness.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 1217
	for massif_index in range(MOUNTAIN_MASSIF_COUNT):
		var best_direction := _random_unit_direction(rng)
		var best_score: float = -INF
		for _attempt in range(10):
			var candidate := _random_unit_direction(rng)
			var factors := _get_region_factors(candidate)
			var score: float = factors.z + factors.y * 0.35 + rng.randf_range(-0.12, 0.12)
			if score > best_score:
				best_score = score
				best_direction = candidate

		var major_massif: bool = massif_index < 12
		var radius_m: float = (
			rng.randf_range(45_000.0, 135_000.0)
			if major_massif
			else rng.randf_range(9_000.0, 52_000.0)
		)
		var height_m: float = (
			rng.randf_range(3000.0, 7600.0)
			if major_massif
			else rng.randf_range(900.0, 4300.0)
		)
		massif_centers.append(best_direction)
		massif_radii.append(radius_m)
		massif_heights.append(height_m)
		massif_roughness.append(rng.randf_range(0.55, 1.0))


func _random_unit_direction(rng: RandomNumberGenerator) -> Vector3:
	var y_value: float = rng.randf_range(-1.0, 1.0)
	var angle: float = rng.randf_range(0.0, TAU)
	var horizontal: float = sqrt(maxf(0.0, 1.0 - y_value * y_value))
	return Vector3(
		horizontal * cos(angle),
		y_value,
		horizontal * sin(angle)
	).normalized()


func _generate_local_craters_for_region(center_direction: Vector3) -> void:
	local_crater_centers.clear()
	local_crater_radii.clear()
	local_crater_depths.clear()
	local_crater_rims.clear()

	var cell_angle: float = LOCAL_CRATER_CELL_SIZE / MOON_RADIUS
	var latitude: float = asin(clampf(center_direction.y, -1.0, 1.0))
	var longitude: float = atan2(center_direction.z, center_direction.x)
	var center_lat_cell: int = floori(latitude / cell_angle)
	var center_lon_cell: int = floori(longitude / cell_angle)
	var search_radius_m: float = LOCAL_CAP_RADIUS + LOCAL_CRATER_MAX_RADIUS * 1.7
	var cell_radius: int = ceili(search_radius_m / LOCAL_CRATER_CELL_SIZE) + 1

	for lat_offset in range(-cell_radius, cell_radius + 1):
		var lat_cell: int = center_lat_cell + lat_offset
		var cell_latitude: float = (float(lat_cell) + 0.5) * cell_angle
		if cell_latitude <= -PI * 0.5 or cell_latitude >= PI * 0.5:
			continue

		for lon_offset in range(-cell_radius, cell_radius + 1):
			var lon_cell: int = center_lon_cell + lon_offset
			var cell_seed: int = (
				WORLD_SEED * 97
				+ lat_cell * 73_856_093
				+ lon_cell * 19_349_663
			)
			if cell_seed < 0:
				cell_seed = -cell_seed
			var rng := RandomNumberGenerator.new()
			rng.seed = cell_seed
			var crater_candidates: int = 1
			if rng.randf() < 0.28:
				crater_candidates = 2

			for _candidate_index in range(crater_candidates):
				var crater_latitude: float = (
					float(lat_cell) + rng.randf_range(0.08, 0.92)
				) * cell_angle
				var crater_longitude: float = (
					float(lon_cell) + rng.randf_range(0.08, 0.92)
				) * cell_angle
				var crater_direction := _direction_from_lat_lon(
					crater_latitude,
					crater_longitude
				)
				var distance_from_region: float = (
					crater_direction - center_direction
				).length() * MOON_RADIUS
				if distance_from_region > search_radius_m:
					continue

				var factors := _get_region_factors(crater_direction)
				var spawn_probability: float = 0.16 + factors.w * 0.67
				spawn_probability += factors.y * 0.08
				if rng.randf() > spawn_probability:
					continue

				var radius_m: float = rng.randf_range(260.0, 2650.0)
				if rng.randf() < 0.12 + factors.w * 0.10:
					radius_m = rng.randf_range(2700.0, LOCAL_CRATER_MAX_RADIUS)
				var depth_ratio: float = rng.randf_range(0.10, 0.22)
				var depth_m: float = radius_m * depth_ratio
				local_crater_centers.append(crater_direction)
				local_crater_radii.append(radius_m)
				local_crater_depths.append(depth_m)
				local_crater_rims.append(depth_m * rng.randf_range(0.20, 0.48))


func _direction_from_lat_lon(latitude: float, longitude: float) -> Vector3:
	var horizontal: float = cos(latitude)
	return Vector3(
		horizontal * cos(longitude),
		sin(latitude),
		horizontal * sin(longitude)
	).normalized()


func _get_local_crater_height(direction: Vector3) -> float:
	if local_crater_centers.is_empty():
		return 0.0
	var region_distance: float = (
		direction - surface_center_direction
	).length() * MOON_RADIUS
	if region_distance > LOCAL_CAP_RADIUS + LOCAL_CRATER_MAX_RADIUS * 1.7:
		return 0.0

	var result: float = 0.0
	for crater_index in range(local_crater_centers.size()):
		var radius_m: float = local_crater_radii[crater_index]
		var distance_m: float = (
			direction - local_crater_centers[crater_index]
		).length() * MOON_RADIUS
		if distance_m > radius_m * 1.48:
			continue
		var normalized_distance: float = distance_m / radius_m
		if normalized_distance < 1.0:
			var bowl: float = 1.0 - normalized_distance * normalized_distance
			result -= local_crater_depths[crater_index] * bowl * bowl
		var rim_distance: float = (normalized_distance - 1.0) / 0.12
		result += local_crater_rims[crater_index] * exp(-rim_distance * rim_distance)
	return result


func _create_materials() -> void:
	surface_material = StandardMaterial3D.new()
	surface_material.vertex_color_use_as_albedo = true
	surface_material.roughness = 1.0
	surface_material.metallic = 0.0
	surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	rock_material = StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.38, 0.39, 0.41)
	rock_material.roughness = 1.0
	rock_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rock_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0004, 0.0005, 0.0012)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.36, 0.41)
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)


func _create_global_moon() -> void:
	global_moon = MeshInstance3D.new()
	global_moon.name = "GlobalMoonLOD"
	global_moon.mesh = _build_global_uv_sphere()
	global_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(global_moon)
	_update_root_positions()


func _build_global_uv_sphere() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for ring_index in range(GLOBAL_RINGS + 1):
		var ring_t: float = float(ring_index) / float(GLOBAL_RINGS)
		var latitude: float = ring_t * PI
		var y_value: float = cos(latitude)
		var horizontal: float = sin(latitude)

		for segment_index in range(GLOBAL_SEGMENTS + 1):
			var segment_t: float = float(segment_index) / float(GLOBAL_SEGMENTS)
			var longitude: float = segment_t * TAU
			var direction := Vector3(
				horizontal * cos(longitude),
				y_value,
				horizontal * sin(longitude)
			).normalized()
			var height: float = get_coarse_surface_height(direction) + GLOBAL_SURFACE_OFFSET
			vertices.append(direction * (MOON_RADIUS + height))
			normals.append(direction)
			colors.append(_lit_surface_color(height, direction, direction))

	for ring_index in range(GLOBAL_RINGS):
		for segment_index in range(GLOBAL_SEGMENTS):
			var row: int = GLOBAL_SEGMENTS + 1
			var i0: int = ring_index * row + segment_index
			var i1: int = i0 + 1
			var i2: int = i0 + row
			var i3: int = i2 + 1
			indices.append_array(PackedInt32Array([i0, i1, i2]))
			indices.append_array(PackedInt32Array([i1, i3, i2]))

	return _make_array_mesh(vertices, normals, colors, indices, surface_material)


func prepare_surface_region(center_direction: Vector3, include_collision: bool = true) -> void:
	surface_center_direction = center_direction.normalized()
	surface_east = _make_east(surface_center_direction)
	surface_north = surface_east.cross(surface_center_direction).normalized()
	_generate_local_craters_for_region(surface_center_direction)
	surface_anchor_world = get_surface_point(surface_center_direction)

	_clear_node(surface_root)
	if include_collision:
		_clear_node(collision_root)

	local_cap = _create_cap_instance(
		"LocalHighDetail",
		0.0,
		LOCAL_CAP_RADIUS,
		LOCAL_CAP_RINGS,
		CAP_SEGMENTS,
		false
	)
	surface_root.add_child(local_cap)

	medium_annulus_cap = _create_cap_instance(
		"MediumAnnulus",
		LOCAL_CAP_RADIUS,
		MEDIUM_CAP_RADIUS,
		MEDIUM_CAP_RINGS,
		CAP_SEGMENTS,
		true
	)
	surface_root.add_child(medium_annulus_cap)

	medium_full_cap = _create_cap_instance(
		"MediumFull",
		0.0,
		MEDIUM_CAP_RADIUS,
		MEDIUM_CAP_RINGS,
		CAP_SEGMENTS,
		true
	)
	surface_root.add_child(medium_full_cap)

	_create_rocks()

	if include_collision:
		_build_collision_from_local_mesh()

	if include_collision:
		current_lod = 0
	_update_root_positions()
	_apply_lod_visibility()


func _create_cap_instance(
	instance_name: String,
	inner_radius: float,
	outer_radius: float,
	ring_count: int,
	segment_count: int,
	blend_to_global: bool
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = _build_radial_cap_mesh(
		inner_radius,
		outer_radius,
		ring_count,
		segment_count,
		blend_to_global
	)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _build_radial_cap_mesh(
	inner_radius: float,
	outer_radius: float,
	ring_count: int,
	segment_count: int,
	blend_to_global: bool
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var directions := PackedVector3Array()
	var heights := PackedFloat64Array()
	var indices := PackedInt32Array()
	var has_center: bool = inner_radius <= 0.001

	if has_center:
		var center_height: float = get_surface_height(surface_center_direction)
		vertices.append(
			surface_center_direction * (MOON_RADIUS + center_height)
			- surface_anchor_world
		)
		directions.append(surface_center_direction)
		heights.append(center_height)

	for ring_index in range(ring_count + 1):
		if has_center and ring_index == 0:
			continue

		var ring_t: float = float(ring_index) / float(ring_count)
		var radial_distance: float = lerpf(inner_radius, outer_radius, ring_t)
		if has_center:
			# Concentrate vertices around the player. The first rings are only a
			# few metres apart, while the outer part becomes progressively coarser.
			var distributed_t: float = pow(
				ring_t,
				LOCAL_RADIAL_DISTRIBUTION_POWER
			)
			radial_distance = outer_radius * distributed_t

		for segment_index in range(segment_count):
			var angle: float = float(segment_index) / float(segment_count) * TAU
			var local_x: float = cos(angle) * radial_distance
			var local_z: float = sin(angle) * radial_distance
			var direction := _direction_from_surface_local(local_x, local_z)
			var detailed_height: float = get_surface_height(direction)
			var final_height: float = detailed_height

			if blend_to_global:
				var edge_blend: float = smoothstep(0.72, 1.0, ring_t)
				var global_height: float = (
					get_coarse_surface_height(direction) + GLOBAL_SURFACE_OFFSET + 120.0
				)
				final_height = lerpf(detailed_height, global_height, edge_blend)

			vertices.append(
				direction * (MOON_RADIUS + final_height) - surface_anchor_world
			)
			directions.append(direction)
			heights.append(final_height)

	if has_center:
		var first_ring_start: int = 1
		for segment_index in range(segment_count):
			var next_segment: int = (segment_index + 1) % segment_count
			indices.append_array(PackedInt32Array([
				0,
				first_ring_start + segment_index,
				first_ring_start + next_segment,
			]))

		for ring_index in range(1, ring_count):
			var current_start: int = 1 + (ring_index - 1) * segment_count
			var next_start: int = current_start + segment_count
			_add_ring_indices(indices, current_start, next_start, segment_count)
	else:
		for ring_index in range(ring_count):
			var current_start: int = ring_index * segment_count
			var next_start: int = current_start + segment_count
			_add_ring_indices(indices, current_start, next_start, segment_count)

	var normals := _calculate_normals(vertices, indices, directions)
	var colors := PackedColorArray()
	for vertex_index in range(vertices.size()):
		colors.append(_lit_surface_color(
			heights[vertex_index],
			directions[vertex_index],
			normals[vertex_index]
		))

	return _make_array_mesh(vertices, normals, colors, indices, surface_material)


func _add_ring_indices(
	indices: PackedInt32Array,
	current_start: int,
	next_start: int,
	segment_count: int
) -> void:
	for segment_index in range(segment_count):
		var next_segment: int = (segment_index + 1) % segment_count
		var i0: int = current_start + segment_index
		var i1: int = current_start + next_segment
		var i2: int = next_start + segment_index
		var i3: int = next_start + next_segment
		indices.append_array(PackedInt32Array([i0, i1, i2]))
		indices.append_array(PackedInt32Array([i1, i3, i2]))


func _calculate_normals(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	fallback_directions: PackedVector3Array
) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(vertices.size())

	for vertex_index in range(result.size()):
		result[vertex_index] = Vector3.ZERO

	for triangle_index in range(0, indices.size(), 3):
		var ia: int = indices[triangle_index]
		var ib: int = indices[triangle_index + 1]
		var ic: int = indices[triangle_index + 2]
		var a: Vector3 = vertices[ia]
		var b: Vector3 = vertices[ib]
		var c: Vector3 = vertices[ic]
		var face_normal := (b - a).cross(c - a)
		var outward := (
			fallback_directions[ia]
			+ fallback_directions[ib]
			+ fallback_directions[ic]
		).normalized()

		if face_normal.dot(outward) < 0.0:
			face_normal = -face_normal

		result[ia] = result[ia] + face_normal
		result[ib] = result[ib] + face_normal
		result[ic] = result[ic] + face_normal

	for vertex_index in range(result.size()):
		if result[vertex_index].length_squared() > 0.000001:
			result[vertex_index] = result[vertex_index].normalized()
		else:
			result[vertex_index] = fallback_directions[vertex_index]

	return result


func _make_array_mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	material: Material
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.surface_set_material(0, material)
	return result


func _build_collision_from_local_mesh() -> void:
	if local_cap == null or local_cap.mesh == null:
		push_error("Local surface mesh is missing; collision was not created.")
		return

	# Critical invariant: the visible playable surface and physics surface use
	# exactly the same triangle mesh. There is no separately sampled lower layer.
	var local_mesh := local_cap.mesh as ArrayMesh
	if local_mesh == null:
		push_error("Local surface is not an ArrayMesh.")
		return

	var terrain_shape := local_mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if terrain_shape == null:
		push_error("Could not create collision from local surface mesh.")
		return

	terrain_shape.backface_collision = true

	var body := StaticBody3D.new()
	body.name = "PlayableSurface"
	body.collision_layer = 1
	body.collision_mask = 1

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "PlayableSurfaceCollision"
	collision_shape.shape = terrain_shape
	body.add_child(collision_shape)
	collision_root.add_child(body)


func _create_rocks() -> void:
	rocks_instance = MultiMeshInstance3D.new()
	rocks_instance.name = "ProceduralRocks"
	rocks_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock_mesh
	multimesh.instance_count = ROCK_COUNT
	multimesh.visible_instance_count = ROCK_COUNT

	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + int(absf(surface_center_direction.x) * 100000.0) + int(absf(surface_center_direction.z) * 170000.0)

	for rock_index in range(ROCK_COUNT):
		var radius_value: float = sqrt(rng.randf()) * ROCK_RADIUS
		var angle: float = rng.randf_range(0.0, TAU)
		var local_x: float = cos(angle) * radius_value
		var local_z: float = sin(angle) * radius_value
		var direction := _direction_from_surface_local(local_x, local_z)
		var point_world := get_surface_point(direction)
		var scale_value: float = (
			rng.randf_range(0.45, 2.4)
			if rock_index > 8
			else rng.randf_range(2.5, 7.5)
		)
		var tangent_x := _make_east(direction)
		var tangent_z := tangent_x.cross(direction).normalized()
		var basis := Basis(tangent_x, direction, tangent_z)
		basis = Basis(direction, rng.randf_range(0.0, TAU)) * basis
		basis = basis.scaled(Vector3.ONE * scale_value)
		multimesh.set_instance_transform(rock_index, Transform3D(
			basis,
			point_world - surface_anchor_world + direction * (0.16 * scale_value)
		))

	rocks_instance.multimesh = multimesh
	surface_root.add_child(rocks_instance)


func _create_rock_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var segments: int = 10
	var rings: int = 5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var ring_offsets: Array[float] = []
	for _ring_index in range(rings + 1):
		ring_offsets.append(rng.randf_range(-0.08, 0.08))

	for ring_index in range(rings + 1):
		var vertical_t: float = float(ring_index) / float(rings)
		var phi: float = vertical_t * PI
		var y_value: float = cos(phi) * 0.55
		var ring_radius: float = sin(phi)

		for segment_index in range(segments):
			var theta: float = float(segment_index) / float(segments) * TAU
			var wobble: float = (
				1.0
				+ 0.17 * sin(theta * 3.0 + 0.7)
				+ 0.11 * cos(theta * 5.0 - 0.4)
				+ ring_offsets[ring_index]
			)
			var vertex := Vector3(
				cos(theta) * ring_radius * wobble,
				y_value * (1.0 + 0.13 * sin(theta * 2.0)),
				sin(theta) * ring_radius * wobble
			)
			vertex.x *= 1.15
			vertex.z *= 0.92
			vertices.append(vertex)
			normals.append(vertex.normalized())

	for ring_index in range(rings):
		for segment_index in range(segments):
			var next_segment: int = (segment_index + 1) % segments
			var i0: int = ring_index * segments + segment_index
			var i1: int = ring_index * segments + next_segment
			var i2: int = (ring_index + 1) * segments + segment_index
			var i3: int = (ring_index + 1) * segments + next_segment
			indices.append_array(PackedInt32Array([i0, i1, i2]))
			indices.append_array(PackedInt32Array([i1, i3, i2]))

	var colors := PackedColorArray()
	for _vertex in vertices:
		colors.append(Color(0.28, 0.285, 0.295))
	return _make_array_mesh(vertices, normals, colors, indices, rock_material)


func update_for_view(
	view_world_position: Vector3,
	new_render_origin_world: Vector3,
	spectator_mode: bool
) -> void:
	set_render_origin(new_render_origin_world)
	var altitude: float = get_altitude(view_world_position)
	_update_lod_state(altitude)

	if spectator_mode and altitude < MEDIUM_LOD_EXIT_ALTITUDE:
		var center_distance: float = (
			get_surface_point(view_world_position.normalized()) - surface_anchor_world
		).length()
		if center_distance > SPECTATOR_CAP_RECENTER_DISTANCE:
			prepare_surface_region(view_world_position.normalized(), false)


func _update_lod_state(altitude: float) -> void:
	if current_lod == 0:
		if altitude > LOCAL_LOD_EXIT_ALTITUDE:
			current_lod = 1
	elif current_lod == 1:
		if altitude < LOCAL_LOD_ENTER_ALTITUDE:
			current_lod = 0
		elif altitude > MEDIUM_LOD_EXIT_ALTITUDE:
			current_lod = 2
	else:
		if altitude < MEDIUM_LOD_ENTER_ALTITUDE:
			current_lod = 1

	_apply_lod_visibility()


func _apply_lod_visibility() -> void:
	if local_cap == null or medium_full_cap == null or medium_annulus_cap == null:
		return

	local_cap.visible = current_lod == 0
	medium_annulus_cap.visible = current_lod == 0
	medium_full_cap.visible = current_lod == 1
	if rocks_instance != null:
		rocks_instance.visible = current_lod == 0


func set_render_origin(new_origin_world: Vector3) -> void:
	render_origin_world = new_origin_world
	_update_root_positions()


func _update_root_positions() -> void:
	if global_moon != null:
		global_moon.position = -render_origin_world
	if surface_root != null:
		surface_root.position = surface_anchor_world - render_origin_world
	if collision_root != null:
		collision_root.position = surface_anchor_world - render_origin_world


func recenter_player(player: CharacterBody3D) -> void:
	if player.global_position.length() < PLAYER_RECENTER_DISTANCE:
		return

	var absolute_position: Vector3 = render_to_world(player.global_position)
	prepare_surface_region(absolute_position.normalized(), true)
	set_render_origin(surface_anchor_world)
	player.global_position = world_to_render(absolute_position)
	player.reset_physics_interpolation()


func world_to_render(world_position: Vector3) -> Vector3:
	return world_position - render_origin_world


func render_to_world(render_position: Vector3) -> Vector3:
	return render_origin_world + render_position


func get_render_origin() -> Vector3:
	return render_origin_world


func get_surface_anchor() -> Vector3:
	return surface_anchor_world


func get_lod_name() -> String:
	match current_lod:
		0:
			return "LOCAL + MEDIUM"
		1:
			return "MEDIUM + GLOBAL"
		_:
			return "GLOBAL"


func get_moon_radius() -> float:
	return MOON_RADIUS


func get_gravity_at_distance(distance_from_center: float) -> float:
	if distance_from_center <= 1.0:
		return MOON_GRAVITY
	var ratio: float = MOON_RADIUS / distance_from_center
	return MOON_GRAVITY * ratio * ratio


func get_surface_height(direction_value: Vector3) -> float:
	var direction := direction_value.normalized()
	var factors := _get_region_factors(direction)
	var result: float = get_coarse_surface_height(direction)

	var detail: float = detail_noise.get_noise_3d(
		direction.x * 260.0,
		direction.y * 260.0,
		direction.z * 260.0
	)
	var small_shape: float = local_shape_noise.get_noise_3d(
		direction.x * 610.0,
		direction.y * 610.0,
		direction.z * 610.0
	)
	var micro_ridge_source: float = ridge_noise.get_noise_3d(
		direction.x * 470.0,
		direction.y * 470.0,
		direction.z * 470.0
	)
	var micro_ridge: float = pow(
		clampf(1.0 - absf(micro_ridge_source), 0.0, 1.0),
		4.0
	)
	var detail_amplitude: float = (
		38.0
		+ factors.y * 125.0
		+ factors.z * 260.0
		+ factors.w * 90.0
	)
	result += detail * detail_amplitude
	result += small_shape * (28.0 + factors.y * 80.0 + factors.z * 135.0)
	result += micro_ridge * (factors.y * 90.0 + factors.z * 330.0)
	result += _get_local_crater_height(direction)
	return clampf(result, -9200.0, 11_200.0)


func get_coarse_surface_height(direction_value: Vector3) -> float:
	var direction := direction_value.normalized()
	var factors := _get_region_factors(direction)
	var plains: float = factors.x
	var highlands: float = factors.y
	var mountains: float = factors.z
	var crater_fields: float = factors.w

	var macro: float = macro_noise.get_noise_3d(
		direction.x * 2.2,
		direction.y * 2.2,
		direction.z * 2.2
	)
	var broad: float = middle_noise.get_noise_3d(
		direction.x * 8.5,
		direction.y * 8.5,
		direction.z * 8.5
	)
	var regional: float = middle_noise.get_noise_3d(
		direction.x * 24.0,
		direction.y * 24.0,
		direction.z * 24.0
	)
	var ridge_source: float = ridge_noise.get_noise_3d(
		direction.x * 33.0,
		direction.y * 33.0,
		direction.z * 33.0
	)
	var fine_ridge_source: float = local_shape_noise.get_noise_3d(
		direction.x * 74.0,
		direction.y * 74.0,
		direction.z * 74.0
	)
	var ridge: float = pow(clampf(1.0 - absf(ridge_source), 0.0, 1.0), 3.2)
	var fine_ridge: float = pow(
		clampf(1.0 - absf(fine_ridge_source), 0.0, 1.0),
		4.0
	)

	var relief_scale: float = lerpf(0.24, 1.0, 1.0 - plains)
	var result: float = macro * 1150.0
	result += broad * (210.0 + highlands * 920.0 + crater_fields * 220.0)
	result += regional * (130.0 + highlands * 620.0 + mountains * 1050.0)
	result *= relief_scale
	result += highlands * 760.0
	result += mountains * (ridge * 3550.0 + fine_ridge * 1450.0)
	result += plains * regional * 75.0
	result += _get_massif_height(direction)

	for crater_index in range(crater_centers.size()):
		var chord_distance: float = (
			direction - crater_centers[crater_index]
		).length() * MOON_RADIUS
		var crater_radius: float = crater_radii[crater_index]
		if chord_distance > crater_radius * 1.58:
			continue

		var normalized_distance: float = chord_distance / crater_radius
		var strength: float = crater_strengths[crater_index]
		if normalized_distance < 1.0:
			var bowl_factor: float = 1.0 - normalized_distance * normalized_distance
			result -= (
				crater_depths[crater_index]
				* bowl_factor
				* bowl_factor
				* strength
			)

			if crater_radius > 32_000.0:
				var peak_width: float = normalized_distance / 0.16
				result += (
					crater_depths[crater_index]
					* 0.16
					* exp(-peak_width * peak_width)
					* strength
				)

		var rim_distance: float = (normalized_distance - 1.0) / 0.115
		result += (
			crater_rims[crater_index]
			* exp(-rim_distance * rim_distance)
			* strength
		)

		if normalized_distance > 1.0 and normalized_distance < 1.58:
			var ejecta_t: float = (normalized_distance - 1.0) / 0.58
			var ejecta_noise: float = local_shape_noise.get_noise_3d(
				direction.x * 185.0 + float(crater_index) * 0.17,
				direction.y * 185.0,
				direction.z * 185.0 - float(crater_index) * 0.11
			)
			result += (
				crater_rims[crater_index]
				* 0.20
				* (1.0 - ejecta_t)
				* maxf(0.0, ejecta_noise)
				* strength
			)

	return clampf(result, -9200.0, 11_200.0)


func _get_massif_height(direction: Vector3) -> float:
	var result: float = 0.0
	for massif_index in range(massif_centers.size()):
		var distance_m: float = (
			direction - massif_centers[massif_index]
		).length() * MOON_RADIUS
		var radius_m: float = massif_radii[massif_index]
		if distance_m >= radius_m:
			continue

		var normalized_distance: float = distance_m / radius_m
		var profile: float = 1.0 - normalized_distance * normalized_distance
		profile = profile * profile
		var broken_peak: float = local_shape_noise.get_noise_3d(
			direction.x * 92.0 + float(massif_index) * 0.31,
			direction.y * 92.0 - float(massif_index) * 0.23,
			direction.z * 92.0
		)
		var rough_factor: float = lerpf(
			0.66,
			1.0,
			clampf((broken_peak + 1.0) * 0.5, 0.0, 1.0)
		)
		result += (
			massif_heights[massif_index]
			* profile
			* lerpf(1.0, rough_factor, massif_roughness[massif_index])
		)
	return result


func _get_region_factors(direction_value: Vector3) -> Vector4:
	var direction := direction_value.normalized()
	var selector: float = region_noise.get_noise_3d(
		direction.x * 7.5,
		direction.y * 7.5,
		direction.z * 7.5
	)
	var rugged_selector: float = rugged_region_noise.get_noise_3d(
		direction.x * 21.0,
		direction.y * 21.0,
		direction.z * 21.0
	)
	var mountain_selector: float = mountain_region_noise.get_noise_3d(
		direction.x * 15.0,
		direction.y * 15.0,
		direction.z * 15.0
	)
	var crater_selector: float = crater_region_noise.get_noise_3d(
		direction.x * 29.0,
		direction.y * 29.0,
		direction.z * 29.0
	)

	var plains: float = _smooth_range(-selector, 0.02, 0.62)
	plains *= 1.0 - _smooth_range(absf(rugged_selector), 0.28, 0.78) * 0.55
	var highlands: float = _smooth_range(
		selector + rugged_selector * 0.36,
		-0.08,
		0.58
	)
	var mountains: float = _smooth_range(
		mountain_selector + selector * 0.46 + rugged_selector * 0.22,
		0.20,
		0.76
	)
	mountains *= 0.32 + highlands * 0.68
	plains *= 1.0 - mountains * 0.86
	var crater_fields: float = _smooth_range(
		crater_selector + rugged_selector * 0.20 - mountains * 0.12,
		-0.02,
		0.58
	)
	return Vector4(
		clampf(plains, 0.0, 1.0),
		clampf(highlands, 0.0, 1.0),
		clampf(mountains, 0.0, 1.0),
		clampf(crater_fields, 0.0, 1.0)
	)


func _smooth_range(value: float, edge_start: float, edge_end: float) -> float:
	if edge_end <= edge_start:
		return 0.0
	var t: float = clampf(
		(value - edge_start) / (edge_end - edge_start),
		0.0,
		1.0
	)
	return t * t * (3.0 - 2.0 * t)


func get_region_name(direction_value: Vector3) -> String:
	var factors := _get_region_factors(direction_value)
	if factors.z > 0.62:
		if factors.w > 0.58:
			return "Кратерное горное нагорье"
		return "Горный массив"
	if factors.w > 0.66:
		return "Кратерное поле"
	if factors.x > 0.66:
		return "Лунная равнина"
	if factors.y > 0.58:
		return "Высокогорье"
	return "Переходная холмистая область"


func get_surface_point(direction_value: Vector3) -> Vector3:
	var direction := direction_value.normalized()
	return direction * (MOON_RADIUS + get_surface_height(direction))


func get_altitude(world_position: Vector3) -> float:
	var distance_from_center: float = world_position.length()
	if distance_from_center <= 0.01:
		return -MOON_RADIUS
	var direction := world_position / distance_from_center
	return distance_from_center - (MOON_RADIUS + get_surface_height(direction))


func get_random_spawn_direction() -> Vector3:
	var target_region: int = spawn_rng.randi_range(0, 3)
	var best_direction := _random_unit_direction(spawn_rng)
	var best_score: float = INF

	for _attempt in range(96):
		var candidate := _random_unit_direction(spawn_rng)
		var factors := _get_region_factors(candidate)
		var region_penalty: float
		match target_region:
			0:
				region_penalty = 1.0 - factors.x
			1:
				region_penalty = 1.0 - factors.w + factors.z * 0.14
			2:
				region_penalty = 1.0 - factors.y + factors.x * 0.20
			_:
				region_penalty = 1.0 - factors.z

		var east := _make_east(candidate)
		var north := east.cross(candidate).normalized()
		var center_height: float = get_surface_height(candidate)
		var sample_distance: float = 28.0
		var east_height: float = get_surface_height(
			(candidate + east * (sample_distance / MOON_RADIUS)).normalized()
		)
		var north_height: float = get_surface_height(
			(candidate + north * (sample_distance / MOON_RADIUS)).normalized()
		)
		var diagonal_height: float = get_surface_height(
			(
				candidate
				+ east * (sample_distance / MOON_RADIUS)
				+ north * (sample_distance / MOON_RADIUS)
			).normalized()
		)
		var local_slope: float = (
			absf(east_height - center_height)
			+ absf(north_height - center_height)
			+ absf(diagonal_height - center_height)
		)
		var slope_penalty: float = local_slope * 0.025
		if target_region == 3:
			slope_penalty *= 0.45
		var score: float = region_penalty * 10.0 + slope_penalty
		if score < best_score:
			best_score = score
			best_direction = candidate

	last_spawn_region_name = get_region_name(best_direction)
	return best_direction


func get_last_spawn_region_name() -> String:
	return last_spawn_region_name


func get_safe_spawn_direction_near(center_direction_value: Vector3) -> Vector3:
	var center_direction := center_direction_value.normalized()
	var east := _make_east(center_direction)
	var north := east.cross(center_direction).normalized()
	var best_direction := center_direction
	var best_score: float = INF
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		WORLD_SEED
		+ int(absf(center_direction.x) * 1_000_000.0) * 31
		+ int(absf(center_direction.y) * 1_000_000.0) * 17
		+ int(absf(center_direction.z) * 1_000_000.0) * 13
	)

	for attempt_index in range(72):
		var radius_m: float = 0.0
		var angle: float = 0.0
		if attempt_index > 0:
			radius_m = sqrt(rng.randf()) * 1550.0
			angle = rng.randf_range(0.0, TAU)
		var candidate := (
			center_direction
			+ east * (cos(angle) * radius_m / MOON_RADIUS)
			+ north * (sin(angle) * radius_m / MOON_RADIUS)
		).normalized()
		var candidate_east := _make_east(candidate)
		var candidate_north := candidate_east.cross(candidate).normalized()
		var center_height: float = get_surface_height(candidate)
		var sample_distance: float = 18.0
		var east_height: float = get_surface_height(
			(candidate + candidate_east * (sample_distance / MOON_RADIUS)).normalized()
		)
		var west_height: float = get_surface_height(
			(candidate - candidate_east * (sample_distance / MOON_RADIUS)).normalized()
		)
		var north_height: float = get_surface_height(
			(candidate + candidate_north * (sample_distance / MOON_RADIUS)).normalized()
		)
		var south_height: float = get_surface_height(
			(candidate - candidate_north * (sample_distance / MOON_RADIUS)).normalized()
		)
		var slope_score: float = (
			absf(east_height - west_height)
			+ absf(north_height - south_height)
			+ absf(center_height - (east_height + west_height + north_height + south_height) * 0.25)
		)
		var distance_penalty: float = radius_m / 1550.0 * 0.6
		var score: float = slope_score + distance_penalty
		if score < best_score:
			best_score = score
			best_direction = candidate
	return best_direction


func _direction_from_surface_local(local_x: float, local_z: float) -> Vector3:
	return (
		surface_center_direction
		+ surface_east * (local_x / MOON_RADIUS)
		+ surface_north * (local_z / MOON_RADIUS)
	).normalized()


func _make_east(direction: Vector3) -> Vector3:
	var reference := Vector3.UP
	if absf(direction.dot(reference)) > 0.94:
		reference = Vector3.RIGHT
	return reference.cross(direction).normalized()


func _surface_base_color(height: float, direction: Vector3) -> Color:
	var factors := _get_region_factors(direction)
	var maria_noise: float = macro_noise.get_noise_3d(
		direction.x * 7.5 + 41.0,
		direction.y * 7.5 - 17.0,
		direction.z * 7.5 + 9.0
	)
	var height_mix: float = clampf((height + 3600.0) / 10_000.0, 0.0, 1.0)
	var maria_mix: float = clampf((-maria_noise - 0.05) * 1.8, 0.0, 1.0)
	var low_color := Color(0.255, 0.26, 0.275)
	var high_color := Color(0.72, 0.70, 0.66)
	var result := low_color.lerp(high_color, height_mix)
	result = result.lerp(Color(0.18, 0.195, 0.225), maria_mix * 0.34)
	result = result.lerp(Color(0.235, 0.245, 0.27), factors.x * 0.22)
	result = result.lerp(Color(0.76, 0.73, 0.68), factors.y * 0.16)
	result = result.lerp(Color(0.80, 0.76, 0.69), factors.z * 0.22)
	result = result.lerp(Color(0.42, 0.41, 0.42), factors.w * 0.10)
	return result


func _lit_surface_color(height: float, direction: Vector3, normal: Vector3) -> Color:
	var base := _surface_base_color(height, direction)
	var sun_amount: float = maxf(normal.normalized().dot(SUN_DIRECTION.normalized()), 0.0)
	var illumination: float = 0.42 + sun_amount * 0.86
	return Color(
		base.r * illumination,
		base.g * illumination,
		base.b * illumination,
		1.0
	)


func _clear_node(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
