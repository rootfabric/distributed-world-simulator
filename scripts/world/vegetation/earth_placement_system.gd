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
