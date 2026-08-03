extends RefCounted

const MovementService = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const FixedTickScheduler = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const InputSequence = preload("res://scripts/network/simulation/input_sequence.gd")

const SCHEMA: String = "planet_simulator.client_prediction_reconciler.v1"
const TICK_RATE_HZ: int = 60
const FIXED_DELTA_SECONDS: float = 1.0 / 60.0
const MAX_HISTORY_TICKS: int = 256
const IGNORE_THRESHOLD_M: float = 0.03
const SMOOTH_THRESHOLD_M: float = 0.15
const FAST_THRESHOLD_M: float = 0.50
const HARD_CORRECTION_THRESHOLD_M: float = 2.0
const SMOOTH_DURATION_SECONDS: float = 0.15
const FAST_DURATION_SECONDS: float = 0.08
const VERY_FAST_DURATION_SECONDS: float = 0.05
const HISTORY_POLICY: String = "SERVER_TICK_KEYED_RING_BUFFER_V1"
const REPLAY_POLICY: String = "AUTHORITATIVE_BASELINE_REPLAY_UNACKNOWLEDGED_TICKS_V1"
const CORRECTION_POLICY: String = "VISUAL_OFFSET_DECAY_THRESHOLDS_V1"
const CLOCK_ONLY_SNAPSHOT_POLICY: String = "FUTURE_IDENTICAL_STATE_ADVANCES_CLOCK_PRESERVES_SMOOTHING_V2"
const HISTORY_MISS_POLICY: String = "AUTHORITATIVE_RESET_WHEN_SNAPSHOT_TICK_OUTSIDE_RING_V1"

var _movement = MovementService.new()
var _scheduler = FixedTickScheduler.new()
var _configured: bool = false
var _predicted_state: Dictionary = {}
var _history: Array[Dictionary] = []
var _current_sequence: int = 0
var _current_intent: Dictionary = {}
var _prediction_tick: int = 0
var _visual_offset: Vector3 = Vector3.ZERO
var _visual_decay_seconds: float = 0.0
var _last_authoritative_tick: int = 0
var _last_authoritative_sequence: int = 0
var _ticks_predicted: int = 0
var _ticks_replayed: int = 0
var _reconciliations: int = 0
var _corrections: int = 0
var _hard_corrections: int = 0
var _history_overflows: int = 0
var _replay_failures: int = 0
var _history_miss_resets: int = 0
var _last_error_m: float = 0.0
var _maximum_error_m: float = 0.0
var _last_correction_mode: String = "NONE"

func configure(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	if server_tick < 0:
		return _failure("INVALID_PREDICTION_SERVER_TICK")
	if not _valid_player_state(authoritative_player):
		return _failure("INVALID_PREDICTION_PLAYER_STATE")
	var scheduler_result: Dictionary = _scheduler.configure(
		TICK_RATE_HZ,
		FixedTickScheduler.DEFAULT_MAX_CATCH_UP_TICKS,
		server_tick
	)
	if not bool(scheduler_result.get("success", false)):
		return scheduler_result
	_predicted_state = authoritative_player.duplicate(true)
	_history.clear()
	_current_sequence = int(authoritative_player.get("last_input_sequence", 0))
	_current_intent = _idle_intent()
	_prediction_tick = server_tick
	_visual_offset = Vector3.ZERO
	_visual_decay_seconds = 0.0
	_last_authoritative_tick = server_tick
	_last_authoritative_sequence = _current_sequence
	_ticks_predicted = 0
	_ticks_replayed = 0
	_reconciliations = 0
	_corrections = 0
	_hard_corrections = 0
	_history_overflows = 0
	_replay_failures = 0
	_history_miss_resets = 0
	_last_error_m = 0.0
	_maximum_error_m = 0.0
	_last_correction_mode = "NONE"
	_configured = true
	return _success(get_report())

func set_input(input_sequence: int, intent: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("PREDICTION_NOT_CONFIGURED")
	if not InputSequence.is_valid(input_sequence):
		return _failure("INVALID_PREDICTION_INPUT_SEQUENCE")
	if (
		_current_sequence != 0
		and input_sequence != _current_sequence
		and not InputSequence.is_newer(input_sequence, _current_sequence)
	):
		return _failure("STALE_PREDICTION_INPUT_SEQUENCE")
	var canonical: Dictionary = _canonical_intent(intent)
	if canonical.is_empty():
		return _failure("INVALID_PREDICTION_INTENT")
	_current_sequence = input_sequence
	_current_intent = canonical
	return _success({"input_sequence": input_sequence})

func advance_frame(frame_delta_seconds: float) -> Dictionary:
	if not _configured:
		return _failure("PREDICTION_NOT_CONFIGURED")
	var scheduled: Dictionary = _scheduler.advance(frame_delta_seconds)
	if not bool(scheduled.get("success", false)):
		return scheduled
	var tick_count: int = int(scheduled.get("details", {}).get("tick_count", 0))
	var first_tick: int = int(scheduled.get("details", {}).get("first_tick", _prediction_tick))
	for offset in range(tick_count):
		var tick: int = first_tick + offset
		var tick_result: Dictionary = _simulate_tick(tick, _current_sequence, _current_intent, false)
		if not bool(tick_result.get("success", false)):
			return tick_result
		_current_intent["jump_pressed"] = false
	_prediction_tick = _scheduler.get_server_tick()
	return _success({
		"tick_count": tick_count,
		"prediction_tick": _prediction_tick,
		"predicted_state": _predicted_state.duplicate(true),
	})

func reconcile(authoritative_player: Dictionary, server_tick: int) -> Dictionary:
	if not _configured:
		return _failure("PREDICTION_NOT_CONFIGURED")
	if server_tick < _last_authoritative_tick:
		return _success({"replay": true, "stale_snapshot": true})
	if not _valid_player_state(authoritative_player):
		return _failure("INVALID_AUTHORITATIVE_PREDICTION_STATE")
	var authoritative_sequence: int = int(authoritative_player.get("last_input_sequence", 0))
	var predicted_at_tick: Dictionary = {}
	var exact_tick_available: bool = server_tick == _prediction_tick
	if exact_tick_available:
		predicted_at_tick = _predicted_state
	else:
		for record in _history:
			if int(record.get("tick", -1)) == server_tick:
				predicted_at_tick = Dictionary(record.get("state", {}))
				exact_tick_available = true
				break
	if server_tick < _prediction_tick and not exact_tick_available:
		return _reset_after_history_miss(authoritative_player, server_tick, authoritative_sequence)
	if server_tick > _prediction_tick and not exact_tick_available:
		# A future clock-only snapshot has no local history record yet. Compare it
		# against the current prediction instead of treating an empty Dictionary
		# as the origin. This also gives future authoritative corrections a real
		# local baseline rather than a synthetic (0, 0, 0) error.
		predicted_at_tick = _predicted_state
		exact_tick_available = true
	var prediction_error: float = _position(predicted_at_tick).distance_to(_position(authoritative_player))
	_last_error_m = prediction_error
	_maximum_error_m = maxf(_maximum_error_m, prediction_error)
	var old_presentation_position: Vector3 = _position(_predicted_state) + _visual_offset
	var replay_source: Array[Dictionary] = []
	for record_value in _history:
		var record: Dictionary = record_value
		if int(record.get("tick", -1)) > server_tick:
			replay_source.append(record.duplicate(true))
	_predicted_state = authoritative_player.duplicate(true)
	_history.clear()
	_last_authoritative_tick = server_tick
	_last_authoritative_sequence = authoritative_sequence
	if authoritative_sequence != 0 and (
		_current_sequence == 0
		or authoritative_sequence == _current_sequence
		or InputSequence.is_newer(authoritative_sequence, _current_sequence)
	):
		_current_sequence = authoritative_sequence
	_reconciliations += 1
	var replayed: int = 0
	for record in replay_source:
		var sequence: int = int(record.get("input_sequence", 0))
		var current_state_sequence: int = int(_predicted_state.get("last_input_sequence", 0))
		if sequence != current_state_sequence and not InputSequence.is_newer(sequence, current_state_sequence):
			continue
		var replay_result: Dictionary = _simulate_tick(
			int(record.get("tick", server_tick)),
			sequence,
			Dictionary(record.get("intent", {})),
			true
		)
		if not bool(replay_result.get("success", false)):
			_replay_failures += 1
			return replay_result
		replayed += 1
	_ticks_replayed += replayed
	if server_tick > _prediction_tick:
		_prediction_tick = server_tick
		var scheduler_result: Dictionary = _scheduler.configure(
			TICK_RATE_HZ,
			FixedTickScheduler.DEFAULT_MAX_CATCH_UP_TICKS,
			server_tick
		)
		if not bool(scheduler_result.get("success", false)):
			return scheduler_result
	var corrected_position: Vector3 = _position(_predicted_state)
	_apply_correction(old_presentation_position - corrected_position, prediction_error)
	return _success({
		"prediction_error_m": prediction_error,
		"replayed_ticks": replayed,
		"prediction_tick": _prediction_tick,
		"correction_mode": _last_correction_mode,
		"hard_correction": _last_correction_mode == "HARD",
		"predicted_state": _predicted_state.duplicate(true),
	})


func _reset_after_history_miss(
	authoritative_player: Dictionary,
	server_tick: int,
	authoritative_sequence: int
) -> Dictionary:
	var old_presentation_position: Vector3 = _position(_predicted_state) + _visual_offset
	var local_sequence: int = _current_sequence
	var local_intent: Dictionary = _current_intent.duplicate(true)
	_predicted_state = authoritative_player.duplicate(true)
	_history.clear()
	_last_authoritative_tick = server_tick
	_last_authoritative_sequence = authoritative_sequence
	_prediction_tick = server_tick
	var scheduler_result: Dictionary = _scheduler.configure(
		TICK_RATE_HZ,
		FixedTickScheduler.DEFAULT_MAX_CATCH_UP_TICKS,
		server_tick
	)
	if not bool(scheduler_result.get("success", false)):
		return scheduler_result
	if (
		InputSequence.is_valid(local_sequence)
		and (
			authoritative_sequence == 0
			or local_sequence == authoritative_sequence
			or InputSequence.is_newer(local_sequence, authoritative_sequence)
		)
	):
		_current_sequence = local_sequence
		_current_intent = local_intent
	else:
		_current_sequence = authoritative_sequence
		_current_intent = _idle_intent()
	_reconciliations += 1
	_history_miss_resets += 1
	var prediction_error: float = old_presentation_position.distance_to(_position(authoritative_player))
	_last_error_m = prediction_error
	_maximum_error_m = maxf(_maximum_error_m, prediction_error)
	_apply_correction(old_presentation_position - _position(authoritative_player), prediction_error)
	return _success({
		"prediction_error_m": prediction_error,
		"replayed_ticks": 0,
		"prediction_tick": _prediction_tick,
		"correction_mode": _last_correction_mode,
		"hard_correction": _last_correction_mode == "HARD",
		"history_miss_reset": true,
		"predicted_state": _predicted_state.duplicate(true),
	})

func sample_presentation(frame_delta_seconds: float) -> Dictionary:
	if not _configured:
		return {}
	if _visual_offset.length_squared() > 0.0000000001 and frame_delta_seconds > 0.0:
		var duration: float = maxf(_visual_decay_seconds, 0.0001)
		var weight: float = 1.0 - exp(-4.605170186 * minf(frame_delta_seconds, 0.1) / duration)
		_visual_offset = _visual_offset.lerp(Vector3.ZERO, clampf(weight, 0.0, 1.0))
		if _visual_offset.length() < 0.0005:
			_visual_offset = Vector3.ZERO
	var state: Dictionary = _predicted_state.duplicate(true)
	var position: Vector3 = _position(state) + _visual_offset
	state["position"] = {"x": position.x, "y": position.y, "z": position.z}
	return state

func get_predicted_state() -> Dictionary:
	return _predicted_state.duplicate(true)

func get_prediction_tick() -> int:
	return _prediction_tick

func is_configured() -> bool:
	return _configured

func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"tick_rate_hz": TICK_RATE_HZ,
		"fixed_delta_seconds": FIXED_DELTA_SECONDS,
		"history_policy": HISTORY_POLICY,
		"replay_policy": REPLAY_POLICY,
		"correction_policy": CORRECTION_POLICY,
		"clock_only_snapshot_policy": CLOCK_ONLY_SNAPSHOT_POLICY,
		"history_miss_policy": HISTORY_MISS_POLICY,
		"max_history_ticks": MAX_HISTORY_TICKS,
		"prediction_tick": _prediction_tick,
		"last_authoritative_tick": _last_authoritative_tick,
		"current_input_sequence": _current_sequence,
		"last_authoritative_sequence": _last_authoritative_sequence,
		"history_size": _history.size(),
		"ticks_predicted": _ticks_predicted,
		"ticks_replayed": _ticks_replayed,
		"reconciliations": _reconciliations,
		"corrections": _corrections,
		"hard_corrections": _hard_corrections,
		"history_overflows": _history_overflows,
		"replay_failures": _replay_failures,
		"history_miss_resets": _history_miss_resets,
		"last_error_m": _last_error_m,
		"maximum_error_m": _maximum_error_m,
		"last_correction_mode": _last_correction_mode,
		"visual_offset_m": _visual_offset.length(),
		"scheduler": _scheduler.get_report(),
	}

func _simulate_tick(
	tick: int,
	input_sequence: int,
	intent: Dictionary,
	replay: bool
) -> Dictionary:
	if input_sequence < 1:
		_prediction_tick = tick
		return _success()
	var result: Dictionary = _movement.apply_fixed_tick(
		_predicted_state,
		input_sequence,
		intent,
		FIXED_DELTA_SECONDS
	)
	if not bool(result.get("success", false)):
		return _failure(String(result.get("error_code", "CLIENT_PREDICTION_TICK_FAILED")), {
			"tick": tick,
			"input_sequence": input_sequence,
			"replay": replay,
		})
	_predicted_state = Dictionary(result.get("details", {}).get("player", {})).duplicate(true)
	_prediction_tick = tick
	_history.append({
		"tick": tick,
		"input_sequence": input_sequence,
		"intent": intent.duplicate(true),
		"state": _predicted_state.duplicate(true),
	})
	while _history.size() > MAX_HISTORY_TICKS:
		_history.pop_front()
		_history_overflows += 1
	if not replay:
		_ticks_predicted += 1
	return _success()

func _apply_correction(presentation_offset: Vector3, error_m: float) -> void:
	_last_correction_mode = "NONE"
	if error_m < IGNORE_THRESHOLD_M:
		# Matching clock-only and duplicate snapshots must not cancel a visual
		# correction that is still decaying from an earlier authoritative update.
		return
	_visual_offset = Vector3.ZERO
	_visual_decay_seconds = 0.0
	_corrections += 1
	if error_m > HARD_CORRECTION_THRESHOLD_M:
		_hard_corrections += 1
		_last_correction_mode = "HARD"
		return
	_visual_offset = presentation_offset
	if error_m <= SMOOTH_THRESHOLD_M:
		_last_correction_mode = "SMOOTH"
		_visual_decay_seconds = SMOOTH_DURATION_SECONDS
	elif error_m <= FAST_THRESHOLD_M:
		_last_correction_mode = "FAST"
		_visual_decay_seconds = FAST_DURATION_SECONDS
	else:
		_last_correction_mode = "VERY_FAST"
		_visual_decay_seconds = VERY_FAST_DURATION_SECONDS

func _canonical_intent(intent: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"move_x": float(intent.get("move_x", 0.0)),
		"move_z": float(intent.get("move_z", 0.0)),
		"look_yaw": float(intent.get("look_yaw", 0.0)),
		"look_pitch": float(intent.get("look_pitch", 0.0)),
		"jump_pressed": bool(intent.get("jump_pressed", false)),
		"sprint": bool(intent.get("sprint", false)),
		"delta_seconds": FIXED_DELTA_SECONDS,
	}
	for key in ["move_x", "move_z", "look_yaw", "look_pitch"]:
		var value: float = float(result[key])
		if is_nan(value) or is_inf(value):
			return {}
	return result

func _valid_player_state(state: Dictionary) -> bool:
	if state.is_empty() or not state.get("position") is Dictionary or not state.get("velocity") is Dictionary:
		return false
	var sequence: int = int(state.get("last_input_sequence", 0))
	return sequence == 0 or InputSequence.is_valid(sequence)

func _position(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("position", {}))
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)

func _idle_intent() -> Dictionary:
	return {
		"move_x": 0.0,
		"move_z": 0.0,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": FIXED_DELTA_SECONDS,
	}

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
