extends Node

var actor
var world
var profile: Dictionary = {}
var logger
var enabled: bool = true


func setup(actor_reference, world_reference, profile_value: Dictionary, logger_reference = null) -> void:
	actor = actor_reference
	world = world_reference
	profile = profile_value.duplicate(true)
	logger = logger_reference


func set_enabled(value: bool) -> void:
	enabled = value


func on_activated() -> void:
	pass


func on_deactivated() -> void:
	pass


func physics_step(_delta: float) -> void:
	pass


func handle_input(event: InputEvent) -> void:
	if not enabled or actor == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var camera_config: Dictionary = profile.get("camera", {})
		var sensitivity: float = float(camera_config.get("mouse_sensitivity", 0.00125))
		actor.adjust_view(
			-event.relative.x * sensitivity,
			-event.relative.y * sensitivity
		)


func get_profile_id() -> String:
	return String(profile.get("profile_id", "unknown"))


func get_display_name() -> String:
	return String(profile.get("display_name", get_profile_id()))


func get_capabilities() -> Array:
	var value = profile.get("capabilities", [])
	return value.duplicate(true) if value is Array else []


func _movement_config() -> Dictionary:
	var value = profile.get("movement", {})
	return value if value is Dictionary else {}
