extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

# R12-02: an extension of the ONE native M3 Service instance, not a wrapper
# containing another Service, player registry, simulation, or replay ledger.
# Inherited canonical owner methods/state remain the only mutation authority.
# Gateway/adapters never access private fields on a foreign owner object.
const FixedInputSequence = preload("res://scripts/network/simulation/input_sequence.gd")
var _live_fixed_input_ticks: Dictionary = {}


func handle_live_fixed_player_input(command: Dictionary, fixed_delta_seconds: float) -> Dictionary:
	var logical_id := String(command.get("logical_player_id", ""))
	if _live_player_port == null or not _live_player_port.actor_ready(logical_id):
		return _failure("LIVE_PLAYER_AUTHORITY_NOT_READY")
	var validation: Dictionary = InputCommand.validate(command)
	if not bool(validation.get("success", false)):
		return validation
	if command.get("input_kind") != "MOVEMENT_INTENT":
		return _failure("LIVE_FIXED_INPUT_INTENT_REQUIRED")
	if not _fixed_tick_authority or not is_equal_approx(fixed_delta_seconds, 1.0 / 60.0):
		return _failure("INVALID_FIXED_TICK_DELTA")
	if int(command.get("authority_epoch", 0)) != _authority_epoch:
		return _failure("STALE_AUTHORITY_EPOCH")
	var operation_id := String(command["operation_id"])
	var fingerprint := Utils.payload_hash(command)
	var replay := _replay(operation_id, fingerprint)
	if not replay.is_empty():
		return replay
	var identity := _validate_owner(logical_id, String(command["transport_session_id"]), int(command["ownership_epoch"]))
	if not bool(identity.get("success", false)):
		return _record_live_fixed_outcome(logical_id, operation_id, fingerprint, identity)
	var current: Dictionary = get_player(logical_id)
	if not FixedInputSequence.is_newer(int(command["input_sequence"]), int(current.get("last_input_sequence", 0))):
		return _record_live_fixed_outcome(logical_id, operation_id, fingerprint, _failure("STALE_INPUT_SEQUENCE"))
	# A new transport packet cannot create an extra physics step in the same
	# server tick. Exact replay above returns the original receipt without a step.
	if _tick < 1 or int(_live_fixed_input_ticks.get(logical_id, -1)) == _tick:
		return _failure("LIVE_FIXED_INPUT_TICK_ALREADY_CONSUMED")
	var result := simulate_fixed_movement_tick(
		logical_id, String(command["transport_session_id"]),
		int(command["ownership_epoch"]), int(command["input_sequence"]),
		Dictionary(command["payload"]), fixed_delta_seconds
	)
	if bool(result.get("success", false)):
		_live_fixed_input_ticks[logical_id] = _tick
	return _record_live_fixed_outcome(logical_id, operation_id, fingerprint, result)


func _record_live_fixed_outcome(logical_id: String, operation_id: String, fingerprint: String, result: Dictionary) -> Dictionary:
	# This is the inherited M3 operation ledger that is exported and validated
	# by the accepted live-player port. No second completion/replay store exists.
	_record(operation_id, fingerprint, result)
	_operation_ledger[operation_id]["live_player_id"] = logical_id
	return result
