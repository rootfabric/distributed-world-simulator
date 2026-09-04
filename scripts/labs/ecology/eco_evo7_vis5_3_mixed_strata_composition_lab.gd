extends Node3D

## ECO.EVO7 VIS5.3 — Mixed-Strata Composition Lab.
##
## Presentation-only composition of one real ProceduralEarth surface region:
##   - canonical ECO.EVO7 evolved macro plants through the accepted VIS4 PH5 path;
##   - VIS5.2 NONCANONICAL_SCENERY ground cover;
##   - deterministic TERRAIN_SCENERY rocks.
##
## The built-in ProceduralEarth placement system is explicitly hidden in this
## lab so its procedural trees cannot visually duplicate the canonical PH5
## macro-plant population.

const EarthWorldScript = preload("res://scripts/world/earth/procedural_earth_world.gd")
const EarthAssetLibraryScript = preload("res://scripts/world/earth/earth_asset_library.gd")
const LoggerScript = preload("res://scripts/diagnostics/lunar_logger.gd")
const WorkbenchScript = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const Vis2AdapterScript = preload("res://scripts/labs/ecology/eco_evo7_vis2_phenotype_render_adapter.gd")
const Vis4AdapterScript = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")
const PresentationScript = preload("res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd")
const SurfaceFrameAdapter = preload("res://scripts/labs/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter.gd")
const GroundCoverBridge = preload("res://scripts/labs/ecology/eco_evo7_vis5_2_noncanonical_ground_cover_bridge.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis5_mixed_strata_composition_lab.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS5.3.R1"
const PRESENTATION_ONLY := true
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false
const MACRO_TRUTH_STATUS := "CANONICAL_ECO_VIS4_PH5"
const GROUND_COVER_TRUTH_STATUS := "NONCANONICAL_SCENERY"
const ROCK_TRUTH_STATUS := "TERRAIN_SCENERY"
const DEFAULT_VISUAL_WORLD_SEED := 360055
const DEFAULT_PRESENTATION_SEED := 20260953
const VEGETATION_CONFIG_PATH := "res://config/generation/earth_vegetation.json"

const DEFAULT_PROFILE := {
	"world_seed": DEFAULT_VISUAL_WORLD_SEED,
	"presentation_seed": DEFAULT_PRESENTATION_SEED,
	"ground_cover_radius_m": 280.0,
	"ground_cover_max_instances": 4500,
	"ground_cover_attempts_multiplier": 4,
	"rock_radius_m": 320.0,
	"max_rocks": 180,
	"rock_attempts_multiplier": 12,
	"maximum_rock_slope_deg": 62.0,
	"terrain_probe_radius_m": 220.0,
	"surface_sample_distance_m": 2.0,
}

@export var auto_initialize := true

var ready_success := false
var logger = null
var earth_world = null
var workbench = null
var vis2_adapter = null
var vis4_adapter = null
var presentation = null
var assets = null
var ground_cover = null
var camera: Camera3D = null
var world_environment: WorldEnvironment = null

var profile: Dictionary = {}
var published_snapshot: Dictionary = {}
var published_ecology: Dictionary = {}
var published_descriptors: Dictionary = {}
var published_morphology: Dictionary = {}
var published_reconstruction: Dictionary = {}
var ground_cover_summary: Dictionary = {}
var rock_summary: Dictionary = {}
var terrain_summary: Dictionary = {}
var composition_summary: Dictionary = {}
var rock_instances: Array[MultiMeshInstance3D] = []
var _last_presentation_seed := DEFAULT_PRESENTATION_SEED


func _ready() -> void:
	name = "EcoEvo7Vis53MixedStrataCompositionLab"
	if auto_initialize:
		initialize_runtime()


func initialize_runtime(profile_override: Dictionary = {}) -> bool:
	if ready_success:
		return true
	profile = DEFAULT_PROFILE.duplicate(true)
	for key in profile_override.keys():
		if not profile.has(key):
			return false
		profile[key] = profile_override[key]
	if not _validate_profile(profile):
		return false

	logger = LoggerScript.new()
	logger.name = "Vis53Logger"
	add_child(logger)
	logger.setup(false)

	earth_world = EarthWorldScript.new()
	earth_world.name = "Vis53ProceduralEarthWorld"
	add_child(earth_world)
	if not earth_world.setup(logger):
		return false
	earth_world.set_primary_lighting_enabled(true)
	_suppress_builtin_earth_placement()

	workbench = WorkbenchScript.new()
	var requested_spec := WorkbenchScript.default_spec()
	requested_spec["world_seed"] = int(profile["world_seed"])
	if not workbench.setup(earth_world, requested_spec):
		return false
	vis2_adapter = Vis2AdapterScript.new()
	vis4_adapter = Vis4AdapterScript.new()

	presentation = PresentationScript.new()
	presentation.name = "Vis53CanonicalMacroPlants"
	add_child(presentation)
	if not presentation.setup(earth_world, workbench.get_patch()):
		return false

	var patch_center: Vector3 = presentation.get_patch_center_direction()
	earth_world.prepare_surface_region(patch_center, true)
	earth_world.set_render_origin(earth_world.get_surface_anchor())
	_hide_builtin_earth_placement()
	_configure_local_lighting(patch_center)

	if not _publish_founder_snapshot():
		return false
	if not advance_to_live_generation():
		return false

	assets = EarthAssetLibraryScript.new()
	assets.setup()
	ground_cover = GroundCoverBridge.new()
	ground_cover.name = "Vis53GroundCover"
	add_child(ground_cover)
	if not ground_cover.setup(earth_world, assets, _ground_cover_config()):
		return false

	_last_presentation_seed = int(profile["presentation_seed"])
	if not rebuild_surface_scenery(_last_presentation_seed):
		return false
	_configure_camera(patch_center)
	ready_success = validate_summary(composition_summary)
	return ready_success


func advance_to_live_generation() -> bool:
	if workbench == null or presentation == null:
		return false
	var result: Dictionary = workbench.advance_generations(1)
	if result.is_empty():
		return false
	return _publish_live_snapshot(result)


func rebuild_surface_scenery(presentation_seed: int = -1) -> bool:
	if earth_world == null or presentation == null or ground_cover == null or assets == null:
		return false
	if presentation_seed < 0:
		presentation_seed = int(profile["presentation_seed"])
	_last_presentation_seed = presentation_seed
	_hide_builtin_earth_placement()
	var patch_center: Vector3 = presentation.get_patch_center_direction()
	var render_origin: Vector3 = earth_world.get_render_origin()
	ground_cover_summary = ground_cover.regenerate(
		patch_center,
		render_origin,
		presentation_seed,
		0
	)
	if ground_cover_summary.is_empty() or not GroundCoverBridge.validate_summary(ground_cover_summary):
		return false
	rock_summary = _regenerate_rocks(patch_center, render_origin, presentation_seed)
	if rock_summary.is_empty():
		return false
	terrain_summary = _sample_terrain(patch_center)
	if terrain_summary.is_empty():
		return false
	_refresh_composition_summary()
	return true


func get_summary() -> Dictionary:
	return composition_summary.duplicate(true)


func get_earth_world():
	return earth_world


func get_workbench():
	return workbench


func get_presentation():
	return presentation


func get_ground_cover_bridge():
	return ground_cover


func get_rock_instances() -> Array[MultiMeshInstance3D]:
	return rock_instances.duplicate()


func get_published_snapshot() -> Dictionary:
	return published_snapshot.duplicate(true)


func get_published_morphology_descriptors() -> Dictionary:
	return published_morphology.duplicate(true)


func get_published_reconstruction_evidence() -> Dictionary:
	return published_reconstruction.duplicate(true)


func is_mixed_ready() -> bool:
	return ready_success and validate_summary(composition_summary)


static func validate_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	if String(summary.get("schema", "")) != SCHEMA:
		return false
	if String(summary.get("version", "")) != VERSION:
		return false
	if String(summary.get("revision", "")) != REVISION:
		return false
	if not bool(summary.get("presentation_only", false)):
		return false
	if bool(summary.get("network_authority", true)):
		return false
	if bool(summary.get("persistence_authority", true)):
		return false
	if String(summary.get("terrain_source", "")) != "ProceduralEarthWorld":
		return false
	if not bool(summary.get("terrain_local_surface_present", false)):
		return false
	if float(summary.get("terrain_relief_range_m", 0.0)) <= 0.01:
		return false
	if String(summary.get("macro_truth_status", "")) != MACRO_TRUTH_STATUS:
		return false
	if not bool(summary.get("macro_ph5_active", false)):
		return false
	if int(summary.get("macro_record_count", 0)) <= 0:
		return false
	if int(summary.get("macro_visible_individual_count", 0)) <= 0:
		return false
	if String(summary.get("source_ecology_hash", "")).length() != 64:
		return false
	if String(summary.get("macro_bridge_hash", "")).length() != 64:
		return false
	if String(summary.get("ground_cover_truth_status", "")) != GROUND_COVER_TRUTH_STATUS:
		return false
	if int(summary.get("ground_cover_instances", 0)) <= 0:
		return false
	if String(summary.get("ground_cover_hash", "")).length() != 64:
		return false
	if String(summary.get("rock_truth_status", "")) != ROCK_TRUTH_STATUS:
		return false
	if int(summary.get("rock_instances", 0)) <= 0:
		return false
	if String(summary.get("rock_hash", "")).length() != 64:
		return false
	if not bool(summary.get("builtin_earth_placement_hidden", false)):
		return false
	for forbidden_true in [
		"procedural_trees_visible",
		"canonical_macro_source_replaced",
		"ecology_individuals_created_by_scenery",
		"ecology_state_hash_changed_by_scenery",
		"descriptor_v2_changed_by_scenery",
		"terrain_written_by_scenery",
	]:
		if bool(summary.get(forbidden_true, true)):
			return false
	return String(summary.get("composition_hash", "")).length() == 64


func _publish_founder_snapshot() -> bool:
	var ecology_snapshot: Dictionary = workbench.get_ecology_snapshot()
	var descriptors: Dictionary = vis2_adapter.build(ecology_snapshot)
	if descriptors.is_empty():
		return false
	if not presentation.apply_snapshot(descriptors, workbench.get_classification()):
		return false
	published_snapshot = workbench.get_workbench_snapshot().duplicate(true)
	published_ecology = ecology_snapshot.duplicate(true)
	published_descriptors = descriptors.duplicate(true)
	published_morphology.clear()
	published_reconstruction.clear()
	return true


func _publish_live_snapshot(workbench_snapshot: Dictionary) -> bool:
	var ecology_snapshot: Dictionary = workbench.get_ecology_snapshot()
	var descriptors: Dictionary = vis2_adapter.build(ecology_snapshot)
	var morphology: Dictionary = workbench.get_morphology_evidence()
	var reconstruction: Dictionary = workbench.get_graph_reconstruction_evidence()
	if descriptors.is_empty() or morphology.is_empty() or reconstruction.is_empty():
		return false
	if not workbench.validate_morphology_evidence(morphology):
		return false
	if not workbench.validate_graph_reconstruction_evidence(reconstruction):
		return false
	var morphology_descriptors: Dictionary = vis4_adapter.build(ecology_snapshot, morphology)
	if morphology_descriptors.is_empty():
		return false
	if not presentation.apply_snapshot(
		descriptors,
		workbench.get_classification(),
		morphology_descriptors,
		reconstruction
	):
		return false
	published_snapshot = workbench_snapshot.duplicate(true)
	published_ecology = ecology_snapshot.duplicate(true)
	published_descriptors = descriptors.duplicate(true)
	published_morphology = morphology_descriptors.duplicate(true)
	published_reconstruction = reconstruction.duplicate(true)
	var center_world: Vector3 = earth_world.get_surface_point(presentation.get_patch_center_direction())
	var up: Vector3 = presentation.get_patch_center_direction().normalized()
	presentation.set_view_world_position(center_world + up * 22.0)
	return true


func _ground_cover_config() -> Dictionary:
	var value := _load_json(VEGETATION_CONFIG_PATH)
	if value.is_empty():
		return {}
	value["grass_radius_m"] = float(profile["ground_cover_radius_m"])
	value["max_grass_instances"] = int(profile["ground_cover_max_instances"])
	value["grass_attempts_multiplier"] = int(profile["ground_cover_attempts_multiplier"])
	value["surface_sample_distance_m"] = float(profile["surface_sample_distance_m"])
	value["snow_grass_cutoff"] = float(value.get("snow_grass_cutoff", 0.16))
	return value


func _suppress_builtin_earth_placement() -> void:
	if earth_world == null or earth_world.placement_system == null:
		return
	var placement = earth_world.placement_system
	placement.visible = false
	# VIS5.3 owns the composition strata explicitly. Suppress the legacy
	# presentation counts before every local rebuild so procedural trees, grass
	# and rocks are not even materialized behind the hidden subtree.
	placement.config["max_near_trees"] = 0
	placement.config["max_billboard_trees"] = 0
	placement.config["max_grass_instances"] = 0
	placement.config["max_rocks"] = 0


func _hide_builtin_earth_placement() -> void:
	_suppress_builtin_earth_placement()


func _regenerate_rocks(
	anchor_direction_value: Vector3,
	render_origin: Vector3,
	presentation_seed: int
) -> Dictionary:
	_clear_rocks()
	var anchor_direction := anchor_direction_value.normalized()
	var tangent := _up_basis(anchor_direction)
	var radius_m := float(profile["rock_radius_m"])
	var maximum := int(profile["max_rocks"])
	var attempts_multiplier := int(profile["rock_attempts_multiplier"])
	var max_slope_deg := float(profile["maximum_rock_slope_deg"])
	var sample_distance_m := float(profile["surface_sample_distance_m"])
	var rng := RandomNumberGenerator.new()
	var seed := _surface_seed(anchor_direction, presentation_seed ^ 0x52A91)
	rng.seed = seed
	var buckets: Array = [[], [], []]
	var accepted := 0
	var rejected_density := 0
	var rejected_water := 0
	var rejected_slope := 0
	var invalid_frame := 0
	var min_normal_alignment := 1.0

	for _attempt in range(maximum * attempts_multiplier):
		if accepted >= maximum:
			break
		var offset := _random_disk(rng, radius_m)
		var direction := _offset_direction(
			anchor_direction,
			tangent.x,
			tangent.z,
			offset
		)
		var state_value = earth_world.get_surface_state(direction, 0)
		if not state_value is Dictionary:
			invalid_frame += 1
			continue
		var state: Dictionary = state_value
		var density := clampf(float(state.get("rock_density", 0.0)), 0.0, 1.0)
		if density <= 0.0 or rng.randf() > density:
			rejected_density += 1
			continue
		if int(state.get("water_kind", 0)) != 0:
			rejected_water += 1
			continue
		var frame := SurfaceFrameAdapter.build(
			earth_world,
			direction,
			sample_distance_m,
			0
		)
		if frame.is_empty() or not SurfaceFrameAdapter.validate(frame):
			invalid_frame += 1
			continue
		if float(frame.get("slope_deg", 90.0)) > max_slope_deg:
			rejected_slope += 1
			continue
		var variant := rng.randi_range(0, 2)
		var base_scale := rng.randf_range(0.35, 2.2)
		var scale_value := Vector3(
			base_scale * rng.randf_range(0.65, 1.35),
			base_scale * rng.randf_range(0.45, 0.95),
			base_scale * rng.randf_range(0.65, 1.35)
		)
		var transform_value := _scenery_transform(
			frame,
			render_origin,
			rng.randf_range(0.0, TAU),
			scale_value
		)
		var normal := Vector3(frame.get("terrain_normal", Vector3.UP)).normalized()
		min_normal_alignment = minf(
			min_normal_alignment,
			transform_value.basis.y.normalized().dot(normal)
		)
		buckets[variant].append(transform_value)
		accepted += 1

	rock_instances = _create_rock_instances(buckets)
	return {
		"truth_status": ROCK_TRUTH_STATUS,
		"presentation_only": true,
		"seed": seed,
		"rock_instances": accepted,
		"bucket_counts": [buckets[0].size(), buckets[1].size(), buckets[2].size()],
		"rejected_density": rejected_density,
		"rejected_water": rejected_water,
		"rejected_slope": rejected_slope,
		"invalid_surface_frame": invalid_frame,
		"min_normal_alignment": min_normal_alignment,
		"procedural_tree_path_used": false,
		"rock_hash": _rock_hash(seed, buckets),
	}


func _create_rock_instances(buckets: Array) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for variant in range(buckets.size()):
		var transforms: Array = buckets[variant]
		if transforms.is_empty():
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = "Vis53TerrainRocks_%d" % variant
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = assets.get_rock_mesh(variant)
		multi_mesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multi_mesh.set_instance_transform(index, transforms[index])
		instance.multimesh = multi_mesh
		instance.material_override = assets.get_rock_material(variant)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(instance)
		result.append(instance)
	return result


func _sample_terrain(anchor_direction: Vector3) -> Dictionary:
	var tangent := _up_basis(anchor_direction.normalized())
	var radius_m := float(profile["terrain_probe_radius_m"])
	var offsets := [
		Vector2.ZERO,
		Vector2(radius_m, 0.0),
		Vector2(-radius_m, 0.0),
		Vector2(0.0, radius_m),
		Vector2(0.0, -radius_m),
		Vector2(radius_m * 0.7, radius_m * 0.7),
		Vector2(-radius_m * 0.7, radius_m * 0.7),
		Vector2(radius_m * 0.7, -radius_m * 0.7),
		Vector2(-radius_m * 0.7, -radius_m * 0.7),
	]
	var min_elevation := INF
	var max_elevation := -INF
	var max_slope := 0.0
	var valid_samples := 0
	var grass_min := INF
	var grass_max := -INF
	var rock_min := INF
	var rock_max := -INF
	for offset in offsets:
		var direction := _offset_direction(
			anchor_direction.normalized(),
			tangent.x,
			tangent.z,
			Vector2(offset)
		)
		var frame := SurfaceFrameAdapter.build(
			earth_world,
			direction,
			float(profile["surface_sample_distance_m"]),
			0
		)
		if frame.is_empty() or not SurfaceFrameAdapter.validate(frame):
			continue
		var state: Dictionary = frame.get("surface_state", {})
		var elevation := float(frame.get("elevation_m", 0.0))
		min_elevation = minf(min_elevation, elevation)
		max_elevation = maxf(max_elevation, elevation)
		max_slope = maxf(max_slope, float(frame.get("slope_deg", 0.0)))
		grass_min = minf(grass_min, float(state.get("grass_density", 0.0)))
		grass_max = maxf(grass_max, float(state.get("grass_density", 0.0)))
		rock_min = minf(rock_min, float(state.get("rock_density", 0.0)))
		rock_max = maxf(rock_max, float(state.get("rock_density", 0.0)))
		valid_samples += 1
	if valid_samples == 0:
		return {}
	return {
		"sample_count": valid_samples,
		"minimum_elevation_m": min_elevation,
		"maximum_elevation_m": max_elevation,
		"relief_range_m": max_elevation - min_elevation,
		"maximum_geometric_slope_deg": max_slope,
		"grass_density_min": grass_min,
		"grass_density_max": grass_max,
		"rock_density_min": rock_min,
		"rock_density_max": rock_max,
	}


func _refresh_composition_summary() -> void:
	var contract: Dictionary = presentation.get_contract() if presentation != null else {}
	var ph5: Dictionary = contract.get("ph5", {})
	var ecology_hash := String(published_snapshot.get("ecology_state_hash", ""))
	var builtin_hidden: bool = (
		earth_world != null
		and earth_world.placement_system != null
		and not earth_world.placement_system.visible
	)
	var local_surface_present := (
		earth_world != null
		and earth_world.local_surface != null
		and earth_world.local_surface.mesh != null
	)
	composition_summary = {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"world_seed": int(profile.get("world_seed", -1)),
		"presentation_seed": _last_presentation_seed,
		"terrain_source": "ProceduralEarthWorld",
		"terrain_local_surface_present": local_surface_present,
		"terrain_sample_count": int(terrain_summary.get("sample_count", 0)),
		"terrain_minimum_elevation_m": float(terrain_summary.get("minimum_elevation_m", 0.0)),
		"terrain_maximum_elevation_m": float(terrain_summary.get("maximum_elevation_m", 0.0)),
		"terrain_relief_range_m": float(terrain_summary.get("relief_range_m", 0.0)),
		"terrain_maximum_geometric_slope_deg": float(terrain_summary.get("maximum_geometric_slope_deg", 0.0)),
		"macro_truth_status": MACRO_TRUTH_STATUS,
		"macro_source": "VIS4 PH5 only",
		"macro_ph5_active": bool(contract.get("ph5_active", false)),
		"macro_record_count": int(ph5.get("record_count", 0)),
		"macro_visible_individual_count": int(ph5.get("visible_individual_count", 0)),
		"macro_bridge_hash": String(ph5.get("source_bridge_hash", "")),
		"source_ecology_hash": ecology_hash,
		"ground_cover_truth_status": String(ground_cover_summary.get("truth_status", "")),
		"ground_cover_instances": int(ground_cover_summary.get("grass_instances", 0)),
		"ground_cover_hash": String(ground_cover_summary.get("generation_hash", "")),
		"ground_cover_min_normal_alignment": float(ground_cover_summary.get("min_normal_alignment", 0.0)),
		"rock_truth_status": String(rock_summary.get("truth_status", "")),
		"rock_instances": int(rock_summary.get("rock_instances", 0)),
		"rock_hash": String(rock_summary.get("rock_hash", "")),
		"rock_min_normal_alignment": float(rock_summary.get("min_normal_alignment", 0.0)),
		"builtin_earth_placement_hidden": builtin_hidden,
		"procedural_trees_visible": false,
		"canonical_macro_source_replaced": false,
		"ecology_individuals_created_by_scenery": false,
		"ecology_state_hash_changed_by_scenery": false,
		"descriptor_v2_changed_by_scenery": false,
		"terrain_written_by_scenery": false,
		"render_origin_world": earth_world.get_render_origin() if earth_world != null else Vector3.ZERO,
	}
	composition_summary["composition_hash"] = _composition_hash(composition_summary)


func _configure_local_lighting(anchor_direction: Vector3) -> void:
	if earth_world == null or earth_world.earth_light == null:
		return
	var up := anchor_direction.normalized()
	var tilt_axis := Vector3.UP.cross(up)
	if tilt_axis.length_squared() < 0.000001:
		tilt_axis = Vector3.RIGHT.cross(up)
	tilt_axis = tilt_axis.normalized()
	var sun_direction := up.rotated(tilt_axis, deg_to_rad(32.0)).normalized()
	earth_world.earth_light.look_at_from_position(
		sun_direction * 1000000.0,
		Vector3.ZERO,
		up
	)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.20, 0.38, 0.72)
	sky_material.sky_horizon_color = Color(0.66, 0.76, 0.87)
	sky_material.ground_bottom_color = Color(0.10, 0.11, 0.12)
	sky_material.ground_horizon_color = Color(0.50, 0.57, 0.64)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.56, 0.63, 0.72)
	environment.ambient_light_energy = 0.75
	world_environment = WorldEnvironment.new()
	world_environment.name = "Vis53WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


func _configure_camera(anchor_direction: Vector3) -> void:
	if earth_world == null:
		return
	var up := anchor_direction.normalized()
	var tangent := _up_basis(up)
	var center_world: Vector3 = earth_world.get_surface_point(up)
	var center_render: Vector3 = center_world - earth_world.get_render_origin()
	camera = Camera3D.new()
	camera.name = "Vis53CompositionCamera"
	camera.fov = 67.0
	add_child(camera)
	camera.position = center_render + up * 70.0 + tangent.x * 105.0 + tangent.z * 95.0
	camera.look_at(center_render + up * 10.0, up)
	camera.current = true


func _clear_rocks() -> void:
	for instance in rock_instances:
		if instance != null and is_instance_valid(instance):
			remove_child(instance)
			instance.free()
	rock_instances.clear()


func _scenery_transform(
	frame: Dictionary,
	render_origin: Vector3,
	yaw: float,
	scale_value: Vector3
) -> Transform3D:
	var terrain_basis := Basis(frame.get("terrain_basis", Basis.IDENTITY))
	var basis := terrain_basis * Basis(Vector3.UP, yaw) * Basis.from_scale(scale_value)
	var position := Vector3(frame.get("surface_point_world", Vector3.ZERO)) - render_origin
	return Transform3D(basis, position)


func _surface_seed(direction: Vector3, presentation_seed: int) -> int:
	var q := Vector3i(
		roundi(direction.x * 10000.0),
		roundi(direction.y * 10000.0),
		roundi(direction.z * 10000.0)
	)
	var value := presentation_seed
	value ^= q.x * 73856093
	value ^= q.y * 19349663
	value ^= q.z * 83492791
	return absi(value)


func _offset_direction(
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	offset: Vector2
) -> Vector3:
	var radius := float(earth_world.get_planet_radius())
	return (
		anchor_direction
		+ east * (offset.x / radius)
		+ north * (offset.y / radius)
	).normalized()


static func _random_disk(rng: RandomNumberGenerator, radius: float) -> Vector2:
	var distance := sqrt(rng.randf()) * radius
	var angle := rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle)) * distance


static func _up_basis(up: Vector3) -> Basis:
	var helper := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _rock_hash(seed: int, buckets: Array) -> String:
	var tokens := PackedStringArray([ROCK_TRUTH_STATUS, str(seed)])
	for variant in range(buckets.size()):
		tokens.append(str(variant))
		var transforms: Array = buckets[variant]
		for transform_value in transforms:
			tokens.append(_transform_token(Transform3D(transform_value)))
	return "|".join(tokens).sha256_text()


static func _composition_hash(summary: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		str(int(summary.get("world_seed", -1))),
		str(int(summary.get("presentation_seed", -1))),
		String(summary.get("source_ecology_hash", "")),
		String(summary.get("macro_bridge_hash", "")),
		String(summary.get("ground_cover_hash", "")),
		String(summary.get("rock_hash", "")),
		"%.6f" % float(summary.get("terrain_relief_range_m", 0.0)),
	])).sha256_text()


static func _transform_token(value: Transform3D) -> String:
	return (
		"%.6f,%.6f,%.6f|%.6f,%.6f,%.6f|"
		+ "%.6f,%.6f,%.6f|%.6f,%.6f,%.6f"
	) % [
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z,
	]


static func _validate_profile(value: Dictionary) -> bool:
	if int(value.get("world_seed", 0)) <= 0:
		return false
	if int(value.get("presentation_seed", 0)) <= 0:
		return false
	if float(value.get("ground_cover_radius_m", 0.0)) <= 0.0:
		return false
	if int(value.get("ground_cover_max_instances", 0)) <= 0:
		return false
	if int(value.get("ground_cover_attempts_multiplier", 0)) < 1:
		return false
	if float(value.get("rock_radius_m", 0.0)) <= 0.0:
		return false
	if int(value.get("max_rocks", 0)) <= 0:
		return false
	if int(value.get("rock_attempts_multiplier", 0)) < 1:
		return false
	var slope := float(value.get("maximum_rock_slope_deg", -1.0))
	if not is_finite(slope) or slope < 0.0 or slope > 90.0:
		return false
	if float(value.get("terrain_probe_radius_m", 0.0)) <= 0.0:
		return false
	var sample_distance := float(value.get("surface_sample_distance_m", 0.0))
	return (
		is_finite(sample_distance)
		and sample_distance >= SurfaceFrameAdapter.MIN_SAMPLE_DISTANCE_M
		and sample_distance <= SurfaceFrameAdapter.MAX_SAMPLE_DISTANCE_M
	)


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
