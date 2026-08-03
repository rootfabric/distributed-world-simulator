extends RefCounted

const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

const SCHEMA := "planet_simulator.remote_snapshot_interpolator.v1"
const DEFAULT_TICK_RATE_HZ := 60.0
const DEFAULT_INTERPOLATION_DELAY_TICKS := 6.0
const DEFAULT_MAX_EXTRAPOLATION_TICKS := 6.0
const DEFAULT_MAX_SNAPSHOTS := 32
const DEFAULT_TELEPORT_DISTANCE_M := 8.0
const DEFAULT_MAX_IMPLIED_SPEED_MPS := 48.0
const EPSILON := 0.000000001

var _configured := false
var _tick_rate_hz := DEFAULT_TICK_RATE_HZ
var _interpolation_delay_ticks := DEFAULT_INTERPOLATION_DELAY_TICKS
var _max_extrapolation_ticks := DEFAULT_MAX_EXTRAPOLATION_TICKS
var _max_snapshots := DEFAULT_MAX_SNAPSHOTS
var _teleport_distance_m := DEFAULT_TELEPORT_DISTANCE_M
var _max_implied_speed_mps := DEFAULT_MAX_IMPLIED_SPEED_MPS

var _logical_player_id := ""
var _player_entity_id := ""
var _transport_session_id := ""
var _ownership_epoch := 0
var _authority_epoch := 0
var _estimated_server_tick := 0.0
var _latest_server_tick := -1
var _timeline: Array[Dictionary] = []

var _snapshots_received := 0
var _snapshots_inserted := 0
var _duplicates_suppressed := 0
var _stale_dropped := 0
var _conflicts_rejected := 0
var _identity_resets := 0
var _teleport_segments := 0
var _overflow_pruned := 0
var _interpolation_samples := 0
var _extrapolation_samples := 0
var _hold_samples := 0
var _buffering_samples := 0


func configure(options: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("REMOTE_INTERPOLATOR_ALREADY_CONFIGURED")
	_tick_rate_hz = float(options.get("tick_rate_hz", DEFAULT_TICK_RATE_HZ))
	_interpolation_delay_ticks = float(options.get(
		"interpolation_delay_ticks", DEFAULT_INTERPOLATION_DELAY_TICKS
	))
	_max_extrapolation_ticks = float(options.get(
		"max_extrapolation_ticks", DEFAULT_MAX_EXTRAPOLATION_TICKS
	))
	_max_snapshots = int(options.get("max_snapshots", DEFAULT_MAX_SNAPSHOTS))
	_teleport_distance_m = float(options.get(
		"teleport_distance_m", DEFAULT_TELEPORT_DISTANCE_M
	))
	_max_implied_speed_mps = float(options.get(
		"max_implied_speed_mps", DEFAULT_MAX_IMPLIED_SPEED_MPS
	))
	if (
		not _is_finite_positive(_tick_rate_hz)
		or not _is_finite_non_negative(_interpolation_delay_ticks)
		or not _is_finite_non_negative(_max_extrapolation_ticks)
		or _max_snapshots < 2
		or _max_snapshots > 4096
		or not _is_finite_positive(_teleport_distance_m)
		or not _is_finite_positive(_max_implied_speed_mps)
	):
		return _failure("INVALID_REMOTE_INTERPOLATOR_CONFIG")
	_configured = true
	return _success({"schema": SCHEMA, "config": get_config()})


func reset() -> void:
	_logical_player_id = ""
	_player_entity_id = ""
	_transport_session_id = ""
	_ownership_epoch = 0
	_authority_epoch = 0
	_estimated_server_tick = 0.0
	_latest_server_tick = -1
	_timeline.clear()


func push_snapshot(
	record: Dictionary,
	server_tick: int,
	snapshot_revision: int,
	authority_epoch: int
) -> Dictionary:
	if not _configured:
		return _failure("REMOTE_INTERPOLATOR_NOT_CONFIGURED")
	_snapshots_received += 1
	var validation: Dictionary = PlayerSnapshot.validate_player_record(record)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_REMOTE_PLAYER_RECORD")))
	if server_tick < 0 or snapshot_revision < 0 or authority_epoch < 1:
		return _failure("INVALID_REMOTE_SNAPSHOT_CLOCK")
	if not bool(record.get("connected", false)):
		return _failure("REMOTE_PLAYER_NOT_CONNECTED")

	var logical_id := String(record.get("logical_player_id", ""))
	var entity_id := String(record.get("player_entity_id", ""))
	var session_id := String(record.get("transport_session_id", ""))
	var ownership_epoch := int(record.get("ownership_epoch", 0))
	var reset_reason := ""
	if _logical_player_id.is_empty():
		_reset_identity(logical_id, entity_id, session_id, ownership_epoch, authority_epoch)
		reset_reason = "INITIAL"
	elif logical_id != _logical_player_id or entity_id != _player_entity_id:
		_conflicts_rejected += 1
		return _failure("REMOTE_PLAYER_IDENTITY_MISMATCH")
	elif (
		ownership_epoch < _ownership_epoch
		or authority_epoch < _authority_epoch
	):
		_stale_dropped += 1
		return _failure("STALE_REMOTE_AUTHORITY_EPOCH")
	elif (
		session_id != _transport_session_id
		and ownership_epoch == _ownership_epoch
		and authority_epoch == _authority_epoch
	):
		_conflicts_rejected += 1
		return _failure("REMOTE_SESSION_CHANGED_WITHOUT_EPOCH")
	elif (
		ownership_epoch > _ownership_epoch
		or authority_epoch > _authority_epoch
		or session_id != _transport_session_id
	):
		_reset_identity(logical_id, entity_id, session_id, ownership_epoch, authority_epoch)
		_identity_resets += 1
		reset_reason = "AUTHORITY_OR_SESSION_CHANGED"

	if (
		_timeline.size() >= _max_snapshots
		and server_tick < int(_timeline[0].get("server_tick", -1))
	):
		_stale_dropped += 1
		return _failure("STALE_REMOTE_SNAPSHOT_TICK")

	var sample := _make_sample(record, server_tick, snapshot_revision, authority_epoch)
	var insertion_index := _find_insertion_index(server_tick)
	if insertion_index < _timeline.size() and int(_timeline[insertion_index].get("server_tick", -1)) == server_tick:
		if _samples_equal(_timeline[insertion_index], sample):
			var existing: Dictionary = _timeline[insertion_index]
			existing["snapshot_revision"] = maxi(
				int(existing.get("snapshot_revision", 0)),
				snapshot_revision
			)
			_timeline[insertion_index] = existing
			_duplicates_suppressed += 1
			_latest_server_tick = maxi(_latest_server_tick, server_tick)
			_estimated_server_tick = maxf(_estimated_server_tick, float(server_tick))
			return _success({"accepted": false, "duplicate": true, "reset_reason": reset_reason})
		_conflicts_rejected += 1
		return _failure("CONFLICTING_REMOTE_SNAPSHOT_TICK")

	_timeline.insert(insertion_index, sample)
	_snapshots_inserted += 1
	_latest_server_tick = maxi(_latest_server_tick, server_tick)
	_estimated_server_tick = maxf(_estimated_server_tick, float(server_tick))
	_rebuild_discontinuities(maxi(0, insertion_index - 1), mini(_timeline.size() - 1, insertion_index + 1))
	while _timeline.size() > _max_snapshots:
		_timeline.pop_front()
		_overflow_pruned += 1
	return _success({
		"accepted": true,
		"duplicate": false,
		"out_of_order": insertion_index < _timeline.size() - 1,
		"reset_reason": reset_reason,
		"buffer_size": _timeline.size(),
	})


func advance(delta_seconds: float) -> Dictionary:
	if not _configured:
		return _failure("REMOTE_INTERPOLATOR_NOT_CONFIGURED")
	if not _is_finite_non_negative(delta_seconds):
		return _failure("INVALID_REMOTE_INTERPOLATION_DELTA")
	if _latest_server_tick >= 0:
		var maximum_clock := (
			float(_latest_server_tick)
			+ _interpolation_delay_ticks
			+ _max_extrapolation_ticks
			+ 1.0
		)
		_estimated_server_tick = minf(
			maximum_clock,
			_estimated_server_tick + minf(delta_seconds, 0.25) * _tick_rate_hz
		)
	return sample_at_render_tick(_estimated_server_tick - _interpolation_delay_ticks)


func sample_at_render_tick(render_tick: float) -> Dictionary:
	if not _configured:
		return _failure("REMOTE_INTERPOLATOR_NOT_CONFIGURED")
	if is_nan(render_tick) or is_inf(render_tick):
		return _failure("INVALID_REMOTE_RENDER_TICK")
	if _timeline.is_empty():
		return _failure("REMOTE_INTERPOLATION_BUFFER_EMPTY")
	if _timeline.size() == 1:
		_buffering_samples += 1
		return _state_result(_timeline[0], "BUFFERING", render_tick, 0.0, 0.0)

	var first_tick := float(_timeline[0].get("server_tick", 0))
	if render_tick <= first_tick:
		_buffering_samples += 1
		return _state_result(_timeline[0], "BUFFERING", render_tick, 0.0, 0.0)

	for index in range(_timeline.size() - 1):
		var left: Dictionary = _timeline[index]
		var right: Dictionary = _timeline[index + 1]
		var left_tick := float(left.get("server_tick", 0))
		var right_tick := float(right.get("server_tick", 0))
		if render_tick > right_tick:
			continue
		if bool(right.get("discontinuous_from_previous", false)):
			if render_tick < right_tick:
				_hold_samples += 1
				return _state_result(left, "HOLD_BEFORE_DISCONTINUITY", render_tick, 0.0, 0.0)
			_hold_samples += 1
			return _state_result(right, "SNAP_DISCONTINUITY", render_tick, 1.0, 0.0)
		var span := maxf(right_tick - left_tick, EPSILON)
		var alpha := clampf((render_tick - left_tick) / span, 0.0, 1.0)
		_interpolation_samples += 1
		return _interpolated_result(left, right, alpha, render_tick)

	var latest: Dictionary = _timeline[_timeline.size() - 1]
	var latest_tick := float(latest.get("server_tick", 0))
	var extrapolation_ticks := maxf(0.0, render_tick - latest_tick)
	if extrapolation_ticks <= _max_extrapolation_ticks + EPSILON:
		_extrapolation_samples += 1
		return _extrapolated_result(latest, extrapolation_ticks, render_tick)
	_hold_samples += 1
	return _state_result(
		latest,
		"HOLD_EXTRAPOLATION_LIMIT",
		render_tick,
		1.0,
		_max_extrapolation_ticks
	)


func get_config() -> Dictionary:
	return {
		"tick_rate_hz": _tick_rate_hz,
		"interpolation_delay_ticks": _interpolation_delay_ticks,
		"interpolation_delay_ms": _interpolation_delay_ticks * 1000.0 / _tick_rate_hz,
		"max_extrapolation_ticks": _max_extrapolation_ticks,
		"max_extrapolation_ms": _max_extrapolation_ticks * 1000.0 / _tick_rate_hz,
		"max_snapshots": _max_snapshots,
		"teleport_distance_m": _teleport_distance_m,
		"max_implied_speed_mps": _max_implied_speed_mps,
	}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"logical_player_id": _logical_player_id,
		"player_entity_id": _player_entity_id,
		"transport_session_id": _transport_session_id,
		"ownership_epoch": _ownership_epoch,
		"authority_epoch": _authority_epoch,
		"estimated_server_tick": _estimated_server_tick,
		"latest_server_tick": _latest_server_tick,
		"buffer_size": _timeline.size(),
		"oldest_server_tick": int(_timeline[0].get("server_tick", -1)) if not _timeline.is_empty() else -1,
		"snapshots_received": _snapshots_received,
		"snapshots_inserted": _snapshots_inserted,
		"duplicates_suppressed": _duplicates_suppressed,
		"stale_dropped": _stale_dropped,
		"conflicts_rejected": _conflicts_rejected,
		"identity_resets": _identity_resets,
		"teleport_segments": _teleport_segments,
		"overflow_pruned": _overflow_pruned,
		"interpolation_samples": _interpolation_samples,
		"extrapolation_samples": _extrapolation_samples,
		"hold_samples": _hold_samples,
		"buffering_samples": _buffering_samples,
		"config": get_config(),
	}


func get_timeline_for_testing() -> Array[Dictionary]:
	return _timeline.duplicate(true)


func _reset_identity(
	logical_id: String,
	entity_id: String,
	session_id: String,
	ownership_epoch: int,
	authority_epoch: int
) -> void:
	_logical_player_id = logical_id
	_player_entity_id = entity_id
	_transport_session_id = session_id
	_ownership_epoch = ownership_epoch
	_authority_epoch = authority_epoch
	_timeline.clear()
	_latest_server_tick = -1
	_estimated_server_tick = 0.0


func _make_sample(
	record: Dictionary,
	server_tick: int,
	snapshot_revision: int,
	authority_epoch: int
) -> Dictionary:
	var position_data: Dictionary = record.get("position", {})
	var velocity_data: Dictionary = record.get("velocity", {})
	return {
		"server_tick": server_tick,
		"snapshot_revision": snapshot_revision,
		"authority_epoch": authority_epoch,
		"ownership_epoch": int(record.get("ownership_epoch", 0)),
		"transport_session_id": String(record.get("transport_session_id", "")),
		"state_revision": int(record.get("state_revision", 0)),
		"position": Vector3(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0)),
			float(position_data.get("z", 0.0))
		),
		"velocity": Vector3(
			float(velocity_data.get("x", 0.0)),
			float(velocity_data.get("y", 0.0)),
			float(velocity_data.get("z", 0.0))
		),
		"orientation_yaw": float(record.get("orientation_yaw", 0.0)),
		"flashlight_enabled": bool(record.get("flashlight_enabled", false)),
		"discontinuous_from_previous": false,
	}


func _find_insertion_index(server_tick: int) -> int:
	var low := 0
	var high := _timeline.size()
	while low < high:
		var middle := (low + high) / 2
		if int(_timeline[middle].get("server_tick", -1)) < server_tick:
			low = middle + 1
		else:
			high = middle
	return low


func _rebuild_discontinuities(from_index: int, to_index: int) -> void:
	if _timeline.is_empty():
		return
	_timeline[0]["discontinuous_from_previous"] = false
	for index in range(maxi(1, from_index), mini(_timeline.size() - 1, to_index) + 1):
		var previous: Dictionary = _timeline[index - 1]
		var current: Dictionary = _timeline[index]
		var delta_ticks := int(current.get("server_tick", 0)) - int(previous.get("server_tick", 0))
		var distance := (current.get("position", Vector3.ZERO) as Vector3).distance_to(
			previous.get("position", Vector3.ZERO) as Vector3
		)
		var duration := float(delta_ticks) / _tick_rate_hz if delta_ticks > 0 else 0.0
		var implied_speed := distance / duration if duration > EPSILON else INF
		var discontinuous := (
			distance > _teleport_distance_m
			or implied_speed > _max_implied_speed_mps
			or int(current.get("ownership_epoch", 0)) != int(previous.get("ownership_epoch", 0))
			or int(current.get("authority_epoch", 0)) != int(previous.get("authority_epoch", 0))
			or String(current.get("transport_session_id", "")) != String(previous.get("transport_session_id", ""))
		)
		var was_discontinuous := bool(current.get("discontinuous_from_previous", false))
		current["discontinuous_from_previous"] = discontinuous
		_timeline[index] = current
		if discontinuous and not was_discontinuous:
			_teleport_segments += 1
		elif not discontinuous and was_discontinuous:
			_teleport_segments = maxi(0, _teleport_segments - 1)


func _interpolated_result(
	left: Dictionary,
	right: Dictionary,
	alpha: float,
	render_tick: float
) -> Dictionary:
	var left_position: Vector3 = left.get("position", Vector3.ZERO)
	var right_position: Vector3 = right.get("position", Vector3.ZERO)
	var left_velocity: Vector3 = left.get("velocity", Vector3.ZERO)
	var right_velocity: Vector3 = right.get("velocity", Vector3.ZERO)
	var yaw := lerp_angle(
		float(left.get("orientation_yaw", 0.0)),
		float(right.get("orientation_yaw", 0.0)),
		alpha
	)
	return _success({
		"mode": "INTERPOLATE",
		"render_tick": render_tick,
		"source_tick": int(left.get("server_tick", 0)),
		"target_tick": int(right.get("server_tick", 0)),
		"alpha": alpha,
		"extrapolation_ticks": 0.0,
		"position": left_position.lerp(right_position, alpha),
		"velocity": left_velocity.lerp(right_velocity, alpha),
		"orientation_yaw": yaw,
		"flashlight_enabled": bool(
			left.get("flashlight_enabled", false)
			if alpha < 0.5
			else right.get("flashlight_enabled", false)
		),
		"state_revision": int(
			left.get("state_revision", 0)
			if alpha < 0.5
			else right.get("state_revision", 0)
		),
	})


func _extrapolated_result(
	latest: Dictionary,
	extrapolation_ticks: float,
	render_tick: float
) -> Dictionary:
	var position: Vector3 = latest.get("position", Vector3.ZERO)
	var velocity: Vector3 = latest.get("velocity", Vector3.ZERO)
	position += velocity * (extrapolation_ticks / _tick_rate_hz)
	return _success({
		"mode": "EXTRAPOLATE",
		"render_tick": render_tick,
		"source_tick": int(latest.get("server_tick", 0)),
		"target_tick": int(latest.get("server_tick", 0)),
		"alpha": 1.0,
		"extrapolation_ticks": extrapolation_ticks,
		"position": position,
		"velocity": velocity,
		"orientation_yaw": float(latest.get("orientation_yaw", 0.0)),
		"flashlight_enabled": bool(latest.get("flashlight_enabled", false)),
		"state_revision": int(latest.get("state_revision", 0)),
	})


func _state_result(
	sample: Dictionary,
	mode: String,
	render_tick: float,
	alpha: float,
	extrapolation_ticks: float
) -> Dictionary:
	return _success({
		"mode": mode,
		"render_tick": render_tick,
		"source_tick": int(sample.get("server_tick", 0)),
		"target_tick": int(sample.get("server_tick", 0)),
		"alpha": alpha,
		"extrapolation_ticks": extrapolation_ticks,
		"position": sample.get("position", Vector3.ZERO),
		"velocity": sample.get("velocity", Vector3.ZERO),
		"orientation_yaw": float(sample.get("orientation_yaw", 0.0)),
		"flashlight_enabled": bool(sample.get("flashlight_enabled", false)),
		"state_revision": int(sample.get("state_revision", 0)),
	})


func _samples_equal(left: Dictionary, right: Dictionary) -> bool:
	return (
		int(left.get("authority_epoch", -1)) == int(right.get("authority_epoch", -2))
		and int(left.get("ownership_epoch", -1)) == int(right.get("ownership_epoch", -2))
		and String(left.get("transport_session_id", "")) == String(right.get("transport_session_id", "!"))
		and int(left.get("state_revision", -1)) == int(right.get("state_revision", -2))
		and (left.get("position", Vector3.ZERO) as Vector3).is_equal_approx(right.get("position", Vector3.ZERO) as Vector3)
		and (left.get("velocity", Vector3.ZERO) as Vector3).is_equal_approx(right.get("velocity", Vector3.ZERO) as Vector3)
		and is_equal_approx(float(left.get("orientation_yaw", 0.0)), float(right.get("orientation_yaw", 1.0)))
		and bool(left.get("flashlight_enabled", false)) == bool(right.get("flashlight_enabled", true))
	)


func _is_finite_positive(value: float) -> bool:
	return not is_nan(value) and not is_inf(value) and value > 0.0


func _is_finite_non_negative(value: float) -> bool:
	return not is_nan(value) and not is_inf(value) and value >= 0.0


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
