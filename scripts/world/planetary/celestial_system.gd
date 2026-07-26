extends Node3D

const CONFIG_PATH: String = "res://config/planets/celestial_system.json"

var config: Dictionary = {}
var bodies: Dictionary = {}
var earth_proxy: MeshInstance3D
var initialized: bool = false


func setup() -> bool:
	config = _load_json(CONFIG_PATH)
	if config.is_empty():
		return false
	for body_value in config.get("bodies", []):
		if body_value is Dictionary:
			bodies[String(body_value.get("id", "unknown"))] = body_value
	_create_earth_proxy()
	initialized = true
	return true


func set_moon_view_active(value: bool) -> void:
	set_proxy_visibility(value)


func set_proxy_visibility(value: bool) -> void:
	if earth_proxy != null:
		earth_proxy.visible = value


func get_body_ids() -> Array[String]:
	var result: Array[String] = []
	for body_id_value in bodies.keys():
		result.append(String(body_id_value))
	return result


func to_body_local(space_position: Vector3, body_id: String) -> Vector3:
	return space_position - get_body_center(body_id)


func to_space(body_local_position: Vector3, body_id: String) -> Vector3:
	return get_body_center(body_id) + body_local_position


func get_surface_distance(body_id: String, space_position: Vector3) -> float:
	return to_body_local(space_position, body_id).length() - get_body_radius(body_id)


func get_nearest_body_id(space_position: Vector3) -> String:
	var nearest_id: String = ""
	var nearest_distance: float = INF
	for body_id in get_body_ids():
		var distance_to_surface: float = absf(get_surface_distance(body_id, space_position))
		if distance_to_surface < nearest_distance:
			nearest_distance = distance_to_surface
			nearest_id = body_id
	return nearest_id


func get_space_snapshot(space_position: Vector3) -> Dictionary:
	var distances: Dictionary = {}
	for body_id in get_body_ids():
		distances[body_id] = get_surface_distance(body_id, space_position)
	return {
		"schema": "planet_simulator.space_observer.v1",
		"space_position_m": [space_position.x, space_position.y, space_position.z],
		"nearest_body_id": get_nearest_body_id(space_position),
		"surface_distances_m": distances,
	}


func get_body_center(body_id: String) -> Vector3:
	var body: Dictionary = bodies.get(body_id, {})
	var values = body.get("absolute_center_m", [0.0, 0.0, 0.0])
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO


func get_body_radius(body_id: String) -> float:
	return float(bodies.get(body_id, {}).get("radius_m", 0.0))


func get_body_config(body_id: String) -> Dictionary:
	return bodies.get(body_id, {}).duplicate(true)


func get_atmosphere_config_path(body_id: String) -> String:
	return String(bodies.get(body_id, {}).get("atmosphere_config", ""))


func get_distance_between(first_body_id: String, second_body_id: String) -> float:
	return (get_body_center(first_body_id) - get_body_center(second_body_id)).length()


func create_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.celestial_system_runtime.v1",
		"distance_model": config.get("distance_model", "unknown"),
		"render_model": config.get("render_model", "unknown"),
		"earth_moon_distance_m": get_distance_between("earth", "moon"),
		"body_ids": bodies.keys(),
		"atmosphere_bodies": _get_atmosphere_body_ids(),
	}


func _get_atmosphere_body_ids() -> Array[String]:
	var result: Array[String] = []
	for body_id in get_body_ids():
		if not get_atmosphere_config_path(body_id).is_empty():
			result.append(body_id)
	return result


func _create_earth_proxy() -> void:
	var moon_center: Vector3 = get_body_center("moon")
	var earth_center: Vector3 = get_body_center("earth")
	var real_delta: Vector3 = earth_center - moon_center
	var real_distance: float = maxf(1.0, real_delta.length())
	var proxy_distance: float = float(config.get("proxy_render_distance_m", 500000.0))
	var angular_radius: float = get_body_radius("earth") / real_distance
	var proxy_radius: float = proxy_distance * angular_radius

	earth_proxy = MeshInstance3D.new()
	earth_proxy.name = "EarthAngularSizeProxy"
	var sphere := SphereMesh.new()
	sphere.radius = proxy_radius
	sphere.height = proxy_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	earth_proxy.mesh = sphere
	earth_proxy.position = real_delta.normalized() * proxy_distance
	earth_proxy.material_override = _create_proxy_material()
	earth_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth_proxy)


func _create_proxy_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _create_proxy_texture()
	material.roughness = 0.78
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _create_proxy_texture() -> ImageTexture:
	var width: int = 512
	var height: int = 256
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 20260726
	noise.frequency = 1.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	for y in range(height):
		var latitude: float = (float(y) / float(height - 1) - 0.5) * PI
		var horizontal: float = cos(latitude)
		for x in range(width):
			var longitude: float = float(x) / float(width - 1) * TAU
			var direction := Vector3(
				horizontal * cos(longitude),
				sin(latitude),
				horizontal * sin(longitude)
			)
			var field: float = noise.get_noise_3d(
				direction.x * 2.2,
				direction.y * 2.2,
				direction.z * 2.2
			)
			var polar: float = smoothstep(0.76, 0.94, absf(direction.y))
			var color := Color(0.025, 0.19, 0.43)
			if field > -0.03:
				color = Color(0.10, 0.34, 0.09).lerp(
					Color(0.45, 0.38, 0.19),
					smoothstep(0.38, 0.75, field)
				)
			color = color.lerp(Color(0.94, 0.97, 1.0), polar)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
