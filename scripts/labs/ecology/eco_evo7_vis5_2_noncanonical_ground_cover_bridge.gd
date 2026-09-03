extends Node3D

## ECO.EVO7 VIS5.2 — presentation-only dense ground-cover bridge.
##
## Decorative grass only. This bridge consumes canonical terrain surface data,
## but never creates ecology individuals and has no population, fitness,
## mutation, generation, Descriptor V2, or ecology-state authority.

const SurfaceFrameAdapter = preload("res://scripts/labs/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis5_noncanonical_ground_cover_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS5.2.R1"
const TRUTH_STATUS := "NONCANONICAL_SCENERY"
const PRESENTATION_ONLY := true
const DEFAULT_CONFIG_PATH := "res://config/generation/earth_vegetation.json"
const DEFAULT_PRESENTATION_SEED := 20260903
const DEFAULT_SAMPLE_DISTANCE_M := 2.0
const MAX_ALLOWED_INSTANCES := 50000

var earth_world
var assets
var config: Dictionary = {}
var grass_types: Array = []
var grass_instances: Array[MultiMeshInstance3D] = []
var _grass_meshes: Dictionary = {}
var _grass_materials: Dictionary = {}
var generation_summary: Dictionary = {}
var _configured := false


func setup(world_reference, asset_library, config_override: Dictionary = {}) -> bool:
	_clear_instances()
	generation_summary.clear()
	_configured = false
	earth_world = world_reference
	assets = asset_library
	if not _valid_world(earth_world) or not _valid_assets(assets):
		return false
	var planet_radius := float(earth_world.get_planet_radius())
	if not is_finite(planet_radius) or planet_radius <= 1.0:
		return false
	config = (
		config_override.duplicate(true)
		if not config_override.is_empty()
		else _load_json(DEFAULT_CONFIG_PATH)
	)
	if not _validate_config(config):
		return false
	grass_types = Array(config.get("grass_types", [])).duplicate(true)
	if not _cache_grass_assets():
		grass_types.clear()
		return false
	_configured = true
	return true


func regenerate(
	anchor_direction_value: Vector3,
	anchor_world: Vector3,
	presentation_seed: int = DEFAULT_PRESENTATION_SEED,
	lod_level: int = 0
) -> Dictionary:
	_clear_instances()
	generation_summary.clear()
	if (
		not _configured
		or not _finite_vec(anchor_direction_value)
		or anchor_direction_value.length_squared() < 0.5
		or not _finite_vec(anchor_world)
		or lod_level < 0
	):
		return {}

	var anchor_direction := anchor_direction_value.normalized()
	var tangent_basis := _up_basis(anchor_direction)
	var radius_m := float(config.get("grass_radius_m", 1250.0))
	var maximum := mini(
		int(config.get("max_grass_instances", 14000)),
		MAX_ALLOWED_INSTANCES
	)
	var max_slope_deg := float(config.get("maximum_grass_slope_deg", 38.0))
	var snow_cutoff := float(config.get("snow_grass_cutoff", 0.16))
	var sample_distance_m := float(
		config.get("surface_sample_distance_m", DEFAULT_SAMPLE_DISTANCE_M)
	)
	var attempts_multiplier := maxi(
		1,
		int(config.get("grass_attempts_multiplier", 3))
	)
	var seed := _anchor_seed(anchor_direction, presentation_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var buckets := _empty_transform_buckets(grass_types)

	var accepted := 0
	var rejected_density := 0
	var rejected_water := 0
	var rejected_snow := 0
	var rejected_slope := 0
	var invalid_surface_frame := 0
	var min_normal_alignment := 1.0

	for _attempt in range(maximum * attempts_multiplier):
		if accepted >= maximum:
			break

		var offset := _random_disk(rng, radius_m)
		var direction := _offset_direction(
			anchor_direction,
			tangent_basis.x,
			tangent_basis.z,
			offset
		)
		var state_value = earth_world.get_surface_state(direction, lod_level)
		if not state_value is Dictionary:
			invalid_surface_frame += 1
			continue
		var state: Dictionary = state_value

		var density := clampf(float(state.get("grass_density", 0.0)), 0.0, 1.0)
		if density <= 0.0 or rng.randf() > density:
			rejected_density += 1
			continue
		if int(state.get("water_kind", 0)) != 0:
			rejected_water += 1
			continue
		if float(state.get("snow_mask", 0.0)) > snow_cutoff:
			rejected_snow += 1
			continue

		var frame := SurfaceFrameAdapter.build(
			earth_world,
			direction,
			sample_distance_m,
			lod_level
		)
		if frame.is_empty() or not SurfaceFrameAdapter.validate(frame):
			invalid_surface_frame += 1
			continue

		var frame_state_value = frame.get("surface_state", {})
		if not frame_state_value is Dictionary:
			invalid_surface_frame += 1
			continue
		var frame_state: Dictionary = frame_state_value
		if float(frame_state.get("grass_density", 0.0)) <= 0.0:
			rejected_density += 1
			continue
		if int(frame_state.get("water_kind", 0)) != 0:
			rejected_water += 1
			continue
		if float(frame_state.get("snow_mask", 0.0)) > snow_cutoff:
			rejected_snow += 1
			continue
		if float(frame.get("slope_deg", 90.0)) > max_slope_deg:
			rejected_slope += 1
			continue

		var type_definition := _weighted_choice(rng, grass_types)
		if type_definition.is_empty():
			invalid_surface_frame += 1
			continue
		var type_id := String(type_definition.get("id", ""))
		if type_id.is_empty() or not buckets.has(type_id):
			invalid_surface_frame += 1
			continue

		var scale_value := rng.randf_range(
			float(type_definition.get("min_scale", 0.7)),
			float(type_definition.get("max_scale", 1.3))
		)
		var transform_value := _ground_cover_transform(
			frame,
			anchor_world,
			rng.randf_range(0.0, TAU),
			Vector3(
				scale_value * rng.randf_range(0.75, 1.25),
				scale_value,
				scale_value * rng.randf_range(0.75, 1.25)
			)
		)
		var terrain_normal := Vector3(
			frame.get("terrain_normal", Vector3.UP)
		).normalized()
		var normal_alignment := (
			transform_value.basis.y.normalized().dot(terrain_normal)
		)
		min_normal_alignment = minf(min_normal_alignment, normal_alignment)
		buckets[type_id].append(transform_value)
		accepted += 1

	grass_instances = _create_grass_instances(buckets)
	generation_summary = {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"truth_status": TRUTH_STATUS,
		"presentation_only": PRESENTATION_ONLY,
		"seed": seed,
		"anchor_direction": anchor_direction,
		"lod_level": lod_level,
		"grass_instances": accepted,
		"bucket_counts": _bucket_counts(buckets),
		"rejected_density": rejected_density,
		"rejected_water": rejected_water,
		"rejected_snow": rejected_snow,
		"rejected_slope": rejected_slope,
		"invalid_surface_frame": invalid_surface_frame,
		"min_normal_alignment": min_normal_alignment,
		"surface_frame_schema": SurfaceFrameAdapter.SCHEMA,
		"procedural_trees_created": false,
		"ecology_individuals_created": false,
		"ecology_count_meaning": false,
		"fitness_meaning": false,
		"mutation_meaning": false,
		"descriptor_v2_changed": false,
		"ecology_state_hash_changed": false,
		"terrain_written": false,
	}
	generation_summary["generation_hash"] = _generation_hash(
		generation_summary,
		buckets
	)
	return generation_summary.duplicate(true)


func get_summary() -> Dictionary:
	return generation_summary.duplicate(true)


func get_grass_instances() -> Array[MultiMeshInstance3D]:
	return grass_instances.duplicate()


func apply_lod_flags(flags: Dictionary) -> void:
	_set_instances_visible(bool(flags.get("ground_cover", false)))


static func validate_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	if String(summary.get("schema", "")) != SCHEMA:
		return false
	if String(summary.get("version", "")) != VERSION:
		return false
	if String(summary.get("revision", "")) != REVISION:
		return false
	if String(summary.get("truth_status", "")) != TRUTH_STATUS:
		return false
	if not bool(summary.get("presentation_only", false)):
		return false
	for forbidden_true in [
		"procedural_trees_created",
		"ecology_individuals_created",
		"ecology_count_meaning",
		"fitness_meaning",
		"mutation_meaning",
		"descriptor_v2_changed",
		"ecology_state_hash_changed",
		"terrain_written",
	]:
		if bool(summary.get(forbidden_true, true)):
			return false
	if int(summary.get("grass_instances", -1)) < 0:
		return false
	if int(summary.get("lod_level", -1)) < 0:
		return false
	var min_normal_alignment := float(
		summary.get("min_normal_alignment", NAN)
	)
	if (
		not is_finite(min_normal_alignment)
		or min_normal_alignment < 0.999999
		or min_normal_alignment > 1.000001
	):
		return false
	if (
		String(summary.get("surface_frame_schema", ""))
		!= SurfaceFrameAdapter.SCHEMA
	):
		return false
	return String(summary.get("generation_hash", "")).length() == 64


func _ground_cover_transform(
	frame: Dictionary,
	anchor_world: Vector3,
	yaw: float,
	scale_value: Vector3
) -> Transform3D:
	var terrain_basis := Basis(
		frame.get("terrain_basis", Basis.IDENTITY)
	)
	# IMPORTANT: yaw is local around terrain-frame Y. Basis.rotated(normal, yaw)
	# would rotate the already oriented basis in world space and can tilt its Y.
	var basis := (
		terrain_basis
		* Basis(Vector3.UP, yaw)
		* Basis.from_scale(scale_value)
	)
	var position := (
		Vector3(frame.get("surface_point_world", Vector3.ZERO))
		- anchor_world
	)
	return Transform3D(basis, position)


func _create_grass_instances(
	buckets: Dictionary
) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for definition_value in grass_types:
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value
		var type_id := String(definition.get("id", ""))
		if type_id.is_empty() or not buckets.has(type_id):
			continue
		var transforms: Array = buckets[type_id]
		if transforms.is_empty():
			continue

		var instance := MultiMeshInstance3D.new()
		instance.name = "GroundCover_%s" % type_id
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = _grass_meshes[type_id]
		multi_mesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multi_mesh.set_instance_transform(index, transforms[index])
		instance.multimesh = multi_mesh
		instance.material_override = _grass_materials[type_id]
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		add_child(instance)
		result.append(instance)
	return result


func _cache_grass_assets() -> bool:
	_grass_meshes.clear()
	_grass_materials.clear()
	for definition_value in grass_types:
		if not definition_value is Dictionary:
			return false
		var definition: Dictionary = definition_value
		var type_id := String(definition.get("id", ""))
		var mesh_value = assets.get_grass_mesh(type_id)
		var material_value = assets.get_grass_material(type_id)
		if not mesh_value is Mesh or not material_value is Material:
			_grass_meshes.clear()
			_grass_materials.clear()
			return false
		_grass_meshes[type_id] = mesh_value
		_grass_materials[type_id] = material_value
	return true


func _set_instances_visible(value: bool) -> void:
	for instance in grass_instances:
		if instance != null and is_instance_valid(instance):
			instance.visible = value


func _clear_instances() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	grass_instances.clear()


func _anchor_seed(
	direction: Vector3,
	presentation_seed: int
) -> int:
	var quantized := Vector3i(
		roundi(direction.x * 10000.0),
		roundi(direction.y * 10000.0),
		roundi(direction.z * 10000.0)
	)
	var value := (
		int(config.get("seed", DEFAULT_PRESENTATION_SEED))
		^ presentation_seed
	)
	value ^= quantized.x * 73856093
	value ^= quantized.y * 19349663
	value ^= quantized.z * 83492791
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


static func _random_disk(
	rng: RandomNumberGenerator,
	radius: float
) -> Vector2:
	var distance := sqrt(rng.randf()) * radius
	var angle := rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle)) * distance


static func _weighted_choice(
	rng: RandomNumberGenerator,
	values: Array
) -> Dictionary:
	var total := 0.0
	for value in values:
		if value is Dictionary:
			total += maxf(0.0, float(value.get("weight", 1.0)))
	if total <= 0.0:
		return {}
	var target := rng.randf() * total
	for value in values:
		if not value is Dictionary:
			continue
		target -= maxf(0.0, float(value.get("weight", 1.0)))
		if target <= 0.0:
			return Dictionary(value)
	var fallback = values.back()
	return Dictionary(fallback) if fallback is Dictionary else {}


static func _empty_transform_buckets(
	definitions: Array
) -> Dictionary:
	var result := {}
	for definition in definitions:
		if definition is Dictionary:
			var type_id := String(definition.get("id", ""))
			if not type_id.is_empty():
				result[type_id] = []
	return result


static func _bucket_counts(buckets: Dictionary) -> Dictionary:
	var result := {}
	for key in buckets.keys():
		var values = buckets[key]
		result[String(key)] = values.size() if values is Array else 0
	return result


static func _generation_hash(
	summary: Dictionary,
	buckets: Dictionary
) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		TRUTH_STATUS,
		str(int(summary.get("seed", 0))),
		str(int(summary.get("lod_level", 0))),
		str(int(summary.get("grass_instances", 0))),
	])
	var keys := PackedStringArray()
	for key in buckets.keys():
		keys.append(String(key))
	keys.sort()
	for key in keys:
		tokens.append(key)
		var transforms: Array = buckets[key]
		for transform_value in transforms:
			tokens.append(_transform_token(Transform3D(transform_value)))
	return "|".join(tokens).sha256_text()


static func _transform_token(value: Transform3D) -> String:
	return (
		"%.6f,%.6f,%.6f|%.6f,%.6f,%.6f|"
		+ "%.6f,%.6f,%.6f|%.6f,%.6f,%.6f"
	) % [
		value.basis.x.x,
		value.basis.x.y,
		value.basis.x.z,
		value.basis.y.x,
		value.basis.y.y,
		value.basis.y.z,
		value.basis.z.x,
		value.basis.z.y,
		value.basis.z.z,
		value.origin.x,
		value.origin.y,
		value.origin.z,
	]


static func _up_basis(up: Vector3) -> Basis:
	var helper := (
		Vector3.UP
		if absf(up.dot(Vector3.UP)) < 0.99
		else Vector3.RIGHT
	)
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _validate_config(value: Dictionary) -> bool:
	var definitions = value.get("grass_types", [])
	if not definitions is Array or definitions.is_empty():
		return false
	var seen := {}
	for definition_value in definitions:
		if not definition_value is Dictionary:
			return false
		var definition: Dictionary = definition_value
		var type_id := String(definition.get("id", ""))
		if type_id.is_empty() or seen.has(type_id):
			return false
		seen[type_id] = true
		var min_scale := float(definition.get("min_scale", 0.0))
		var max_scale := float(definition.get("max_scale", 0.0))
		var weight := float(definition.get("weight", 1.0))
		if (
			not is_finite(min_scale)
			or not is_finite(max_scale)
			or min_scale <= 0.0
			or max_scale < min_scale
			or not is_finite(weight)
			or weight < 0.0
		):
			return false

	var radius := float(value.get("grass_radius_m", 1250.0))
	var maximum := int(value.get("max_grass_instances", 14000))
	var slope := float(value.get("maximum_grass_slope_deg", 38.0))
	var sample_distance := float(
		value.get("surface_sample_distance_m", DEFAULT_SAMPLE_DISTANCE_M)
	)
	var snow_cutoff := float(value.get("snow_grass_cutoff", 0.16))
	var attempts_multiplier := int(
		value.get("grass_attempts_multiplier", 3)
	)
	return (
		is_finite(radius)
		and radius > 0.0
		and maximum > 0
		and maximum <= MAX_ALLOWED_INSTANCES
		and is_finite(slope)
		and slope >= 0.0
		and slope <= 90.0
		and is_finite(sample_distance)
		and sample_distance >= SurfaceFrameAdapter.MIN_SAMPLE_DISTANCE_M
		and sample_distance <= SurfaceFrameAdapter.MAX_SAMPLE_DISTANCE_M
		and is_finite(snow_cutoff)
		and snow_cutoff >= 0.0
		and snow_cutoff <= 1.0
		and attempts_multiplier >= 1
		and attempts_multiplier <= 16
	)


static func _valid_world(value) -> bool:
	return (
		value != null
		and value.has_method("get_planet_radius")
		and value.has_method("get_surface_point")
		and value.has_method("get_surface_state")
	)


static func _valid_assets(value) -> bool:
	return (
		value != null
		and value.has_method("get_grass_mesh")
		and value.has_method("get_grass_material")
	)


static func _finite_vec(value: Vector3) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
	)


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
