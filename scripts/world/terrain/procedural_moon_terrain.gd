extends Node3D

signal terrain_streaming_test_completed(summary: Dictionary)

const LunarLodPolicyScript = preload("res://scripts/world/lod/lunar_lod_policy.gd")
const LunarMaterialLibraryScript = preload("res://scripts/world/materials/lunar_material_library.gd")
const TerrainStreamingManagerScript = preload(
	"res://scripts/world/terrain/streaming/terrain_streaming_manager.gd"
)
const GravityMathScript = preload(
	"res://scripts/simulation/gravity/gravity_math.gd"
)

const MOON_RADIUS: float = 1_737_400.0
const MOON_GRAVITY: float = 1.62
const MOON_GRAVITATIONAL_PARAMETER_M3_S2: float = 4_890_065_191_200.0
const WORLD_SEED: int = 20260724

const GLOBAL_SEGMENTS: int = LunarLodPolicyScript.GLOBAL_SEGMENTS
const GLOBAL_RINGS: int = LunarLodPolicyScript.GLOBAL_RINGS
const GLOBAL_SURFACE_OFFSET: float = -650.0

const LOCAL_CAP_RADIUS: float = LunarLodPolicyScript.LOCAL_RADIUS
# One adaptive playable mesh: ultra-dense around the astronaut, progressively
# coarser toward the 14 km boundary. Rendering and collision share this mesh.
const MICRO_DETAIL_RADIUS: float = LunarLodPolicyScript.ULTRA_RADIUS
const MICRO_DETAIL_RINGS: int = LunarLodPolicyScript.ULTRA_RINGS
const LOCAL_OUTER_RINGS: int = LunarLodPolicyScript.LOCAL_OUTER_RINGS
const LOCAL_CAP_RINGS: int = MICRO_DETAIL_RINGS + LOCAL_OUTER_RINGS
const LOCAL_CAP_SEGMENTS: int = LunarLodPolicyScript.LOCAL_SEGMENTS
const CAP_SEGMENTS: int = LunarLodPolicyScript.REGIONAL_SEGMENTS
const MEDIUM_CAP_RADIUS: float = LunarLodPolicyScript.REGIONAL_RADIUS
const MEDIUM_CAP_RINGS: int = LunarLodPolicyScript.REGIONAL_RINGS

const LOCAL_LOD_EXIT_ALTITUDE: float = LunarLodPolicyScript.LOCAL_EXIT_ALTITUDE
const LOCAL_LOD_ENTER_ALTITUDE: float = LunarLodPolicyScript.LOCAL_ENTER_ALTITUDE
const MEDIUM_LOD_EXIT_ALTITUDE: float = LunarLodPolicyScript.REGIONAL_EXIT_ALTITUDE
const MEDIUM_LOD_ENTER_ALTITUDE: float = LunarLodPolicyScript.REGIONAL_ENTER_ALTITUDE

# The playable surface is a single radial mesh. The exact same ArrayMesh is
# used for rendering and ConcavePolygonShape3D collision.
const LOCAL_RADIAL_DISTRIBUTION_POWER: float = 2.0
const PLAYER_RECENTER_DISTANCE: float = 150.0
const MICRO_DETAIL_FADE_END: float = 720.0
const MESO_DETAIL_FADE_END: float = 3200.0
const MEDIUM_LOCAL_RECENTER_DISTANCE: float = 1200.0
# Spectator streaming thresholds. At low altitude the ultra-detailed centre
# follows the point directly below the camera. Higher up, recentering becomes
# progressively less frequent because only regional/global geometry is useful.
const SPECTATOR_ULTRA_ALTITUDE: float = LunarLodPolicyScript.SPECTATOR_ULTRA_ALTITUDE
const SPECTATOR_LOCAL_ALTITUDE: float = LunarLodPolicyScript.SPECTATOR_LOCAL_ALTITUDE
const LOCAL_CENTER_PATCH_RADIUS: float = 0.78
const SPECTATOR_MEDIUM_ALTITUDE: float = LunarLodPolicyScript.SPECTATOR_MEDIUM_ALTITUDE
const SPECTATOR_ULTRA_RECENTER_DISTANCE: float = LunarLodPolicyScript.SPECTATOR_ULTRA_RECENTER
const SPECTATOR_LOCAL_RECENTER_DISTANCE: float = LunarLodPolicyScript.SPECTATOR_LOCAL_RECENTER
const SPECTATOR_MEDIUM_RECENTER_DISTANCE: float = LunarLodPolicyScript.SPECTATOR_MEDIUM_RECENTER
const SPECTATOR_HIGH_RECENTER_DISTANCE: float = LunarLodPolicyScript.SPECTATOR_HIGH_RECENTER
const SPECTATOR_REBUILD_COOLDOWN: float = 0.40

const LARGE_CRATER_COUNT: int = 30
const MEDIUM_CRATER_COUNT: int = 105
const LOCAL_CRATER_COUNT: int = 250
const MARIA_BASIN_COUNT: int = 9
const MOUNTAIN_MASSIF_COUNT: int = 44
const LOCAL_CRATER_CELL_SIZE: float = 6000.0
const LOCAL_CRATER_MAX_RADIUS: float = 5200.0
const MICRO_CRATER_CELL_SIZE: float = 95.0
const MICRO_CRATER_FIELD_RADIUS: float = 650.0
const MICRO_CRATER_MAX_RADIUS: float = 46.0

const LARGE_ROCK_RADIUS: float = 6800.0
const MEDIUM_ROCK_RADIUS: float = 1900.0
const SMALL_ROCK_RADIUS: float = 540.0
const PEBBLE_RADIUS: float = 190.0
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
var meso_surface_noise := FastNoiseLite.new()
var micro_surface_noise := FastNoiseLite.new()
var fine_surface_noise := FastNoiseLite.new()
var grain_surface_noise := FastNoiseLite.new()

var maria_centers := PackedVector3Array()
var maria_radii := PackedFloat64Array()
var maria_depths := PackedFloat64Array()
var maria_darkness := PackedFloat64Array()

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
var local_crater_degradation := PackedFloat64Array()
var local_crater_ejecta := PackedFloat64Array()

var micro_crater_centers := PackedVector3Array()
var micro_crater_radii := PackedFloat64Array()
var micro_crater_depths := PackedFloat64Array()
var micro_crater_rims := PackedFloat64Array()
var micro_crater_degradation := PackedFloat64Array()
var micro_crater_ejecta := PackedFloat64Array()

var global_moon: MeshInstance3D
var local_cap: MeshInstance3D
var medium_full_cap: MeshInstance3D
var medium_annulus_cap: MeshInstance3D
var rocks_instance: MultiMeshInstance3D
var rock_instances: Array[MultiMeshInstance3D] = []
var collision_root: Node3D
var surface_root: Node3D

var surface_material: StandardMaterial3D
var local_surface_material: StandardMaterial3D
var medium_surface_material: StandardMaterial3D
var global_surface_material: StandardMaterial3D
var rock_material: StandardMaterial3D
var lod_policy
var material_library
var local_debug_material: StandardMaterial3D
var medium_debug_material: StandardMaterial3D
var global_debug_material: StandardMaterial3D
var rock_mesh: ArrayMesh
var rock_meshes: Array[ArrayMesh] = []

var render_origin_world: Vector3 = Vector3.ZERO
var surface_anchor_world: Vector3 = Vector3.ZERO
var medium_anchor_world: Vector3 = Vector3.ZERO
var surface_center_direction: Vector3 = Vector3.UP
var surface_east: Vector3 = Vector3.RIGHT
var surface_north: Vector3 = Vector3.FORWARD

var current_lod: int = 0
var initialized: bool = false
var spawn_rng := RandomNumberGenerator.new()
var last_spawn_region_name: String = "Не определён"
var spectator_tracking_enabled: bool = true
var lod_debug_enabled: bool = false
var spectator_stream_cooldown: float = 0.0
var last_spectator_anchor_distance: float = 0.0
var last_streaming_status: String = "Ожидание"
var logger
var terrain_streamer
var generation_only_initialized: bool = false
var streaming_actors: Array[CharacterBody3D] = []
var recent_surface_cache: Dictionary = {}
var recent_surface_cache_order: Array[String] = []
var recent_surface_cache_capacity: int = 8
var recent_surface_cache_evictions: int = 0
var pinned_surface_cells: Dictionary = {}
var max_pinned_surface_cells: int = 8


func setup(logger_reference = null) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	logger = logger_reference
	if initialized:
		return

	initialized = true
	spawn_rng.randomize()
	setup_generation_only()
	material_library = LunarMaterialLibraryScript.new()
	material_library.setup()
	_create_materials()
	_create_environment()

	surface_root = Node3D.new()
	surface_root.name = "SurfaceLOD"
	add_child(surface_root)

	collision_root = Node3D.new()
	collision_root.name = "LocalCollision"
	add_child(collision_root)

	rock_meshes.clear()
	for variant_index in range(6):
		rock_meshes.append(_create_rock_mesh(
			WORLD_SEED + 9001 + variant_index * 977,
			variant_index
		))
	rock_mesh = rock_meshes[0]
	_create_global_moon()

	var worker_sampler = get_script().new()
	worker_sampler.setup_generation_only()
	terrain_streamer = TerrainStreamingManagerScript.new()
	terrain_streamer.name = "TerrainStreamingManager"
	add_child(terrain_streamer)
	terrain_streamer.setup(self, worker_sampler, logger)
	terrain_streamer.stream_test_completed.connect(_on_stream_test_completed)


func setup_generation_only() -> void:
	if generation_only_initialized:
		return
	generation_only_initialized = true
	lod_policy = LunarLodPolicyScript.new()
	_configure_noise()
	_generate_maria_basins()
	_generate_craters()
	_generate_mountain_massifs()


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
	meso_surface_noise.seed = WORLD_SEED + 907
	meso_surface_noise.frequency = 1.0
	micro_surface_noise.seed = WORLD_SEED + 1009
	micro_surface_noise.frequency = 1.0
	fine_surface_noise.seed = WORLD_SEED + 1103
	fine_surface_noise.frequency = 1.0
	grain_surface_noise.seed = WORLD_SEED + 1201
	grain_surface_noise.frequency = 1.0


func _generate_maria_basins() -> void:
	maria_centers.clear()
	maria_radii.clear()
	maria_depths.clear()
	maria_darkness.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + 353
	for basin_index in range(MARIA_BASIN_COUNT):
		var center := _random_unit_direction(rng)
		# Keep most maria away from the extreme poles to form broad visible seas.
		for _attempt in range(8):
			if absf(center.y) < 0.78:
				break
			center = _random_unit_direction(rng)
		var radius_m: float = rng.randf_range(145_000.0, 430_000.0)
		if basin_index < 3:
			radius_m = rng.randf_range(360_000.0, 610_000.0)
		maria_centers.append(center)
		maria_radii.append(radius_m)
		maria_depths.append(rng.randf_range(520.0, 1450.0))
		maria_darkness.append(rng.randf_range(0.42, 0.78))


func _get_maria_height(direction: Vector3) -> float:
	var result: float = 0.0
	for basin_index in range(maria_centers.size()):
		var distance_m: float = (
			direction - maria_centers[basin_index]
		).length() * MOON_RADIUS
		var radius_m: float = maria_radii[basin_index]
		if distance_m > radius_m * 1.13:
			continue
		var normalized_distance: float = distance_m / radius_m
		if normalized_distance < 1.0:
			var interior: float = 1.0 - normalized_distance * normalized_distance
			result -= maria_depths[basin_index] * interior * interior * interior
		var rim_distance: float = (normalized_distance - 1.0) / 0.075
		result += maria_depths[basin_index] * 0.22 * exp(-rim_distance * rim_distance)
	return result


func _get_maria_factor(direction: Vector3) -> float:
	var factor: float = 0.0
	for basin_index in range(maria_centers.size()):
		var distance_m: float = (
			direction - maria_centers[basin_index]
		).length() * MOON_RADIUS
		var radius_m: float = maria_radii[basin_index]
		if distance_m >= radius_m:
			continue
		var normalized_distance: float = distance_m / radius_m
		var interior: float = 1.0 - smoothstep(0.68, 1.0, normalized_distance)
		factor = maxf(factor, interior * maria_darkness[basin_index])
	return factor


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
	local_crater_degradation.clear()
	local_crater_ejecta.clear()

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
			var density_roll: float = rng.randf()
			if density_roll < 0.18:
				crater_candidates = 3
			elif density_roll < 0.52:
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

				# Power-law-like sampling: many small craters, progressively fewer large ones.
				var size_roll: float = pow(rng.randf(), 3.35)
				var radius_m: float = lerpf(95.0, 2850.0, size_roll)
				if rng.randf() < 0.055 + factors.w * 0.085:
					radius_m = lerpf(2850.0, LOCAL_CRATER_MAX_RADIUS, pow(rng.randf(), 2.1))
				var degradation: float = pow(rng.randf(), 1.35)
				var depth_ratio: float = lerpf(0.205, 0.075, degradation)
				var depth_m: float = radius_m * depth_ratio
				local_crater_centers.append(crater_direction)
				local_crater_radii.append(radius_m)
				local_crater_depths.append(depth_m)
				local_crater_rims.append(depth_m * lerpf(0.48, 0.16, degradation))
				local_crater_degradation.append(degradation)
				local_crater_ejecta.append(rng.randf_range(0.30, 1.0) * (1.0 - degradation * 0.58))


func _generate_micro_craters_for_region(center_direction: Vector3) -> void:
	micro_crater_centers.clear()
	micro_crater_radii.clear()
	micro_crater_depths.clear()
	micro_crater_rims.clear()
	micro_crater_degradation.clear()
	micro_crater_ejecta.clear()

	var cell_angle: float = MICRO_CRATER_CELL_SIZE / MOON_RADIUS
	var latitude: float = asin(clampf(center_direction.y, -1.0, 1.0))
	var longitude: float = atan2(center_direction.z, center_direction.x)
	var center_lat_cell: int = floori(latitude / cell_angle)
	var center_lon_cell: int = floori(longitude / cell_angle)
	var search_radius: float = MICRO_CRATER_FIELD_RADIUS + MICRO_CRATER_MAX_RADIUS * 1.8
	var cell_radius: int = ceili(search_radius / MICRO_CRATER_CELL_SIZE) + 1

	for lat_offset in range(-cell_radius, cell_radius + 1):
		var lat_cell: int = center_lat_cell + lat_offset
		var cell_latitude: float = (float(lat_cell) + 0.5) * cell_angle
		if cell_latitude <= -PI * 0.5 or cell_latitude >= PI * 0.5:
			continue

		for lon_offset in range(-cell_radius, cell_radius + 1):
			var lon_cell: int = center_lon_cell + lon_offset
			var cell_seed: int = (
				WORLD_SEED * 193
				+ lat_cell * 73_856_093
				+ lon_cell * 19_349_663
				+ 1_297_423
			)
			if cell_seed < 0:
				cell_seed = -cell_seed
			var rng := RandomNumberGenerator.new()
			rng.seed = cell_seed

			var candidate_count: int = 1 + int(rng.randf() < 0.32)
			for _candidate_index in range(candidate_count):
				var crater_latitude: float = (
					float(lat_cell) + rng.randf_range(0.06, 0.94)
				) * cell_angle
				var crater_longitude: float = (
					float(lon_cell) + rng.randf_range(0.06, 0.94)
				) * cell_angle
				var crater_direction := _direction_from_lat_lon(
					crater_latitude,
					crater_longitude
				)
				var distance_from_center: float = (
					crater_direction - center_direction
				).length() * MOON_RADIUS
				if distance_from_center > search_radius:
					continue

				var factors := _get_region_factors(crater_direction)
				var probability: float = 0.20 + factors.w * 0.38 + factors.y * 0.08
				if rng.randf() > probability:
					continue

				var radius_m: float = lerpf(0.8, 19.0, pow(rng.randf(), 3.1))
				if rng.randf() < 0.12 + factors.w * 0.14:
					radius_m = lerpf(19.0, MICRO_CRATER_MAX_RADIUS, pow(rng.randf(), 2.0))
				var degradation: float = pow(rng.randf(), 1.45)
				var depth_m: float = radius_m * lerpf(0.19, 0.055, degradation)
				micro_crater_centers.append(crater_direction)
				micro_crater_radii.append(radius_m)
				micro_crater_depths.append(depth_m)
				micro_crater_rims.append(depth_m * lerpf(0.44, 0.12, degradation))
				micro_crater_degradation.append(degradation)
				micro_crater_ejecta.append(rng.randf_range(0.25, 1.0) * (1.0 - degradation * 0.62))


func _get_micro_crater_height(direction: Vector3) -> float:
	if micro_crater_centers.is_empty():
		return 0.0
	var center_distance: float = (
		direction - surface_center_direction
	).length() * MOON_RADIUS
	if center_distance > MICRO_CRATER_FIELD_RADIUS + MICRO_CRATER_MAX_RADIUS * 1.8:
		return 0.0

	var result: float = 0.0
	for crater_index in range(micro_crater_centers.size()):
		var radius_m: float = micro_crater_radii[crater_index]
		var distance_m: float = (
			direction - micro_crater_centers[crater_index]
		).length() * MOON_RADIUS
		if distance_m > radius_m * 2.05:
			continue
		var degradation: float = micro_crater_degradation[crater_index]
		var normalized_distance: float = distance_m / radius_m
		var edge_noise: float = local_shape_noise.get_noise_3d(
			direction.x * 185_000.0 + float(crater_index) * 0.23,
			direction.y * 185_000.0,
			direction.z * 185_000.0 - float(crater_index) * 0.17
		)
		var distorted_distance: float = normalized_distance * (
			1.0 + edge_noise * lerpf(0.025, 0.11, degradation)
		)
		if distorted_distance < 1.0:
			var bowl: float = 1.0 - distorted_distance * distorted_distance
			result -= micro_crater_depths[crater_index] * bowl * bowl
		var rim_width: float = lerpf(0.10, 0.22, degradation)
		var rim_distance: float = (distorted_distance - 1.0) / rim_width
		result += micro_crater_rims[crater_index] * exp(-rim_distance * rim_distance)
		if distorted_distance > 1.0 and distorted_distance < 1.95:
			var ejecta_t: float = (distorted_distance - 1.0) / 0.95
			result += (
				micro_crater_rims[crater_index]
				* micro_crater_ejecta[crater_index]
				* 0.22
				* (1.0 - ejecta_t)
				* maxf(0.0, edge_noise)
			)
	return result


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
		if distance_m > radius_m * 2.15:
			continue
		var degradation: float = local_crater_degradation[crater_index]
		var normalized_distance: float = distance_m / radius_m
		var edge_noise: float = local_shape_noise.get_noise_3d(
			direction.x * 6800.0 + float(crater_index) * 0.31,
			direction.y * 6800.0 - float(crater_index) * 0.19,
			direction.z * 6800.0
		)
		var distorted_distance: float = normalized_distance * (
			1.0 + edge_noise * lerpf(0.018, 0.095, degradation)
		)
		if distorted_distance < 1.0:
			var bowl: float = 1.0 - distorted_distance * distorted_distance
			var floor_shape: float = bowl * bowl
			if radius_m > 1050.0:
				floor_shape = lerpf(floor_shape, bowl * 0.56, smoothstep(0.0, 0.46, distorted_distance))
			result -= local_crater_depths[crater_index] * floor_shape
			if radius_m > 2400.0 and degradation < 0.58:
				var peak_width: float = distorted_distance / 0.13
				result += local_crater_depths[crater_index] * 0.095 * exp(-peak_width * peak_width)
		var rim_width: float = lerpf(0.095, 0.235, degradation)
		var rim_distance: float = (distorted_distance - 1.0) / rim_width
		result += local_crater_rims[crater_index] * exp(-rim_distance * rim_distance)
		if distorted_distance > 1.0 and distorted_distance < 2.05:
			var ejecta_t: float = (distorted_distance - 1.0) / 1.05
			var ray_noise: float = maxf(0.0, local_shape_noise.get_noise_3d(
				direction.x * 18_000.0 + float(crater_index) * 0.43,
				direction.y * 18_000.0,
				direction.z * 18_000.0 - float(crater_index) * 0.29
			))
			result += (
				local_crater_rims[crater_index]
				* local_crater_ejecta[crater_index]
				* 0.31
				* (1.0 - ejecta_t)
				* ray_noise
			)
	return result


func _create_materials() -> void:
	local_surface_material = material_library.get_local_material()
	medium_surface_material = material_library.get_regional_material()
	global_surface_material = material_library.get_global_material()
	rock_material = material_library.get_rock_material()
	surface_material = local_surface_material

	local_debug_material = _create_debug_material(Color(0.95, 0.30, 0.08))
	medium_debug_material = _create_debug_material(Color(0.05, 0.48, 0.92))
	global_debug_material = _create_debug_material(Color(0.44, 0.18, 0.72))


func _create_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.00015, 0.00018, 0.00035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.23, 0.245, 0.285)
	environment.ambient_light_energy = 0.34
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.08
	environment.adjustment_contrast = 1.13
	environment.adjustment_saturation = 0.78
	world_environment.environment = environment
	add_child(world_environment)

	# Stable sunlight without shadow maps. Crater contrast comes from geometry,
	# per-pixel normals and procedural normal maps, avoiding earlier shadow acne.
	var sunlight := DirectionalLight3D.new()
	sunlight.name = "ProceduralSun"
	sunlight.light_color = Color(1.0, 0.975, 0.92)
	sunlight.light_energy = 1.72
	sunlight.shadow_enabled = false
	sunlight.rotation_degrees = Vector3(-34.0, -128.0, 0.0)
	add_child(sunlight)


func _create_global_moon() -> void:
	global_moon = MeshInstance3D.new()
	global_moon.name = "GlobalMoonLOD"
	global_moon.mesh = _build_global_uv_sphere()
	global_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(global_moon)
	_apply_debug_materials()
	_update_root_positions()


func _build_global_uv_sphere() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
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
			colors.append(_surface_base_color(height, direction))
			uvs.append(Vector2(segment_t, ring_t))

	for ring_index in range(GLOBAL_RINGS):
		for segment_index in range(GLOBAL_SEGMENTS):
			var row: int = GLOBAL_SEGMENTS + 1
			var i0: int = ring_index * row + segment_index
			var i1: int = i0 + 1
			var i2: int = i0 + row
			var i3: int = i2 + 1
			indices.append_array(PackedInt32Array([i0, i1, i2]))
			indices.append_array(PackedInt32Array([i1, i3, i2]))

	return _make_array_mesh(
		vertices,
		normals,
		colors,
		indices,
		global_surface_material,
		uvs
	)


func prepare_surface_region(center_direction: Vector3, include_collision: bool = true) -> void:
	var total_started_usec: int = Time.get_ticks_usec()
	var timings: Dictionary = {}
	if terrain_streamer != null:
		terrain_streamer.cancel_all("synchronous_prepare_surface_region")

	var stage_started_usec: int = Time.get_ticks_usec()
	surface_center_direction = center_direction.normalized()
	surface_east = _make_east(surface_center_direction)
	surface_north = surface_east.cross(surface_center_direction).normalized()
	_generate_local_craters_for_region(surface_center_direction)
	_generate_micro_craters_for_region(surface_center_direction)
	surface_anchor_world = get_surface_point(surface_center_direction)
	timings["craters_and_anchor_ms"] = _elapsed_ms(stage_started_usec)

	stage_started_usec = Time.get_ticks_usec()
	_clear_node(surface_root)
	if include_collision:
		_clear_node(collision_root)
	timings["clear_old_nodes_ms"] = _elapsed_ms(stage_started_usec)

	stage_started_usec = Time.get_ticks_usec()
	local_cap = _create_cap_instance(
		"LocalHighDetail",
		0.0,
		LOCAL_CAP_RADIUS,
		LOCAL_CAP_RINGS,
		LOCAL_CAP_SEGMENTS,
		false
	)
	surface_root.add_child(local_cap)
	timings["local_mesh_total_ms"] = _elapsed_ms(stage_started_usec)

	stage_started_usec = Time.get_ticks_usec()
	medium_annulus_cap = _create_cap_instance(
		"MediumAnnulus",
		LOCAL_CAP_RADIUS,
		MEDIUM_CAP_RADIUS,
		MEDIUM_CAP_RINGS,
		CAP_SEGMENTS,
		true
	)
	surface_root.add_child(medium_annulus_cap)
	timings["medium_annulus_total_ms"] = _elapsed_ms(stage_started_usec)

	stage_started_usec = Time.get_ticks_usec()
	medium_full_cap = _create_cap_instance(
		"MediumFull",
		0.0,
		MEDIUM_CAP_RADIUS,
		MEDIUM_CAP_RINGS,
		CAP_SEGMENTS,
		true
	)
	surface_root.add_child(medium_full_cap)
	timings["medium_full_total_ms"] = _elapsed_ms(stage_started_usec)
	medium_anchor_world = surface_anchor_world
	medium_annulus_cap.position = Vector3.ZERO
	medium_full_cap.position = Vector3.ZERO

	stage_started_usec = Time.get_ticks_usec()
	_create_rocks()
	timings["rocks_total_ms"] = _elapsed_ms(stage_started_usec)
	_apply_debug_materials()

	if include_collision:
		stage_started_usec = Time.get_ticks_usec()
		_build_collision_from_local_mesh()
		timings["collision_total_ms"] = _elapsed_ms(stage_started_usec)
		current_lod = 0
	_update_root_positions()
	_apply_lod_visibility()
	if terrain_streamer != null:
		terrain_streamer.mark_active_surface(surface_center_direction)
	timings["total_sync_rebuild_ms"] = _elapsed_ms(total_started_usec)
	_log_terrain_performance("synchronous_surface_rebuild", {
		"include_collision": include_collision,
		"center_direction": [
			surface_center_direction.x,
			surface_center_direction.y,
			surface_center_direction.z,
		],
		"local_vertex_target": LOCAL_CAP_SEGMENTS * (LOCAL_CAP_RINGS + 1),
		"timings_ms": timings,
	})


func _rebuild_local_playable_surface(center_direction: Vector3) -> void:
	# Frequent recentering only rebuilds the single playable mesh, its collision
	# and nearby rocks. The expensive 520 km medium cap stays in place until the
	# player has moved far enough to justify rebuilding it.
	if local_cap != null and is_instance_valid(local_cap):
		if local_cap.get_parent() != null:
			local_cap.get_parent().remove_child(local_cap)
		local_cap.free()
	local_cap = null

	for rock_instance in rock_instances:
		if rock_instance != null and is_instance_valid(rock_instance):
			if rock_instance.get_parent() != null:
				rock_instance.get_parent().remove_child(rock_instance)
			rock_instance.free()
	rock_instances.clear()
	rocks_instance = null
	_clear_node(collision_root)

	surface_center_direction = center_direction.normalized()
	surface_east = _make_east(surface_center_direction)
	surface_north = surface_east.cross(surface_center_direction).normalized()
	_generate_local_craters_for_region(surface_center_direction)
	_generate_micro_craters_for_region(surface_center_direction)
	surface_anchor_world = get_surface_point(surface_center_direction)

	local_cap = _create_cap_instance(
		"LocalHighDetail",
		0.0,
		LOCAL_CAP_RADIUS,
		LOCAL_CAP_RINGS,
		LOCAL_CAP_SEGMENTS,
		false
	)
	surface_root.add_child(local_cap)
	_create_rocks()
	_apply_debug_materials()
	_build_collision_from_local_mesh()

	if medium_annulus_cap != null and is_instance_valid(medium_annulus_cap):
		medium_annulus_cap.position = medium_anchor_world - surface_anchor_world
	if medium_full_cap != null and is_instance_valid(medium_full_cap):
		medium_full_cap.position = medium_anchor_world - surface_anchor_world

	current_lod = 0
	_update_root_positions()
	_apply_lod_visibility()


func _rebuild_spectator_local_surface(center_direction: Vector3) -> void:
	# Spectator version of the local rebuild. It deliberately does not create a
	# physics shape: the frozen astronaut keeps its old collision region until
	# the user returns or teleports. The visible ultra mesh and rocks follow the
	# surface point under the spectator camera.
	if local_cap != null and is_instance_valid(local_cap):
		if local_cap.get_parent() != null:
			local_cap.get_parent().remove_child(local_cap)
		local_cap.free()
	local_cap = null

	for rock_instance in rock_instances:
		if rock_instance != null and is_instance_valid(rock_instance):
			if rock_instance.get_parent() != null:
				rock_instance.get_parent().remove_child(rock_instance)
			rock_instance.free()
	rock_instances.clear()
	rocks_instance = null

	surface_center_direction = center_direction.normalized()
	surface_east = _make_east(surface_center_direction)
	surface_north = surface_east.cross(surface_center_direction).normalized()
	_generate_local_craters_for_region(surface_center_direction)
	_generate_micro_craters_for_region(surface_center_direction)
	surface_anchor_world = get_surface_point(surface_center_direction)

	local_cap = _create_cap_instance(
		"LocalHighDetail",
		0.0,
		LOCAL_CAP_RADIUS,
		LOCAL_CAP_RINGS,
		LOCAL_CAP_SEGMENTS,
		false
	)
	surface_root.add_child(local_cap)
	_create_rocks()

	if medium_annulus_cap != null and is_instance_valid(medium_annulus_cap):
		medium_annulus_cap.position = medium_anchor_world - surface_anchor_world
	if medium_full_cap != null and is_instance_valid(medium_full_cap):
		medium_full_cap.position = medium_anchor_world - surface_anchor_world

	_apply_debug_materials()
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
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var has_center: bool = inner_radius <= 0.001
	var local_surface_cap: bool = has_center and absf(outer_radius - LOCAL_CAP_RADIUS) < 0.01
	var use_center_vertex: bool = has_center and not local_surface_cap
	var fill_innermost_ring: bool = local_surface_cap
	var ring_radii := PackedFloat64Array()

	if local_surface_cap:
		ring_radii.append(LOCAL_CENTER_PATCH_RADIUS)
		ring_radii.append_array(_build_local_ring_radii())
	else:
		for ring_index in range(ring_count + 1):
			if has_center and ring_index == 0:
				continue
			var ring_t: float = float(ring_index) / float(ring_count)
			var radial_distance: float = lerpf(inner_radius, outer_radius, ring_t)
			if has_center:
				var distributed_t: float = pow(
					ring_t,
					LOCAL_RADIAL_DISTRIBUTION_POWER
				)
				radial_distance = outer_radius * distributed_t
			ring_radii.append(radial_distance)

	if use_center_vertex:
		var center_height: float = get_surface_height(surface_center_direction)
		vertices.append(
			surface_center_direction * (MOON_RADIUS + center_height)
			- surface_anchor_world
		)
		directions.append(surface_center_direction)
		heights.append(center_height)
		uvs.append(_stable_lunar_uv(surface_center_direction, outer_radius))

	for ring_array_index in range(ring_radii.size()):
		var radial_distance: float = ring_radii[ring_array_index]
		var ring_t: float = (
			float(ring_array_index) / float(maxi(ring_radii.size() - 1, 1))
		)

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
					get_coarse_surface_height(direction)
					+ GLOBAL_SURFACE_OFFSET
					+ 120.0
				)
				final_height = lerpf(detailed_height, global_height, edge_blend)

			vertices.append(
				direction * (MOON_RADIUS + final_height) - surface_anchor_world
			)
			directions.append(direction)
			heights.append(final_height)
			uvs.append(_stable_lunar_uv(direction, outer_radius))

	if use_center_vertex:
		var first_ring_start: int = 1
		for segment_index in range(segment_count):
			var next_segment: int = (segment_index + 1) % segment_count
			indices.append_array(PackedInt32Array([
				0,
				first_ring_start + segment_index,
				first_ring_start + next_segment,
			]))

		for ring_index in range(1, ring_radii.size()):
			var current_start: int = 1 + (ring_index - 1) * segment_count
			var next_start: int = current_start + segment_count
			_add_ring_indices(indices, current_start, next_start, segment_count)
	else:
		if fill_innermost_ring:
			_add_central_disc_indices(indices, segment_count)
		for ring_index in range(ring_radii.size() - 1):
			var current_start: int = ring_index * segment_count
			var next_start: int = current_start + segment_count
			_add_ring_indices(indices, current_start, next_start, segment_count)

	var normals := _calculate_normals(vertices, indices, directions)
	var colors := PackedColorArray()
	for vertex_index in range(vertices.size()):
		colors.append(_surface_base_color(
			heights[vertex_index],
			directions[vertex_index]
		))

	var target_material: Material = (
		medium_surface_material if blend_to_global else local_surface_material
	)
	return _make_array_mesh(
		vertices,
		normals,
		colors,
		indices,
		target_material,
		uvs
	)


func _build_local_ring_radii() -> PackedFloat64Array:
	return lod_policy.build_local_ring_radii()


func _add_central_disc_indices(
	indices: PackedInt32Array,
	segment_count: int
) -> void:
	for segment_index in range(1, segment_count - 1):
		indices.append_array(PackedInt32Array([
			0,
			segment_index,
			segment_index + 1,
		]))


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


func _calculate_tangents(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> PackedFloat32Array:
	var tangent_accum: Array[Vector3] = []
	var bitangent_accum: Array[Vector3] = []
	tangent_accum.resize(vertices.size())
	bitangent_accum.resize(vertices.size())
	for vertex_index in range(vertices.size()):
		tangent_accum[vertex_index] = Vector3.ZERO
		bitangent_accum[vertex_index] = Vector3.ZERO

	for triangle_index in range(0, indices.size(), 3):
		var ia: int = indices[triangle_index]
		var ib: int = indices[triangle_index + 1]
		var ic: int = indices[triangle_index + 2]
		var edge_1: Vector3 = vertices[ib] - vertices[ia]
		var edge_2: Vector3 = vertices[ic] - vertices[ia]
		var uv_1: Vector2 = uvs[ib] - uvs[ia]
		var uv_2: Vector2 = uvs[ic] - uvs[ia]
		var determinant: float = uv_1.x * uv_2.y - uv_2.x * uv_1.y
		if absf(determinant) < 0.0000001:
			continue
		var reciprocal: float = 1.0 / determinant
		var tangent: Vector3 = (
			edge_1 * uv_2.y - edge_2 * uv_1.y
		) * reciprocal
		var bitangent: Vector3 = (
			edge_2 * uv_1.x - edge_1 * uv_2.x
		) * reciprocal
		for vertex_index in [ia, ib, ic]:
			tangent_accum[vertex_index] += tangent
			bitangent_accum[vertex_index] += bitangent

	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	for vertex_index in range(vertices.size()):
		var normal: Vector3 = normals[vertex_index]
		var tangent: Vector3 = tangent_accum[vertex_index]
		tangent = tangent - normal * normal.dot(tangent)
		if tangent.length_squared() < 0.000001:
			tangent = _make_east(normal)
		else:
			tangent = tangent.normalized()
		var handedness: float = (
			-1.0
			if normal.cross(tangent).dot(bitangent_accum[vertex_index]) < 0.0
			else 1.0
		)
		var offset: int = vertex_index * 4
		tangents[offset] = tangent.x
		tangents[offset + 1] = tangent.y
		tangents[offset + 2] = tangent.z
		tangents[offset + 3] = handedness
	return tangents


func _make_array_mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	material: Material,
	uvs: PackedVector2Array = PackedVector2Array()
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TANGENT] = _calculate_tangents(
			vertices,
			normals,
			uvs,
			indices
		)
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
	rock_instances.clear()
	if rock_meshes.size() < 6:
		return

	_create_rock_layer(
		"AngularBoulders", 0, LARGE_ROCK_RADIUS, 245.0, 0.16,
		0.65, 6.8, 470, 301, true, 0.23, 0.25
	)
	_create_rock_layer(
		"FlatSlabs", 1, MEDIUM_ROCK_RADIUS, 58.0, 0.31,
		0.24, 2.8, 900, 503, true, 0.08, 0.35
	)
	_create_rock_layer(
		"SharpFragments", 2, SMALL_ROCK_RADIUS, 13.0, 0.42,
		0.08, 0.82, 2300, 709, false, 0.11, 0.65
	)
	_create_rock_layer(
		"PebbleScatter", 3, 240.0, 4.6, 0.62,
		0.018, 0.18, 5200, 907, false, 0.025, 0.20
	)
	_create_rock_layer(
		"CraterRimBlocks", 4, 2600.0, 34.0, 0.14,
		0.32, 3.4, 1300, 1103, true, 0.13, 2.8
	)
	_create_rock_layer(
		"BrecciaClusters", 5, 780.0, 8.5, 0.24,
		0.055, 0.48, 2900, 1301, false, 0.045, 1.65
	)

	rocks_instance = rock_instances[0] if not rock_instances.is_empty() else null


func _create_rock_layer(
	layer_name: String,
	variant_index: int,
	layer_radius: float,
	cell_size: float,
	spawn_probability: float,
	min_scale: float,
	max_scale: float,
	max_instances: int,
	seed_offset: int,
	align_to_surface: bool,
	bury_factor: float,
	ejecta_bias: float = 0.0
) -> void:
	var transforms: Array[Transform3D] = []
	var cell_angle: float = cell_size / MOON_RADIUS
	var latitude: float = asin(clampf(surface_center_direction.y, -1.0, 1.0))
	var longitude: float = atan2(surface_center_direction.z, surface_center_direction.x)
	var center_lat_cell: int = floori(latitude / cell_angle)
	var center_lon_cell: int = floori(longitude / cell_angle)
	var cell_radius: int = ceili(layer_radius / cell_size) + 2

	for lat_offset in range(-cell_radius, cell_radius + 1):
		if transforms.size() >= max_instances:
			break
		var lat_cell: int = center_lat_cell + lat_offset
		var cell_latitude: float = (float(lat_cell) + 0.5) * cell_angle
		if cell_latitude <= -PI * 0.5 or cell_latitude >= PI * 0.5:
			continue

		for lon_offset in range(-cell_radius, cell_radius + 1):
			if transforms.size() >= max_instances:
				break
			var lon_cell: int = center_lon_cell + lon_offset
			var cell_seed: int = (
				WORLD_SEED * 211
				+ lat_cell * 73_856_093
				+ lon_cell * 19_349_663
				+ seed_offset * 83_492_791
			)
			if cell_seed < 0:
				cell_seed = -cell_seed
			var rng := RandomNumberGenerator.new()
			rng.seed = cell_seed

			var candidate_latitude: float = (
				float(lat_cell) + rng.randf_range(0.06, 0.94)
			) * cell_angle
			var candidate_longitude: float = (
				float(lon_cell) + rng.randf_range(0.06, 0.94)
			) * cell_angle
			var direction := _direction_from_lat_lon(
				candidate_latitude,
				candidate_longitude
			)
			var distance_m: float = (
				direction - surface_center_direction
			).length() * MOON_RADIUS
			if distance_m > layer_radius:
				continue

			var ejecta_factor: float = _get_local_ejecta_factor(direction)
			var factors := _get_region_factors(direction)
			var local_probability: float = spawn_probability * (
				0.78
				+ factors.w * 0.34
				+ factors.y * 0.12
				+ ejecta_factor * ejecta_bias
			)
			if rng.randf() > clampf(local_probability, 0.0, 0.96):
				continue

			var normal: Vector3 = direction
			if align_to_surface:
				normal = _estimate_surface_normal(
					direction,
					clampf(cell_size * 0.12, 1.0, 28.0)
				)
				if normal.dot(direction) < 0.58:
					continue

			var point_world := get_surface_point(direction)
			var scale_value: float = rng.randf_range(min_scale, max_scale)
			var tangent_x := _make_east(normal)
			var tangent_z := tangent_x.cross(normal).normalized()
			var basis := Basis(tangent_x, normal, tangent_z)
			basis = Basis(normal, rng.randf_range(0.0, TAU)) * basis
			var anisotropy := Vector3(
				rng.randf_range(0.82, 1.22),
				rng.randf_range(0.82, 1.16),
				rng.randf_range(0.82, 1.22)
			)
			basis = basis.scaled(anisotropy * scale_value)
			transforms.append(Transform3D(
				basis,
				point_world - surface_anchor_world + normal * (bury_factor * scale_value)
			))

	if transforms.is_empty():
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock_meshes[variant_index]
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for instance_index in range(transforms.size()):
		multimesh.set_instance_transform(instance_index, transforms[instance_index])

	var instance := MultiMeshInstance3D.new()
	instance.name = layer_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface_root.add_child(instance)
	rock_instances.append(instance)


func _estimate_surface_normal(direction: Vector3, sample_distance: float) -> Vector3:
	var east := _make_east(direction)
	var north := east.cross(direction).normalized()
	var angular_step: float = sample_distance / MOON_RADIUS
	var east_direction := (direction + east * angular_step).normalized()
	var west_direction := (direction - east * angular_step).normalized()
	var north_direction := (direction + north * angular_step).normalized()
	var south_direction := (direction - north * angular_step).normalized()
	var east_point := get_surface_point(east_direction)
	var west_point := get_surface_point(west_direction)
	var north_point := get_surface_point(north_direction)
	var south_point := get_surface_point(south_direction)
	var tangent_east := east_point - west_point
	var tangent_north := north_point - south_point
	var normal := tangent_north.cross(tangent_east).normalized()
	if normal.dot(direction) < 0.0:
		normal = -normal
	return normal


func _create_rock_mesh(seed_value: int, variant_index: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var segments: int = 11
	var rings: int = 6
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var ring_offsets: Array[float] = []
	for _ring_index in range(rings + 1):
		ring_offsets.append(rng.randf_range(-0.11, 0.11))

	for ring_index in range(rings + 1):
		var vertical_t: float = float(ring_index) / float(rings)
		var phi: float = vertical_t * PI
		var y_value: float = cos(phi) * 0.55
		var ring_radius: float = sin(phi)

		for segment_index in range(segments):
			var theta: float = float(segment_index) / float(segments) * TAU
			var wobble: float = (
				1.0
				+ 0.20 * sin(theta * 3.0 + 0.7)
				+ 0.10 * cos(theta * 5.0 - 0.4)
				+ ring_offsets[ring_index]
			)
			var vertex := Vector3(
				cos(theta) * ring_radius * wobble,
				y_value * (1.0 + 0.15 * sin(theta * 2.0)),
				sin(theta) * ring_radius * wobble
			)

			match variant_index:
				0: # angular boulder
					vertex *= Vector3(1.18, 0.95, 0.94)
				1: # flat fractured slab
					vertex *= Vector3(1.55, 0.34, 1.12)
					vertex.x += vertex.y * 0.18
				2: # sharp ejecta fragment
					vertex *= Vector3(0.62, 1.55, 0.54)
					vertex.x += (vertical_t - 0.5) * 0.22
					vertex.z -= (vertical_t - 0.5) * 0.13
				3: # rounded pebble
					vertex *= Vector3(1.18, 0.54, 0.92)
				4: # fractured rim block
					vertex *= Vector3(1.42, 0.72, 0.68)
					vertex.y += absf(vertex.x) * 0.10
				_: # compact breccia cluster
					vertex *= Vector3(0.88, 0.62, 1.30)
					vertex.x += sin(theta * 4.0) * 0.12

			vertices.append(vertex)
			normals.append(vertex.normalized())
			uvs.append(Vector2(
				float(segment_index) / float(segments),
				vertical_t
			))

	for ring_index in range(rings):
		for segment_index in range(segments):
			var next_segment: int = (segment_index + 1) % segments
			var i0: int = ring_index * segments + segment_index
			var i1: int = ring_index * segments + next_segment
			var i2: int = (ring_index + 1) * segments + segment_index
			var i3: int = (ring_index + 1) * segments + next_segment
			indices.append_array(PackedInt32Array([i0, i1, i2]))
			indices.append_array(PackedInt32Array([i1, i3, i2]))

	var variant_colors: Array[Color] = [
		Color(0.31, 0.315, 0.33),
		Color(0.38, 0.37, 0.36),
		Color(0.27, 0.28, 0.30),
		Color(0.46, 0.45, 0.43),
		Color(0.33, 0.325, 0.32),
		Color(0.40, 0.39, 0.375),
	]
	var colors := PackedColorArray()
	for vertex_index in range(vertices.size()):
		var height_mix: float = clampf(vertices[vertex_index].y + 0.5, 0.0, 1.0)
		colors.append(variant_colors[variant_index].lightened(height_mix * 0.10))
	return _make_array_mesh(
		vertices,
		normals,
		colors,
		indices,
		rock_material,
		uvs
	)


func update_for_view(
	view_world_position: Vector3,
	new_render_origin_world: Vector3,
	spectator_mode: bool,
	delta: float = 0.0
) -> void:
	set_render_origin(new_render_origin_world)
	spectator_stream_cooldown = maxf(0.0, spectator_stream_cooldown - delta)

	var altitude: float = get_altitude(view_world_position)
	_update_lod_state(altitude)

	if spectator_mode and spectator_tracking_enabled:
		_update_spectator_streaming(view_world_position, altitude)
	elif spectator_mode:
		last_streaming_status = "Автоподгрузка спектатора выключена"
	else:
		last_spectator_anchor_distance = 0.0
		last_streaming_status = (
			terrain_streamer.get_runtime_summary()
			if terrain_streamer != null
			else "Детальная поверхность следует за персонажем"
		)


func _update_spectator_streaming(
	view_world_position: Vector3,
	altitude: float
) -> void:
	if view_world_position.length_squared() < 1.0:
		return
	if altitude >= MEDIUM_LOD_EXIT_ALTITUDE:
		last_spectator_anchor_distance = 0.0
		last_streaming_status = "Только глобальная Луна: локальные слои не нужны"
		return

	var view_direction: Vector3 = view_world_position.normalized()
	var target_surface_point: Vector3 = get_surface_point(view_direction)
	var anchor_distance: float = (target_surface_point - surface_anchor_world).length()
	last_spectator_anchor_distance = anchor_distance
	var recenter_distance: float = _get_spectator_recenter_distance(altitude)
	if anchor_distance <= recenter_distance:
		last_streaming_status = _spectator_streaming_status_for_altitude(altitude)
		return
	if spectator_stream_cooldown > 0.0:
		last_streaming_status = "Фоновая подготовка LOD уже запрошена"
		return

	var medium_distance: float = (target_surface_point - medium_anchor_world).length()
	var include_medium: bool = (
		altitude > SPECTATOR_LOCAL_ALTITUDE
		or medium_distance > SPECTATOR_MEDIUM_RECENTER_DISTANCE
	)
	if terrain_streamer != null and terrain_streamer.is_enabled():
		terrain_streamer.request_surface(
			view_direction,
			false,
			include_medium,
			"spectator_predictive_stream",
			1,
			false,
			{"altitude_m": altitude, "anchor_distance_m": anchor_distance}
		)
		last_streaming_status = "GENERATING: новый LOD готовится в фоне"
	else:
		if include_medium:
			prepare_surface_region(view_direction, false)
		else:
			_rebuild_spectator_local_surface(view_direction)
		last_streaming_status = "Fallback: синхронная перестройка"
	spectator_stream_cooldown = SPECTATOR_REBUILD_COOLDOWN


func _get_spectator_recenter_distance(altitude: float) -> float:
	return lod_policy.spectator_recenter_distance(altitude)


func _spectator_streaming_status_for_altitude(altitude: float) -> String:
	if altitude <= SPECTATOR_ULTRA_ALTITUDE:
		return "ULTRA следует под спектатором: микрорельеф + 4 слоя камней"
	if altitude <= SPECTATOR_LOCAL_ALTITUDE:
		return "LOCAL следует под спектатором: поверхность радиусом 14 км"
	if altitude <= SPECTATOR_MEDIUM_ALTITUDE:
		return "REGIONAL следует под спектатором: cap радиусом 520 км"
	return "REGIONAL редкой частоты + глобальная сфера"


func _update_lod_state(altitude: float) -> void:
	current_lod = lod_policy.update_state(current_lod, altitude)
	_apply_lod_visibility()


func _apply_lod_visibility() -> void:
	if local_cap == null or medium_full_cap == null or medium_annulus_cap == null:
		return

	local_cap.visible = current_lod == 0
	medium_annulus_cap.visible = current_lod == 0
	medium_full_cap.visible = current_lod == 1
	for rock_instance in rock_instances:
		if rock_instance != null:
			rock_instance.visible = current_lod == 0


func set_spectator_tracking_enabled(enabled: bool) -> void:
	spectator_tracking_enabled = enabled
	spectator_stream_cooldown = 0.0
	last_streaming_status = (
		"Автоподгрузка спектатора включена"
		if enabled
		else "Автоподгрузка спектатора выключена"
	)


func is_spectator_tracking_enabled() -> bool:
	return spectator_tracking_enabled


func set_lod_debug_enabled(enabled: bool) -> void:
	lod_debug_enabled = enabled
	_apply_debug_materials()


func is_lod_debug_enabled() -> bool:
	return lod_debug_enabled


func _apply_debug_materials() -> void:
	if material_library != null:
		local_surface_material = material_library.get_local_material()
		medium_surface_material = material_library.get_regional_material()
		global_surface_material = material_library.get_global_material()
		rock_material = material_library.get_rock_material()
	if global_moon != null:
		global_moon.material_override = (
			global_debug_material if lod_debug_enabled else global_surface_material
		)
	if local_cap != null:
		local_cap.material_override = (
			local_debug_material if lod_debug_enabled else local_surface_material
		)
	if medium_full_cap != null:
		medium_full_cap.material_override = (
			medium_debug_material if lod_debug_enabled else medium_surface_material
		)
	if medium_annulus_cap != null:
		medium_annulus_cap.material_override = (
			medium_debug_material if lod_debug_enabled else medium_surface_material
		)
	for rock_instance in rock_instances:
		if rock_instance != null:
			rock_instance.material_override = rock_material


func cycle_surface_style() -> void:
	if material_library == null:
		return
	material_library.cycle_style()
	_apply_debug_materials()


func get_surface_style_name() -> String:
	if material_library == null:
		return "Не определён"
	return material_library.get_style_name()


func get_streaming_status() -> String:
	return last_streaming_status


func get_spectator_anchor_distance() -> float:
	return last_spectator_anchor_distance


func get_layer_stack_name() -> String:
	return lod_policy.layer_stack_name(current_lod)


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
	var absolute_position: Vector3 = render_to_world(player.global_position)
	if absolute_position.length_squared() < 1.0:
		return
	var new_direction: Vector3 = absolute_position.normalized()
	var tangential_velocity: Vector3 = player.velocity.slide(new_direction)
	var medium_distance: float = (
		new_direction * MOON_RADIUS - medium_anchor_world
	).length()
	var include_medium: bool = medium_distance > MEDIUM_LOCAL_RECENTER_DISTANCE

	if terrain_streamer != null and terrain_streamer.is_enabled():
		terrain_streamer.request_predicted_surface(
			absolute_position,
			tangential_velocity,
			true,
			include_medium,
			"player_predictive_stream"
		)
	else:
		var anchor_distance: float = (
			new_direction * MOON_RADIUS - surface_anchor_world
		).length()
		if anchor_distance > PLAYER_RECENTER_DISTANCE:
			if include_medium:
				prepare_surface_region(new_direction, true)
			else:
				_rebuild_local_playable_surface(new_direction)

	# Render-origin rebasing is cheap and independent from terrain generation.
	# The old 14 km surface remains active while the next surface is prepared.
	if player.global_position.length() >= PLAYER_RECENTER_DISTANCE:
		set_render_origin(absolute_position)
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


func get_detail_name() -> String:
	return lod_policy.detail_name(current_lod)


func get_moon_radius() -> float:
	return MOON_RADIUS


func get_gravity_at_distance(distance_from_center: float) -> float:
	return GravityMathScript.acceleration_magnitude(
		distance_from_center,
		MOON_RADIUS,
		MOON_GRAVITATIONAL_PARAMETER_M3_S2,
		"uniform_sphere"
	)


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
	result += _get_micro_surface_relief(direction, factors)
	result += _get_micro_crater_height(direction)
	return clampf(result, -9200.0, 11_200.0)


func _get_micro_surface_relief(direction: Vector3, factors: Vector4) -> float:
	var center_distance: float = (
		direction - surface_center_direction
	).length() * MOON_RADIUS
	var meso_fade: float = 1.0 - smoothstep(1600.0, MESO_DETAIL_FADE_END, center_distance)
	var micro_fade: float = 1.0 - smoothstep(360.0, MICRO_DETAIL_FADE_END, center_distance)
	var fine_fade: float = 1.0 - smoothstep(210.0, 470.0, center_distance)
	var grain_fade: float = 1.0 - smoothstep(105.0, 260.0, center_distance)

	var ruggedness: float = clampf(
		0.35 + factors.y * 0.50 + factors.z * 0.85 + factors.w * 0.28,
		0.25,
		1.65
	)
	var meso: float = meso_surface_noise.get_noise_3d(
		direction.x * 6500.0,
		direction.y * 6500.0,
		direction.z * 6500.0
	)
	var micro: float = micro_surface_noise.get_noise_3d(
		direction.x * 22_000.0,
		direction.y * 22_000.0,
		direction.z * 22_000.0
	)
	var fine: float = fine_surface_noise.get_noise_3d(
		direction.x * 78_000.0,
		direction.y * 78_000.0,
		direction.z * 78_000.0
	)
	var grain_source: float = grain_surface_noise.get_noise_3d(
		direction.x * 245_000.0,
		direction.y * 245_000.0,
		direction.z * 245_000.0
	)
	var broken_regolith: float = (
		pow(absf(grain_source), 1.7) - 0.28
	)

	var result: float = meso * (10.0 + 30.0 * ruggedness) * meso_fade
	result += micro * (1.8 + 7.2 * ruggedness) * micro_fade
	result += fine * (0.35 + 1.55 * ruggedness) * fine_fade
	result += broken_regolith * (0.08 + 0.28 * ruggedness) * grain_fade
	return result


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
	result += _get_maria_height(direction)
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
	var maria_mix: float = clampf((-maria_noise - 0.03) * 1.95, 0.0, 1.0)
	maria_mix = maxf(maria_mix, _get_maria_factor(direction))
	var low_color := Color(0.38, 0.39, 0.405)
	var high_color := Color(0.73, 0.715, 0.685)
	var result := low_color.lerp(high_color, height_mix)
	result = result.lerp(Color(0.245, 0.255, 0.275), maria_mix * 0.48)
	result = result.lerp(Color(0.45, 0.46, 0.475), factors.x * 0.18)
	result = result.lerp(Color(0.76, 0.735, 0.69), factors.y * 0.15)
	result = result.lerp(Color(0.80, 0.755, 0.69), factors.z * 0.20)
	result = result.lerp(Color(0.42, 0.415, 0.42), factors.w * 0.12)
	var regolith_variation: float = grain_surface_noise.get_noise_3d(
		direction.x * 92_000.0,
		direction.y * 92_000.0,
		direction.z * 92_000.0
	)
	result = result.lightened(maxf(regolith_variation, 0.0) * 0.035)
	result = result.darkened(maxf(-regolith_variation, 0.0) * 0.045)
	return result


func _lit_surface_color(height: float, direction: Vector3, _normal: Vector3) -> Color:
	return _surface_base_color(height, direction)


func _stable_lunar_uv(direction_value: Vector3, outer_radius: float) -> Vector2:
	var direction := direction_value.normalized()
	var latitude: float = asin(clampf(direction.y, -1.0, 1.0))
	var longitude: float = atan2(direction.z, direction.x)
	var east_m: float = longitude * MOON_RADIUS * maxf(cos(latitude), 0.08)
	var north_m: float = latitude * MOON_RADIUS
	var tile_meters: float = 512.0
	if outer_radius > LOCAL_CAP_RADIUS + 1.0:
		tile_meters = 32_000.0
	return Vector2(east_m / tile_meters, north_m / tile_meters)


func _get_local_ejecta_factor(direction: Vector3) -> float:
	var best: float = 0.0
	for crater_index in range(local_crater_centers.size()):
		var radius_m: float = local_crater_radii[crater_index]
		var distance_m: float = (
			direction - local_crater_centers[crater_index]
		).length() * MOON_RADIUS
		var normalized_distance: float = distance_m / maxf(radius_m, 0.01)
		if normalized_distance < 0.78 or normalized_distance > 2.15:
			continue
		var rim_band: float = exp(-pow((normalized_distance - 1.05) / 0.30, 2.0))
		var ejecta_band: float = maxf(0.0, 1.0 - (normalized_distance - 1.0) / 1.15)
		best = maxf(best, maxf(rim_band, ejecta_band * 0.62) * local_crater_ejecta[crater_index])
	return clampf(best, 0.0, 1.0)


func _clear_node(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.free()


# -----------------------------------------------------------------------------
# Asynchronous terrain streaming worker API.
# These methods are intentionally data-only. A dedicated off-tree sampler calls
# them from WorkerThreadPool and returns PackedArrays/Transform3D descriptors.
# Scene nodes and rendering/physics resources are created only on the main thread.
# -----------------------------------------------------------------------------

func build_streaming_payload(request: Dictionary) -> Dictionary:
	var total_started_usec: int = Time.get_ticks_usec()
	var timings: Dictionary = {}
	var center_value = request.get("center_direction", Vector3.UP)
	var center_direction: Vector3 = (
		center_value if center_value is Vector3 else Vector3.UP
	).normalized()

	var stage_started_usec: int = Time.get_ticks_usec()
	surface_center_direction = center_direction
	surface_east = _make_east(surface_center_direction)
	surface_north = surface_east.cross(surface_center_direction).normalized()
	_generate_local_craters_for_region(surface_center_direction)
	_generate_micro_craters_for_region(surface_center_direction)
	surface_anchor_world = get_surface_point(surface_center_direction)
	timings["crater_catalogs_and_anchor_ms"] = _elapsed_ms(stage_started_usec)

	var local_profile: Dictionary = _profiled_radial_cap_data(
		0.0,
		LOCAL_CAP_RADIUS,
		LOCAL_CAP_RINGS,
		LOCAL_CAP_SEGMENTS,
		false
	)
	var local_data: Dictionary = local_profile.get("data", {})
	_merge_prefixed_timings(timings, "local_", local_profile.get("timings_ms", {}))

	var include_collision: bool = bool(request.get("include_collision", false))
	var collision_tiles: Array[Dictionary] = []
	if include_collision:
		stage_started_usec = Time.get_ticks_usec()
		collision_tiles = _partition_collision_faces(
			local_data,
			maxi(256, int(request.get("collision_triangles_per_tile", 2048)))
		)
		timings["collision_partition_ms"] = _elapsed_ms(stage_started_usec)

	var include_medium: bool = bool(request.get("include_medium", false))
	var medium_annulus_data: Dictionary = {}
	var medium_full_data: Dictionary = {}
	if include_medium:
		var annulus_profile: Dictionary = _profiled_radial_cap_data(
			LOCAL_CAP_RADIUS,
			MEDIUM_CAP_RADIUS,
			MEDIUM_CAP_RINGS,
			CAP_SEGMENTS,
			true
		)
		medium_annulus_data = annulus_profile.get("data", {})
		_merge_prefixed_timings(
			timings,
			"medium_annulus_",
			annulus_profile.get("timings_ms", {})
		)
		var full_profile: Dictionary = _profiled_radial_cap_data(
			0.0,
			MEDIUM_CAP_RADIUS,
			MEDIUM_CAP_RINGS,
			CAP_SEGMENTS,
			true
		)
		medium_full_data = full_profile.get("data", {})
		_merge_prefixed_timings(
			timings,
			"medium_full_",
			full_profile.get("timings_ms", {})
		)

	stage_started_usec = Time.get_ticks_usec()
	var rock_layers: Array[Dictionary] = _build_streaming_rock_layers()
	timings["rock_descriptors_ms"] = _elapsed_ms(stage_started_usec)
	var rock_instance_count: int = 0
	for layer in rock_layers:
		rock_instance_count += int(layer.get("instance_count", 0))

	timings["total_background_ms"] = _elapsed_ms(total_started_usec)
	return {
		"schema": "lunar.terrain_build_result.v1",
		"request_id": request.get("request_id", -1),
		"generation_revision": request.get("generation_revision", -1),
		"cell_id": request.get("cell_id", "-"),
		"reason": request.get("reason", ""),
		"extra": request.get("extra", {}).duplicate(true),
		"center_direction": center_direction,
		"include_collision": include_collision,
		"include_medium": include_medium,
		"requested_ticks_usec": request.get("requested_ticks_usec", 0),
		"completed_ticks_usec": Time.get_ticks_usec(),
		"generation_state": _capture_generation_state(),
		"local_mesh_data": local_data,
		"medium_annulus_data": medium_annulus_data,
		"medium_full_data": medium_full_data,
		"rock_layers": rock_layers,
		"collision_tiles": collision_tiles,
		"collision_tile_count": collision_tiles.size(),
		"timings_ms": timings,
		"local_vertex_count": int(local_data.get("vertex_count", 0)),
		"local_triangle_count": int(local_data.get("triangle_count", 0)),
		"rock_instance_count": rock_instance_count,
	}


func _profiled_radial_cap_data(
	inner_radius: float,
	outer_radius: float,
	ring_count: int,
	segment_count: int,
	blend_to_global: bool
) -> Dictionary:
	var timings: Dictionary = {}
	var started_usec: int = Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	var directions := PackedVector3Array()
	var heights := PackedFloat64Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var has_center: bool = inner_radius <= 0.001
	var local_surface_cap: bool = has_center and absf(outer_radius - LOCAL_CAP_RADIUS) < 0.01
	var use_center_vertex: bool = has_center and not local_surface_cap
	var fill_innermost_ring: bool = local_surface_cap
	var ring_radii := PackedFloat64Array()

	if local_surface_cap:
		ring_radii.append(LOCAL_CENTER_PATCH_RADIUS)
		ring_radii.append_array(_build_local_ring_radii())
	else:
		for ring_index in range(ring_count + 1):
			if has_center and ring_index == 0:
				continue
			var ring_t: float = float(ring_index) / float(ring_count)
			var radial_distance: float = lerpf(inner_radius, outer_radius, ring_t)
			if has_center:
				radial_distance = outer_radius * pow(
					ring_t,
					LOCAL_RADIAL_DISTRIBUTION_POWER
				)
			ring_radii.append(radial_distance)

	if use_center_vertex:
		var center_height: float = get_surface_height(surface_center_direction)
		vertices.append(
			surface_center_direction * (MOON_RADIUS + center_height)
			- surface_anchor_world
		)
		directions.append(surface_center_direction)
		heights.append(center_height)
		uvs.append(_stable_lunar_uv(surface_center_direction, outer_radius))

	for ring_array_index in range(ring_radii.size()):
		var radial_distance: float = ring_radii[ring_array_index]
		var ring_t: float = (
			float(ring_array_index) / float(maxi(ring_radii.size() - 1, 1))
		)
		for segment_index in range(segment_count):
			var angle: float = float(segment_index) / float(segment_count) * TAU
			var local_x: float = cos(angle) * radial_distance
			var local_z: float = sin(angle) * radial_distance
			var direction: Vector3 = _direction_from_surface_local(local_x, local_z)
			var detailed_height: float = get_surface_height(direction)
			var final_height: float = detailed_height
			if blend_to_global:
				var edge_blend: float = smoothstep(0.72, 1.0, ring_t)
				var global_height: float = (
					get_coarse_surface_height(direction)
					+ GLOBAL_SURFACE_OFFSET
					+ 120.0
				)
				final_height = lerpf(detailed_height, global_height, edge_blend)
			vertices.append(
				direction * (MOON_RADIUS + final_height) - surface_anchor_world
			)
			directions.append(direction)
			heights.append(final_height)
			uvs.append(_stable_lunar_uv(direction, outer_radius))

	if use_center_vertex:
		var first_ring_start: int = 1
		for segment_index in range(segment_count):
			var next_segment: int = (segment_index + 1) % segment_count
			indices.append_array(PackedInt32Array([
				0,
				first_ring_start + segment_index,
				first_ring_start + next_segment,
			]))
		for ring_index in range(1, ring_radii.size()):
			var current_start: int = 1 + (ring_index - 1) * segment_count
			var next_start: int = current_start + segment_count
			_add_ring_indices(indices, current_start, next_start, segment_count)
	else:
		if fill_innermost_ring:
			_add_central_disc_indices(indices, segment_count)
		for ring_index in range(ring_radii.size() - 1):
			var current_start: int = ring_index * segment_count
			var next_start: int = current_start + segment_count
			_add_ring_indices(indices, current_start, next_start, segment_count)
	timings["sampling_and_indices_ms"] = _elapsed_ms(started_usec)

	started_usec = Time.get_ticks_usec()
	var normals: PackedVector3Array = _calculate_normals(vertices, indices, directions)
	timings["normals_ms"] = _elapsed_ms(started_usec)

	started_usec = Time.get_ticks_usec()
	var colors := PackedColorArray()
	for vertex_index in range(vertices.size()):
		colors.append(_surface_base_color(
			heights[vertex_index],
			directions[vertex_index]
		))
	timings["colors_ms"] = _elapsed_ms(started_usec)

	started_usec = Time.get_ticks_usec()
	var tangents: PackedFloat32Array = _calculate_tangents(
		vertices,
		normals,
		uvs,
		indices
	)
	timings["tangents_ms"] = _elapsed_ms(started_usec)
	return {
		"data": {
			"vertices": vertices,
			"normals": normals,
			"colors": colors,
			"uvs": uvs,
			"tangents": tangents,
			"indices": indices,
			"vertex_count": vertices.size(),
			"triangle_count": int(indices.size() / 3),
		},
		"timings_ms": timings,
	}


func _partition_collision_faces(
	mesh_data: Dictionary,
	triangles_per_tile: int
) -> Array[Dictionary]:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var result: Array[Dictionary] = []
	if vertices.is_empty() or indices.size() < 3:
		return result
	var tile_faces := PackedVector3Array()
	var triangle_count: int = 0
	var tile_index: int = 0
	for triangle_offset in range(0, indices.size(), 3):
		var ia: int = indices[triangle_offset]
		var ib: int = indices[triangle_offset + 1]
		var ic: int = indices[triangle_offset + 2]
		tile_faces.append(vertices[ia])
		tile_faces.append(vertices[ib])
		tile_faces.append(vertices[ic])
		triangle_count += 1
		if triangle_count >= triangles_per_tile:
			result.append({
				"tile_index": tile_index,
				"faces": tile_faces,
				"triangle_count": triangle_count,
			})
			tile_index += 1
			tile_faces = PackedVector3Array()
			triangle_count = 0
	if triangle_count > 0:
		result.append({
			"tile_index": tile_index,
			"faces": tile_faces,
			"triangle_count": triangle_count,
		})
	return result


func _build_streaming_rock_layers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec in _streaming_rock_specs():
		var transforms: Array[Transform3D] = _build_rock_layer_transforms(
			float(spec.get("layer_radius", 0.0)),
			float(spec.get("cell_size", 1.0)),
			float(spec.get("spawn_probability", 0.0)),
			float(spec.get("min_scale", 1.0)),
			float(spec.get("max_scale", 1.0)),
			int(spec.get("max_instances", 0)),
			int(spec.get("seed_offset", 0)),
			bool(spec.get("align_to_surface", false)),
			float(spec.get("bury_factor", 0.0)),
			float(spec.get("ejecta_bias", 0.0))
		)
		var layer: Dictionary = spec.duplicate(true)
		layer["transforms"] = transforms
		layer["instance_count"] = transforms.size()
		result.append(layer)
	return result


func _streaming_rock_specs() -> Array[Dictionary]:
	return [
		{
			"layer_name": "AngularBoulders", "variant_index": 0,
			"layer_radius": LARGE_ROCK_RADIUS, "cell_size": 245.0,
			"spawn_probability": 0.16, "min_scale": 0.65, "max_scale": 6.8,
			"max_instances": 470, "seed_offset": 301,
			"align_to_surface": true, "bury_factor": 0.23, "ejecta_bias": 0.25,
		},
		{
			"layer_name": "FlatSlabs", "variant_index": 1,
			"layer_radius": MEDIUM_ROCK_RADIUS, "cell_size": 58.0,
			"spawn_probability": 0.31, "min_scale": 0.24, "max_scale": 2.8,
			"max_instances": 900, "seed_offset": 503,
			"align_to_surface": true, "bury_factor": 0.08, "ejecta_bias": 0.35,
		},
		{
			"layer_name": "SharpFragments", "variant_index": 2,
			"layer_radius": SMALL_ROCK_RADIUS, "cell_size": 13.0,
			"spawn_probability": 0.42, "min_scale": 0.08, "max_scale": 0.82,
			"max_instances": 2300, "seed_offset": 709,
			"align_to_surface": false, "bury_factor": 0.11, "ejecta_bias": 0.65,
		},
		{
			"layer_name": "PebbleScatter", "variant_index": 3,
			"layer_radius": 240.0, "cell_size": 4.6,
			"spawn_probability": 0.62, "min_scale": 0.018, "max_scale": 0.18,
			"max_instances": 5200, "seed_offset": 907,
			"align_to_surface": false, "bury_factor": 0.025, "ejecta_bias": 0.20,
		},
		{
			"layer_name": "CraterRimBlocks", "variant_index": 4,
			"layer_radius": 2600.0, "cell_size": 34.0,
			"spawn_probability": 0.14, "min_scale": 0.32, "max_scale": 3.4,
			"max_instances": 1300, "seed_offset": 1103,
			"align_to_surface": true, "bury_factor": 0.13, "ejecta_bias": 2.8,
		},
		{
			"layer_name": "BrecciaClusters", "variant_index": 5,
			"layer_radius": 780.0, "cell_size": 8.5,
			"spawn_probability": 0.24, "min_scale": 0.055, "max_scale": 0.48,
			"max_instances": 2900, "seed_offset": 1301,
			"align_to_surface": false, "bury_factor": 0.045, "ejecta_bias": 1.65,
		},
	]


func _build_rock_layer_transforms(
	layer_radius: float,
	cell_size: float,
	spawn_probability: float,
	min_scale: float,
	max_scale: float,
	max_instances: int,
	seed_offset: int,
	align_to_surface: bool,
	bury_factor: float,
	ejecta_bias: float
) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var cell_angle: float = cell_size / MOON_RADIUS
	var latitude: float = asin(clampf(surface_center_direction.y, -1.0, 1.0))
	var longitude: float = atan2(surface_center_direction.z, surface_center_direction.x)
	var center_lat_cell: int = floori(latitude / cell_angle)
	var center_lon_cell: int = floori(longitude / cell_angle)
	var cell_radius: int = ceili(layer_radius / cell_size) + 2
	for lat_offset in range(-cell_radius, cell_radius + 1):
		if transforms.size() >= max_instances:
			break
		var lat_cell: int = center_lat_cell + lat_offset
		var cell_latitude: float = (float(lat_cell) + 0.5) * cell_angle
		if cell_latitude <= -PI * 0.5 or cell_latitude >= PI * 0.5:
			continue
		for lon_offset in range(-cell_radius, cell_radius + 1):
			if transforms.size() >= max_instances:
				break
			var lon_cell: int = center_lon_cell + lon_offset
			var cell_seed: int = (
				WORLD_SEED * 211
				+ lat_cell * 73_856_093
				+ lon_cell * 19_349_663
				+ seed_offset * 83_492_791
			)
			if cell_seed < 0:
				cell_seed = -cell_seed
			var rng := RandomNumberGenerator.new()
			rng.seed = cell_seed
			var candidate_latitude: float = (
				float(lat_cell) + rng.randf_range(0.06, 0.94)
			) * cell_angle
			var candidate_longitude: float = (
				float(lon_cell) + rng.randf_range(0.06, 0.94)
			) * cell_angle
			var direction: Vector3 = _direction_from_lat_lon(
				candidate_latitude,
				candidate_longitude
			)
			var distance_m: float = (
				direction - surface_center_direction
			).length() * MOON_RADIUS
			if distance_m > layer_radius:
				continue
			var ejecta_factor: float = _get_local_ejecta_factor(direction)
			var factors: Vector4 = _get_region_factors(direction)
			var local_probability: float = spawn_probability * (
				0.78
				+ factors.w * 0.34
				+ factors.y * 0.12
				+ ejecta_factor * ejecta_bias
			)
			if rng.randf() > clampf(local_probability, 0.0, 0.96):
				continue
			var normal: Vector3 = direction
			if align_to_surface:
				normal = _estimate_surface_normal(
					direction,
					clampf(cell_size * 0.12, 1.0, 28.0)
				)
				if normal.dot(direction) < 0.58:
					continue
			var point_world: Vector3 = get_surface_point(direction)
			var scale_value: float = rng.randf_range(min_scale, max_scale)
			var tangent_x: Vector3 = _make_east(normal)
			var tangent_z: Vector3 = tangent_x.cross(normal).normalized()
			var basis: Basis = Basis(tangent_x, normal, tangent_z)
			basis = Basis(normal, rng.randf_range(0.0, TAU)) * basis
			var anisotropy := Vector3(
				rng.randf_range(0.82, 1.22),
				rng.randf_range(0.82, 1.16),
				rng.randf_range(0.82, 1.22)
			)
			basis = basis.scaled(anisotropy * scale_value)
			transforms.append(Transform3D(
				basis,
				point_world - surface_anchor_world + normal * (bury_factor * scale_value)
			))
	return transforms


func _capture_generation_state() -> Dictionary:
	return {
		"surface_center_direction": surface_center_direction,
		"surface_east": surface_east,
		"surface_north": surface_north,
		"surface_anchor_world": surface_anchor_world,
		"local_crater_centers": local_crater_centers.duplicate(),
		"local_crater_radii": local_crater_radii.duplicate(),
		"local_crater_depths": local_crater_depths.duplicate(),
		"local_crater_rims": local_crater_rims.duplicate(),
		"local_crater_degradation": local_crater_degradation.duplicate(),
		"local_crater_ejecta": local_crater_ejecta.duplicate(),
		"micro_crater_centers": micro_crater_centers.duplicate(),
		"micro_crater_radii": micro_crater_radii.duplicate(),
		"micro_crater_depths": micro_crater_depths.duplicate(),
		"micro_crater_rims": micro_crater_rims.duplicate(),
		"micro_crater_degradation": micro_crater_degradation.duplicate(),
		"micro_crater_ejecta": micro_crater_ejecta.duplicate(),
	}


func _apply_generation_state(state: Dictionary) -> void:
	var center_value = state.get("surface_center_direction", Vector3.UP)
	surface_center_direction = (
		center_value if center_value is Vector3 else Vector3.UP
	).normalized()
	var east_value = state.get("surface_east", _make_east(surface_center_direction))
	surface_east = (
		east_value if east_value is Vector3 else _make_east(surface_center_direction)
	)
	var north_fallback: Vector3 = surface_east.cross(surface_center_direction).normalized()
	var north_value = state.get("surface_north", north_fallback)
	surface_north = north_value if north_value is Vector3 else north_fallback
	var anchor_value = state.get(
		"surface_anchor_world",
		surface_center_direction * MOON_RADIUS
	)
	surface_anchor_world = (
		anchor_value
		if anchor_value is Vector3
		else surface_center_direction * MOON_RADIUS
	)
	local_crater_centers = state.get("local_crater_centers", PackedVector3Array())
	local_crater_radii = state.get("local_crater_radii", PackedFloat64Array())
	local_crater_depths = state.get("local_crater_depths", PackedFloat64Array())
	local_crater_rims = state.get("local_crater_rims", PackedFloat64Array())
	local_crater_degradation = state.get("local_crater_degradation", PackedFloat64Array())
	local_crater_ejecta = state.get("local_crater_ejecta", PackedFloat64Array())
	micro_crater_centers = state.get("micro_crater_centers", PackedVector3Array())
	micro_crater_radii = state.get("micro_crater_radii", PackedFloat64Array())
	micro_crater_depths = state.get("micro_crater_depths", PackedFloat64Array())
	micro_crater_rims = state.get("micro_crater_rims", PackedFloat64Array())
	micro_crater_degradation = state.get("micro_crater_degradation", PackedFloat64Array())
	micro_crater_ejecta = state.get("micro_crater_ejecta", PackedFloat64Array())


func streaming_create_mesh(mesh_data: Dictionary, material_kind: String) -> ArrayMesh:
	if mesh_data.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_TEX_UV] = mesh_data.get("uvs", PackedVector2Array())
	arrays[Mesh.ARRAY_TANGENT] = mesh_data.get("tangents", PackedFloat32Array())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: Material = local_surface_material
	if material_kind == "regional":
		material = medium_surface_material
	elif material_kind == "global":
		material = global_surface_material
	result.surface_set_material(0, material)
	return result


func streaming_create_mesh_instance(instance_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func streaming_create_collision_root() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PlayableSurfaceTiled"
	body.collision_layer = 1
	body.collision_mask = 1
	return body


func streaming_add_collision_tile(
	body: StaticBody3D,
	tile_data: Dictionary,
	tile_index: int
) -> bool:
	if body == null:
		return false
	var faces: PackedVector3Array = tile_data.get("faces", PackedVector3Array())
	if faces.size() < 3:
		return false
	var terrain_shape := ConcavePolygonShape3D.new()
	terrain_shape.backface_collision = true
	terrain_shape.set_faces(faces)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionTile_%03d" % tile_index
	collision_shape.shape = terrain_shape
	body.add_child(collision_shape)
	return true


func streaming_create_collision_body(mesh: ArrayMesh) -> StaticBody3D:
	# Legacy synchronous fallback retained for spawn/teleport paths.
	if mesh == null:
		return null
	var terrain_shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if terrain_shape == null:
		return null
	terrain_shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "PlayableSurface"
	body.collision_layer = 1
	body.collision_mask = 1
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "PlayableSurfaceCollision"
	collision_shape.shape = terrain_shape
	body.add_child(collision_shape)
	return body


func streaming_create_rock_instance(layer_data: Dictionary) -> MultiMeshInstance3D:
	var variant_index: int = int(layer_data.get("variant_index", -1))
	if variant_index < 0 or variant_index >= rock_meshes.size():
		return null
	var transforms: Array = layer_data.get("transforms", [])
	if transforms.is_empty():
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock_meshes[variant_index]
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for instance_index in range(transforms.size()):
		multimesh.set_instance_transform(instance_index, transforms[instance_index])
	var instance := MultiMeshInstance3D.new()
	instance.name = String(layer_data.get("layer_name", "RockLayer"))
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func configure_recent_surface_cache(capacity: int) -> void:
	recent_surface_cache_capacity = maxi(0, capacity)
	_prune_recent_surface_cache()


func configure_pinned_surface_cells(
	cell_ids: Array,
	max_pinned: int = 8
) -> void:
	max_pinned_surface_cells = maxi(0, max_pinned)
	pinned_surface_cells.clear()
	if max_pinned_surface_cells <= 0:
		_prune_recent_surface_cache()
		return
	for cell_id_value in cell_ids:
		var cell_id: String = String(cell_id_value)
		if cell_id.is_empty() or cell_id == "-":
			continue
		pinned_surface_cells[cell_id] = true
		if pinned_surface_cells.size() >= max_pinned_surface_cells:
			break
	_prune_recent_surface_cache()


func streaming_has_cached_surface(cell_id: String) -> bool:
	return (
		recent_surface_cache_capacity > 0
		and not cell_id.is_empty()
		and recent_surface_cache.has(cell_id)
	)


func get_recent_surface_cache_snapshot() -> Dictionary:
	var entries: Array[Dictionary] = []
	for cell_id in recent_surface_cache_order:
		var entry: Dictionary = recent_surface_cache.get(cell_id, {})
		if entry.is_empty():
			continue
		entries.append({
			"cell_id": cell_id,
			"pinned": pinned_surface_cells.has(cell_id),
			"vertex_count": entry.get("vertex_count", 0),
			"triangle_count": entry.get("triangle_count", 0),
			"collision_shape_count": entry.get("collision_shape_count", 0),
			"rock_layer_count": entry.get("rock_layer_count", 0),
			"cached_ticks_msec": entry.get("cached_ticks_msec", 0),
		})
	return {
		"schema": "lunar.recent_surface_cache.v1",
		"size": recent_surface_cache.size(),
		"capacity": recent_surface_cache_capacity,
		"max_pinned_surface_cells": max_pinned_surface_cells,
		"pinned_cell_ids": pinned_surface_cells.keys(),
		"evictions": recent_surface_cache_evictions,
		"cells_lru": recent_surface_cache_order.duplicate(),
		"entries": entries,
	}


func _cache_current_surface(cell_id: String) -> Dictionary:
	if (
		recent_surface_cache_capacity <= 0
		or cell_id.is_empty()
		or cell_id == "-"
		or local_cap == null
		or not is_instance_valid(local_cap)
		or local_cap.mesh == null
	):
		return {"cached": false}

	var local_mesh_resource: ArrayMesh = local_cap.mesh as ArrayMesh
	if local_mesh_resource == null:
		return {"cached": false}

	var collision_shapes: Array = []
	for body in collision_root.get_children():
		if not (body is CollisionObject3D):
			continue
		for child in body.get_children():
			if child is CollisionShape3D and child.shape != null:
				collision_shapes.append(child.shape)

	var rock_multimeshes: Array = []
	var rock_names: Array[String] = []
	for rock_instance in rock_instances:
		if (
			rock_instance != null
			and is_instance_valid(rock_instance)
			and rock_instance.multimesh != null
		):
			rock_multimeshes.append(rock_instance.multimesh)
			rock_names.append(String(rock_instance.name))

	var vertex_count: int = 0
	var index_count: int = 0
	if local_mesh_resource.get_surface_count() > 0:
		vertex_count = local_mesh_resource.surface_get_array_len(0)
		index_count = local_mesh_resource.surface_get_array_index_len(0)

	recent_surface_cache.erase(cell_id)
	recent_surface_cache_order.erase(cell_id)
	recent_surface_cache[cell_id] = {
		"schema": "lunar.cached_surface.v1",
		"cell_id": cell_id,
		"generation_state": _capture_generation_state(),
		"local_mesh": local_mesh_resource,
		"collision_shapes": collision_shapes,
		"rock_multimeshes": rock_multimeshes,
		"rock_names": rock_names,
		"vertex_count": vertex_count,
		"triangle_count": int(index_count / 3),
		"collision_shape_count": collision_shapes.size(),
		"rock_layer_count": rock_multimeshes.size(),
		"cached_ticks_msec": Time.get_ticks_msec(),
	}
	recent_surface_cache_order.append(cell_id)
	_prune_recent_surface_cache()
	var summary: Dictionary = {
		"cached": true,
		"cell_id": cell_id,
		"cache_size": recent_surface_cache.size(),
		"cache_capacity": recent_surface_cache_capacity,
		"pinned": pinned_surface_cells.has(cell_id),
		"vertex_count": vertex_count,
		"triangle_count": int(index_count / 3),
		"collision_shape_count": collision_shapes.size(),
		"rock_layer_count": rock_multimeshes.size(),
	}
	_log_terrain_performance("terrain_surface_cached", summary)
	return summary


func _prune_recent_surface_cache() -> void:
	var pinned_in_cache: int = 0
	for cell_id in recent_surface_cache_order:
		if pinned_surface_cells.has(cell_id):
			pinned_in_cache += 1
	var allowed_pinned: int = mini(
		pinned_in_cache,
		max_pinned_surface_cells
	)
	var max_total: int = recent_surface_cache_capacity + allowed_pinned
	while recent_surface_cache_order.size() > max_total:
		var eviction_index: int = -1
		for index in range(recent_surface_cache_order.size()):
			var candidate: String = recent_surface_cache_order[index]
			if not pinned_surface_cells.has(candidate):
				eviction_index = index
				break
		if eviction_index < 0:
			eviction_index = 0
		var evicted_cell_id: String = recent_surface_cache_order[eviction_index]
		recent_surface_cache_order.remove_at(eviction_index)
		var evicted_entry: Dictionary = recent_surface_cache.get(
			evicted_cell_id,
			{}
		)
		recent_surface_cache.erase(evicted_cell_id)
		recent_surface_cache_evictions += 1
		_log_terrain_performance("terrain_surface_cache_evicted", {
			"cell_id": evicted_cell_id,
			"pinned": pinned_surface_cells.has(evicted_cell_id),
			"cache_size": recent_surface_cache.size(),
			"cache_capacity": recent_surface_cache_capacity,
			"max_total_with_pins": max_total,
			"vertex_count": evicted_entry.get("vertex_count", 0),
			"triangle_count": evicted_entry.get("triangle_count", 0),
		})


func streaming_activate_cached_surface(
	cell_id: String,
	previous_cell_id: String
) -> Dictionary:
	if not recent_surface_cache.has(cell_id):
		return {
			"success": false,
			"reason": "cache_entry_not_found",
			"cell_id": cell_id,
		}
	var total_started_usec: int = Time.get_ticks_usec()
	var entry: Dictionary = recent_surface_cache.get(cell_id, {})
	recent_surface_cache.erase(cell_id)
	recent_surface_cache_order.erase(cell_id)

	var actor_snapshots: Array[Dictionary] = _capture_streaming_actor_snapshots()
	var old_local = local_cap
	var old_rocks: Array = rock_instances.duplicate()
	var old_collision_bodies: Array[Node] = []
	for child in collision_root.get_children():
		old_collision_bodies.append(child)

	var cache_started_usec: int = Time.get_ticks_usec()
	if previous_cell_id != cell_id:
		_cache_current_surface(previous_cell_id)
	var cache_previous_ms: float = _elapsed_ms(cache_started_usec)

	var state_started_usec: int = Time.get_ticks_usec()
	_apply_generation_state(entry.get("generation_state", {}))
	var apply_state_ms: float = _elapsed_ms(state_started_usec)

	var local_started_usec: int = Time.get_ticks_usec()
	var cached_local_mesh: ArrayMesh = entry.get("local_mesh") as ArrayMesh
	local_cap = streaming_create_mesh_instance(
		"LocalHighDetail",
		cached_local_mesh
	)
	if local_cap == null:
		recent_surface_cache[cell_id] = entry
		recent_surface_cache_order.append(cell_id)
		return {
			"success": false,
			"reason": "cached_local_instance_failed",
			"cell_id": cell_id,
		}
	surface_root.add_child(local_cap)
	var local_instance_ms: float = _elapsed_ms(local_started_usec)

	if medium_annulus_cap != null:
		medium_annulus_cap.position = medium_anchor_world - surface_anchor_world
	if medium_full_cap != null:
		medium_full_cap.position = medium_anchor_world - surface_anchor_world

	var collision_started_usec: int = Time.get_ticks_usec()
	var collision_body := streaming_create_collision_root()
	var collision_index: int = 0
	for shape_resource in entry.get("collision_shapes", []):
		if shape_resource == null:
			continue
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CachedCollision_%03d" % collision_index
		collision_shape.shape = shape_resource
		collision_body.add_child(collision_shape)
		collision_index += 1
	if collision_index > 0:
		collision_root.add_child(collision_body)
		current_lod = 0
	else:
		collision_body.free()
		collision_body = null
	var collision_nodes_ms: float = _elapsed_ms(collision_started_usec)

	var rocks_started_usec: int = Time.get_ticks_usec()
	rock_instances.clear()
	var cached_multimeshes: Array = entry.get("rock_multimeshes", [])
	var cached_names: Array = entry.get("rock_names", [])
	for layer_index in range(cached_multimeshes.size()):
		var multimesh_resource = cached_multimeshes[layer_index]
		if multimesh_resource == null:
			continue
		var rock_instance := MultiMeshInstance3D.new()
		rock_instance.name = (
			String(cached_names[layer_index])
			if layer_index < cached_names.size()
			else "CachedRockLayer_%d" % layer_index
		)
		rock_instance.multimesh = multimesh_resource
		rock_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface_root.add_child(rock_instance)
		rock_instances.append(rock_instance)
	rocks_instance = rock_instances[0] if not rock_instances.is_empty() else null
	var rock_nodes_ms: float = _elapsed_ms(rocks_started_usec)

	var swap_started_usec: int = Time.get_ticks_usec()
	_update_root_positions()
	_apply_debug_materials()
	_apply_lod_visibility()
	_reconcile_streaming_actors(actor_snapshots)

	if old_local != null:
		old_local.visible = false
	for old_rock in old_rocks:
		if old_rock != null:
			old_rock.visible = false
	for old_body in old_collision_bodies:
		if old_body is CollisionObject3D:
			old_body.collision_layer = 0
			old_body.collision_mask = 0

	_retire_node_deferred(old_local)
	for old_rock in old_rocks:
		_retire_node_deferred(old_rock)
	for old_body in old_collision_bodies:
		_retire_node_deferred(old_body)
	var swap_ms: float = _elapsed_ms(swap_started_usec)

	var cached_generation_state: Dictionary = entry.get("generation_state", {})
	var center_direction = cached_generation_state.get(
		"surface_center_direction",
		surface_center_direction
	)
	var result: Dictionary = {
		"success": true,
		"cell_id": cell_id,
		"previous_cell_id": previous_cell_id,
		"center_direction": center_direction,
		"cache_size": recent_surface_cache.size(),
		"cache_capacity": recent_surface_cache_capacity,
		"timings_ms": {
			"cache_previous_surface_ms": cache_previous_ms,
			"apply_generation_state_ms": apply_state_ms,
			"local_instance_ms": local_instance_ms,
			"collision_nodes_ms": collision_nodes_ms,
			"rock_nodes_ms": rock_nodes_ms,
			"swap_ms": swap_ms,
			"total_cache_activation_ms": _elapsed_ms(total_started_usec),
		},
	}
	_log_terrain_performance("terrain_cached_surface_activated", result)
	return result


func register_streaming_actor(actor: CharacterBody3D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if not streaming_actors.has(actor):
		streaming_actors.append(actor)


func unregister_streaming_actor(actor: CharacterBody3D) -> void:
	streaming_actors.erase(actor)


func _capture_streaming_actor_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for actor in streaming_actors:
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
			continue
		var world_position: Vector3 = render_to_world(actor.global_position)
		if world_position.length_squared() < 1.0:
			continue
		var direction: Vector3 = world_position.normalized()
		var old_surface_point: Vector3 = get_surface_point(direction)
		var clearance: float = world_position.length() - old_surface_point.length()
		snapshots.append({
			"actor": actor,
			"world_position": world_position,
			"direction": direction,
			"clearance": clearance,
			"was_on_floor": actor.is_on_floor(),
		})
	return snapshots


func _reconcile_streaming_actors(snapshots: Array[Dictionary]) -> void:
	for snapshot in snapshots:
		var actor = snapshot.get("actor")
		if actor == null or not is_instance_valid(actor):
			continue
		var direction: Vector3 = snapshot.get("direction", Vector3.ZERO)
		if direction.length_squared() < 0.5:
			continue
		var distance_from_new_center: float = (
			direction - surface_center_direction
		).length() * MOON_RADIUS
		if distance_from_new_center > LOCAL_CAP_RADIUS * 0.88:
			continue
		var old_clearance: float = float(snapshot.get("clearance", 0.0))
		var was_on_floor: bool = bool(snapshot.get("was_on_floor", false))
		# Do not pull a hovering jetpack/drone down to the terrain. Reconciliation
		# is only for grounded actors or actors already almost touching the surface.
		if not was_on_floor and (old_clearance > 0.65 or old_clearance < -3.0):
			continue
		var previous_world_position: Vector3 = snapshot.get("world_position", Vector3.ZERO)
		var new_surface_point: Vector3 = get_surface_point(direction)
		var target_clearance: float = clampf(old_clearance, 0.08, 1.5)
		var target_world_position: Vector3 = new_surface_point + direction * target_clearance
		var vertical_delta: float = target_world_position.length() - previous_world_position.length()
		actor.global_position = world_to_render(target_world_position)
		var radial_speed: float = actor.velocity.dot(direction)
		if was_on_floor or radial_speed < 0.0:
			actor.velocity -= direction * radial_speed
		actor.reset_physics_interpolation()
		_log_terrain_performance("terrain_actor_surface_reconciled", {
			"actor_path": String(actor.get_path()),
			"vertical_delta_m": vertical_delta,
			"old_clearance_m": old_clearance,
			"target_clearance_m": target_clearance,
			"was_on_floor": was_on_floor,
		})


func streaming_discard_staging(staging_data: Dictionary) -> void:
	var node_keys := [
		"local_instance",
		"medium_annulus_instance",
		"medium_full_instance",
		"collision_body",
	]
	for key in node_keys:
		var node = staging_data.get(key)
		if node != null and is_instance_valid(node):
			node.free()
	var staged_rocks: Array = staging_data.get("rock_instances", [])
	for rock_instance in staged_rocks:
		if rock_instance != null and is_instance_valid(rock_instance):
			rock_instance.free()


func streaming_apply_swap(
	result: Dictionary,
	staging: Dictionary,
	previous_cell_id: String = "",
	cache_capacity: int = 4
) -> void:
	var actor_snapshots: Array[Dictionary] = _capture_streaming_actor_snapshots()
	var old_local = local_cap
	var old_medium_annulus = medium_annulus_cap
	var old_medium_full = medium_full_cap
	var old_rocks: Array = rock_instances.duplicate()
	var old_collision_bodies: Array[Node] = []
	for child in collision_root.get_children():
		old_collision_bodies.append(child)

	configure_recent_surface_cache(cache_capacity)
	_cache_current_surface(previous_cell_id)

	# Apply the data snapshot first, while the previous collision is still active.
	# This prevents actors from entering a frame with no supporting surface.
	_apply_generation_state(result.get("generation_state", {}))
	local_cap = staging.get("local_instance")
	if local_cap != null:
		surface_root.add_child(local_cap)

	if bool(result.get("include_medium", false)):
		medium_annulus_cap = staging.get("medium_annulus_instance")
		medium_full_cap = staging.get("medium_full_instance")
		medium_anchor_world = surface_anchor_world
		if medium_annulus_cap != null:
			surface_root.add_child(medium_annulus_cap)
			medium_annulus_cap.position = Vector3.ZERO
		if medium_full_cap != null:
			surface_root.add_child(medium_full_cap)
			medium_full_cap.position = Vector3.ZERO
	else:
		if medium_annulus_cap != null:
			medium_annulus_cap.position = medium_anchor_world - surface_anchor_world
		if medium_full_cap != null:
			medium_full_cap.position = medium_anchor_world - surface_anchor_world

	rock_instances.clear()
	var staged_rocks: Array = staging.get("rock_instances", [])
	for rock_instance in staged_rocks:
		if rock_instance == null:
			continue
		surface_root.add_child(rock_instance)
		rock_instances.append(rock_instance)
	rocks_instance = rock_instances[0] if not rock_instances.is_empty() else null

	var collision_body = staging.get("collision_body")
	if collision_body != null:
		collision_root.add_child(collision_body)
		current_lod = 0

	_update_root_positions()
	_apply_debug_materials()
	_apply_lod_visibility()
	_reconcile_streaming_actors(actor_snapshots)

	# Only after the new mesh, tiled collision and actor reconciliation are ready
	# do we retire the previous slot.
	if old_local != null:
		old_local.visible = false
	for old_rock in old_rocks:
		if old_rock != null:
			old_rock.visible = false
	if bool(result.get("include_medium", false)):
		if old_medium_annulus != null:
			old_medium_annulus.visible = false
		if old_medium_full != null:
			old_medium_full.visible = false
	if collision_body != null:
		for old_body in old_collision_bodies:
			if old_body is CollisionObject3D:
				old_body.collision_layer = 0
				old_body.collision_mask = 0

	_retire_node_deferred(old_local)
	if bool(result.get("include_medium", false)):
		_retire_node_deferred(old_medium_annulus)
		_retire_node_deferred(old_medium_full)
	for old_rock in old_rocks:
		_retire_node_deferred(old_rock)
	if collision_body != null:
		for old_body in old_collision_bodies:
			_retire_node_deferred(old_body)


func _retire_node_deferred(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.queue_free()


func set_streaming_landmark_positions(world_positions: Array) -> void:
	if terrain_streamer == null:
		return
	var directions: Array = []
	for position_value in world_positions:
		if not (position_value is Vector3):
			continue
		var world_position: Vector3 = position_value
		if world_position.length_squared() > 1.0:
			directions.append(world_position.normalized())
	terrain_streamer.set_pinned_surface_directions(directions)


func get_terrain_streaming_snapshot() -> Dictionary:
	if terrain_streamer == null:
		return {"enabled": false, "state": "NOT_INITIALIZED"}
	return terrain_streamer.create_snapshot()


func get_terrain_streaming_summary() -> String:
	if terrain_streamer == null:
		return "не инициализирован"
	return terrain_streamer.get_runtime_summary()


func get_terrain_performance_log_path() -> String:
	if logger != null and logger.has_method("get_performance_log_path"):
		return logger.get_performance_log_path()
	return "user://logs/terrain_performance.jsonl"


func run_terrain_streaming_mini_test(
	world_position: Vector3,
	forward_world: Vector3
) -> Dictionary:
	if terrain_streamer == null:
		return {"passed": false, "summary": "FAIL: manager не создан"}
	return terrain_streamer.run_mini_test(world_position, forward_world)


func _on_stream_test_completed(summary: Dictionary) -> void:
	terrain_streaming_test_completed.emit(summary)


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0


func _merge_prefixed_timings(
	target: Dictionary,
	prefix: String,
	source: Dictionary
) -> void:
	for key in source.keys():
		target[prefix + String(key)] = source[key]


func _log_terrain_performance(event_name: String, data: Dictionary) -> void:
	if logger == null:
		return
	if logger.has_method("performance"):
		logger.performance(event_name, data)
	else:
		logger.info("terrain_performance", event_name, data)
