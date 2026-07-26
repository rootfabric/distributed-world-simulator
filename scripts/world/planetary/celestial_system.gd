extends Node3D

const CONFIG_PATH: String = "res://config/planets/celestial_system.json"
const SimulationClockScript = preload(
	"res://scripts/simulation/time/simulation_clock.gd"
)
const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)
const FrameGraphScript = preload(
	"res://scripts/simulation/frames/frame_graph.gd"
)
const OrbitProviderScript = preload(
	"res://scripts/simulation/frames/providers/orbit_provider.gd"
)
const RotationProviderScript = preload(
	"res://scripts/simulation/frames/providers/rotation_provider.gd"
)
const FrameMotionProviderScript = preload(
	"res://scripts/simulation/frames/providers/frame_motion_provider.gd"
)

var config: Dictionary = {}
var all_bodies: Dictionary = {}
var bodies: Dictionary = {}
var body_order: Array[String] = []
var frame_graph
var simulation_clock
var owns_clock: bool = false
var earth_proxy: MeshInstance3D
var initialized: bool = false
var universe_id: String = "main"
var instance_id: String = "persistent"
var space_id: String = "sol"
var root_frame_id: String = "sol.barycentric"


func setup(
	body_filter: Array[String] = [],
	clock_reference = null,
	instance_id_value: String = "persistent"
) -> bool:
	_reset_runtime_state()
	config = _load_json(CONFIG_PATH)
	if config.is_empty():
		return false
	universe_id = String(config.get("universe_id", "main"))
	instance_id = instance_id_value
	space_id = String(config.get("space_id", "sol"))
	root_frame_id = String(config.get("root_frame_id", "sol.barycentric"))
	simulation_clock = clock_reference
	if simulation_clock == null:
		simulation_clock = SimulationClockScript.new()
		simulation_clock.setup(config.get("clock", {}))
		owns_clock = true
	all_bodies.clear()
	bodies.clear()
	body_order.clear()
	for body_value in config.get("bodies", []):
		if not body_value is Dictionary:
			continue
		var body: Dictionary = body_value.duplicate(true)
		var body_id: String = String(body.get("id", ""))
		if body_id.is_empty():
			continue
		all_bodies[body_id] = body
		body_order.append(body_id)
		if body_filter.is_empty() or body_filter.has(body_id):
			bodies[body_id] = body
	if bodies.is_empty():
		return false
	if not _build_frame_graph():
		return false
	if bodies.has("earth") and bodies.has("moon"):
		_create_earth_proxy()
	set_process(true)
	initialized = true
	return true


func _reset_runtime_state() -> void:
	set_process(false)
	initialized = false
	owns_clock = false
	simulation_clock = null
	frame_graph = null
	if earth_proxy != null and is_instance_valid(earth_proxy):
		if earth_proxy.get_parent() != null:
			earth_proxy.get_parent().remove_child(earth_proxy)
		earth_proxy.free()
	earth_proxy = null


func _process(delta: float) -> void:
	if owns_clock and simulation_clock != null:
		simulation_clock.advance(delta)
	if initialized and earth_proxy != null and earth_proxy.visible:
		_update_earth_proxy()


func set_moon_view_active(value: bool) -> void:
	set_proxy_visibility(value)


func set_proxy_visibility(value: bool) -> void:
	if earth_proxy != null:
		earth_proxy.visible = value
		if value:
			_update_earth_proxy()


func get_body_ids() -> Array[String]:
	var result: Array[String] = []
	for body_id in body_order:
		if bodies.has(body_id):
			result.append(body_id)
	return result


func get_root_frame_id() -> String:
	return root_frame_id


func get_universe_id() -> String:
	return universe_id


func get_space_id() -> String:
	return space_id


func get_current_time_s() -> float:
	return (
		float(simulation_clock.get_time_seconds())
		if simulation_clock != null
		else 0.0
	)


func get_body_inertial_frame_id(body_id: String) -> String:
	return String(all_bodies.get(body_id, {}).get(
		"inertial_frame_id",
		"body/%s/inertial" % body_id
	))


func get_body_fixed_frame_id(body_id: String) -> String:
	return String(all_bodies.get(body_id, {}).get(
		"body_fixed_frame_id",
		"body/%s/fixed" % body_id
	))


func has_frame(frame_id: String) -> bool:
	return frame_graph != null and frame_graph.has_frame(frame_id)


func to_body_local(
	space_position: Vector3,
	body_id: String,
	sample_time_s: float = INF
) -> Vector3:
	return transform_point(
		space_position,
		root_frame_id,
		get_body_fixed_frame_id(body_id),
		_resolve_time(sample_time_s)
	)


func to_space(
	body_local_position: Vector3,
	body_id: String,
	sample_time_s: float = INF
) -> Vector3:
	return transform_point(
		body_local_position,
		get_body_fixed_frame_id(body_id),
		root_frame_id,
		_resolve_time(sample_time_s)
	)


func transform_point(
	position: Vector3,
	source_frame_id: String,
	target_frame_id: String,
	sample_time_s: float = INF
) -> Vector3:
	if frame_graph == null:
		return Vector3.ZERO
	return frame_graph.transform_point(
		position,
		source_frame_id,
		target_frame_id,
		_resolve_time(sample_time_s)
	)


func transform_direction(
	direction: Vector3,
	source_frame_id: String,
	target_frame_id: String,
	sample_time_s: float = INF
) -> Vector3:
	if frame_graph == null:
		return direction
	return frame_graph.transform_direction(
		direction,
		source_frame_id,
		target_frame_id,
		_resolve_time(sample_time_s)
	)


func get_relative_basis(
	source_frame_id: String,
	target_frame_id: String,
	sample_time_s: float = INF
) -> Basis:
	if frame_graph == null:
		return Basis.IDENTITY
	return frame_graph.get_relative_basis(
		source_frame_id,
		target_frame_id,
		_resolve_time(sample_time_s)
	)


func create_spatial_ref(
	frame_id: String,
	position_m: Vector3,
	basis_value: Basis = Basis.IDENTITY,
	linear_velocity_mps: Vector3 = Vector3.ZERO,
	angular_velocity_rps: Vector3 = Vector3.ZERO,
	sample_time_s: float = INF
) -> Dictionary:
	return SpatialRefScript.create(
		frame_id,
		position_m,
		basis_value,
		linear_velocity_mps,
		angular_velocity_rps,
		_resolve_time(sample_time_s),
		universe_id,
		space_id,
		instance_id
	)


func transform_spatial_ref(
	spatial_ref: Dictionary,
	target_frame_id: String,
	sample_time_s: float = INF
) -> Dictionary:
	if frame_graph == null:
		return {}
	var resolved_time_s: float = (
		float(spatial_ref.get("sample_time_s", get_current_time_s()))
		if sample_time_s == INF
		else sample_time_s
	)
	return frame_graph.transform_spatial_ref(
		spatial_ref,
		target_frame_id,
		resolved_time_s
	)


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
		"schema": "planet_simulator.space_observer.v2",
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"root_frame_id": root_frame_id,
		"sample_time_s": get_current_time_s(),
		"space_position_m": [space_position.x, space_position.y, space_position.z],
		"nearest_body_id": get_nearest_body_id(space_position),
		"surface_distances_m": distances,
	}


func get_body_center(body_id: String, sample_time_s: float = INF) -> Vector3:
	if frame_graph == null:
		return Vector3.ZERO
	var state: Dictionary = frame_graph.get_frame_state_in_root(
		get_body_inertial_frame_id(body_id),
		_resolve_time(sample_time_s)
	)
	return state.get("origin_root_m", Vector3.ZERO)


func get_body_velocity(body_id: String, sample_time_s: float = INF) -> Vector3:
	if frame_graph == null:
		return Vector3.ZERO
	var state: Dictionary = frame_graph.get_frame_state_in_root(
		get_body_inertial_frame_id(body_id),
		_resolve_time(sample_time_s)
	)
	return state.get("linear_velocity_root_mps", Vector3.ZERO)


func get_body_radius(body_id: String) -> float:
	return float(all_bodies.get(body_id, {}).get("radius_m", 0.0))


func get_body_config(body_id: String) -> Dictionary:
	return all_bodies.get(body_id, {}).duplicate(true)


func get_atmosphere_config_path(body_id: String) -> String:
	return String(all_bodies.get(body_id, {}).get("atmosphere_config", ""))


func get_distance_between(
	first_body_id: String,
	second_body_id: String,
	sample_time_s: float = INF
) -> float:
	var time_s: float = _resolve_time(sample_time_s)
	return (
		get_body_center(first_body_id, time_s)
		- get_body_center(second_body_id, time_s)
	).length()


func create_snapshot() -> Dictionary:
	var time_s: float = get_current_time_s()
	var body_states: Dictionary = {}
	for body_id in get_body_ids():
		var center: Vector3 = get_body_center(body_id, time_s)
		var velocity: Vector3 = get_body_velocity(body_id, time_s)
		body_states[body_id] = {
			"inertial_frame_id": get_body_inertial_frame_id(body_id),
			"body_fixed_frame_id": get_body_fixed_frame_id(body_id),
			"center_root_m": [center.x, center.y, center.z],
			"velocity_root_mps": [velocity.x, velocity.y, velocity.z],
			"radius_m": get_body_radius(body_id),
		}
	return {
		"schema": "planet_simulator.celestial_system_runtime.v2",
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"root_frame_id": root_frame_id,
		"motion_model": config.get("motion_model", "unknown"),
		"render_model": config.get("render_model", "unknown"),
		"sample_time_s": time_s,
		"earth_moon_distance_m": (
			get_distance_between("earth", "moon", time_s)
			if all_bodies.has("earth") and all_bodies.has("moon")
			else 0.0
		),
		"body_ids": get_body_ids(),
		"body_states": body_states,
		"atmosphere_bodies": _get_atmosphere_body_ids(),
		"clock": simulation_clock.create_snapshot() if simulation_clock != null else {},
		"frame_graph": frame_graph.create_snapshot(time_s) if frame_graph != null else {},
	}


func _build_frame_graph() -> bool:
	frame_graph = FrameGraphScript.new()
	if not frame_graph.setup(root_frame_id, {
		"kind": "star_system_barycentric",
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
	}):
		return false
	var pending_body_ids: Array[String] = body_order.duplicate()
	while not pending_body_ids.is_empty():
		var progressed: bool = false
		for body_id in pending_body_ids.duplicate():
			var body: Dictionary = all_bodies[body_id]
			var parent_frame_id: String = String(body.get("parent_frame_id", root_frame_id))
			if not frame_graph.has_frame(parent_frame_id):
				continue
			if not _add_body_frames(body_id, body, parent_frame_id):
				return false
			pending_body_ids.erase(body_id)
			progressed = true
		if not progressed:
			return false
	return true


func _add_body_frames(
	body_id: String,
	body: Dictionary,
	parent_frame_id: String
) -> bool:
	var inertial_frame_id: String = get_body_inertial_frame_id(body_id)
	var fixed_frame_id: String = get_body_fixed_frame_id(body_id)
	var orbit_provider = OrbitProviderScript.new()
	orbit_provider.setup(body.get("orbit", {"type": "static"}))
	var inertial_motion = FrameMotionProviderScript.new()
	inertial_motion.setup(orbit_provider, null)
	if not frame_graph.add_frame(
		inertial_frame_id,
		parent_frame_id,
		inertial_motion,
		{
			"kind": "body_centered_inertial",
			"body_id": body_id,
			"authority_space_id": String(body.get("authority_space_id", body_id)),
		}
	):
		return false
	var rotation_provider = RotationProviderScript.new()
	rotation_provider.setup(body.get("rotation", {"type": "static"}), orbit_provider)
	var fixed_motion = FrameMotionProviderScript.new()
	fixed_motion.setup(null, rotation_provider)
	return frame_graph.add_frame(
		fixed_frame_id,
		inertial_frame_id,
		fixed_motion,
		{
			"kind": "body_fixed",
			"body_id": body_id,
			"authority_space_id": String(body.get("authority_space_id", body_id)),
		}
	)


func _get_atmosphere_body_ids() -> Array[String]:
	var result: Array[String] = []
	for body_id in get_body_ids():
		if not get_atmosphere_config_path(body_id).is_empty():
			result.append(body_id)
	return result


func _create_earth_proxy() -> void:
	earth_proxy = MeshInstance3D.new()
	earth_proxy.name = "EarthAngularSizeProxy"
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24
	earth_proxy.mesh = sphere
	earth_proxy.material_override = _create_proxy_material()
	earth_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth_proxy)
	_update_earth_proxy()


func _update_earth_proxy() -> void:
	if earth_proxy == null or frame_graph == null:
		return
	var time_s: float = get_current_time_s()
	var real_delta: Vector3 = frame_graph.transform_point(
		Vector3.ZERO,
		get_body_fixed_frame_id("earth"),
		get_body_fixed_frame_id("moon"),
		time_s
	)
	var real_distance: float = maxf(1.0, real_delta.length())
	var proxy_distance: float = float(config.get("proxy_render_distance_m", 500000.0))
	var radius_ratio: float = clampf(
		get_body_radius("earth") / real_distance,
		0.0,
		0.999999
	)
	var angular_radius: float = asin(radius_ratio)
	var proxy_radius: float = proxy_distance * tan(angular_radius)
	var sphere := earth_proxy.mesh as SphereMesh
	if sphere != null:
		sphere.radius = proxy_radius
		sphere.height = proxy_radius * 2.0
	earth_proxy.position = real_delta.normalized() * proxy_distance


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


func _resolve_time(sample_time_s: float) -> float:
	return get_current_time_s() if sample_time_s == INF else sample_time_s


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
