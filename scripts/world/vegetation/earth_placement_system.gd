extends Node3D

const CONFIG_PATH: String = "res://config/generation/earth_vegetation.json"

var earth_world
var pipeline
var assets
var config: Dictionary = {}
var tree_types: Array = []
var grass_types: Array = []
var near_tree_instances: Array[MultiMeshInstance3D] = []
var billboard_tree_instances: Array[MultiMeshInstance3D] = []
var grass_instances: Array[MultiMeshInstance3D] = []
var rock_instances: Array[MultiMeshInstance3D] = []
var generation_summary: Dictionary = {}
# Exact CPU-side source transforms per committed MultiMesh name. Reading back
# a MultiMesh depends on the rendering backend (the headless dummy server
# returns identity), so tests and verification use these authoritative arrays.
var committed_transform_sources: Dictionary = {}


func setup(world_reference, pipeline_reference, asset_library) -> bool:
	earth_world = world_reference
	pipeline = pipeline_reference
	assets = asset_library
	config = _load_json(CONFIG_PATH)
	if config.is_empty():
		return false
	tree_types = config.get("tree_types", [])
	grass_types = config.get("grass_types", [])
	return true


func regenerate(
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	anchor_world: Vector3
) -> Dictionary:
	_clear_instances()
	var started_usec: int = Time.get_ticks_usec()
	var pipeline_samples_before: int = int(
		pipeline.get_performance_snapshot().get("total_sample_count", 0)
	)
	var seed: int = _anchor_seed(anchor_direction)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var near_tree_transforms: Dictionary = _empty_transform_buckets(tree_types)
	var billboard_transforms: Dictionary = _empty_transform_buckets(tree_types)
	var grass_transforms: Dictionary = _empty_transform_buckets(grass_types)
	var rock_transforms: Array = [[], [], []]

	_generate_trees(
		rng,
		anchor_direction,
		east,
		north,
		anchor_world,
		near_tree_transforms,
		billboard_transforms
	)
	_generate_grass(
		rng,
		anchor_direction,
		east,
		north,
		anchor_world,
		grass_transforms
	)
	_generate_rocks(
		rng,
		anchor_direction,
		east,
		north,
		anchor_world,
		rock_transforms
	)

	near_tree_instances = _create_typed_instances(
		near_tree_transforms,
		"NearTrees",
		true,
		false
	)
	billboard_tree_instances = _create_typed_instances(
		billboard_transforms,
		"BillboardTrees",
		true,
		true
	)
	grass_instances = _create_typed_instances(
		grass_transforms,
		"Grass",
		false,
		false
	)
	rock_instances = _create_rock_instances(rock_transforms)
	_record_transform_sources(near_tree_transforms, billboard_transforms, grass_transforms, rock_transforms)

	var pipeline_samples_after: int = int(
		pipeline.get_performance_snapshot().get("total_sample_count", 0)
	)
	generation_summary = {
		"seed": seed,
		"elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"pipeline_samples": pipeline_samples_after - pipeline_samples_before,
		"near_trees": _count_bucket_transforms(near_tree_transforms),
		"billboard_trees": _count_bucket_transforms(billboard_transforms),
		"grass": _count_bucket_transforms(grass_transforms),
		"rocks": _count_array_buckets(rock_transforms),
	}
	return generation_summary.duplicate(true)


func apply_lod_flags(flags: Dictionary) -> void:
	_set_instance_group_visible(near_tree_instances, bool(flags.get("near_trees", false)))
	_set_instance_group_visible(billboard_tree_instances, bool(flags.get("billboard_trees", false)))
	_set_instance_group_visible(grass_instances, bool(flags.get("grass", false)))
	_set_instance_group_visible(rock_instances, bool(flags.get("rocks", false)))


func get_summary() -> Dictionary:
	return generation_summary.duplicate(true)


func _generate_trees(
	rng: RandomNumberGenerator,
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	anchor_world: Vector3,
	near_buckets: Dictionary,
	billboard_buckets: Dictionary
) -> void:
	var near_radius: float = float(config.get("near_tree_radius_m", 3600.0))
	var billboard_radius: float = float(config.get("billboard_tree_radius_m", 9200.0))
	var max_near: int = int(config.get("max_near_trees", 1600))
	var max_billboards: int = int(config.get("max_billboard_trees", 5200))
	var max_slope: float = float(config.get("maximum_tree_slope_deg", 31.0))
	var snow_cutoff: float = float(config.get("snow_tree_cutoff", 0.22))
	var attempts: int = (max_near + max_billboards) * 4
	var near_count: int = 0
	var billboard_count: int = 0
	for _attempt in range(attempts):
		if near_count >= max_near and billboard_count >= max_billboards:
			break
		var offset: Vector2 = _random_disk(rng, billboard_radius)
		var distance: float = offset.length()
		var direction: Vector3 = _offset_direction(anchor_direction, east, north, offset)
		var state: Dictionary = pipeline.sample(direction, 0)
		var density: float = float(state.get("tree_density", 0.0))
		if density <= 0.0 or rng.randf() > density:
			continue
		if int(state.get("water_kind", 0)) != 0:
			continue
		if float(state.get("snow_mask", 0.0)) > snow_cutoff:
			continue
		if float(state.get("slope_hint_deg", 90.0)) > max_slope:
			continue
		if float(state.get("rockiness", 0.0)) > 0.78:
			continue
		var type_definition: Dictionary = _weighted_choice(rng, tree_types)
		var type_id: String = String(type_definition.get("id", "broadleaf"))
		var scale_value: float = rng.randf_range(
			float(type_definition.get("min_scale", 0.7)),
			float(type_definition.get("max_scale", 1.3))
		)
		var transform_value: Transform3D = _surface_transform(
			direction,
			anchor_world,
			rng.randf_range(0.0, TAU),
			Vector3(
				scale_value * rng.randf_range(0.82, 1.18),
				scale_value * rng.randf_range(0.82, 1.24),
				scale_value * rng.randf_range(0.82, 1.18)
			)
		)
		if distance <= near_radius and near_count < max_near:
			near_buckets[type_id].append(transform_value)
			near_count += 1
		elif billboard_count < max_billboards:
			billboard_buckets[type_id].append(transform_value)
			billboard_count += 1


func _generate_grass(
	rng: RandomNumberGenerator,
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	anchor_world: Vector3,
	buckets: Dictionary
) -> void:
	var radius: float = float(config.get("grass_radius_m", 1250.0))
	var maximum: int = int(config.get("max_grass_instances", 14000))
	var max_slope: float = float(config.get("maximum_grass_slope_deg", 38.0))
	var count: int = 0
	for _attempt in range(maximum * 3):
		if count >= maximum:
			break
		var offset: Vector2 = _random_disk(rng, radius)
		var direction: Vector3 = _offset_direction(anchor_direction, east, north, offset)
		var state: Dictionary = pipeline.sample(direction, 0)
		var density: float = float(state.get("grass_density", 0.0))
		var cluster_noise: float = rng.randf()
		if density <= 0.0 or cluster_noise > density:
			continue
		if int(state.get("water_kind", 0)) != 0:
			continue
		if float(state.get("snow_mask", 0.0)) > 0.16:
			continue
		if float(state.get("slope_hint_deg", 90.0)) > max_slope:
			continue
		var type_definition: Dictionary = _weighted_choice(rng, grass_types)
		var type_id: String = String(type_definition.get("id", "short"))
		var scale_value: float = rng.randf_range(
			float(type_definition.get("min_scale", 0.7)),
			float(type_definition.get("max_scale", 1.3))
		)
		buckets[type_id].append(_surface_transform(
			direction,
			anchor_world,
			rng.randf_range(0.0, TAU),
			Vector3(
				scale_value * rng.randf_range(0.75, 1.25),
				scale_value,
				scale_value * rng.randf_range(0.75, 1.25)
			)
		))
		count += 1


func _generate_rocks(
	rng: RandomNumberGenerator,
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	anchor_world: Vector3,
	buckets: Array
) -> void:
	var radius: float = float(config.get("rock_radius_m", 5400.0))
	var maximum: int = int(config.get("max_rocks", 2300))
	var count: int = 0
	for _attempt in range(maximum * 3):
		if count >= maximum:
			break
		var offset: Vector2 = _random_disk(rng, radius)
		var direction: Vector3 = _offset_direction(anchor_direction, east, north, offset)
		var state: Dictionary = pipeline.sample(direction, 0)
		var density: float = float(state.get("rock_density", 0.0))
		if density <= 0.0 or rng.randf() > density:
			continue
		if int(state.get("water_kind", 0)) != 0:
			continue
		var variant: int = rng.randi_range(0, 2)
		var scale_value: float = rng.randf_range(0.35, 2.8)
		buckets[variant].append(_surface_transform(
			direction,
			anchor_world,
			rng.randf_range(0.0, TAU),
			Vector3(
				scale_value * rng.randf_range(0.65, 1.45),
				scale_value * rng.randf_range(0.45, 1.10),
				scale_value * rng.randf_range(0.65, 1.45)
			)
		))
		count += 1


func _surface_transform(
	direction: Vector3,
	anchor_world: Vector3,
	yaw: float,
	scale_value: Vector3
) -> Transform3D:
	var up: Vector3 = direction.normalized()
	var tangent_x: Vector3 = Vector3.UP.cross(up)
	if tangent_x.length_squared() < 0.000001:
		tangent_x = Vector3.RIGHT.cross(up)
	tangent_x = tangent_x.normalized()
	var tangent_z: Vector3 = tangent_x.cross(up).normalized()
	var basis := Basis(tangent_x, up, tangent_z).rotated(up, yaw)
	basis = basis.scaled(scale_value)
	var position: Vector3 = earth_world.get_surface_point(direction) - anchor_world
	return Transform3D(basis, position)


func _offset_direction(
	anchor_direction: Vector3,
	east: Vector3,
	north: Vector3,
	offset: Vector2
) -> Vector3:
	return (
		anchor_direction
		+ east * (offset.x / earth_world.get_planet_radius())
		+ north * (offset.y / earth_world.get_planet_radius())
	).normalized()


func _random_disk(rng: RandomNumberGenerator, radius: float) -> Vector2:
	var distance: float = sqrt(rng.randf()) * radius
	var angle: float = rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle)) * distance


func _weighted_choice(rng: RandomNumberGenerator, values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var total: float = 0.0
	for value in values:
		if value is Dictionary:
			total += maxf(0.0, float(value.get("weight", 1.0)))
	var target: float = rng.randf() * maxf(total, 0.0001)
	for value in values:
		if not value is Dictionary:
			continue
		target -= maxf(0.0, float(value.get("weight", 1.0)))
		if target <= 0.0:
			return value
	var fallback = values.back()
	return fallback if fallback is Dictionary else {}


func _empty_transform_buckets(definitions: Array) -> Dictionary:
	var result: Dictionary = {}
	for definition in definitions:
		if definition is Dictionary:
			result[String(definition.get("id", "default"))] = []
	return result


func _create_typed_instances(
	buckets: Dictionary,
	group_name: String,
	is_tree: bool,
	billboard: bool
) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for type_id_value in buckets.keys():
		var type_id: String = String(type_id_value)
		var transforms: Array = buckets[type_id]
		if transforms.is_empty():
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%s" % [group_name, type_id]
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		if billboard:
			multi_mesh.mesh = assets.get_billboard_mesh(type_id)
		elif is_tree:
			multi_mesh.mesh = assets.get_tree_mesh(type_id)
		else:
			multi_mesh.mesh = assets.get_grass_mesh(type_id)
		multi_mesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multi_mesh.set_instance_transform(index, transforms[index])
		instance.multimesh = multi_mesh
		if billboard:
			instance.material_override = assets.get_billboard_material(type_id)
		elif is_tree:
			# Tree meshes keep separate trunk and crown surface materials.
			instance.material_override = null
		else:
			instance.material_override = assets.get_grass_material(type_id)
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if billboard or not is_tree
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		add_child(instance)
		result.append(instance)
	return result


func _create_rock_instances(buckets: Array) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for variant in range(buckets.size()):
		var transforms: Array = buckets[variant]
		if transforms.is_empty():
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = "Rocks_%d" % variant
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


func _set_instance_group_visible(instances: Array, value: bool) -> void:
	for instance in instances:
		if instance != null and is_instance_valid(instance):
			instance.visible = value


func _clear_instances() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	near_tree_instances.clear()
	billboard_tree_instances.clear()
	grass_instances.clear()
	rock_instances.clear()
	committed_transform_sources.clear()


func _record_transform_sources(
	near_buckets: Dictionary,
	billboard_buckets: Dictionary,
	grass_buckets: Dictionary,
	rock_buckets: Array
) -> void:
	committed_transform_sources.clear()
	for type_id in near_buckets.keys():
		if near_buckets[type_id] is Array and not (near_buckets[type_id] as Array).is_empty():
			committed_transform_sources["NearTrees_%s" % type_id] = near_buckets[type_id]
	for type_id in billboard_buckets.keys():
		if billboard_buckets[type_id] is Array and not (billboard_buckets[type_id] as Array).is_empty():
			committed_transform_sources["BillboardTrees_%s" % type_id] = billboard_buckets[type_id]
	for type_id in grass_buckets.keys():
		if grass_buckets[type_id] is Array and not (grass_buckets[type_id] as Array).is_empty():
			committed_transform_sources["Grass_%s" % type_id] = grass_buckets[type_id]
	for variant in range(rock_buckets.size()):
		if rock_buckets[variant] is Array and not (rock_buckets[variant] as Array).is_empty():
			committed_transform_sources["Rocks_%d" % variant] = rock_buckets[variant]


func _count_bucket_transforms(buckets: Dictionary) -> int:
	var result: int = 0
	for values in buckets.values():
		if values is Array:
			result += values.size()
	return result


func _count_array_buckets(buckets: Array) -> int:
	var result: int = 0
	for values in buckets:
		if values is Array:
			result += values.size()
	return result


func _anchor_seed(direction: Vector3) -> int:
	var quantized := Vector3i(
		roundi(direction.x * 10000.0),
		roundi(direction.y * 10000.0),
		roundi(direction.z * 10000.0)
	)
	var value: int = int(config.get("seed", 20260726))
	value ^= quantized.x * 73856093
	value ^= quantized.y * 19349663
	value ^= quantized.z * 83492791
	return absi(value)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# R3C3 R2 STAGE B/C: staged GPU preparation and atomic visual swap.
# The legacy synchronous regenerate() above stays byte-identical for the
# default-off path. These methods are main-thread only and never touch the
# live visible instances until commit_staged_generation().
# ---------------------------------------------------------------------------

const R3C3R2_PHASE_IDLE := "IDLE"
const R3C3R2_PHASE_ALLOCATED := "GPU_ALLOCATE_DONE"
const R3C3R2_PHASE_UPLOADING := "GPU_UPLOAD_CHUNKS"
const R3C3R2_PHASE_READY := "UPLOAD_READY"
const R3C3R2_PHASE_COMMITTED := "COMMITTED"
const R3C3R2_PHASE_FAILED := "FAILED"
const R3C21_PHASE_PREATTACH := "GPU_PREATTACH"
const R3C21_PHASE_PREATTACHED := "GPU_PREATTACHED"

var _r3c3r2_candidate_nodes: Array[MultiMeshInstance3D] = []
var _r3c3r2_upload_queue: Array = []
var _r3c3r2_token := 0
var _r3c3r2_phase := R3C3R2_PHASE_IDLE
var _r3c3r2_failure := ""
var _r3c3r2_allocate_ms := 0.0
var _r3c3r2_upload_ms_total := 0.0
var _r3c3r2_upload_ms_max := 0.0
var _r3c3r2_commit_ms := 0.0
var _r3c3r2_instance_count_total := 0
var _r3c3r2_instances_uploaded := 0
var _r3c3r2_source_transforms: Dictionary = {}

# R3C3 R2.1: candidates are still fully GPU-uploaded off-tree. Afterward,
# register ONE invisible render node per frame rather than registering every
# MultiMeshInstance3D on the same first-visible commit frame. Only client
# staged-Earth opt-in activates this behavior. Original R2 is unchanged.
var _r3c21_pre_attach_enabled := false
var _r3c21_preattached_count := 0
var _r3c21_preattach_ms_max := 0.0
var _r3c21_preattach_ms_total := 0.0
var _r3c21_retired_nodes: Array[MultiMeshInstance3D] = []
var _r3c21_retired_released := 0
var _r3c21_visibility_swap_ms := 0.0


func configure_frame_paced_preattach(enabled: bool) -> void:
	# Called on the scene's main thread before its first vegetation build.
	# Turning it off cannot strand already preattached candidates in-tree.
	if _r3c3r2_phase == R3C3R2_PHASE_IDLE 			or _r3c3r2_phase == R3C3R2_PHASE_COMMITTED:
		_r3c21_pre_attach_enabled = enabled


func begin_staged_generation(
	token: int,
	near_buckets: Dictionary,
	billboard_buckets: Dictionary,
	grass_buckets: Dictionary,
	rock_buckets: Array
) -> Dictionary:
	cancel_staged_generation()
	if token < 1:
		return _r3c3r2_fail("R3C3R2_GENERATION_TOKEN_INVALID")
	if _r3c3r2_phase == R3C3R2_PHASE_COMMITTED and _r3c3r2_token == token:
		return _r3c3r2_fail("R3C3R2_DOUBLE_COMMIT_SAME_REGION")
	# Defensive structure validation before any GPU allocation: a corrupted
	# bucket must never reach a MultiMesh.
	for type_id in near_buckets.keys():
		if not near_buckets[type_id] is Array:
			return _r3c3r2_fail("R3C3R2_CORRUPT_NEAR_BUCKET")
	for type_id in billboard_buckets.keys():
		if not billboard_buckets[type_id] is Array:
			return _r3c3r2_fail("R3C3R2_CORRUPT_BILLBOARD_BUCKET")
	for type_id in grass_buckets.keys():
		if not grass_buckets[type_id] is Array:
			return _r3c3r2_fail("R3C3R2_CORRUPT_GRASS_BUCKET")
	if rock_buckets.size() != 3:
		return _r3c3r2_fail("R3C3R2_CORRUPT_ROCK_BUCKETS")
	for values in rock_buckets:
		if not values is Array:
			return _r3c3r2_fail("R3C3R2_CORRUPT_ROCK_BUCKET")
	_r3c3r2_token = token
	_r3c3r2_failure = ""
	_r3c3r2_allocate_ms = 0.0
	_r3c3r2_upload_ms_total = 0.0
	_r3c3r2_upload_ms_max = 0.0
	_r3c3r2_commit_ms = 0.0
	_r3c3r2_instance_count_total = 0
	_r3c3r2_instances_uploaded = 0
	_r3c3r2_source_transforms = {}
	_r3c21_preattached_count = 0
	_r3c21_preattach_ms_max = 0.0
	_r3c21_preattach_ms_total = 0.0
	_r3c21_visibility_swap_ms = 0.0
	# Candidates are created detached from the scene tree: the old complete
	# region remains visible and untouched during the entire upload.
	var started: int = Time.get_ticks_usec()
	_r3c3r2_upload_queue.clear()
	_r3c3r2_candidate_nodes.clear()
	if _r3c3r2_collect_candidates(
		near_buckets, "NearTrees", true, false
	) and _r3c3r2_collect_candidates(
		billboard_buckets, "BillboardTrees", true, true
	) and _r3c3r2_collect_candidates(
		grass_buckets, "Grass", false, false
	):
		for variant in range(rock_buckets.size()):
			var transforms: Array = rock_buckets[variant]
			if transforms.is_empty():
				continue
			if not _r3c3r2_allocate_candidate(
				transforms, "Rocks_%d" % variant,
				assets.get_rock_mesh(variant),
				assets.get_rock_material(variant),
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
				false
			):
				return _r3c3r2_fail("R3C3R2_ROCK_MESH_REQUIRED")
	else:
		return _r3c3r2_fail("R3C3R2_ASSET_MESH_REQUIRED")
	_r3c3r2_allocate_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_r3c3r2_phase = R3C3R2_PHASE_ALLOCATED
	return {"success": true, "error_code": "", "details": {
		"token": token,
		"candidates": _r3c3r2_candidate_nodes.size(),
		"instance_count_total": _r3c3r2_instance_count_total,
		"allocate_ms": _r3c3r2_allocate_ms,
	}}


func _r3c3r2_collect_candidates(
	buckets: Dictionary,
	group_name: String,
	is_tree: bool,
	billboard: bool
) -> bool:
	for type_id_value in buckets.keys():
		var type_id: String = String(type_id_value)
		var transforms: Array = buckets[type_id]
		if transforms.is_empty():
			continue
		var mesh: Mesh
		var material: Material
		if billboard:
			mesh = assets.get_billboard_mesh(type_id)
			material = assets.get_billboard_material(type_id)
		elif is_tree:
			# Tree meshes keep separate trunk and crown surface materials.
			mesh = assets.get_tree_mesh(type_id)
			material = null
		else:
			mesh = assets.get_grass_mesh(type_id)
			material = assets.get_grass_material(type_id)
		var cast_shadow := (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if billboard or not is_tree
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		if not _r3c3r2_allocate_candidate(
			transforms, "%s_%s" % [group_name, type_id],
			mesh, material, cast_shadow, billboard
		):
			return false
	return true


func _r3c3r2_allocate_candidate(
	transforms: Array,
	node_name: String,
	mesh: Mesh,
	material: Material,
	cast_shadow: int,
	_billboard: bool
) -> bool:
	if mesh == null:
		return false
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	# Single bounded allocation point; its duration is measured and reported.
	multi_mesh.instance_count = transforms.size()
	instance.multimesh = multi_mesh
	if material != null:
		instance.material_override = material
	instance.cast_shadow = cast_shadow
	instance.visible = false
	_r3c3r2_candidate_nodes.append(instance)
	_r3c3r2_upload_queue.append({
		"instance": instance,
		"multimesh": multi_mesh,
		"transforms": transforms,
		"cursor": 0,
	})
	_r3c3r2_source_transforms[node_name] = transforms
	_r3c3r2_instance_count_total += transforms.size()
	return true


func advance_staged_upload(max_instances: int = 2048) -> Dictionary:
	if _r3c3r2_phase == R3C3R2_PHASE_FAILED:
		return {"success": false, "error_code": _r3c3r2_failure}
	if max_instances < 1:
		return _r3c3r2_reject("R3C3R2_INVALID_UPLOAD_BUDGET")
	if _r3c3r2_phase == R3C3R2_PHASE_IDLE:
		return _r3c3r2_reject("R3C3R2_UPLOAD_BEFORE_ALLOCATE")
	if _r3c3r2_phase == R3C3R2_PHASE_COMMITTED:
		return _r3c3r2_reject("R3C3R2_UPLOAD_AFTER_COMMIT")
	if _r3c3r2_phase == R3C3R2_PHASE_READY:
		return {"success": true, "error_code": "", "details": {
			"ready": true, "uploaded": 0, "elapsed_us": 0,
		}}
	var started: int = Time.get_ticks_usec()
	var uploaded := 0
	while uploaded < max_instances and not _r3c3r2_upload_queue.is_empty():
		var entry: Dictionary = _r3c3r2_upload_queue[0]
		var transforms: Array = entry["transforms"]
		var cursor: int = int(entry["cursor"])
		var multi_mesh: MultiMesh = entry["multimesh"]
		while cursor < transforms.size() and uploaded < max_instances:
			multi_mesh.set_instance_transform(cursor, transforms[cursor])
			cursor += 1
			uploaded += 1
			_r3c3r2_instances_uploaded += 1
		entry["cursor"] = cursor
		if cursor >= transforms.size():
			_r3c3r2_upload_queue.pop_front()
	var elapsed_us: int = Time.get_ticks_usec() - started
	var elapsed_ms: float = float(elapsed_us) / 1000.0
	_r3c3r2_upload_ms_total += elapsed_ms
	_r3c3r2_upload_ms_max = maxf(_r3c3r2_upload_ms_max, elapsed_ms)
	if _r3c3r2_upload_queue.is_empty():
		_r3c3r2_phase = R3C3R2_PHASE_READY
	return {"success": true, "error_code": "", "details": {
		"ready": _r3c3r2_phase == R3C3R2_PHASE_READY,
		"uploaded": uploaded,
		"elapsed_us": elapsed_us,
		"token": _r3c3r2_token,
	}}


# R2.1 registration is intentionally after all GPU transforms upload. The
# candidates join the same parent as the old visible nodes but stay invisible
# until an atomic visual commit; neither the old LOD lists nor canonical world
# data are changed during preattach.
func advance_staged_preattach(token: int, max_nodes: int = 1) -> Dictionary:
	if not _r3c21_pre_attach_enabled:
		return _r3c3r2_reject("R3C21_PREATTACH_DISABLED")
	if token != _r3c3r2_token:
		return _r3c3r2_reject("R3C21_STALE_PREATTACH_TOKEN")
	if max_nodes < 1:
		return _r3c3r2_reject("R3C21_PREATTACH_BUDGET_REQUIRED")
	if not (_r3c3r2_phase in [
		R3C3R2_PHASE_READY, R3C21_PHASE_PREATTACH, R3C21_PHASE_PREATTACHED
	]):
		return _r3c3r2_reject("R3C21_PREATTACH_BEFORE_GPU_READY")
	if _r3c3r2_instances_uploaded != _r3c3r2_instance_count_total:
		return _r3c3r2_reject("R3C21_PREATTACH_BEFORE_UPLOAD_COMPLETE")
	if _r3c3r2_phase == R3C21_PHASE_PREATTACHED:
		return {"success": true, "error_code": "", "details": {
			"ready": true, "attached": 0, "attached_total": _r3c21_preattached_count,
			"elapsed_us": 0, "token": token,
		}}
	var started := Time.get_ticks_usec()
	var attached := 0
	while attached < max_nodes and _r3c21_preattached_count < _r3c3r2_candidate_nodes.size():
		var candidate: MultiMeshInstance3D = _r3c3r2_candidate_nodes[_r3c21_preattached_count]
		if candidate == null or not is_instance_valid(candidate) or candidate.get_parent() != null:
			return _r3c3r2_fail("R3C21_PREATTACH_CANDIDATE_INVALID")
		# Old and pending trees/grass may have the same canonical name.
		# Temporarily prefix invisible siblings to avoid Godot's automatic
		# Node.name collision suffix, then restore accepted name at commit.
		var canonical_name := String(candidate.name)
		if canonical_name.is_empty():
			return _r3c3r2_fail("R3C21_CANDIDATE_NAME_REQUIRED")
		candidate.set_meta("r3c21_canonical_name", canonical_name)
		candidate.name = "_R3C21_PENDING_%d_%d" % [token, _r3c21_preattached_count]
		candidate.visible = false
		add_child(candidate)
		_r3c21_preattached_count += 1
		attached += 1
	var elapsed_us := Time.get_ticks_usec() - started
	var elapsed_ms := float(elapsed_us) / 1000.0
	_r3c21_preattach_ms_max = maxf(_r3c21_preattach_ms_max, elapsed_ms)
	_r3c21_preattach_ms_total += elapsed_ms
	_r3c3r2_phase = (
		R3C21_PHASE_PREATTACHED if _r3c21_preattached_count == _r3c3r2_candidate_nodes.size()
		else R3C21_PHASE_PREATTACH
	)
	return {"success": true, "error_code": "", "details": {
		"ready": _r3c3r2_phase == R3C21_PHASE_PREATTACHED,
		"attached": attached, "attached_total": _r3c21_preattached_count,
		"elapsed_us": elapsed_us, "token": token,
	}}


func is_staged_upload_ready(token: int) -> bool:
	return (
		_r3c3r2_phase == (
			R3C21_PHASE_PREATTACHED if _r3c21_pre_attach_enabled
			else R3C3R2_PHASE_READY
		)
		and _r3c3r2_token == token
		and _r3c3r2_instances_uploaded == _r3c3r2_instance_count_total
		and (
			not _r3c21_pre_attach_enabled
			or _r3c21_preattached_count == _r3c3r2_candidate_nodes.size()
		)
	)


# STAGE C: atomic visual commit. The old complete region is only replaced here,
# after every transform of the new candidate is uploaded and verified.
func commit_staged_generation(token: int) -> Dictionary:
	if _r3c3r2_phase == R3C3R2_PHASE_FAILED:
		return {"success": false, "error_code": _r3c3r2_failure}
	if _r3c3r2_phase == R3C3R2_PHASE_COMMITTED and _r3c3r2_token == token:
		return _r3c3r2_reject("R3C3R2_DOUBLE_COMMIT_SAME_REGION")
	if _r3c3r2_token != token:
		return _r3c3r2_reject("R3C3R2_STALE_GENERATION_TOKEN")
	if _r3c3r2_phase != (
		R3C21_PHASE_PREATTACHED if _r3c21_pre_attach_enabled
		else R3C3R2_PHASE_READY
	):
		return _r3c3r2_reject("R3C3R2_COMMIT_BEFORE_UPLOAD_READY")
	if _r3c3r2_instances_uploaded != _r3c3r2_instance_count_total:
		return _r3c3r2_reject("R3C3R2_INCOMPLETE_GPU_UPLOAD")
	var started: int = Time.get_ticks_usec()
	# Atomic point: clear old, show complete new candidates. R2.1 moved
	# their expensive SceneTree registration onto earlier separate frames.
	# Only current live nodes are detached, not the invisible candidates.
	if _r3c21_pre_attach_enabled:
		if _r3c21_preattached_count != _r3c3r2_candidate_nodes.size():
			return _r3c3r2_reject("R3C21_PREATTACH_NOT_COMPLETE")
		for child in get_children():
			if child is MultiMeshInstance3D and not _r3c3r2_candidate_nodes.has(child):
				remove_child(child)
				child.visible = false
				_r3c21_retired_nodes.append(child)
		for instance in _r3c3r2_candidate_nodes:
			if instance.get_parent() != self or instance.visible:
				return _r3c3r2_fail("R3C21_INCOMPLETE_HIDDEN_CANDIDATE")
			var canonical_name := String(
				instance.get_meta("r3c21_canonical_name", "")
			)
			if canonical_name.is_empty() or not String(instance.name).begins_with("_R3C21_PENDING_"):
				return _r3c3r2_fail("R3C21_CANONICAL_NAME_FENCE_FAILED")
			instance.name = canonical_name
			instance.remove_meta("r3c21_canonical_name")
			instance.visible = true
	else:
		_clear_instances()
		for instance in _r3c3r2_candidate_nodes:
			instance.visible = true
			add_child(instance)
	var committed: Array[MultiMeshInstance3D] = []
	committed.assign(_r3c3r2_candidate_nodes)
	_r3c3r2_candidate_nodes = []
	_r3c3r2_upload_queue.clear()
	committed_transform_sources = _r3c3r2_source_transforms
	_r3c3r2_source_transforms = {}
	_rebuild_live_lists_from_children()
	_r3c3r2_commit_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_r3c21_visibility_swap_ms = _r3c3r2_commit_ms
	_r3c3r2_phase = R3C3R2_PHASE_COMMITTED
	return {"success": true, "error_code": "", "details": {
		"token": token,
		"instances": committed.size(),
		"instance_count_total": _r3c3r2_instance_count_total,
		"commit_ms": _r3c3r2_commit_ms,
	}}


func cancel_staged_generation() -> void:
	# Free detached scratch GPU candidates; nothing invisible accumulates.
	for instance in _r3c3r2_candidate_nodes:
		if instance != null and is_instance_valid(instance):
			if instance.get_parent() == self:
				remove_child(instance)
			instance.queue_free()
	_r3c3r2_candidate_nodes = []
	_r3c21_preattached_count = 0
	_r3c3r2_upload_queue = []
	_r3c3r2_source_transforms = {}
	_r3c3r2_phase = R3C3R2_PHASE_IDLE
	_r3c3r2_failure = ""
	_r3c3r2_instances_uploaded = 0
	_r3c3r2_instance_count_total = 0


# Releasing every old MultiMesh on one render frame can introduce a second
# renderer spike after an otherwise tiny swap. Detach all old visuals at the
# atomic handoff, but drain their already-hidden GPU resources one per frame.
# The queue is bounded by the finite number of renderer instance groups.
func drain_retired_visuals(max_nodes: int = 1) -> Dictionary:
	if max_nodes < 1:
		return _r3c3r2_reject("R3C21_RETIRED_DRAIN_BUDGET_REQUIRED")
	var drained := 0
	while drained < max_nodes and not _r3c21_retired_nodes.is_empty():
		var old = _r3c21_retired_nodes.pop_front()
		if old != null and is_instance_valid(old):
			if old.get_parent() != null:
				return _r3c3r2_fail("R3C21_RETIRED_VISUAL_STILL_PARENTED")
			old.queue_free()
		drained += 1
		_r3c21_retired_released += 1
	return {"success": true, "error_code": "", "details": {
		"drained": drained, "remaining": _r3c21_retired_nodes.size(),
	}}


func _rebuild_live_lists_from_children() -> void:
	near_tree_instances.clear()
	billboard_tree_instances.clear()
	grass_instances.clear()
	rock_instances.clear()
	for child in get_children():
		if child is MultiMeshInstance3D:
			var node_name: String = String(child.name)
			if node_name.begins_with("NearTrees_"):
				near_tree_instances.append(child)
			elif node_name.begins_with("BillboardTrees_"):
				billboard_tree_instances.append(child)
			elif node_name.begins_with("Grass_"):
				grass_instances.append(child)
			elif node_name.begins_with("Rocks_"):
				rock_instances.append(child)


func apply_staged_generation_summary(summary: Dictionary) -> void:
	generation_summary = summary.duplicate(true)


func get_staged_upload_report() -> Dictionary:
	return {
		"phase": _r3c3r2_phase,
		"token": _r3c3r2_token,
		"error": _r3c3r2_failure,
		"candidates": _r3c3r2_candidate_nodes.size(),
		"instance_count_total": _r3c3r2_instance_count_total,
		"instances_uploaded": _r3c3r2_instances_uploaded,
		"allocate_ms": _r3c3r2_allocate_ms,
		"upload_ms_total": _r3c3r2_upload_ms_total,
		"upload_ms_max": _r3c3r2_upload_ms_max,
		"commit_ms": _r3c3r2_commit_ms,
		"r21_preattach_enabled": _r3c21_pre_attach_enabled,
		"r21_preattach_nodes": _r3c21_preattached_count,
		"r21_preattach_ms_max": _r3c21_preattach_ms_max,
		"r21_preattach_ms_total": _r3c21_preattach_ms_total,
		"r21_visibility_swap_ms": _r3c21_visibility_swap_ms,
		"r21_retired_remaining": _r3c21_retired_nodes.size(),
		"r21_retired_released": _r3c21_retired_released,
	}


func _r3c3r2_fail(error_code: String) -> Dictionary:
	_r3c3r2_failure = error_code
	_r3c3r2_phase = R3C3R2_PHASE_FAILED
	return {"success": false, "error_code": error_code}


# Validation rejects keep the state machine usable: only structural corruption
# permanently fails the generation pipeline.
func _r3c3r2_reject(error_code: String) -> Dictionary:
	_r3c3r2_failure = error_code
	return {"success": false, "error_code": error_code}
