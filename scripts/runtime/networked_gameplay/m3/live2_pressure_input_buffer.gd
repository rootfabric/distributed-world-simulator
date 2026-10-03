extends "res://scripts/network/simulation/fixed_tick_input_buffer.gd"

# LIVE.2 R3 product policy: retain FIFO state transitions and jump edges, but
# compact adjacent identical held states when the queue is under pressure.
# The legacy NX3 buffer and its default capacity/sequence/hold limits remain
# unchanged. This is the same server-owned buffer, not another input authority.
const PRESSURE_HIGH_WATER := 16
const PRESSURE_POLICY := "ADJACENT_IDENTICAL_LEVEL_INPUTS_UNDER_PRESSURE_V1"

var _pressure_coalesced := 0
var _pressure_compactions := 0
var _max_pending_observed := 0
var _last_received_tick := 0


func configure(last_processed_sequence: int = 0) -> Dictionary:
	_pressure_coalesced = 0
	_pressure_compactions = 0
	_max_pending_observed = 0
	_last_received_tick = 0
	return super.configure(last_processed_sequence)


func enqueue(input: Dictionary, received_server_tick: int) -> Dictionary:
	_last_received_tick = maxi(_last_received_tick, received_server_tick)
	# Invalid, stale, duplicate and out-of-window packets must not mutate the
	# queue through a backpressure side door. The base validates them as before.
	var sequence := int(input.get("input_sequence", 0))
	var eligible := received_server_tick >= 0 and input.get("intent", {}) is Dictionary
	eligible = eligible and Sequence.is_valid(sequence) and Sequence.is_newer(sequence, _last_processed_sequence)
	var distance := Sequence.forward_distance(_last_processed_sequence, sequence) if eligible else 0
	eligible = eligible and distance >= 1 and distance <= MAX_SEQUENCE_AHEAD
	if eligible:
		for queued in _pending:
			if int(queued.get("input_sequence", 0)) == sequence:
				eligible = false
				break
	if eligible and _pending.size() >= PRESSURE_HIGH_WATER:
		_compact_identical_levels()
	var result: Dictionary = super.enqueue(input, received_server_tick)
	_max_pending_observed = maxi(_max_pending_observed, _pending.size())
	return result


func _compact_identical_levels() -> void:
	var compacted: Array[Dictionary] = []
	var removed := 0
	for queued in _pending:
		if not compacted.is_empty() and _same_held_state(compacted.back(), queued):
			# Keep the newest sequence/operation for acknowledgement, but do not
			# extend the lifetime of a backlog by refreshing its received tick.
			var replacement: Dictionary = queued.duplicate(true)
			replacement["received_server_tick"] = mini(
				int(compacted.back().get("received_server_tick", 0)),
				int(queued.get("received_server_tick", 0))
			)
			compacted[compacted.size() - 1] = replacement
			removed += 1
		else:
			compacted.append(queued)
	if removed > 0:
		_pending = compacted
		_pressure_coalesced += removed
		_pressure_compactions += 1


func _same_held_state(left: Dictionary, right: Dictionary) -> bool:
	var left_intent: Dictionary = Dictionary(left.get("intent", {})).duplicate(true)
	var right_intent: Dictionary = Dictionary(right.get("intent", {})).duplicate(true)
	# Never fold a jump edge, direction change, stop, sprint transition, or
	# changed look direction. Unknown intent fields must match as well.
	if bool(left_intent.get("jump_pressed", false)) or bool(right_intent.get("jump_pressed", false)):
		return false
	# Duration is assigned by the fixed server tick, not by packet history.
	left_intent.erase("delta_seconds")
	right_intent.erase("delta_seconds")
	return left_intent == right_intent


func _reject(error_code: String) -> Dictionary:
	var result: Dictionary = super._reject(error_code)
	result["details"] = {
		"pending": _pending.size(),
		"capacity": MAX_PENDING_INPUTS,
		"oldest_queue_age_ticks": _oldest_queue_age(_last_received_tick),
		"last_processed_sequence": _last_processed_sequence,
		"last_received_sequence": _last_received_sequence,
		"pressure_coalesced": _pressure_coalesced,
	}
	return result


func get_report(server_tick: int = 0) -> Dictionary:
	var report: Dictionary = super.get_report(server_tick)
	report["pressure_policy"] = PRESSURE_POLICY
	report["pressure_high_water"] = PRESSURE_HIGH_WATER
	report["pressure_coalesced"] = _pressure_coalesced
	report["pressure_compactions"] = _pressure_compactions
	report["max_pending_observed"] = _max_pending_observed
	return report
