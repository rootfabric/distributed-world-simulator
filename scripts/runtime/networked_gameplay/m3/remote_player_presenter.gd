extends Node3D

const SCHEMA := "planet_simulator.remote_player_presenter.v1"

var logical_player_id := ""
var player_entity_id := ""
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var target_forward := Vector3.FORWARD
var target_orientation_yaw := 0.0
var target_flashlight := false
var interpolation_rate := 12.0
var replica_revision := 0
var updates := 0
var _visual: MeshInstance3D
var _flashlight: SpotLight3D

func setup(record: Dictionary) -> Dictionary:
	logical_player_id = String(record.get("logical_player_id", "")).strip_edges().to_lower()
	player_entity_id = String(record.get("player_entity_id", "")).strip_edges()
	if logical_player_id.is_empty() or player_entity_id != "player/%s" % logical_player_id:
		return {"success": false, "error_code": "INVALID_REMOTE_PLAYER_IDENTITY", "details": {}}
	name = "RemotePlayer_%s" % logical_player_id
	_visual = MeshInstance3D.new()
	_visual.name = "RemoteBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_visual.mesh = capsule
	add_child(_visual)
	_flashlight = SpotLight3D.new()
	_flashlight.name = "RemoteFlashlight"
	_flashlight.spot_range = 14.0
	_flashlight.spot_angle = 32.0
	_flashlight.light_energy = 2.0
	_flashlight.visible = false
	add_child(_flashlight)
	apply_replica(record, true)
	set_process(true)
	return {"success": true, "error_code": "", "details": {}}

func apply_replica(record: Dictionary, snap: bool = false) -> Dictionary:
	if String(record.get("player_entity_id", "")) != player_entity_id:
		return {"success": false, "error_code": "REMOTE_PLAYER_IDENTITY_MISMATCH", "details": {}}
	var position_data: Dictionary = record.get("position", {})
	var velocity: Dictionary = record.get("velocity", {})
	target_position = Vector3(float(position_data.get("x", 0.0)), float(position_data.get("y", 0.0)), float(position_data.get("z", 0.0)))
	target_velocity = Vector3(float(velocity.get("x", 0.0)), float(velocity.get("y", 0.0)), float(velocity.get("z", 0.0)))
	target_orientation_yaw = float(record.get("orientation_yaw", 0.0))
	target_forward = Vector3(sin(target_orientation_yaw), 0.0, cos(target_orientation_yaw))
	target_flashlight = bool(record.get("flashlight_enabled", false))
	replica_revision = int(record.get("state_revision", replica_revision))
	updates += 1
	if snap:
		position = target_position
		_apply_orientation()
		_apply_flashlight()
	return {"success": true, "error_code": "", "details": {}}

func _process(delta: float) -> void:
	var weight := 1.0 - exp(-interpolation_rate * clampf(delta, 0.0, 0.1))
	position = position.lerp(target_position, weight)
	_apply_orientation()
	_apply_flashlight()

func _apply_orientation() -> void:
	rotation.y = target_orientation_yaw

func _apply_flashlight() -> void:
	if _flashlight != null:
		_flashlight.visible = target_flashlight

func has_input_authority() -> bool:
	return false

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"position": [position.x, position.y, position.z],
		"target_position": [target_position.x, target_position.y, target_position.z],
		"velocity": [target_velocity.x, target_velocity.y, target_velocity.z],
		"orientation_yaw": target_orientation_yaw,
		"flashlight_enabled": target_flashlight,
		"replica_revision": replica_revision,
		"updates": updates,
		"input_authority": false,
		"interpolation_rate": interpolation_rate,
	}
