extends "res://scripts/network/simulation/fixed_tick_input_buffer.gd"

# FIX10 keeps the accepted NX3/FIX4 input queue, pressure compaction, jump and
# failsafe behavior underneath, but carries the client prediction tick already
# present on the wire.
#
# FIX10 fix6 originally anchored every input to one absolute client->server tick
# offset captured from the first packet. In a real graphical session that turns
# startup/handshake phase into permanent authority latency: later inputs can sit
# 6-12 server ticks in a LOCAL queue even though authority has capacity to apply
# them. Snapshot reconciliation then replays that entire artificial tail.
#
# V2 preserves the semantic property we actually need: the number of client fixed
# ticks for which the previous input state was active. The first available input
# applies immediately. A later transition with client tick delta N targets N
# server ticks after the previous applied transition. Late packets still apply
# immediately and thereby rebase the schedule without accumulating playout lag.
const FIX10_INPUT_TIMELINE_POLICY: String = "PRESERVE_CLIENT_TICK_ON_CONSUMED_INPUT_V1"
const FIX10_FIX6_SEMANTIC_SCHEDULE_POLICY: String = \
	"RELATIVE_APPLIED_TICK_PRESERVES_CLIENT_SPACING_V2"

var _fix10_current_client_tick: int = 0
var _fix10_current_input_applied_server_tick: int = 0
var _fix10_current_input_sequence: int = 0
var _fix10_consumed_with_client_tick: int = 0
var _fix10_missing_client_tick_metadata: int = 0

# Compatibility/diagnostic field. Unlike V1 this is the offset of the most
# recently APPLIED transition, never a permanent scheduling anchor.
var _fix10_fix6_client_to_server_tick_offset: int = 0
var _fix10_fix6_semantic_wait_ticks: int = 0
var _fix10_fix6_late_apply_events: int = 0
var _fix10_fix6_max_late_apply_ticks: int = 0
var _fix10_fix6_same_client_tick_compactions: int = 0
var _fix10_fix6_same_client_tick_inputs_dropped: int = 0
var _fix10_fix6_last_target_server_tick: int = 0
var _fix10_fix6_first_inputs_applied_immediately: int = 0
var _fix10_fix6_relative_targets: int = 0
var _fix10_fix6_max_future_wait_ticks: int = 0


func configure(last_processed_sequence: int = 0) -> Dictionary:
	_fix10_current_client_tick = 0
	_fix10_current_input_applied_server_tick = 0
	_fix10_current_input_sequence = 0
	_fix10_consumed_with_client_tick = 0
	_fix10_missing_client_tick_metadata = 0
	_fix10_fix6_client_to_server_tick_offset = 0
	_fix10_fix6_semantic_wait_ticks = 0
	_fix10_fix6_late_apply_events = 0
	_fix10_fix6_max_late_apply_ticks = 0
	_fix10_fix6_same_client_tick_compactions = 0
	_fix10_fix6_same_client_tick_inputs_dropped = 0
	_fix10_fix6_last_target_server_tick = 0
	_fix10_fix6_first_inputs_applied_immediately = 0
	_fix10_fix6_relative_targets = 0
	_fix10_fix6_max_future_wait_ticks = 0
	return super.configure(last_processed_sequence)


func consume_for_tick(server_tick: int) -> Dictionary:
	if server_tick < 1:
		return super.consume_for_tick(server_tick)

	_drop_stale(server_tick)
	_fix10_fix6_compact_same_client_tick_front()

	var semantic_target_tick: int = server_tick
	if not _pending.is_empty():
		var next_input: Dictionary = Dictionary(_pending.front())
		var next_client_tick: int = int(next_input.get("client_tick", 0))
		if next_client_tick > 0:
			semantic_target_tick = _fix10_fix6_relative_target_tick(
				server_tick,
				next_client_tick
			)
			_fix10_fix6_last_target_server_tick = semantic_target_tick
			if semantic_target_tick > server_tick:
				var wait_ticks: int = semantic_target_tick - server_tick
				_fix10_fix6_semantic_wait_ticks += 1
				_fix10_fix6_max_future_wait_ticks = maxi(
					_fix10_fix6_max_future_wait_ticks,
					wait_ticks
				)
				return _fix10_fix6_hold_without_consuming(
					server_tick,
					semantic_target_tick
				)

	var client_tick_by_sequence: Dictionary = {}
	for queued_value in _pending:
		var queued: Dictionary = Dictionary(queued_value)
		var queued_sequence: int = int(queued.get("input_sequence", 0))
		if queued_sequence > 0:
			client_tick_by_sequence[queued_sequence] = int(queued.get("client_tick", 0))

	var result: Dictionary = super.consume_for_tick(server_tick)
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	if bool(details.get("consumed_new_input", false)):
		var sequence: int = int(details.get("input_sequence", 0))
		var client_tick: int = int(client_tick_by_sequence.get(sequence, 0))
		if client_tick > 0:
			var had_previous_transition: bool = (
				_fix10_current_client_tick > 0
				and _fix10_current_input_applied_server_tick > 0
			)
			_fix10_current_client_tick = client_tick
			_fix10_current_input_applied_server_tick = server_tick
			_fix10_current_input_sequence = sequence
			_fix10_consumed_with_client_tick += 1
			_fix10_fix6_client_to_server_tick_offset = server_tick - client_tick
			if not had_previous_transition:
				_fix10_fix6_first_inputs_applied_immediately += 1
			var late_ticks: int = maxi(server_tick - semantic_target_tick, 0)
			if late_ticks > 0:
				_fix10_fix6_late_apply_events += 1
				_fix10_fix6_max_late_apply_ticks = maxi(
					_fix10_fix6_max_late_apply_ticks,
					late_ticks
				)
		else:
			_fix10_missing_client_tick_metadata += 1
	details["fix10_client_tick"] = _fix10_current_client_tick
	details["fix10_input_applied_server_tick"] = _fix10_current_input_applied_server_tick
	details["fix10_input_sequence"] = _fix10_current_input_sequence
	details["fix10_fix6_semantic_target_server_tick"] = semantic_target_tick
	details["fix10_fix6_client_to_server_tick_offset"] = _fix10_fix6_client_to_server_tick_offset
	result["details"] = details
	return result


func _fix10_fix6_relative_target_tick(server_tick: int, next_client_tick: int) -> int:
	# No previous semantic transition exists: consume the first packet now. Startup
	# phase, JOIN latency and process scheduling must never become permanent input
	# latency for the rest of the session.
	if (
		_fix10_current_client_tick < 1
		or _fix10_current_input_applied_server_tick < 1
	):
		return server_tick

	# Non-forward metadata is never allowed to move authority backwards. The base
	# sequence window still owns stale/duplicate rejection; schedule it for now so
	# that layer can decide immediately.
	if next_client_tick <= _fix10_current_client_tick:
		return server_tick

	var client_spacing_ticks: int = next_client_tick - _fix10_current_client_tick
	_fix10_fix6_relative_targets += 1
	return _fix10_current_input_applied_server_tick + client_spacing_ticks


func _fix10_fix6_hold_without_consuming(
	server_tick: int,
	semantic_target_tick: int
) -> Dictionary:
	# Reuse the accepted parent hold/expiry/jump-clearing behavior without allowing
	# it to pop the semantically-future pending entry.
	var saved_pending: Array[Dictionary] = _pending
	_pending = []
	var result: Dictionary = super.consume_for_tick(server_tick)
	_pending = saved_pending
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["pending"] = _pending.size()
	details["queue_age_ticks"] = _oldest_queue_age(server_tick)
	details["fix10_client_tick"] = _fix10_current_client_tick
	details["fix10_input_applied_server_tick"] = _fix10_current_input_applied_server_tick
	details["fix10_input_sequence"] = _fix10_current_input_sequence
	details["fix10_fix6_semantic_wait"] = true
	details["fix10_fix6_semantic_target_server_tick"] = semantic_target_tick
	details["fix10_fix6_client_to_server_tick_offset"] = _fix10_fix6_client_to_server_tick_offset
	result["details"] = details
	return result


func _fix10_fix6_compact_same_client_tick_front() -> void:
	if _pending.size() < 2:
		return
	var front_tick: int = int(_pending.front().get("client_tick", 0))
	if front_tick < 1:
		return
	var group_size: int = 1
	while (
		group_size < _pending.size()
		and int(_pending[group_size].get("client_tick", 0)) == front_tick
	):
		group_size += 1
	if group_size < 2:
		return

	var newest: Dictionary = Dictionary(_pending[group_size - 1]).duplicate(true)
	for index in range(group_size - 1):
		var dropped_sequence: int = int(_pending[index].get("input_sequence", 0))
		if dropped_sequence > 0:
			_pressure_discarded_sequences[dropped_sequence] = true
	for _index in range(group_size):
		_pending.pop_front()
	_pending.push_front(newest)
	_fix10_fix6_same_client_tick_compactions += 1
	_fix10_fix6_same_client_tick_inputs_dropped += group_size - 1


func get_report(server_tick: int = 0) -> Dictionary:
	var report: Dictionary = super.get_report(server_tick)
	report["fix10_input_timeline_policy"] = FIX10_INPUT_TIMELINE_POLICY
	report["fix10_current_client_tick"] = _fix10_current_client_tick
	report["fix10_current_input_applied_server_tick"] = _fix10_current_input_applied_server_tick
	report["fix10_current_input_sequence"] = _fix10_current_input_sequence
	report["fix10_consumed_with_client_tick"] = _fix10_consumed_with_client_tick
	report["fix10_missing_client_tick_metadata"] = _fix10_missing_client_tick_metadata
	report["fix10_fix6_semantic_schedule_policy"] = FIX10_FIX6_SEMANTIC_SCHEDULE_POLICY
	# Kept for report compatibility; V2 updates it on every applied transition.
	report["fix10_fix6_tick_offset_initialized"] = _fix10_current_client_tick > 0
	report["fix10_fix6_client_to_server_tick_offset"] = _fix10_fix6_client_to_server_tick_offset
	report["fix10_fix6_semantic_wait_ticks"] = _fix10_fix6_semantic_wait_ticks
	report["fix10_fix6_late_apply_events"] = _fix10_fix6_late_apply_events
	report["fix10_fix6_max_late_apply_ticks"] = _fix10_fix6_max_late_apply_ticks
	report["fix10_fix6_same_client_tick_compactions"] = _fix10_fix6_same_client_tick_compactions
	report["fix10_fix6_same_client_tick_inputs_dropped"] = _fix10_fix6_same_client_tick_inputs_dropped
	report["fix10_fix6_last_target_server_tick"] = _fix10_fix6_last_target_server_tick
	report["fix10_fix6_first_inputs_applied_immediately"] = _fix10_fix6_first_inputs_applied_immediately
	report["fix10_fix6_relative_targets"] = _fix10_fix6_relative_targets
	report["fix10_fix6_max_future_wait_ticks"] = _fix10_fix6_max_future_wait_ticks
	return report
