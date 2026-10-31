extends RefCounted

# R4.1 proof kernel: ordered, single-inflight durable generation and bounded
# ACK escrow. This class never performs IO and never sends packets. The runtime
# must not publish staged mutations or send a success result until complete()
# accepts a successful durable repository commit for the exact generation.
# A new instance is created after restart; replay idempotency remains M6-owned.

const DEFAULT_READY_LIMIT := 32
const MAX_READY_LIMIT := 128

var _ready_limit := DEFAULT_READY_LIMIT
var _persisted_generation := 0
var _pending: Dictionary = {}
var _ready: Array[Dictionary] = []
var _fatal_error := ""

func configure(persisted_generation: int, ready_limit: int = DEFAULT_READY_LIMIT) -> Dictionary:
	if persisted_generation < 0 or ready_limit < 1 or ready_limit > MAX_READY_LIMIT:
		return _failure("DURABLE_GATE_INVALID_CONFIG")
	if not _pending.is_empty() or not _ready.is_empty():
		return _failure("DURABLE_GATE_NOT_QUIESCENT")
	_persisted_generation = persisted_generation
	_ready_limit = ready_limit
	_fatal_error = ""
	return _success({"generation": persisted_generation})

func observe_periodic_commit(generation: int) -> Dictionary:
	# The single checkpoint writer also persists ordinary periodic snapshots.
	# Those generations must be observed before staging a durable command.
	if not _fatal_error.is_empty() or not _pending.is_empty():
		return _failure("DURABLE_GATE_PERIODIC_WHILE_PENDING")
	if generation != _persisted_generation + 1:
		return _failure("DURABLE_GATE_GENERATION_OUT_OF_ORDER")
	_persisted_generation = generation
	return _success({"generation": generation})

func can_accept_mutation() -> bool:
	return _fatal_error.is_empty() and _pending.is_empty() and _ready.size() < _ready_limit

func stage(operation_id: String, peer_id: String, session_id: String,
		logical_player_id: String, ownership_epoch: int,
		command_type: String, result: Dictionary, generation: int) -> Dictionary:
	if not _fatal_error.is_empty():
		return _failure("DURABLE_GATE_FATAL")
	if not _pending.is_empty():
		return _failure("DURABLE_GATE_COMMIT_PENDING")
	if _ready.size() >= _ready_limit:
		return _failure("DURABLE_GATE_BACKPRESSURE")
	if operation_id.is_empty() or peer_id.is_empty() or session_id.is_empty() or logical_player_id.is_empty() or ownership_epoch < 1 or command_type.is_empty():
		return _failure("DURABLE_GATE_IDENTITY_REQUIRED")
	if generation != _persisted_generation + 1:
		return _failure("DURABLE_GATE_GENERATION_OUT_OF_ORDER")
	for entry in _ready:
		if String(entry.get("operation_id", "")) == operation_id:
			return _failure("DURABLE_GATE_OPERATION_ALREADY_ESCROWED")
	_pending = {
		"state": "STAGED", "operation_id": operation_id,
		"peer_id": peer_id, "session_id": session_id,
		"logical_player_id": logical_player_id, "ownership_epoch": ownership_epoch,
		"command_type": command_type,
		"result": result.duplicate(true), "generation": generation,
	}
	return _success({"generation": generation})

func mark_submitted(operation_id: String, generation: int) -> Dictionary:
	if _pending.is_empty() or String(_pending.get("operation_id", "")) != operation_id:
		return _failure("DURABLE_GATE_NO_MATCHING_OPERATION")
	if int(_pending.get("generation", -1)) != generation:
		return _failure("DURABLE_GATE_GENERATION_OUT_OF_ORDER")
	if String(_pending.get("state", "")) != "STAGED":
		return _failure("DURABLE_GATE_INVALID_STATE")
	_pending["state"] = "COMMIT_PENDING"
	return _success()

func complete(operation_id: String, generation: int, committed: Dictionary) -> Dictionary:
	if _pending.is_empty() or String(_pending.get("operation_id", "")) != operation_id:
		return _failure("DURABLE_GATE_NO_MATCHING_OPERATION")
	if String(_pending.get("state", "")) != "COMMIT_PENDING":
		return _failure("DURABLE_GATE_INVALID_STATE")
	if int(_pending.get("generation", -1)) != generation or generation != _persisted_generation + 1:
		return _failure("DURABLE_GATE_GENERATION_OUT_OF_ORDER")
	if not bool(committed.get("success", false)) or int(committed.get("generation", -1)) != generation:
		_fatal_error = "DURABLE_GATE_COMMIT_FAILED_OR_MISMATCHED"
		return _failure(_fatal_error)
	_persisted_generation = generation
	var record: Dictionary = _pending.duplicate(true)
	record["state"] = "ACK_ELIGIBLE"
	if not bool(record.get("stale_session", false)):
		_ready.append(record)
	_pending = {}
	return _success({"generation": generation, "ack_eligible": true})

func peek_ack(peer_id: String, session_id: String,
		logical_player_id: String, ownership_epoch: int) -> Dictionary:
	# The caller receives no successful result for a stale transport or
	# ownership epoch even before attempting reliable enqueue.
	if _ready.is_empty() or not _fatal_error.is_empty():
		return {}
	var first: Dictionary = _ready[0]
	if String(first.get("peer_id", "")) != peer_id or String(first.get("session_id", "")) != session_id:
		return {}
	if String(first.get("logical_player_id", "")) != logical_player_id or int(first.get("ownership_epoch", 0)) != ownership_epoch:
		return {}
	return first.duplicate(true)

func mark_delivered(operation_id: String, peer_id: String, session_id: String,
		logical_player_id: String, ownership_epoch: int) -> Dictionary:
	if _ready.is_empty():
		return _failure("DURABLE_GATE_NO_ACK")
	var first: Dictionary = _ready[0]
	if String(first.get("operation_id", "")) != operation_id:
		return _failure("DURABLE_GATE_ACK_OUT_OF_ORDER")
	if String(first.get("peer_id", "")) != peer_id or String(first.get("session_id", "")) != session_id:
		return _failure("DURABLE_GATE_SESSION_MISMATCH")
	if String(first.get("logical_player_id", "")) != logical_player_id or int(first.get("ownership_epoch", 0)) != ownership_epoch:
		return _failure("DURABLE_GATE_OWNERSHIP_MISMATCH")
	_ready.remove_at(0)
	return _success()

func discard_stale_session(peer_id: String, session_id: String) -> Dictionary:
	# A disconnect while IO is still in-flight must quarantine the future ACK.
	# Persistence continues; after commit the reconnecting peer resolves the
	# canonical command outcome by M6 operation-id replay.
	if not _pending.is_empty() and String(_pending.get("peer_id", "")) == peer_id and String(_pending.get("session_id", "")) == session_id:
		_pending["stale_session"] = true
	# A transport leave must not cause an ACK to be delivered into an old
	# session; a retry after reconnect is resolved by canonical M6 replay.
	var removed := 0
	for i in range(_ready.size() - 1, -1, -1):
		var entry: Dictionary = _ready[i]
		if String(entry.get("peer_id", "")) == peer_id and String(entry.get("session_id", "")) == session_id:
			_ready.remove_at(i)
			removed += 1
	return _success({"removed": removed})

func fail_closed(error_code: String) -> Dictionary:
	_fatal_error = error_code if not error_code.is_empty() else "DURABLE_GATE_FATAL"
	return _failure(_fatal_error)

func get_report() -> Dictionary:
	return {
		"generation": _persisted_generation,
		"pending": not _pending.is_empty(),
		"pending_state": String(_pending.get("state", "")),
		"ready_count": _ready.size(), "ready_limit": _ready_limit,
		"fatal": not _fatal_error.is_empty(), "error_code": _fatal_error,
	}

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
