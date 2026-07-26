extends Node

const PlanetAtmosphereScript = preload(
	"res://scripts/world/atmosphere/planet_atmosphere.gd"
)

var celestial_system
var body_worlds: Dictionary = {}
var world_environment: WorldEnvironment
var baseline_environment: Environment
var active_environment: Environment
var atmosphere_sky: Sky
var sky_material: ProceduralSkyMaterial
var logger
var atmospheres: Dictionary = {}
var initialized: bool = false
var active_body_id: String = ""
var last_applied_body_id: String = ""
var last_applied_altitude_m: float = INF
var last_applied_intensity: float = -1.0
var last_applied_up_direction: Vector3 = Vector3.ZERO
var last_summary: Dictionary = {}


func setup(
	celestial_reference,
	body_world_references: Dictionary,
	world_environment_reference: WorldEnvironment,
	logger_reference = null
) -> bool:
	if initialized:
		return true
	celestial_system = celestial_reference
	body_worlds = body_world_references.duplicate()
	world_environment = world_environment_reference
	logger = logger_reference
	if celestial_system == null:
		_log_error("atmosphere_manager_missing_celestial_system", {})
		return false
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "AtmosphereWorldEnvironment"
		add_child(world_environment)
	if world_environment.environment == null:
		world_environment.environment = _create_fallback_environment()
	baseline_environment = world_environment.environment
	active_environment = baseline_environment.duplicate(true) as Environment
	if active_environment == null:
		active_environment = _create_fallback_environment()
	_create_sky_resources()
	_load_planet_atmospheres()
	initialized = true
	_log_info("atmosphere_manager_initialized", {
		"body_ids": atmospheres.keys(),
		"environment_owner": world_environment.get_path(),
	})
	return true


func update_for_observer(space_position: Vector3, camera: Camera3D, delta: float) -> void:
	if not initialized:
		return
	var selected_atmosphere
	var selected_state: Dictionary = {}
	var selected_score: float = 0.0
	for body_id_value in atmospheres.keys():
		var body_id: String = String(body_id_value)
		var atmosphere = atmospheres[body_id]
		var state: Dictionary = atmosphere.update_for_observer(space_position, camera, delta)
		var score: float = float(state.get("intensity", 0.0))
		if bool(state.get("active", false)) and score > selected_score:
			selected_score = score
			selected_atmosphere = atmosphere
			selected_state = state
	if selected_atmosphere == null:
		_restore_baseline_environment()
		active_body_id = ""
		last_summary = {
			"active": false,
			"body_id": "",
			"intensity": 0.0,
		}
		return
	active_body_id = String(selected_state.get("body_id", ""))
	_apply_atmosphere_environment(selected_atmosphere, selected_state)
	last_summary = {
		"active": true,
		"body_id": active_body_id,
		"altitude_m": float(selected_state.get("altitude_m", 0.0)),
		"intensity": selected_score,
		"plugins": selected_atmosphere.get_plugin_ids(),
	}


func deactivate() -> void:
	for atmosphere in atmospheres.values():
		atmosphere.deactivate()
	active_body_id = ""
	last_summary = {
		"active": false,
		"body_id": "",
		"intensity": 0.0,
	}
	_restore_baseline_environment()


func get_runtime_summary() -> Dictionary:
	return last_summary.duplicate(true)


func create_snapshot() -> Dictionary:
	var atmosphere_snapshots: Dictionary = {}
	for body_id_value in atmospheres.keys():
		var body_id: String = String(body_id_value)
		atmosphere_snapshots[body_id] = atmospheres[body_id].create_snapshot()
	return {
		"schema": "planet_simulator.atmosphere_manager_runtime.v1",
		"initialized": initialized,
		"active_body_id": active_body_id,
		"last_summary": last_summary.duplicate(true),
		"atmospheres": atmosphere_snapshots,
	}


func _load_planet_atmospheres() -> void:
	for body_id in celestial_system.get_body_ids():
		var config_path: String = celestial_system.get_atmosphere_config_path(body_id)
		if config_path.is_empty():
			continue
		var atmosphere = PlanetAtmosphereScript.new()
		atmosphere.name = "%sAtmosphere" % body_id.capitalize()
		add_child(atmosphere)
		if not atmosphere.setup(
			config_path,
			celestial_system,
			body_worlds.get(body_id),
			logger
		):
			atmosphere.queue_free()
			continue
		atmospheres[body_id] = atmosphere


func _create_sky_resources() -> void:
	atmosphere_sky = Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	atmosphere_sky.sky_material = sky_material
	active_environment.background_mode = Environment.BG_SKY
	active_environment.sky = atmosphere_sky
	active_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	active_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	active_environment.ambient_light_sky_contribution = 0.0


func _apply_atmosphere_environment(atmosphere, state: Dictionary) -> void:
	if world_environment.environment != active_environment:
		world_environment.environment = active_environment
	var altitude_m: float = maxf(0.0, float(state.get("altitude_m", 0.0)))
	var intensity: float = clampf(float(state.get("intensity", 0.0)), 0.0, 1.0)
	var environment_config: Dictionary = atmosphere.get_environment_config()

	# ProceduralSkyMaterial assumes that its +Y axis is the zenith. On a
	# spherical world the observer's zenith is the radial vector from the body
	# centre, not the global +Y axis. Environment.sky_rotation is therefore
	# updated independently from color/altitude throttling.
	_apply_local_sky_orientation(environment_config, state)

	if (
		last_applied_body_id == active_body_id
		and absf(last_applied_altitude_m - altitude_m) < 50.0
		and absf(last_applied_intensity - intensity) < 0.002
	):
		return
	last_applied_body_id = active_body_id
	last_applied_altitude_m = altitude_m
	last_applied_intensity = intensity
	var fog_config: Dictionary = atmosphere.get_fog_config()
	var top_altitude_m: float = maxf(1.0, atmosphere.top_altitude_m)
	var altitude_t: float = clampf(altitude_m / top_altitude_m, 0.0, 1.0)
	var upper_t: float = smoothstep(0.0, 1.0, altitude_t)

	var space_color: Color = _color_from_array(
		environment_config.get("space_color", [0.00015, 0.00018, 0.00035, 1.0])
	)
	var surface_top: Color = _color_from_array(
		environment_config.get("surface_sky_top", [0.08, 0.32, 0.72, 1.0])
	)
	var surface_horizon: Color = _color_from_array(
		environment_config.get("surface_sky_horizon", [0.48, 0.72, 0.96, 1.0])
	)
	var surface_ground_horizon: Color = _color_from_array(
		environment_config.get("surface_ground_horizon", [0.42, 0.61, 0.78, 1.0])
	)
	var surface_ground_bottom: Color = _color_from_array(
		environment_config.get("surface_ground_bottom", [0.06, 0.10, 0.16, 1.0])
	)
	var upper_top: Color = _color_from_array(
		environment_config.get("upper_sky_top", [0.004, 0.018, 0.065, 1.0])
	)
	var upper_horizon: Color = _color_from_array(
		environment_config.get("upper_sky_horizon", [0.06, 0.18, 0.36, 1.0])
	)

	var top_color: Color = surface_top.lerp(upper_top, upper_t).lerp(space_color, 1.0 - intensity)
	var horizon_color: Color = surface_horizon.lerp(upper_horizon, upper_t).lerp(
		space_color,
		1.0 - intensity
	)
	var ground_horizon: Color = surface_ground_horizon.lerp(upper_horizon, upper_t).lerp(
		space_color,
		1.0 - intensity
	)
	# Matching both horizon colors removes the one-pixel discontinuity between
	# ProceduralSkyMaterial's sky and ground hemispheres. The lower hemisphere
	# can still darken normally through ground_bottom_color.
	if bool(environment_config.get("continuous_horizon", true)):
		ground_horizon = horizon_color
	var ground_bottom: Color = surface_ground_bottom.lerp(space_color, upper_t)
	_set_property_if_present(sky_material, "sky_top_color", top_color)
	_set_property_if_present(sky_material, "sky_horizon_color", horizon_color)
	_set_property_if_present(sky_material, "ground_horizon_color", ground_horizon)
	_set_property_if_present(sky_material, "ground_bottom_color", ground_bottom)
	_set_property_if_present(sky_material, "sky_curve", 0.12 + upper_t * 0.18)
	_set_property_if_present(sky_material, "ground_curve", 0.10 + upper_t * 0.20)
	var sky_energy: float = lerpf(
		float(environment_config.get("sky_energy_surface", 1.0)),
		float(environment_config.get("sky_energy_upper", 0.20)),
		upper_t
	) * maxf(0.05, intensity)
	_set_property_if_present(sky_material, "sky_energy_multiplier", sky_energy)
	_set_property_if_present(sky_material, "ground_energy_multiplier", sky_energy * 0.72)

	var ambient_surface: Color = _color_from_array(
		environment_config.get("ambient_surface_color", [0.49, 0.62, 0.78, 1.0])
	)
	active_environment.ambient_light_color = ambient_surface.lerp(space_color, upper_t)
	active_environment.ambient_light_energy = lerpf(
		float(environment_config.get("ambient_surface_energy", 0.72)),
		float(environment_config.get("ambient_space_energy", 0.34)),
		upper_t
	)
	_apply_fog(fog_config, altitude_m, intensity)


func _apply_local_sky_orientation(
	environment_config: Dictionary,
	state: Dictionary
) -> void:
	if not bool(environment_config.get("align_sky_to_local_up", true)):
		if last_applied_up_direction != Vector3.UP:
			active_environment.sky_rotation = Vector3.ZERO
			last_applied_up_direction = Vector3.UP
		return

	var local_up: Vector3 = _vector3_from_value(
		state.get("local_up", [0.0, 1.0, 0.0]),
		Vector3.UP
	)
	if local_up.length_squared() < 0.5:
		local_up = Vector3.UP
	else:
		local_up = local_up.normalized()

	# Avoid rewriting the Environment resource when the radial direction has
	# not changed enough to affect the rendered horizon.
	if (
		last_applied_up_direction.length_squared() > 0.5
		and last_applied_up_direction.dot(local_up) > 0.9999995
	):
		return

	# This basis maps the procedural sky's local +Y to the body's radial up.
	# Godot internally applies the inverse sky orientation before the camera
	# basis, which is exactly the required world-to-sky conversion.
	var sky_orientation := Basis(Quaternion(Vector3.UP, local_up)).orthonormalized()
	active_environment.sky_rotation = sky_orientation.get_euler()
	last_applied_up_direction = local_up


func _vector3_from_value(value, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(
			float(value[0]),
			float(value[1]),
			float(value[2])
		)
	return fallback


func _apply_fog(fog_config: Dictionary, altitude_m: float, intensity: float) -> void:
	var fog_enabled: bool = bool(fog_config.get("enabled", true))
	var maximum_altitude_m: float = maxf(
		1.0,
		float(fog_config.get("maximum_altitude_m", 24000.0))
	)
	var fog_t: float = clampf(altitude_m / maximum_altitude_m, 0.0, 1.0)
	var exponent: float = maxf(0.1, float(fog_config.get("density_exponent", 1.65)))
	var density: float = (
		float(fog_config.get("surface_density", 0.000035))
		* pow(1.0 - fog_t, exponent)
		* intensity
	)
	_set_property_if_present(
		active_environment,
		"fog_enabled",
		fog_enabled and density > 0.0000001
	)
	_set_property_if_present(active_environment, "fog_density", density)
	_set_property_if_present(
		active_environment,
		"fog_light_color",
		_color_from_array(fog_config.get("light_color", [0.62, 0.76, 0.94, 1.0]))
	)
	_set_property_if_present(
		active_environment,
		"fog_light_energy",
		float(fog_config.get("light_energy", 0.72))
	)
	_set_property_if_present(
		active_environment,
		"fog_sky_affect",
		float(fog_config.get("sky_affect", 0.28))
	)


func _restore_baseline_environment() -> void:
	last_applied_body_id = ""
	last_applied_altitude_m = INF
	last_applied_intensity = -1.0
	last_applied_up_direction = Vector3.ZERO
	if world_environment != null and baseline_environment != null:
		world_environment.environment = baseline_environment


func _create_fallback_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.00015, 0.00018, 0.00035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.23, 0.245, 0.285)
	environment.ambient_light_energy = 0.34
	return environment


func _set_property_if_present(target: Object, property_name: String, value) -> void:
	for property_info in target.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			target.set(property_name, value)
			return


func _color_from_array(value) -> Color:
	if value is Array and value.size() >= 3:
		return Color(
			float(value[0]),
			float(value[1]),
			float(value[2]),
			float(value[3]) if value.size() >= 4 else 1.0
		)
	if value is Color:
		return value
	return Color.WHITE


func _log_info(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.info("atmosphere", event_name, data)


func _log_error(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.error("atmosphere", event_name, data)
