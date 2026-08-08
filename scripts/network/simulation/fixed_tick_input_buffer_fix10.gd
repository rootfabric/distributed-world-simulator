extends "res://scripts/network/simulation/fixed_tick_input_buffer.gd"

# FIX10 keeps the accepted NX3/FIX4 input-selection semantics intact while
# carrying the client prediction tick that already exists on the wire. The
# server uses this metadata only to identify the authoritative state immediately
# after a newly consumed input sequence; it does not change queue order, hold,
# compaction, jump-edge, or authority behavior.
const FIX10_INPUT_TIMELINE_POLICY: String = "PRESERVE_CLIENT_TICK_ON_CONSUMED_INPUT_V1"

var _fix10_current_client_tick: int = 0
var _fix10_current_input_applied_server_tick: int = 0
var _fix10_current_input_sequence: int = 0
var _fix10_consumed_with_client_tick: int = 0
var _fix10_missing_client_tick_metadata: int = 0


func configure(last_processed_sequence: int = 0) -> Dictionary:
	_fix10_current_client_tick = 0
	_fix10_current_input_applied_server_tick = 0
	_fix10_current_input_sequence = 0
	_fix10_consumed_with_client_tick = 0
	_fix10_missing_client_tick_metadata = 0
	return super.configure(last_processed_sequence)


func consume_for_tick(server_tick: int) -> Dictionary:
	# `super.consume_for_tick()` may discard stale entries before popping the next
	# input. Snapshot metadata for every pending sequence first so the exact entry
	# that wins selection can still be identified after it has been removed.
	var client_tick_by_sequence: Dictionary = {}
	for queued_value in _pending:
		var queued: Dictionary = Dictionary(queued_value)
		var sequence: int = int(queued.get("input_sequence", 0))
		if sequence > 0:
			client_tick_by_sequence[sequence] = int(queued.get("client_tick", 0))

	var result: Dictionary = super.consume_for_tick(server_tick)
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	if bool(details.get("consumed_new_input", false)):
		var sequence: int = int(details.get("input_sequence", 0))
		var client_tick: int = int(client_tick_by_sequence.get(sequence, 0))
		if client_tick > 0:
			_fix10_current_client_tick = client_tick
			_fix10_current_input_applied_server_tick = server_tick
			_fix10_current_input_sequence = sequence
			_fix10_consumed_with_client_tick += 1
		else:
			_fix10_missing_client_tick_metadata += 1
	details["fix10_client_tick"] = _fix10_current_client_tick
	details["fix10_input_applied_server_tick"] = _fix10_current_input_applied_server_tick
	details["fix10_input_sequence"] = _fix10_current_input_sequence
	result["details"] = details
	return result


func get_report(server_tick: int = 0) -> Dictionary:
	var report: Dictionary = super.get_report(server_tick)
	report["fix10_input_timeline_policy"] = FIX10_INPUT_TIMELINE_POLICY
	report["fix10_current_client_tick"] = _fix10_current_client_tick
	report["fix10_current_input_applied_server_tick"] = _fix10_current_input_applied_server_tick
	report["fix10_current_input_sequence"] = _fix10_current_input_sequence
	report["fix10_consumed_with_client_tick"] = _fix10_consumed_with_client_tick
	report["fix10_missing_client_tick_metadata"] = _fix10_missing_client_tick_metadata
	return report
