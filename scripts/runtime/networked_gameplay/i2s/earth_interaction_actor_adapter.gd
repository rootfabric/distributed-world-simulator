extends Node3D

const RESULT_SCHEMA := "planet_simulator.i2s_earth_interaction_actor_adapter.v1"

var _earth_explorer: Node3D


func setup(earth_explorer_reference: Node3D) -> Dictionary:
	if earth_explorer_reference == null:
		return _failure("I2S_EARTH_EXPLORER_REQUIRED")
	if (
		not earth_explorer_reference.has_method("get_active_camera")
		and not earth_explorer_reference.has_method("get_camera")
	):
		return _failure("I2S_EARTH_EXPLORER_CAMERA_REQUIRED")
	_earth_explorer = earth_explorer_reference
	return _success()


func get_active_camera() -> Camera3D:
	if _earth_explorer == null or not is_instance_valid(_earth_explorer):
		return null
	if _earth_explorer.has_method("get_active_camera"):
		return _earth_explorer.call("get_active_camera") as Camera3D
	return _earth_explorer.call("get_camera") as Camera3D


func _success() -> Dictionary:
	return {
		"schema": RESULT_SCHEMA,
		"success": true,
		"error_code": "",
	}


func _failure(error_code: String) -> Dictionary:
	return {
		"schema": RESULT_SCHEMA,
		"success": false,
		"error_code": error_code,
	}
