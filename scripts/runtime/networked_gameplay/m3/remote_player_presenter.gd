extends Node3D

const RemoteSnapshotInterpolator = preload(
	"res://scripts/network/interpolation/remote_snapshot_interpolator.gd"
)

const SCHEMA := "planet_simulator.remote_player_presenter.v2"
const LEGACY_SCHEMA := "planet_simulator.remote_player_presenter.v1"
const FIX8_REMOTE_BUFFER_TELEMETRY_POLICY := "MOVING_HOLD_AND_SNAPSHOT_GAP_DIAGNOSTICS_V1"
const FIX8_MOVING_SPEED_EPSILON_MPS := 0.05

var logical_player_id := ""
var player_entity_id := ""
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var target_forward := Vector3.FORWARD
var target_orientation_yaw := 0.0
var target_flashlight := false
var interpolation_rate := 0.0
var replica_revision := 0
var updates := 0
var interpolation_failures := 0
var last_apply_error_code := ""
var _visual: MeshInstance3D
var _flashlight: SpotLight3D
var _interpolator
var _fallback_server_tick := 0
var _last_mode := "UNINITIALIZED"
var _last_render_tick := 0.0

var _fix8_last_snapshot_tick := -1
var _fix8_snapshot_gap_samples := 0
var _fix8_snapshot_gap_total_ticks := 0
var _fix8_max_snapshot_gap_ticks := 0
var _fix8_moving_extrapolation_samples := 0
var _fix8_moving_hold_samples := 0
var _fix8_moving_buffer_underruns := 0
var _fix8_current_moving_hold_streak := 0
var _fix8_max_moving_hold_streak := 0


func setup(record: Dictionary, snapshot_context: Dictionary = {}) -> Dictionary:
	logical_player_id = String(record.get("logical_player_id", "")).strip_edges().to_lower()
	player_entity_id = String(record.get("player_entity_id", "")).strip_edges()
	if logical_player_id.is_empty() or player_entity_id != "player/%s" % logical_player_id:
		return _failure("INVALID_REMOTE_PLAYER_IDENTITY")
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
	_interpolator = RemoteSnapshotInterpolator.new()
	var configured: Dictionary = _interpolator.configure()
	if not bool(configured.get("success", false)):
		return configured
	var applied: Dictionary = apply_replica(record, true, snapshot_context)
	if not bool(applied.get("success", false)):
		return applied
	set_process(true)
	return _success()


func apply_replica(
	record: Dictionary,
	snap: bool = false,
	snapshot_context: Dictionary = {}
) -> Dictionary:
	if String(record.get("player_entity_id", "")) != player_entity_id:
		return _apply_failure("REMOTE_PLAYER_IDENTITY_MISMATCH")
	if _interpolator == null:
		return _apply_failure("REMOTE_INTERPOLATOR_NOT_READY")
	var context := _resolve_snapshot_context(record, snapshot_context)
	var server_tick := int(context.get("server_tick", -1))
	var snapshot_revision := int(context.get("snapshot_revision", -1))
	var authority_epoch := int(context.get("authority_epoch", 0))
	var pushed: Dictionary = _interpolator.push_snapshot(
		record,
		server_tick,
		snapshot_revision,
		authority_epoch
	)
	if not bool(pushed.get("success", false)):
		return _apply_failure(
			String(pushed.get("error_code", "REMOTE_SNAPSHOT_PUSH_FAILED")),
			Dictionary(pushed.get("details", {}))
		)
	var push_details: Dictionary = pushed.get("details", {})
	if bool(push_details.get("stale", false)):
		last_apply_error_code = ""
		return _success({
			"server_tick": server_tick,
			"snapshot_revision": snapshot_revision,
			"authority_epoch": authority_epoch,
			"accepted": false,
			"duplicate": false,
			"stale": true,
			"same_tick": bool(push_details.get("same_tick", false)),
			"reset_reason": String(push_details.get("reset_reason", "")),
		})
	last_apply_error_code = ""
	_observe_fix8_snapshot_gap(
		server_tick,
		String(push_details.get("reset_reason", ""))
	)
	var position_data: Dictionary = record.get("position", {})
	var velocity_data: Dictionary = record.get("velocity", {})
	target_position = Vector3(
		float(position_data.get("x", 0.0)),
		float(position_data.get("y", 0.0)),
		float(position_data.get("z", 0.0))
	)
	target_velocity = Vector3(
		float(velocity_data.get("x", 0.0)),
		float(velocity_data.get("y", 0.0)),
		float(velocity_data.get("z", 0.0))
	)
	target_orientation_yaw = float(record.get("orientation_yaw", 0.0))
	target_forward = Vector3(
		sin(target_orientation_yaw),
		0.0,
		cos(target_orientation_yaw)
	)
	target_flashlight = bool(record.get("flashlight_enabled", false))
	replica_revision = int(record.get("state_revision", replica_revision))
	updates += 1
	var reset_reason := String(push_details.get("reset_reason", ""))
	if snap or reset_reason in ["INITIAL", "AUTHORITY_OR_SESSION_CHANGED"]:
		var baseline: Dictionary = _interpolator.sample_at_render_tick(float(server_tick))
		if bool(baseline.get("success", false)):
			_apply_interpolated_state(baseline.get("details", {}))
	return _success({
		"server_tick": server_tick,
		"snapshot_revision": snapshot_revision,
		"authority_epoch": authority_epoch,
		"accepted": bool(push_details.get("accepted", false)),
		"duplicate": bool(push_details.get("duplicate", false)),
		"stale": false,
		"same_tick": bool(push_details.get("same_tick", false)),
		"same_tick_replacement": bool(
			push_details.get("same_tick_replacement", false)
		),
		"reset_reason": reset_reason,
	})


func _process(delta: float) -> void:
	if _interpolator == null:
		return
	var sampled: Dictionary = _interpolator.advance(delta)
	if not bool(sampled.get("success", false)):
		return
	_apply_interpolated_state(sampled.get("details", {}))


func _apply_interpolated_state(state: Dictionary) -> void:
	var previous_mode := _last_mode
	position = state.get("position", position)
	target_velocity = state.get("velocity", target_velocity)
	target_orientation_yaw = float(state.get(
		"orientation_yaw", target_orientation_yaw
	))
	target_forward = Vector3(
		sin(target_orientation_yaw),
		0.0,
		cos(target_orientation_yaw)
	)
	target_flashlight = bool(state.get(
		"flashlight_enabled", target_flashlight
	))
	replica_revision = maxi(
		replica_revision,
		int(state.get("state_revision", replica_revision))
	)
	_last_mode = String(state.get("mode", "UNKNOWN"))
	_last_render_tick = float(state.get("render_tick", _last_render_tick))
	_observe_fix8_remote_buffer_sample(previous_mode, _last_mode, target_velocity)
	_apply_orientation()
	_apply_flashlight()


func _observe_fix8_snapshot_gap(server_tick: int, reset_reason: String) -> void:
	if server_tick < 0:
		return
	if (
		_fix8_last_snapshot_tick < 0
		or reset_reason in ["INITIAL", "AUTHORITY_OR_SESSION_CHANGED"]
	):
		_fix8_last_snapshot_tick = server_tick
		return
	if server_tick <= _fix8_last_snapshot_tick:
		return
	var gap_ticks := server_tick - _fix8_last_snapshot_tick
	_fix8_snapshot_gap_samples += 1
	_fix8_snapshot_gap_total_ticks += gap_ticks
	_fix8_max_snapshot_gap_ticks = maxi(_fix8_max_snapshot_gap_ticks, gap_ticks)
	_fix8_last_snapshot_tick = server_tick


func _observe_fix8_remote_buffer_sample(
	previous_mode: String,
	mode: String,
	velocity: Vector3
) -> void:
	var moving := velocity.length() > FIX8_MOVING_SPEED_EPSILON_MPS
	if moving and mode == "EXTRAPOLATE":
		_fix8_moving_extrapolation_samples += 1
	if moving and mode == "HOLD_EXTRAPOLATION_LIMIT":
		_fix8_moving_hold_samples += 1
		_fix8_current_moving_hold_streak += 1
		_fix8_max_moving_hold_streak = maxi(
			_fix8_max_moving_hold_streak,
			_fix8_current_moving_hold_streak
		)
		if previous_mode != "HOLD_EXTRAPOLATION_LIMIT":
			_fix8_moving_buffer_underruns += 1
	else:
		_fix8_current_moving_hold_streak = 0


func _resolve_snapshot_context(
	record: Dictionary,
	explicit_context: Dictionary
) -> Dictionary:
	var context := explicit_context.duplicate(true)
	if (
		int(context.get("server_tick", -1)) >= 0
		and int(context.get("snapshot_revision", -1)) >= 0
		and int(context.get("authority_epoch", 0)) >= 1
	):
		return context
	var parent_snapshot := _get_parent_snapshot()
	if not parent_snapshot.is_empty():
		context["server_tick"] = int(parent_snapshot.get("server_tick", -1))
		context["snapshot_revision"] = int(parent_snapshot.get("revision", -1))
		context["authority_epoch"] = int(parent_snapshot.get("authority_epoch", 0))
	if (
		int(context.get("server_tick", -1)) < 0
		or int(context.get("snapshot_revision", -1)) < 0
		or int(context.get("authority_epoch", 0)) < 1
	):
		_fallback_server_tick = maxi(
			_fallback_server_tick + 1,
			int(record.get("state_revision", 1))
		)
		context["server_tick"] = _fallback_server_tick
		context["snapshot_revision"] = maxi(
			0,
			int(record.get("state_revision", 1))
		)
		context["authority_epoch"] = maxi(
			1,
			int(record.get("ownership_epoch", 1))
		)
	return context


func _get_parent_snapshot() -> Dictionary:
	var parent := get_parent()
	if parent == null:
		return {}
	var runtime = parent.get("m3_multiplayer_client_runtime")
	if runtime == null or not is_instance_valid(runtime):
		return {}
	if not runtime.has_method("get_snapshot"):
		return {}
	var snapshot_value = runtime.call("get_snapshot")
	return snapshot_value.duplicate(true) if snapshot_value is Dictionary else {}


func _apply_orientation() -> void:
	rotation.y = target_orientation_yaw


func _apply_flashlight() -> void:
	if _flashlight != null:
		_flashlight.visible = target_flashlight


func has_input_authority() -> bool:
	return false


func get_interpolation_report() -> Dictionary:
	return _interpolator.get_report() if _interpolator != null else {}


func get_report() -> Dictionary:
	var mean_gap_ticks := (
		float(_fix8_snapshot_gap_total_ticks) / float(_fix8_snapshot_gap_samples)
		if _fix8_snapshot_gap_samples > 0
		else 0.0
	)
	return {
		"schema": SCHEMA,
		"legacy_schema": LEGACY_SCHEMA,
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"position": [position.x, position.y, position.z],
		"target_position": [
			target_position.x,
			target_position.y,
			target_position.z,
		],
		"velocity": [
			target_velocity.x,
			target_velocity.y,
			target_velocity.z,
		],
		"orientation_yaw": target_orientation_yaw,
		"flashlight_enabled": target_flashlight,
		"replica_revision": replica_revision,
		"updates": updates,
		"input_authority": false,
		"interpolation_rate": interpolation_rate,
		"interpolation_mode": _last_mode,
		"render_tick": _last_render_tick,
		"interpolation_failures": interpolation_failures,
		"last_apply_error_code": last_apply_error_code,
		"interpolation": get_interpolation_report(),
		"fix8_remote_buffer_policy": FIX8_REMOTE_BUFFER_TELEMETRY_POLICY,
		"fix8_snapshot_gap_samples": _fix8_snapshot_gap_samples,
		"fix8_mean_snapshot_gap_ticks": mean_gap_ticks,
		"fix8_max_snapshot_gap_ticks": _fix8_max_snapshot_gap_ticks,
		"fix8_moving_extrapolation_samples": _fix8_moving_extrapolation_samples,
		"fix8_moving_hold_samples": _fix8_moving_hold_samples,
		"fix8_moving_buffer_underruns": _fix8_moving_buffer_underruns,
		"fix8_max_moving_hold_streak": _fix8_max_moving_hold_streak,
	}


func _apply_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	interpolation_failures += 1
	last_apply_error_code = error_code
	push_warning(
		"[remote_player_presenter:%s] apply_replica failed: %s"
		% [logical_player_id, error_code]
	)
	return _failure(error_code, details)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
