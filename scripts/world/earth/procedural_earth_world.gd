extends Node3D

signal earth_rebuilt(summary: Dictionary)

const BODY_CONFIG_PATH: String = "res://config/planets/earth.json"
const LOD_CONFIG_PATH: String = "res://config/generation/earth_lod.json"
const EarthRulePipelineScript = preload(
	"res://scripts/world/planetary/earth_rule_pipeline.gd"
)
const EarthAssetLibraryScript = preload(
	"res://scripts/world/earth/earth_asset_library.gd"
)
const EarthPlacementSystemScript = preload(
	"res://scripts/world/vegetation/earth_placement_system.gd"
)
const GravityMathScript = preload(
	"res://scripts/simulation/gravity/gravity_math.gd"
)

var body_config: Dictionary = {}
var lod_config: Dictionary = {}
var pipeline
var assets
var placement_system
var logger

var planet_radius_m: float = 6_371_000.0
var gravity_mps2: float = 9.80665
var gravitational_parameter_m3_s2: float = 398_048_402_912_650.0
var gravity_interior_model: String = "uniform_sphere"
var global_segments: int = 128
var global_rings: int = 64
var global_surface_offset_m: float = -120.0
var local_radius_m: float = 24_000.0
var local_rings: int = 72
var local_segments: int = 192
var local_recenter_distance_m: float = 6500.0
var local_max_visible_altitude_m: float = 180_000.0

var global_earth: MeshInstance3D
var local_root: Node3D
var local_surface: MeshInstance3D
var earth_light: DirectionalLight3D
var render_origin_world: Vector3 = Vector3.ZERO
var surface_anchor_world: Vector3 = Vector3.ZERO
var surface_center_direction: Vector3 = Vector3.UP
var surface_east: Vector3 = Vector3.RIGHT
var surface_north: Vector3 = Vector3.FORWARD
var initialized: bool = false
var current_lod_tier: String = "global"
var debug_view: int = 0
var rebuild_cooldown_sec: float = 0.0
var last_rebuild_summary: Dictionary = {}
var cached_biome_directions: Dictionary = {}
var last_local_mesh_statistics: Dictionary = {}
var last_global_mesh_statistics: Dictionary = {}


func setup(logger_reference = null) -> bool:
	if initialized:
		return true
	logger = logger_reference
	body_config = _load_json(BODY_CONFIG_PATH)
	lod_config = _load_json(LOD_CONFIG_PATH)
	if body_config.is_empty() or lod_config.is_empty():
		_log_error("earth_config_load_failed", {
			"body_config": not body_config.is_empty(),
			"lod_config": not lod_config.is_empty(),
		})
		return false
	_apply_config()
	pipeline = EarthRulePipelineScript.new()
	if not pipeline.setup():
		_log_error("earth_rule_pipeline_invalid", {
			"errors": pipeline.get_validation_errors(),
		})
		return false
	assets = EarthAssetLibraryScript.new()
	assets.setup()
	assets.set_surface_debug_mode(false)
	_create_nodes()
	pipeline.begin_batch("global_earth")
	global_earth.mesh = _build_global_mesh()
	var global_profile: Dictionary = pipeline.end_batch()
	var default_spawn: Dictionary = body_config.get("default_spawn", {})
	var default_direction: Vector3 = direction_from_lat_lon(
		deg_to_rad(float(default_spawn.get("latitude_deg", 45.0))),
		deg_to_rad(float(default_spawn.get("longitude_deg", 25.0)))
	)
	prepare_surface_region(default_direction, false)
	initialized = true
	_log_info("earth_world_initialized", {
		"radius_m": planet_radius_m,
		"active_rules": pipeline.get_active_rule_ids(),
		"global_generation": global_profile,
		"local_generation": last_rebuild_summary,
	})
	return true


func _apply_config() -> void:
	planet_radius_m = float(body_config.get("radius_m", planet_radius_m))
	gravity_mps2 = float(body_config.get("gravity_mps2", gravity_mps2))
	gravitational_parameter_m3_s2 = GravityMathScript.resolve_gravitational_parameter(body_config)
	gravity_interior_model = String(body_config.get("interior_model", gravity_interior_model))
	var global_config: Dictionary = body_config.get("global", {})
	global_segments = int(global_config.get("segments", global_segments))
	global_rings = int(global_config.get("rings", global_rings))
	global_surface_offset_m = float(
		global_config.get("surface_offset_m", global_surface_offset_m)
	)
	var local_config: Dictionary = body_config.get("local", {})
	local_radius_m = float(local_config.get("radius_m", local_radius_m))
	local_rings = int(local_config.get("rings", local_rings))
	local_segments = int(local_config.get("segments", local_segments))
	local_recenter_distance_m = float(
		local_config.get("recenter_distance_m", local_recenter_distance_m)
	)
	local_max_visible_altitude_m = float(
		local_config.get("max_visible_altitude_m", local_max_visible_altitude_m)
	)


func _create_nodes() -> void:
	global_earth = MeshInstance3D.new()
	global_earth.name = "GlobalEarthLOD"
	global_earth.material_override = assets.get_surface_material(true)
	global_earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(global_earth)

	local_root = Node3D.new()
	local_root.name = "EarthLocalSurfaceRoot"
	add_child(local_root)

	local_surface = MeshInstance3D.new()
	local_surface.name = "EarthLocalTerrain"
	local_surface.material_override = assets.get_surface_material(false)
	local_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	local_root.add_child(local_surface)

	placement_system = EarthPlacementSystemScript.new()
	placement_system.name = "EarthPlacementSystem"
	local_root.add_child(placement_system)
	placement_system.setup(self, pipeline, assets)

	earth_light = DirectionalLight3D.new()
	earth_light.name = "EarthSun"
	earth_light.light_color = Color(1.0, 0.97, 0.90)
	earth_light.light_energy = 1.45
	earth_light.shadow_enabled = true
	earth_light.directional_shadow_max_distance = 18_000.0
	earth_light.rotation_degrees = Vector3(-42.0, -132.0, 0.0)
	earth_light.visible = false
	add_child(earth_light)


func prepare_surface_region(center_direction: Vector3, _include_collision: bool = false) -> void:
	if pipeline == null:
		return
	var started_usec: int = Time.get_ticks_usec()
	surface_center_direction = center_direction.normalized()
	surface_east = _make_east(surface_center_direction)
	surface_north = surface_east.cross(surface_center_direction).normalized()
	surface_anchor_world = get_surface_point(surface_center_direction)
	pipeline.begin_batch("local_earth_surface")
	local_surface.mesh = _build_local_mesh()
	var terrain_profile: Dictionary = pipeline.end_batch()
	var placement_summary: Dictionary = placement_system.regenerate(
		surface_center_direction,
		surface_east,
		surface_north,
		surface_anchor_world
	)
	_update_root_positions()
	_apply_lod_visibility()
	last_rebuild_summary = {
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"terrain": terrain_profile,
		"mesh": last_local_mesh_statistics.duplicate(true),
		"placement": placement_summary,
		"center_direction": [
			surface_center_direction.x,
			surface_center_direction.y,
			surface_center_direction.z,
		],
		"biome": get_biome_name_at(surface_center_direction),
	}
	earth_rebuilt.emit(last_rebuild_summary.duplicate(true))
	_log_info("earth_surface_rebuilt", last_rebuild_summary)
	if logger != null:
		logger.performance("earth_surface_rebuild", last_rebuild_summary)


func update_for_view(
	view_world_position: Vector3,
	new_render_origin_world: Vector3,
	_spectator_mode: bool,
	delta: float = 0.0
) -> void:
	if not initialized:
		return
	set_render_origin(new_render_origin_world)
	rebuild_cooldown_sec = maxf(0.0, rebuild_cooldown_sec - delta)
	var altitude: float = get_altitude(view_world_position)
	_update_lod_tier(altitude)
	if altitude > local_max_visible_altitude_m:
		return
	if view_world_position.length_squared() < 1.0:
		return
	var target_direction: Vector3 = view_world_position.normalized()
	var target_surface: Vector3 = get_surface_point(target_direction)
	var distance_from_anchor: float = (target_surface - surface_anchor_world).length()
	if distance_from_anchor > local_recenter_distance_m and rebuild_cooldown_sec <= 0.0:
		prepare_surface_region(target_direction, false)
		rebuild_cooldown_sec = 0.75


func set_render_origin(new_origin_world: Vector3) -> void:
	render_origin_world = new_origin_world
	_update_root_positions()


func set_primary_lighting_enabled(enabled: bool) -> void:
	if earth_light != null:
		earth_light.visible = enabled


func _update_root_positions() -> void:
	if global_earth != null:
		global_earth.position = -render_origin_world
	if local_root != null:
		local_root.position = surface_anchor_world - render_origin_world


func world_to_render(world_position: Vector3) -> Vector3:
	return world_position - render_origin_world


func render_to_world(render_position: Vector3) -> Vector3:
	return render_position + render_origin_world


func get_render_origin() -> Vector3:
	return render_origin_world


func get_surface_anchor() -> Vector3:
	return surface_anchor_world


func get_planet_radius() -> float:
	return planet_radius_m


func get_moon_radius() -> float:
	return planet_radius_m


func get_surface_height(direction_value: Vector3) -> float:
	if pipeline == null:
		return 0.0
	var state: Dictionary = pipeline.sample(direction_value.normalized(), 0)
	return float(state.get("elevation_m", 0.0))


func get_surface_point(direction_value: Vector3) -> Vector3:
	var direction: Vector3 = direction_value.normalized()
	return direction * (planet_radius_m + get_surface_height(direction))


func get_altitude(world_position: Vector3) -> float:
	if world_position.length_squared() < 1.0:
		return -planet_radius_m
	var direction: Vector3 = world_position.normalized()
	return world_position.length() - planet_radius_m - get_surface_height(direction)


func get_gravity_at_distance(distance_from_center: float) -> float:
	return GravityMathScript.acceleration_magnitude(
		distance_from_center,
		planet_radius_m,
		gravitational_parameter_m3_s2,
		gravity_interior_model
	)


func recenter_player(actor: CharacterBody3D) -> void:
	if actor == null:
		return
	var world_position: Vector3 = render_to_world(actor.global_position)
	var surface_distance: float = (
		get_surface_point(world_position.normalized()) - surface_anchor_world
	).length()
	if surface_distance <= local_recenter_distance_m:
		return
	prepare_surface_region(world_position.normalized(), true)
	set_render_origin(surface_anchor_world)
	actor.global_position = world_to_render(world_position)
	actor.reset_physics_interpolation()


func register_streaming_actor(_actor: CharacterBody3D) -> void:
	pass


func get_biome_name_at(direction: Vector3) -> String:
	if pipeline == null:
		return "unknown"
	var state: Dictionary = pipeline.sample(direction.normalized(), 0)
	return pipeline.biome_name(int(state.get("biome_code", -1)))


func get_surface_state(direction: Vector3, lod_level: int = 0) -> Dictionary:
	return pipeline.sample(direction.normalized(), lod_level) if pipeline != null else {}


func find_biome_direction(biome_name: String) -> Vector3:
	if cached_biome_directions.has(biome_name):
		return cached_biome_directions[biome_name]
	var target_code: int = _biome_code_from_name(biome_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(body_config.get("seed", 20260726)) + target_code * 10_007
	var best_direction: Vector3 = surface_center_direction
	var best_score: float = -INF
	for _attempt in range(5200):
		var candidate: Vector3 = _random_unit_direction(rng)
		var state: Dictionary = pipeline.sample(candidate, 1)
		var code: int = int(state.get("biome_code", -1))
		var score: float = 0.0
		if code == target_code:
			score += 10.0
		match biome_name:
			"forest":
				score += float(state.get("tree_density", 0.0)) * 3.0
			"grassland":
				score += float(state.get("grass_density", 0.0)) * 2.0
			"desert":
				score += float(state.get("aridity", 0.0)) * 2.0
			"tundra":
				score += float(state.get("polar_mask", 0.0)) * 2.0
			"alpine_snow":
				score += float(state.get("snow_mask", 0.0)) * 2.0
		if score > best_score:
			best_score = score
			best_direction = candidate
		if score > 12.3:
			break
	cached_biome_directions[biome_name] = best_direction
	return best_direction


func cycle_debug_view() -> String:
	debug_view = (debug_view + 1) % 4
	if assets != null:
		assets.set_surface_debug_mode(debug_view != 0)
	prepare_surface_region(surface_center_direction, false)
	return get_debug_view_name()


func get_debug_view_name() -> String:
	match debug_view:
		1:
			return "biome"
		2:
			return "elevation"
		3:
			return "ecology_density"
		_:
			return "final_surface"


func reload_rules() -> bool:
	var new_pipeline = EarthRulePipelineScript.new()
	if not new_pipeline.setup():
		_log_error("earth_rule_reload_failed", {
			"errors": new_pipeline.get_validation_errors(),
		})
		return false
	pipeline = new_pipeline
	placement_system.setup(self, pipeline, assets)
	assets.set_surface_debug_mode(debug_view != 0)
	pipeline.begin_batch("global_earth_reload")
	global_earth.mesh = _build_global_mesh()
	pipeline.end_batch()
	prepare_surface_region(surface_center_direction, false)
	cached_biome_directions.clear()
	return true


func get_runtime_summary() -> String:
	var placement: Dictionary = placement_system.get_summary() if placement_system != null else {}
	return (
		"Earth LOD=%s | biome=%s | relief=%.1f m | slope=%.1f deg | rules=%d | trees=%d+%d | grass=%d | rocks=%d"
		% [
			current_lod_tier,
			get_biome_name_at(surface_center_direction),
			float(last_local_mesh_statistics.get("relief_range_m", 0.0)),
			float(last_local_mesh_statistics.get("maximum_geometric_slope_deg", 0.0)),
			pipeline.get_active_rule_ids().size() if pipeline != null else 0,
			int(placement.get("near_trees", 0)),
			int(placement.get("billboard_trees", 0)),
			int(placement.get("grass", 0)),
			int(placement.get("rocks", 0)),
		]
	)


func create_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.earth_runtime.v1",
		"radius_m": planet_radius_m,
		"gravity_mps2": gravity_mps2,
		"gravitational_parameter_m3_s2": gravitational_parameter_m3_s2,
		"lod_tier": current_lod_tier,
		"debug_view": get_debug_view_name(),
		"active_rules": pipeline.get_active_rule_ids() if pipeline != null else [],
		"pipeline": pipeline.get_performance_snapshot() if pipeline != null else {},
		"last_rebuild": last_rebuild_summary.duplicate(true),
		"local_mesh_statistics": last_local_mesh_statistics.duplicate(true),
		"global_mesh_statistics": last_global_mesh_statistics.duplicate(true),
		"placement": placement_system.get_summary() if placement_system != null else {},
	}


func get_local_mesh_statistics() -> Dictionary:
	return last_local_mesh_statistics.duplicate(true)


func get_global_mesh_statistics() -> Dictionary:
	return last_global_mesh_statistics.duplicate(true)


func direction_from_lat_lon(latitude: float, longitude: float) -> Vector3:
	var horizontal: float = cos(latitude)
	return Vector3(
		horizontal * cos(longitude),
		sin(latitude),
		horizontal * sin(longitude)
	).normalized()


func _build_global_mesh() -> ArrayMesh:
	var statistics: Dictionary = _new_mesh_statistics("global")
	var vertices := PackedVector3Array()
	var directions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring_index in range(global_rings + 1):
		var ring_t: float = float(ring_index) / float(global_rings)
		var latitude: float = ring_t * PI
		var y_value: float = cos(latitude)
		var horizontal: float = sin(latitude)
		for segment_index in range(global_segments + 1):
			var segment_t: float = float(segment_index) / float(global_segments)
			var longitude: float = segment_t * TAU
			var direction := Vector3(
				horizontal * cos(longitude),
				y_value,
				horizontal * sin(longitude)
			).normalized()
			var state: Dictionary = pipeline.sample(direction, 2)
			_accumulate_mesh_statistics(statistics, state)
			var elevation: float = float(state.get("elevation_m", 0.0)) + global_surface_offset_m
			vertices.append(direction * (planet_radius_m + elevation))
			directions.append(direction)
			colors.append(_display_color(state))
			uvs.append(Vector2(segment_t, ring_t))
	for ring_index in range(global_rings):
		for segment_index in range(global_segments):
			var row: int = global_segments + 1
			var i0: int = ring_index * row + segment_index
			var i1: int = i0 + 1
			var i2: int = i0 + row
			var i3: int = i2 + 1
			indices.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))
	# Recompute and validate global normals from triangle winding so the visible
	# face is guaranteed to be oriented outward. This fixes the case where the
	# Earth shell shades like an inward-facing surface at global LOD.
	var normals: PackedVector3Array = _build_normals(vertices, directions, indices)
	last_global_mesh_statistics = _finalize_mesh_statistics(
		statistics,
		normals,
		directions
	)
	return _make_array_mesh(vertices, normals, colors, uvs, indices)


func _build_local_mesh() -> ArrayMesh:
	var statistics: Dictionary = _new_mesh_statistics("local")
	var vertices := PackedVector3Array()
	var directions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var center_state: Dictionary = pipeline.sample(surface_center_direction, 0)
	_accumulate_mesh_statistics(statistics, center_state)
	vertices.append(get_surface_point_from_state(surface_center_direction, center_state) - surface_anchor_world)
	directions.append(surface_center_direction)
	colors.append(_display_color(center_state))
	uvs.append(Vector2(0.5, 0.5))

	for ring_index in range(1, local_rings + 1):
		var ring_t: float = float(ring_index) / float(local_rings)
		var radius_m: float = local_radius_m * pow(ring_t, 1.55)
		for segment_index in range(local_segments):
			var angle: float = float(segment_index) / float(local_segments) * TAU
			var tangent_offset: Vector3 = (
				surface_east * cos(angle) + surface_north * sin(angle)
			) * radius_m
			var direction: Vector3 = (
				surface_center_direction + tangent_offset / planet_radius_m
			).normalized()
			var state: Dictionary = pipeline.sample(direction, 0)
			_accumulate_mesh_statistics(statistics, state)
			vertices.append(get_surface_point_from_state(direction, state) - surface_anchor_world)
			directions.append(direction)
			colors.append(_display_color(state))
			uvs.append(Vector2(
				0.5 + cos(angle) * ring_t * 0.5,
				0.5 + sin(angle) * ring_t * 0.5
			))

	for segment_index in range(local_segments):
		var current: int = 1 + segment_index
		var next: int = 1 + (segment_index + 1) % local_segments
		indices.append_array(PackedInt32Array([0, current, next]))
	for ring_index in range(1, local_rings):
		var current_start: int = 1 + (ring_index - 1) * local_segments
		var next_start: int = current_start + local_segments
		for segment_index in range(local_segments):
			var next_segment: int = (segment_index + 1) % local_segments
			var i0: int = current_start + segment_index
			var i1: int = current_start + next_segment
			var i2: int = next_start + segment_index
			var i3: int = next_start + next_segment
			indices.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))

	var normals: PackedVector3Array = _build_normals(vertices, directions, indices)
	last_local_mesh_statistics = _finalize_mesh_statistics(
		statistics,
		normals,
		directions
	)
	return _make_array_mesh(vertices, normals, colors, uvs, indices)


func get_surface_point_from_state(direction: Vector3, state: Dictionary) -> Vector3:
	return direction * (planet_radius_m + float(state.get("elevation_m", 0.0)))


func _new_mesh_statistics(label: String) -> Dictionary:
	return {
		"label": label,
		"sample_count": 0,
		"minimum_elevation_m": INF,
		"maximum_elevation_m": -INF,
		"elevation_sum_m": 0.0,
		"mountain_mask_sum": 0.0,
		"water_sample_count": 0,
		"snow_sample_count": 0,
		"biome_counts": {},
	}


func _accumulate_mesh_statistics(statistics: Dictionary, state: Dictionary) -> void:
	var elevation: float = float(state.get("elevation_m", 0.0))
	statistics["sample_count"] = int(statistics["sample_count"]) + 1
	statistics["minimum_elevation_m"] = minf(
		float(statistics["minimum_elevation_m"]),
		elevation
	)
	statistics["maximum_elevation_m"] = maxf(
		float(statistics["maximum_elevation_m"]),
		elevation
	)
	statistics["elevation_sum_m"] = float(statistics["elevation_sum_m"]) + elevation
	statistics["mountain_mask_sum"] = (
		float(statistics["mountain_mask_sum"])
		+ float(state.get("mountain_mask", 0.0))
	)
	if int(state.get("water_kind", 0)) != 0:
		statistics["water_sample_count"] = int(statistics["water_sample_count"]) + 1
	if float(state.get("snow_mask", 0.0)) > 0.18:
		statistics["snow_sample_count"] = int(statistics["snow_sample_count"]) + 1
	var biome_key: String = str(int(state.get("biome_code", -1)))
	var biome_counts: Dictionary = statistics["biome_counts"]
	biome_counts[biome_key] = int(biome_counts.get(biome_key, 0)) + 1


func _finalize_mesh_statistics(
	statistics: Dictionary,
	normals: PackedVector3Array,
	directions: PackedVector3Array
) -> Dictionary:
	var sample_count: int = maxi(1, int(statistics.get("sample_count", 0)))
	var minimum_elevation: float = float(statistics.get("minimum_elevation_m", 0.0))
	var maximum_elevation: float = float(statistics.get("maximum_elevation_m", 0.0))
	statistics["average_elevation_m"] = float(statistics.get("elevation_sum_m", 0.0)) / sample_count
	statistics["relief_range_m"] = maximum_elevation - minimum_elevation
	statistics["average_mountain_mask"] = float(
		statistics.get("mountain_mask_sum", 0.0)
	) / sample_count
	statistics["water_fraction"] = float(
		statistics.get("water_sample_count", 0)
	) / sample_count
	statistics["snow_fraction"] = float(
		statistics.get("snow_sample_count", 0)
	) / sample_count
	var slope_sum: float = 0.0
	var maximum_slope: float = 0.0
	var slope_count: int = mini(normals.size(), directions.size())
	for index in range(slope_count):
		var dot_value: float = clampf(normals[index].dot(directions[index]), -1.0, 1.0)
		var slope_deg: float = rad_to_deg(acos(dot_value))
		slope_sum += slope_deg
		maximum_slope = maxf(maximum_slope, slope_deg)
	statistics["average_geometric_slope_deg"] = slope_sum / maxi(1, slope_count)
	statistics["maximum_geometric_slope_deg"] = maximum_slope
	statistics.erase("elevation_sum_m")
	statistics.erase("mountain_mask_sum")
	return statistics


func _build_normals(
	vertices: PackedVector3Array,
	directions: PackedVector3Array,
	indices: PackedInt32Array
) -> PackedVector3Array:
	var accumulated: Array[Vector3] = []
	accumulated.resize(vertices.size())
	for index in range(accumulated.size()):
		accumulated[index] = Vector3.ZERO
	for triangle_start in range(0, indices.size(), 3):
		var i0: int = indices[triangle_start]
		var i1: int = indices[triangle_start + 1]
		var i2: int = indices[triangle_start + 2]
		var normal: Vector3 = (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
		# Keep the authored triangle winding untouched for backface culling, but
		# force the lighting normal to point away from the planet center.
		if normal.dot(directions[i0]) < 0.0:
			normal = -normal
		accumulated[i0] += normal
		accumulated[i1] += normal
		accumulated[i2] += normal
	var result := PackedVector3Array()
	for vertex_index in range(accumulated.size()):
		var normal: Vector3 = accumulated[vertex_index].normalized()
		if normal.length_squared() < 0.5:
			normal = directions[vertex_index]
		result.append(normal)
	return result


func _make_array_mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _display_color(state: Dictionary) -> Color:
	if debug_view == 1:
		match int(state.get("biome_code", -1)):
			0:
				return Color(0.02, 0.16, 0.48)
			1:
				return Color(0.02, 0.55, 0.90)
			2:
				return Color(0.95, 0.62, 0.08)
			3:
				return Color(0.68, 0.88, 1.0)
			4:
				return Color(0.02, 0.48, 0.06)
			5:
				return Color(0.52, 0.78, 0.08)
			6:
				return Color(1.0, 1.0, 1.0)
			7:
				return Color(0.40, 0.36, 0.34)
	if debug_view == 2:
		var elevation: float = float(state.get("elevation_m", 0.0))
		var normalized: float = clampf((elevation + 6500.0) / 14_000.0, 0.0, 1.0)
		return Color(normalized, normalized, normalized)
	if debug_view == 3:
		return Color(
			float(state.get("tree_density", 0.0)),
			float(state.get("grass_density", 0.0)),
			float(state.get("rock_density", 0.0))
		)
	return state.get("surface_color", Color.MAGENTA)


func _update_lod_tier(altitude: float) -> void:
	var tiers = lod_config.get("tiers", [])
	var selected: Dictionary = {}
	for tier_value in tiers:
		if not tier_value is Dictionary:
			continue
		var tier: Dictionary = tier_value
		if altitude <= float(tier.get("max_altitude_m", INF)):
			selected = tier
			break
	if selected.is_empty():
		selected = {"id": "global", "terrain": false}
	var selected_id: String = String(selected.get("id", "global"))
	if selected_id == current_lod_tier:
		return
	current_lod_tier = selected_id
	_apply_lod_visibility(selected)


func _apply_lod_visibility(flags: Dictionary = {}) -> void:
	var effective_flags: Dictionary = flags
	if effective_flags.is_empty():
		for tier_value in lod_config.get("tiers", []):
			if tier_value is Dictionary and String(tier_value.get("id", "")) == current_lod_tier:
				effective_flags = tier_value
				break
	global_earth.visible = true
	local_root.visible = bool(effective_flags.get("terrain", current_lod_tier != "global"))
	if placement_system != null:
		placement_system.apply_lod_flags(effective_flags)


func _make_east(direction: Vector3) -> Vector3:
	var east: Vector3 = Vector3.UP.cross(direction)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(direction)
	return east.normalized()


func _random_unit_direction(rng: RandomNumberGenerator) -> Vector3:
	var y_value: float = rng.randf_range(-1.0, 1.0)
	var angle: float = rng.randf_range(0.0, TAU)
	var horizontal: float = sqrt(maxf(0.0, 1.0 - y_value * y_value))
	return Vector3(
		horizontal * cos(angle),
		y_value,
		horizontal * sin(angle)
	).normalized()


func _biome_code_from_name(biome_name: String) -> int:
	match biome_name:
		"ocean":
			return 0
		"river_or_lake":
			return 1
		"desert":
			return 2
		"tundra":
			return 3
		"forest":
			return 4
		"grassland":
			return 5
		"alpine_snow":
			return 6
		"rock":
			return 7
		_:
			return 5


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _log_info(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.info("earth", event_name, data)


func _log_error(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.error("earth", event_name, data)
