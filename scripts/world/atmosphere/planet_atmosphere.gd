extends Node3D

signal atmosphere_state_changed(body_id: String, active: bool)

var atmosphere_config: Dictionary = {}
var atmosphere_id: String = ""
var body_id: String = ""
var celestial_system
var body_world
var logger
var plugins: Array[Node] = []
var enabled: bool = true
var bottom_altitude_m: float = -1000.0
var top_altitude_m: float = 100000.0
var full_effect_altitude_m: float = 18000.0
var fade_start_altitude_m: float = 65000.0
var active: bool = false
var last_state: Dictionary = {}


func setup(
	config_path: String,
	celestial_reference,
	body_world_reference = null,
	logger_reference = null
) -> bool:
	atmosphere_config = _load_json(config_path)
	if atmosphere_config.is_empty():
		_log_error("atmosphere_config_load_failed", {"path": config_path})
		return false
	celestial_system = celestial_reference
	body_world = body_world_reference
	logger = logger_reference
	atmosphere_id = String(atmosphere_config.get("id", "atmosphere"))
	body_id = String(atmosphere_config.get("body_id", ""))
	enabled = bool(atmosphere_config.get("enabled", true))
	bottom_altitude_m = float(atmosphere_config.get("bottom_altitude_m", bottom_altitude_m))
	top_altitude_m = float(atmosphere_config.get("top_altitude_m", top_altitude_m))
	full_effect_altitude_m = float(
		atmosphere_config.get("full_effect_altitude_m", full_effect_altitude_m)
	)
	fade_start_altitude_m = float(
		atmosphere_config.get("fade_start_altitude_m", fade_start_altitude_m)
	)
	name = atmosphere_id
	if body_id.is_empty() or celestial_system == null:
		_log_error("atmosphere_contract_invalid", {
			"id": atmosphere_id,
			"body_id": body_id,
		})
		return false
	_load_plugins()
	_log_info("planet_atmosphere_initialized", {
		"id": atmosphere_id,
		"body_id": body_id,
		"top_altitude_m": top_altitude_m,
		"plugins": get_plugin_ids(),
	})
	return true


func update_for_observer(space_position: Vector3, camera: Camera3D, delta: float) -> Dictionary:
	var body_local_position: Vector3 = celestial_system.to_body_local(space_position, body_id)
	var direction := Vector3.UP
	if body_local_position.length_squared() > 1.0:
		direction = body_local_position.normalized()
	var surface_height_m: float = _get_surface_height(direction)
	var body_radius_m: float = celestial_system.get_body_radius(body_id)
	var altitude_m: float = body_local_position.length() - body_radius_m - surface_height_m
	var intensity: float = _calculate_intensity(altitude_m)
	var new_active: bool = enabled and intensity > 0.0001 and altitude_m >= bottom_altitude_m
	if new_active != active:
		active = new_active
		atmosphere_state_changed.emit(body_id, active)
		_log_info("atmosphere_state_changed", {
			"body_id": body_id,
			"active": active,
			"altitude_m": altitude_m,
			"intensity": intensity,
		})
	var context: Dictionary = {
		"active": active,
		"atmosphere_id": atmosphere_id,
		"body_id": body_id,
		"space_position": space_position,
		"body_local_position": body_local_position,
		"body_center": celestial_system.get_body_center(body_id),
		"body_radius_m": body_radius_m,
		"surface_height_m": surface_height_m,
		"surface_radius_m": body_radius_m + surface_height_m,
		"altitude_m": altitude_m,
		"direction": direction,
		"intensity": intensity,
		"camera": camera,
		"body_world": body_world,
		"celestial_system": celestial_system,
	}
	for plugin in plugins:
		if plugin != null and plugin.has_method("update_layer"):
			plugin.update_layer(context, delta)
	last_state = {
		"body_id": body_id,
		"active": active,
		"altitude_m": altitude_m,
		"intensity": intensity,
		"surface_height_m": surface_height_m,
		# JSON-safe radial up vector. The environment layer uses it to align
		# a sky material with the local horizon of this spherical body.
		"local_up": [direction.x, direction.y, direction.z],
	}
	return last_state


func deactivate() -> void:
	active = false
	for plugin in plugins:
		if plugin != null and plugin.has_method("set_layer_active"):
			plugin.set_layer_active(false)
	last_state = {
		"body_id": body_id,
		"active": false,
		"altitude_m": INF,
		"intensity": 0.0,
	}


func get_environment_config() -> Dictionary:
	return atmosphere_config.get("environment", {}).duplicate(true)


func get_fog_config() -> Dictionary:
	return atmosphere_config.get("fog", {}).duplicate(true)


func get_last_state() -> Dictionary:
	return last_state.duplicate(true)


func get_plugin_ids() -> Array[String]:
	var result: Array[String] = []
	for plugin in plugins:
		if plugin != null and plugin.has_method("get_plugin_id"):
			result.append(String(plugin.get_plugin_id()))
	return result


func create_snapshot() -> Dictionary:
	var plugin_snapshots: Array = []
	for plugin in plugins:
		if plugin != null and plugin.has_method("create_snapshot"):
			plugin_snapshots.append(plugin.create_snapshot())
	return {
		"schema": "planet_simulator.atmosphere_runtime.v1",
		"id": atmosphere_id,
		"body_id": body_id,
		"enabled": enabled,
		"active": active,
		"bottom_altitude_m": bottom_altitude_m,
		"top_altitude_m": top_altitude_m,
		"last_state": last_state.duplicate(true),
		"plugins": plugin_snapshots,
	}


func _calculate_intensity(altitude_m: float) -> float:
	if altitude_m < bottom_altitude_m or altitude_m >= top_altitude_m:
		return 0.0
	if altitude_m <= full_effect_altitude_m:
		return 1.0
	var fade_start: float = maxf(full_effect_altitude_m, fade_start_altitude_m)
	if altitude_m <= fade_start:
		var upper_t: float = inverse_lerp(full_effect_altitude_m, fade_start, altitude_m)
		return lerpf(1.0, 0.72, smoothstep(0.0, 1.0, upper_t))
	var fade_t: float = inverse_lerp(fade_start, top_altitude_m, altitude_m)
	return 0.72 * (1.0 - smoothstep(0.0, 1.0, fade_t))


func _get_surface_height(direction: Vector3) -> float:
	if body_world != null and body_world.has_method("get_surface_height"):
		return float(body_world.get_surface_height(direction))
	return 0.0


func _load_plugins() -> void:
	for child in plugins:
		if is_instance_valid(child):
			child.queue_free()
	plugins.clear()
	for descriptor_value in atmosphere_config.get("plugins", []):
		if not descriptor_value is Dictionary:
			continue
		var descriptor: Dictionary = descriptor_value
		if not bool(descriptor.get("enabled", true)):
			continue
		var script_path: String = String(descriptor.get("script", ""))
		if script_path.is_empty() or not ResourceLoader.exists(script_path):
			_log_error("atmosphere_plugin_script_missing", {
				"atmosphere_id": atmosphere_id,
				"script": script_path,
			})
			continue
		var plugin_config: Dictionary = {}
		var plugin_config_path: String = String(descriptor.get("config", ""))
		if not plugin_config_path.is_empty():
			plugin_config = _load_json(plugin_config_path)
		for key in descriptor.keys():
			if key != "script" and key != "config":
				plugin_config[key] = descriptor[key]
		var plugin_script = load(script_path)
		var plugin = plugin_script.new()
		add_child(plugin)
		var setup_ok: bool = true
		if plugin.has_method("setup"):
			setup_ok = bool(plugin.setup(self, plugin_config, logger))
		if not setup_ok:
			plugin.queue_free()
			_log_error("atmosphere_plugin_setup_failed", {
				"atmosphere_id": atmosphere_id,
				"script": script_path,
			})
			continue
		plugins.append(plugin)


func _load_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _log_info(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.info("atmosphere", event_name, data)


func _log_error(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.error("atmosphere", event_name, data)
