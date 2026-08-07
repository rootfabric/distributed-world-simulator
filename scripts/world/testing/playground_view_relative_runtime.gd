extends "res://scripts/world/testing/playground_runtime.gd"

# Network-playground specialization that keeps local camera input independent
# from the authoritative avatar-facing yaw and keeps client prediction on the
# physics clock. The shared movement kernel consumes an absolute world-space
# yaw, so derive it from the active camera's real view basis instead of reusing
# an accumulated local camera_yaw value.

var _pending_prediction_presentation: Dictionary = {}
var _pending_prediction_presentation_dirty: bool = false
var _physics_prediction_steps: int = 0
var _render_prediction_steps_suppressed: int = 0


func _process(delta: float) -> void:
	if runtime_role != "game-client":
		return
	if _m3_attached:
		if _network_playground_enabled:
			# Prediction owns a 60 Hz fixed physics clock. Advancing it from render
			# frames makes the CharacterBody and interpolated Camera3D fight the
			# physics interpolation path and produces visible micro-stutter.
			_render_prediction_steps_suppressed += 1
			return
		_apply_m3_network_input(delta)
	elif _m2_attached:
		_apply_m2_flat_input(delta)
		_sync_m2_player_state(delta)


func _physics_process(delta: float) -> void:
	if (
		runtime_role != "game-client"
		or not _m3_attached
		or not _network_playground_enabled
	):
		_flush_pending_prediction_presentation()
		return
	_sync_m7_predicted_player_state(delta)
	_flush_pending_prediction_presentation()
	_physics_prediction_steps += 1


func _create_m7_movement_intent(
	delta_seconds: float,
	input_override: Vector2 = Vector2(INF, INF),
	jump_override: int = -1,
	sprint_override: int = -1
) -> Dictionary:
	var input_vector := input_override
	if is_inf(input_vector.x) or is_inf(input_vector.y):
		input_vector = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()
	return {
		"move_x": input_vector.x,
		"move_z": -input_vector.y,
		"look_yaw": _network_view_yaw(),
		"look_pitch": clampf(player.camera_pitch, -1.45, 1.45),
		"jump_pressed": (
			Input.is_action_pressed("jump") if jump_override < 0 else jump_override > 0
		),
		"sprint": (
			Input.is_action_pressed("boost") if sprint_override < 0 else sprint_override > 0
		),
		"delta_seconds": clampf(delta_seconds, 0.000001, 0.25),
	}


func _network_view_yaw() -> float:
	if player == null:
		return 0.0
	var view_basis: Basis = player.get_view_basis()
	var camera_forward: Vector3 = (-view_basis.z).slide(Vector3.UP)
	if camera_forward.length_squared() < 0.000001:
		return wrapf(float(player.camera_yaw), -PI, PI)
	camera_forward = camera_forward.normalized()
	return atan2(-camera_forward.x, -camera_forward.z)


func _apply_m7_prediction_presentation(state: Dictionary) -> void:
	if state.is_empty() or player == null:
		return
	# Reconciliation arrives from the transport/render process, while local
	# prediction is advanced from the physics process. Never mutate the
	# CharacterBody transform directly from the transport callback: queue the
	# newest presentation and apply it once on the next physics tick.
	_pending_prediction_presentation = state.duplicate(true)
	_pending_prediction_presentation_dirty = true


func _flush_pending_prediction_presentation() -> void:
	if not _pending_prediction_presentation_dirty or player == null:
		return
	var state: Dictionary = _pending_prediction_presentation
	_pending_prediction_presentation = {}
	_pending_prediction_presentation_dirty = false
	var position: Dictionary = Dictionary(state.get("position", {}))
	var velocity: Dictionary = Dictionary(state.get("velocity", {}))
	player.set_world_position(Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	))
	player.velocity = Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	var yaw: float = float(state.get("orientation_yaw", 0.0))
	# Rotate only the visible astronaut. Rotating the CharacterBody root would
	# rotate CameraAnchor as well and apply yaw twice for the local player.
	if player.visual_root != null:
		player.visual_root.rotation.y = yaw


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["view_relative_prediction"] = {
		"clock": "PHYSICS_60HZ",
		"physics_prediction_steps": _physics_prediction_steps,
		"render_prediction_steps_suppressed": _render_prediction_steps_suppressed,
		"presentation_pending": _pending_prediction_presentation_dirty,
	}
	return report
