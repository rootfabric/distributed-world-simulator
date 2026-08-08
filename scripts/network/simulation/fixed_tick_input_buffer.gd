extends RefCounted

const Sequence = preload("res://scripts/network/simulation/input_sequence.gd")

const SCHEMA: String = "planet_simulator.fixed_tick_input_buffer.v1"
const MAX_PENDING_INPUTS: int = 64
const MAX_SEQUENCE_AHEAD: int = 2048
const MAX_QUEUE_AGE_TICKS: int = 120
const MAX_INPUT_HOLD_TICKS: int = 15
const PRESSURE_COMPACTION_THRESHOLD: int = 8
const INPUT_SELECTION_POLICY: String = "FIFO_STATE_TRANSITIONS_ONE_PER_FIXED_TICK_V1"
const INPUT_COALESCING_POLICY: String = "PRESSURE_LATEST_STATE_WITH_JUMP_EDGE_PRESERVATION_V3"
const JUMP_POLICY: String = "EDGE_ON_CONSUMED_INPUT_V1"
const HOLD_POLICY: String = "LAST_INPUT_WITH_250MS_FAILSAFE_V1"

var _pending: Array[Dictionary] = []
var _last_processed_sequence: int = 0
var _last_received_sequence: int = 0
var _current_intent: Dictionary = {}
var _current_operation_id: String = ""
var _hold_until_tick: int = 0
var _accepted: int = 0
var _redundant: int = 0
var _rejected: int = 0
var _stale_dropped: int = 0
var _window_rejected: int = 0
var _queue_full_rejected: int = 0
var _hold_expirations: int = 0
var _jump_edges: int = 0
var _coalesced_refreshes: int = 0
var _queue_pressure_recoveries: int = 0
var _pressure_compactions: int = 0
var _pressure_dropped_inputs: int = 0
var _peak_pending: int = 0

func configure(last_processed_sequence: int = 0) -> Dictionary:
	if last_processed_sequence != 0 and not Sequence.is_valid(last_processed_sequence):
		return _failure("INVALID_LAST_PROCESSED_INPUT_SEQUENCE")
	_pending.clear()
	_last_processed_sequence = last_processed_sequence
	_last_received_sequence = last_processed_sequence
	_current_intent.clear()
	_current_operation_id = ""
	_hold_until_tick = 0
	_accepted = 0
	_redundant = 0
	_rejected = 0
	_stale_dropped = 0
	_window_rejected = 0
	_queue_full_rejected = 0
	_hold_expirations = 0
	_jump_edges = 0
	_coalesced_refreshes = 0
	_queue_pressure_recoveries = 0
	_pressure_compactions = 0
	_pressure_dropped_inputs = 0
	_peak_pending = 0
	return _success()

func enqueue(input: Dictionary, received_server_tick: int) -> Dictionary:
	if received_server_tick < 0:
		return _reject("INVALID_INPUT_RECEIVED_TICK")
	var sequence: int = int(input.get("input_sequence", 0))
	if not Sequence.is_valid(sequence):
		return _reject("INVALID_INPUT_SEQUENCE")
	if not Sequence.is_newer(sequence, _last_processed_sequence):
		_redundant += 1
		return _success({"accepted": false, "redundant": true})
	var distance: int = Sequence.forward_distance(_last_processed_sequence, sequence)
	if distance < 1 or distance > MAX_SEQUENCE_AHEAD:
		_window_rejected += 1
		return _reject("INPUT_SEQUENCE_WINDOW_EXCEEDED")
	for queued in _pending:
		if int(queued.get("input_sequence", 0)) == sequence:
			_redundant += 1
			return _success({"accepted": false, "redundant": true})
	var intent_value = input.get("intent", {})
	if not intent_value is Dictionary:
		return _reject("MOVEMENT_INTENT_REQUIRED")
	var queued_input: Dictionary = input.duplicate(true)
	queued_input["received_server_tick"] = received_server_tick

	# A realtime input queue is a stream of state samples, not a command ledger.
	# Once it develops visible latency, replaying every historical look/movement
	# sample one-per-server-tick makes the authority walk through stale states and
	# eventually pulls the predicted player backwards. Under pressure, retain every
	# jump edge but collapse superseded continuous samples to the newest state.
	# Normal shallow queues still keep the accepted NX3 FIFO behavior exactly.
	if _pending.size() >= MAX_PENDING_INPUTS:
		_compact_pressure_backlog()
	var queue_was_full: bool = _pending.size() >= MAX_PENDING_INPUTS
	if queue_was_full and _try_coalesce_latest_refresh(queued_input):
		if Sequence.is_newer(sequence, _last_received_sequence):
			_last_received_sequence = sequence
		_accepted += 1
		_coalesced_refreshes += 1
		_queue_pressure_recoveries += 1
		return _success({
			"accepted": true,
			"redundant": false,
			"coalesced": true,
			"pressure_compacted": false,
			"pending": _pending.size(),
		})
	if _pending.size() >= MAX_PENDING_INPUTS:
		_queue_full_rejected += 1
		return _reject("INPUT_QUEUE_FULL")

	_insert_in_sequence_order(queued_input)
	_peak_pending = maxi(_peak_pending, _pending.size())
	if Sequence.is_newer(sequence, _last_received_sequence):
		_last_received_sequence = sequence
	_accepted += 1
	var dropped_by_pressure: int = 0
	if _pending.size() > PRESSURE_COMPACTION_THRESHOLD:
		dropped_by_pressure = _compact_pressure_backlog()
	return _success({
		"accepted": true,
		"redundant": false,
		"coalesced": false,
		"pressure_compacted": dropped_by_pressure > 0,
		"pressure_dropped": dropped_by_pressure,
		"pending": _pending.size(),
	})

func consume_for_tick(server_tick: int) -> Dictionary:
	if server_tick < 1:
		return _failure("INVALID_FIXED_SERVER_TICK")
	_drop_stale(server_tick)
	var consumed_new_input: bool = false
	var operation_id: String = _current_operation_id
	var jump_edge: bool = false
	if not _pending.is_empty():
		var next_input: Dictionary = _pending.pop_front()
		_last_processed_sequence = int(next_input.get("input_sequence", 0))
		_current_intent = Dictionary(next_input.get("intent", {})).duplicate(true)
		_current_operation_id = String(next_input.get("operation_id", ""))
		operation_id = _current_operation_id
		_hold_until_tick = server_tick + MAX_INPUT_HOLD_TICKS - 1
		jump_edge = bool(_current_intent.get("jump_pressed", false))
		if jump_edge:
			_jump_edges += 1
		consumed_new_input = true
	elif not _current_intent.is_empty() and server_tick > _hold_until_tick:
		if _has_active_motion(_current_intent):
			_hold_expirations += 1
		_current_intent["move_x"] = 0.0
		_current_intent["move_z"] = 0.0
		_current_intent["sprint"] = false
		_current_intent["jump_pressed"] = false
	var intent: Dictionary = _current_intent.duplicate(true)
	if intent.is_empty():
		intent = _idle_intent()
	intent["jump_pressed"] = jump_edge
	return _success({
		"input_sequence": _last_processed_sequence,
		"operation_id": operation_id,
		"intent": intent,
		"consumed_new_input": consumed_new_input,
		"jump_edge": jump_edge,
		"pending": _pending.size(),
		"queue_age_ticks": _oldest_queue_age(server_tick),
	})

func get_last_processed_sequence() -> int:
	return _last_processed_sequence

func get_pending_count() -> int:
	return _pending.size()

func get_report(server_tick: int = 0) -> Dictionary:
	return {
		"schema": SCHEMA,
		"selection_policy": INPUT_SELECTION_POLICY,
		"coalescing_policy": INPUT_COALESCING_POLICY,
		"jump_policy": JUMP_POLICY,
		"hold_policy": HOLD_POLICY,
		"pressure_compaction_threshold": PRESSURE_COMPACTION_THRESHOLD,
		"last_processed_sequence": _last_processed_sequence,
		"last_received_sequence": _last_received_sequence,
		"pending": _pending.size(),
		"peak_pending": _peak_pending,
		"oldest_queue_age_ticks": _oldest_queue_age(server_tick),
		"hold_until_tick": _hold_until_tick,
		"accepted": _accepted,
		"redundant": _redundant,
		"rejected": _rejected,
		"stale_dropped": _stale_dropped,
		"window_rejected": _window_rejected,
		"queue_full_rejected": _queue_full_rejected,
		"coalesced_refreshes": _coalesced_refreshes,
		"queue_pressure_recoveries": _queue_pressure_recoveries,
		"pressure_compactions": _pressure_compactions,
		"pressure_dropped_inputs": _pressure_dropped_inputs,
		"hold_expirations": _hold_expirations,
		"jump_edges": _jump_edges,
	}

func _compact_pressure_backlog() -> int:
	if _pending.size() <= PRESSURE_COMPACTION_THRESHOLD:
		return 0
	var compacted: Array[Dictionary] = []
	var latest_non_jump: Dictionary = {}
	for queued_value in _pending:
		var queued: Dictionary = Dictionary(queued_value)
		var intent_value = queued.get("intent", {})
		var is_jump: bool = intent_value is Dictionary and bool(intent_value.get("jump_pressed", false))
		if is_jump:
			compacted.append(queued.duplicate(true))
		else:
			latest_non_jump = queued.duplicate(true)
	if not latest_non_jump.is_empty():
		# `_pending` is sequence ordered. Insert the retained newest continuous
		# sample at its original sequence position relative to any preserved jumps.
		var latest_sequence: int = int(latest_non_jump.get("input_sequence", 0))
		var inserted: bool = false
		for index in range(compacted.size()):
			var jump_sequence: int = int(compacted[index].get("input_sequence", 0))
			if Sequence.forward_distance(_last_processed_sequence, latest_sequence) < Sequence.forward_distance(_last_processed_sequence, jump_sequence):
				compacted.insert(index, latest_non_jump)
				inserted = true
				break
		if not inserted:
			compacted.append(latest_non_jump)
	var dropped: int = _pending.size() - compacted.size()
	if dropped <= 0:
		return 0
	_pending = compacted
	_pressure_compactions += 1
	_pressure_dropped_inputs += dropped
	_queue_pressure_recoveries += 1
	return dropped

func _try_coalesce_latest_refresh(input: Dictionary) -> bool:
	if _pending.is_empty():
		return false
	var tail: Dictionary = _pending.back()
	var sequence: int = int(input.get("input_sequence", 0))
	var tail_sequence: int = int(tail.get("input_sequence", 0))
	if not Sequence.is_newer(sequence, tail_sequence):
		return false
	# Keep the existing wrap-spanning FIFO contract exact. Sequence wrap is rare
	# and preserving both sides of the boundary is safer than collapsing it.
	if sequence <= tail_sequence:
		return false
	var incoming_intent_value = input.get("intent", {})
	var tail_intent_value = tail.get("intent", {})
	if not incoming_intent_value is Dictionary or not tail_intent_value is Dictionary:
		return false
	var incoming_intent: Dictionary = incoming_intent_value
	var tail_intent: Dictionary = tail_intent_value
	if bool(incoming_intent.get("jump_pressed", false)) or bool(tail_intent.get("jump_pressed", false)):
		return false
	if not _same_continuous_motion_state(incoming_intent, tail_intent):
		return false
	_pending[_pending.size() - 1] = input.duplicate(true)
	return true

func _same_continuous_motion_state(left: Dictionary, right: Dictionary) -> bool:
	return (
		is_equal_approx(float(left.get("move_x", 0.0)), float(right.get("move_x", 0.0)))
		and is_equal_approx(float(left.get("move_z", 0.0)), float(right.get("move_z", 0.0)))
		and is_equal_approx(float(left.get("look_yaw", 0.0)), float(right.get("look_yaw", 0.0)))
		and is_equal_approx(float(left.get("look_pitch", 0.0)), float(right.get("look_pitch", 0.0)))
		and bool(left.get("sprint", false)) == bool(right.get("sprint", false))
	)

func _insert_in_sequence_order(input: Dictionary) -> void:
	var sequence: int = int(input.get("input_sequence", 0))
	var distance: int = Sequence.forward_distance(_last_processed_sequence, sequence)
	var index: int = 0
	while index < _pending.size():
		var queued_sequence: int = int(_pending[index].get("input_sequence", 0))
		var queued_distance: int = Sequence.forward_distance(_last_processed_sequence, queued_sequence)
		if distance < queued_distance:
			break
		index += 1
	_pending.insert(index, input)

func _drop_stale(server_tick: int) -> void:
	while not _pending.is_empty():
		var received_tick: int = int(_pending.front().get("received_server_tick", server_tick))
		if server_tick - received_tick <= MAX_QUEUE_AGE_TICKS:
			break
		_pending.pop_front()
		_stale_dropped += 1

func _oldest_queue_age(server_tick: int) -> int:
	if server_tick < 1 or _pending.is_empty():
		return 0
	return maxi(server_tick - int(_pending.front().get("received_server_tick", server_tick)), 0)

func _has_active_motion(intent: Dictionary) -> bool:
	return absf(float(intent.get("move_x", 0.0))) > 0.000001 \
		or absf(float(intent.get("move_z", 0.0))) > 0.000001 \
		or bool(intent.get("sprint", false)) \
		or bool(intent.get("jump_pressed", false))

func _idle_intent() -> Dictionary:
	return {
		"move_x": 0.0,
		"move_z": 0.0,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 1.0 / 60.0,
	}

func _reject(error_code: String) -> Dictionary:
	_rejected += 1
	return _failure(error_code)

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
