extends "res://scripts/world/atmosphere/atmosphere_plugin_base.gd"

var cloud_instance: MultiMeshInstance3D
var cloud_multimesh: MultiMesh
var cloud_material: StandardMaterial3D
var density_noise: FastNoiseLite
var seed: int = 2026072604
var cloud_altitude_m: float = 4000.0
var cloud_thickness_m: float = 850.0
var maximum_observer_altitude_m: float = 32000.0
var patch_radius_m: float = 70000.0
var recenter_distance_m: float = 14000.0
var candidate_count: int = 760
var maximum_instances: int = 320
var coverage: float = 0.48
var macro_noise_scale_m: float = 18000.0
var minimum_size_m := Vector2(900.0, 420.0)
var maximum_size_m := Vector2(4800.0, 1900.0)
var vertical_jitter_m: float = 380.0
var base_opacity: float = 0.68
var cloud_color := Color(0.96, 0.975, 1.0, 1.0)
var wind_velocity := Vector2(14.0, 4.0)
var wind_offset := Vector2.ZERO
var anchor_direction := Vector3.UP
var anchor_body_local := Vector3.ZERO
var anchor_east := Vector3.RIGHT
var anchor_north := Vector3.FORWARD
var has_anchor: bool = false
var generated_instances: int = 0
var rebuild_count: int = 0


func setup(owner_reference, config_value: Dictionary, logger_reference = null) -> bool:
	if not super.setup(owner_reference, config_value, logger_reference):
		return false
	seed = int(plugin_config.get("seed", seed))
	cloud_altitude_m = float(plugin_config.get("altitude_m", cloud_altitude_m))
	cloud_thickness_m = float(plugin_config.get("thickness_m", cloud_thickness_m))
	maximum_observer_altitude_m = float(
		plugin_config.get("maximum_observer_altitude_m", maximum_observer_altitude_m)
	)
	patch_radius_m = float(plugin_config.get("patch_radius_m", patch_radius_m))
	recenter_distance_m = float(
		plugin_config.get("recenter_distance_m", recenter_distance_m)
	)
	candidate_count = int(plugin_config.get("candidate_count", candidate_count))
	maximum_instances = int(plugin_config.get("maximum_instances", maximum_instances))
	coverage = clampf(float(plugin_config.get("coverage", coverage)), 0.0, 1.0)
	macro_noise_scale_m = maxf(
		100.0,
		float(plugin_config.get("macro_noise_scale_m", macro_noise_scale_m))
	)
	minimum_size_m = _vector2_from_array(
		plugin_config.get("minimum_size_m", [minimum_size_m.x, minimum_size_m.y]),
		minimum_size_m
	)
	maximum_size_m = _vector2_from_array(
		plugin_config.get("maximum_size_m", [maximum_size_m.x, maximum_size_m.y]),
		maximum_size_m
	)
	vertical_jitter_m = float(plugin_config.get("vertical_jitter_m", vertical_jitter_m))
	base_opacity = clampf(float(plugin_config.get("opacity", base_opacity)), 0.0, 1.0)
	cloud_color = _color_from_array(plugin_config.get("color", [0.96, 0.975, 1.0, 1.0]))
	wind_velocity = Vector2(
		float(plugin_config.get("wind_east_mps", wind_velocity.x)),
		float(plugin_config.get("wind_north_mps", wind_velocity.y))
	)
	_create_assets()
	set_layer_active(false)
	return true


func update_layer(context: Dictionary, delta: float) -> void:
	last_context = context
	var observer_altitude_m: float = float(context.get("altitude_m", INF))
	var atmosphere_intensity: float = float(context.get("intensity", 0.0))
	var should_be_visible: bool = (
		enabled
		and bool(context.get("active", false))
		and observer_altitude_m <= maximum_observer_altitude_m
		and atmosphere_intensity > 0.01
	)
	set_layer_active(should_be_visible)
	if not should_be_visible:
		return
	var observer_body_local: Vector3 = context.get("body_local_position", Vector3.ZERO)
	var observer_direction: Vector3 = context.get("direction", Vector3.UP)
	var body_radius_m: float = float(context.get("body_radius_m", 0.0))
	var surface_height_m: float = float(context.get("surface_height_m", 0.0))
	if not has_anchor or _surface_distance_between(anchor_direction, observer_direction, body_radius_m) > recenter_distance_m:
		_rebuild_patch(observer_direction, body_radius_m, surface_height_m)
	wind_offset += wind_velocity * delta
	if wind_offset.length() > recenter_distance_m:
		_rebuild_patch(observer_direction, body_radius_m, surface_height_m)
	cloud_instance.position = (
		anchor_body_local
		- observer_body_local
		+ anchor_east * wind_offset.x
		+ anchor_north * wind_offset.y
	)
	var altitude_visibility: float = 1.0 - smoothstep(
		maximum_observer_altitude_m * 0.72,
		maximum_observer_altitude_m,
		observer_altitude_m
	)
	var opacity: float = base_opacity * atmosphere_intensity * altitude_visibility
	cloud_material.albedo_color = Color(
		cloud_color.r,
		cloud_color.g,
		cloud_color.b,
		opacity
	)


func set_layer_active(value: bool) -> void:
	super.set_layer_active(value)
	if cloud_instance != null:
		cloud_instance.visible = value


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.create_snapshot()
	snapshot.merge({
		"schema": "planet_simulator.atmosphere_plugin.cloud_layer_runtime.v1",
		"altitude_m": cloud_altitude_m,
		"thickness_m": cloud_thickness_m,
		"generated_instances": generated_instances,
		"rebuild_count": rebuild_count,
		"patch_radius_m": patch_radius_m,
		"wind_offset_m": [wind_offset.x, wind_offset.y],
	}, true)
	return snapshot


func _create_assets() -> void:
	cloud_instance = MultiMeshInstance3D.new()
	cloud_instance.name = "CloudPatchLayer"
	cloud_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud_instance)

	cloud_material = StandardMaterial3D.new()
	cloud_material.albedo_texture = _create_cloud_texture()
	cloud_material.albedo_color = Color(cloud_color.r, cloud_color.g, cloud_color.b, base_opacity)
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloud_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = cloud_material
	cloud_multimesh = MultiMesh.new()
	cloud_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	cloud_multimesh.mesh = quad
	cloud_multimesh.instance_count = 0
	cloud_instance.multimesh = cloud_multimesh

	density_noise = FastNoiseLite.new()
	density_noise.seed = seed
	density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	density_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	density_noise.fractal_octaves = 4
	density_noise.fractal_gain = 0.56
	density_noise.frequency = 1.0 / macro_noise_scale_m


func _rebuild_patch(
	new_anchor_direction: Vector3,
	body_radius_m: float,
	surface_height_m: float
) -> void:
	anchor_direction = new_anchor_direction.normalized()
	anchor_east = _make_east(anchor_direction)
	anchor_north = anchor_east.cross(anchor_direction).normalized()
	anchor_body_local = anchor_direction * (
		body_radius_m
		+ surface_height_m
		+ cloud_altitude_m
	)
	wind_offset = Vector2.ZERO
	has_anchor = true
	rebuild_count += 1

	var latitude: float = asin(clampf(anchor_direction.y, -1.0, 1.0))
	var longitude: float = atan2(anchor_direction.z, anchor_direction.x)
	var latitude_cell: int = floori(latitude * 1000.0)
	var longitude_cell: int = floori(longitude * 1000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ (latitude_cell * 73856093) ^ (longitude_cell * 19349663)
	var transforms: Array[Transform3D] = []
	for _candidate_index in range(candidate_count):
		if transforms.size() >= maximum_instances:
			break
		var radius_t: float = sqrt(rng.randf())
		var angle: float = rng.randf_range(0.0, TAU)
		var offset := Vector2(cos(angle), sin(angle)) * patch_radius_m * radius_t
		var field: float = density_noise.get_noise_2d(
			offset.x + float(latitude_cell) * 113.0,
			offset.y + float(longitude_cell) * 127.0
		)
		var normalized_field: float = field * 0.5 + 0.5
		var threshold: float = 1.0 - coverage
		if normalized_field < threshold or rng.randf() > normalized_field:
			continue
		var tangent_offset: Vector3 = anchor_east * offset.x + anchor_north * offset.y
		var direction: Vector3 = (
			anchor_direction + tangent_offset / maxf(1.0, body_radius_m)
		).normalized()
		var vertical_half_range: float = maxf(
			vertical_jitter_m,
			cloud_thickness_m * 0.5
		)
		var layer_height: float = (
			body_radius_m
			+ surface_height_m
			+ cloud_altitude_m
			+ rng.randf_range(-vertical_half_range, vertical_half_range)
		)
		var cloud_body_local: Vector3 = direction * layer_height
		var relative_position: Vector3 = cloud_body_local - anchor_body_local
		var width_m: float = rng.randf_range(minimum_size_m.x, maximum_size_m.x)
		var height_m: float = rng.randf_range(minimum_size_m.y, maximum_size_m.y)
		var cloud_east: Vector3 = _make_east(direction)
		var cloud_north: Vector3 = cloud_east.cross(direction).normalized()
		var rotation_angle: float = rng.randf_range(-PI, PI)
		var rotated_east: Vector3 = (
			cloud_east * cos(rotation_angle)
			+ cloud_north * sin(rotation_angle)
		).normalized()
		var rotated_north: Vector3 = (
			-cloud_east * sin(rotation_angle)
			+ cloud_north * cos(rotation_angle)
		).normalized()
		var basis := Basis(
			rotated_east * width_m,
			rotated_north * height_m,
			direction
		)
		transforms.append(Transform3D(basis, relative_position))
	cloud_multimesh.instance_count = transforms.size()
	for transform_index in range(transforms.size()):
		cloud_multimesh.set_instance_transform(transform_index, transforms[transform_index])
	var aabb_extent: float = patch_radius_m + maximum_size_m.x + cloud_thickness_m
	cloud_multimesh.custom_aabb = AABB(
		Vector3(-aabb_extent, -aabb_extent, -aabb_extent),
		Vector3(aabb_extent * 2.0, aabb_extent * 2.0, aabb_extent * 2.0)
	)
	generated_instances = transforms.size()
	_log_info("cloud_layer_rebuilt", {
		"plugin_id": plugin_id,
		"instances": generated_instances,
		"altitude_m": cloud_altitude_m,
		"patch_radius_m": patch_radius_m,
	})


func _create_cloud_texture() -> ImageTexture:
	var width: int = 128
	var height: int = 64
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var texture_noise := FastNoiseLite.new()
	texture_noise.seed = seed + 91
	texture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	texture_noise.frequency = 0.075
	texture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	texture_noise.fractal_octaves = 4
	for y in range(height):
		var normalized_y: float = (float(y) / float(height - 1)) * 2.0 - 1.0
		for x in range(width):
			var normalized_x: float = (float(x) / float(width - 1)) * 2.0 - 1.0
			var ellipse: float = normalized_x * normalized_x + normalized_y * normalized_y * 2.4
			var radial: float = 1.0 - smoothstep(0.32, 1.0, ellipse)
			var noise_value: float = texture_noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var alpha: float = clampf(radial * smoothstep(0.22, 0.72, noise_value + radial * 0.34), 0.0, 1.0)
			var brightness: float = lerpf(0.82, 1.0, noise_value)
			image.set_pixel(x, y, Color(brightness, brightness, 1.0, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _surface_distance_between(first: Vector3, second: Vector3, radius_m: float) -> float:
	var angle: float = acos(clampf(first.normalized().dot(second.normalized()), -1.0, 1.0))
	return angle * radius_m


func _make_east(direction: Vector3) -> Vector3:
	var east: Vector3 = Vector3.UP.cross(direction)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(direction)
	return east.normalized()


func _vector2_from_array(value, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


func _color_from_array(value) -> Color:
	if value is Array and value.size() >= 3:
		return Color(
			float(value[0]),
			float(value[1]),
			float(value[2]),
			float(value[3]) if value.size() >= 4 else 1.0
		)
	return Color.WHITE
