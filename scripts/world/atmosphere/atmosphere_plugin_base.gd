extends Node3D

var atmosphere_owner
var plugin_config: Dictionary = {}
var logger
var plugin_id: String = "atmosphere_plugin"
var enabled: bool = true
var last_context: Dictionary = {}


func setup(owner_reference, config_value: Dictionary, logger_reference = null) -> bool:
	atmosphere_owner = owner_reference
	plugin_config = config_value.duplicate(true)
	logger = logger_reference
	plugin_id = String(plugin_config.get("id", name))
	enabled = bool(plugin_config.get("enabled", true))
	name = plugin_id
	visible = false
	return true


func update_layer(context: Dictionary, _delta: float) -> void:
	last_context = context
	set_layer_active(enabled and bool(context.get("active", false)))


func set_layer_active(value: bool) -> void:
	visible = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED


func get_plugin_id() -> String:
	return plugin_id


func create_snapshot() -> Dictionary:
	return {
		"id": plugin_id,
		"enabled": enabled,
		"visible": visible,
	}


func _log_info(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.info("atmosphere", event_name, data)


func _log_error(event_name: String, data: Dictionary) -> void:
	if logger != null:
		logger.error("atmosphere", event_name, data)
