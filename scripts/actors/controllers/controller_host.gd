extends Node

signal controller_changed(previous_id: String, current_id: String)

const ProfileLoaderScript = preload(
	"res://scripts/actors/controllers/controller_profile_loader.gd"
)
const PROFILE_PATHS := {
	"lunar_humanoid": "res://config/controllers/lunar_humanoid.json",
	"lunar_jetpack": "res://config/controllers/lunar_jetpack.json",
	"earth_humanoid": "res://config/controllers/earth_humanoid.json",
}

var actor
var world
var logger
var profiles: Dictionary = {}
var current_controller
var current_profile_id: String = ""
var enabled: bool = true


func setup(actor_reference, world_reference, logger_reference = null) -> void:
	actor = actor_reference
	world = world_reference
	logger = logger_reference
	_load_profiles()
	activate_controller("lunar_humanoid", false)


func _load_profiles() -> void:
	profiles.clear()
	for profile_id in PROFILE_PATHS.keys():
		var path: String = String(PROFILE_PATHS[profile_id])
		var profile: Dictionary = ProfileLoaderScript.load_profile(path)
		if profile.is_empty():
			_log("ERROR", "controller_profile_load_failed", {
				"profile_id": profile_id,
				"path": path,
			})
			continue
		profiles[String(profile.get("profile_id", profile_id))] = profile


func activate_controller(profile_id: String, preserve_camera_mode: bool = true) -> bool:
	if not profiles.has(profile_id):
		return false
	if profile_id == current_profile_id and current_controller != null:
		return true
	var profile: Dictionary = profiles[profile_id]
	var controller_script_path: String = String(profile.get("controller_script", ""))
	var controller_script = load(controller_script_path)
	if controller_script == null:
		return false
	var previous_id: String = current_profile_id
	if current_controller != null:
		current_controller.on_deactivated()
		current_controller.queue_free()
	current_controller = controller_script.new()
	current_controller.name = "MovementController_%s" % profile_id
	add_child(current_controller)
	current_controller.setup(actor, world, profile, logger)
	current_controller.set_enabled(enabled)
	current_profile_id = profile_id
	actor.apply_camera_profile(
		profile.get("camera", {}),
		not preserve_camera_mode or previous_id.is_empty()
	)
	current_controller.on_activated()
	controller_changed.emit(previous_id, current_profile_id)
	_log("INFO", "controller_activated", {
		"previous_id": previous_id,
		"current_id": current_profile_id,
		"display_name": get_current_display_name(),
	})
	return true


func physics_step(delta: float) -> void:
	if enabled and current_controller != null:
		current_controller.physics_step(delta)


func handle_input(event: InputEvent) -> void:
	if enabled and current_controller != null:
		current_controller.handle_input(event)


func set_enabled(value: bool) -> void:
	enabled = value
	if current_controller != null:
		current_controller.set_enabled(value)


func get_current_profile_id() -> String:
	return current_profile_id


func get_current_display_name() -> String:
	if current_controller == null:
		return "Не выбран"
	return current_controller.get_display_name()


func get_available_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for profile_id in profiles.keys():
		result.append(String(profile_id))
	result.sort()
	return result


func get_profile(profile_id: String) -> Dictionary:
	var value = profiles.get(profile_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func create_snapshot() -> Dictionary:
	return {
		"schema": "lunar.controller_host.v1",
		"current_profile_id": current_profile_id,
		"display_name": get_current_display_name(),
		"enabled": enabled,
		"available_profiles": get_available_profile_ids(),
		"profile": get_profile(current_profile_id),
	}


func _log(level: String, event_name: String, data: Dictionary) -> void:
	if logger == null:
		return
	match level:
		"ERROR":
			logger.error("controller", event_name, data)
		"WARNING":
			logger.warning("controller", event_name, data)
		_:
			logger.info("controller", event_name, data)
