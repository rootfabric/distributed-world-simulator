extends RefCounted

# NET-SMOOTH1 R4.2-P1-A — isolated command/periodic writer ownership PROOF.
# Not wired to M3 production handlers. No packets, SceneTree or live gameplay
# references are stored or accessed here. No blocking waits / IO / sleep.
#
# Production P1-B must explicitly integrate canonical mutation+outbox,
# deferred broadcast, writer-result polling and startup/reconnect recovery.
# One writer instance MUST be shared with the existing periodic checkpoint path.
const PHASE_UNCONFIGURED := "UNCONFIGURED"
const PHASE_IDLE := "IDLE"
const PHASE_APPLYING := "APPLYING"
const PHASE_COMMIT_PENDING := "COMMIT_PENDING"
const PHASE_ACK_READY := "ACK_READY"
const PHASE_FATAL := "FATAL"

var _writer
var _ack_gate
var _phase := PHASE_UNCONFIGURED
var _held: Dictionary = {}
var _fatal_code := ""
var _successful_commits := 0
var _stale_quarantines := 0
var _prior_periodic_observed := 0


func configure(writer_ref, ack_gate_ref) -> Dictionary:
	if _phase != PHASE_UNCONFIGURED:
		return _failure("P1A_ALREADY_CONFIGURED")
	if writer_ref == null or ack_gate_ref == null:
		return _failure("P1A_WRITER_AND_GATE_REQUIRED")
	for method in ["submit", "poll_completed", "is_busy"]:
		if not writer_ref.has_method(method):
			return _failure("P1A_SINGLE_WRITER_REQUIRED")
	for method in ["get_report", "can_accept_mutation", "stage",
		"mark_submitted", "complete", "peek_ack", "mark_delivered",
		"discard_stale_session", "observe_periodic_commit", "fail_closed"]:
		if not ack_gate_ref.has_method(method):
			return _failure("P1A_M6_ACK_GATE_REQUIRED")
	var report: Dictionary = ack_gate_ref.get_report()
	if bool(report.get("fatal", false)) or bool(report.get("pending", false)):
		return _failure("P1A_GATE_NOT_QUIESCENT")
	if int(report.get("ready_count", -1)) != 0:
		return _failure("P1A_UNDELIVERED_ACKS")
	if int(report.get("generation", -1)) < 0:
		return _failure("P1A_GATE_GENERATION_REQUIRED")
	_writer = writer_ref
	_ack_gate = ack_gate_ref
	_phase = PHASE_IDLE
	return _success({"generation": int(report["generation"])})


# Pre-mutation reservation. During a previous periodic checkpoint, do not
# apply a conflicting command and do not busy-wait for its completion.
func reserve_mutation(operation_id: String, peer_id: String, session_id: String,
		player_id: String, ownership_epoch: int, command_type: String) -> Dictionary:
	if _phase == PHASE_FATAL:
		return _failure(_fatal_code)
	if _phase != PHASE_IDLE:
		return _failure("P1A_MUTATION_FENCED")
	if operation_id.is_empty() or peer_id.is_empty() or session_id.is_empty() or player_id.is_empty():
		return _failure("P1A_IDENTITY_REQUIRED")
	if ownership_epoch < 1 or command_type.is_empty():
		return _failure("P1A_OWNERSHIP_AND_TYPE_REQUIRED")
	if _writer.is_busy():
		return _failure("P1A_WAIT_PRIOR_PERIODIC")
	var gate_report: Dictionary = _ack_gate.get_report()
	if (not _ack_gate.can_accept_mutation()
		or int(gate_report.get("ready_count", 0)) != 0):
		return _failure("P1A_GATE_BACKPRESSURE")
	var current_generation := int(gate_report.get("generation", -1))
	if current_generation < 0:
		return fail_closed("P1A_GATE_GENERATION_INVALID")
	_held = {
		"operation_id": operation_id, "peer_id": peer_id,
		"session_id": session_id, "player_id": player_id,
		"ownership_epoch": ownership_epoch, "command_type": command_type,
		"previous_generation": current_generation,
		"generation": current_generation + 1,
		"stale_session": false,
	}
	_phase = PHASE_APPLYING
	return _success({"generation": current_generation + 1,
		"previous_generation": current_generation})


# Called ONLY after successful canonical mutation + durable replay/outbox stage.
# Caller-supplied dictionaries are detached by the existing writer.submit().
# A failed submit after mutation is fatal; never issue an early ACK or retry
# the same in-memory mutation by guessing whether it was committed.
func submit_frozen(operation_id: String, result: Dictionary,
		authority_state: Dictionary, replay_state: Dictionary) -> Dictionary:
	if _phase != PHASE_APPLYING or String(_held.get("operation_id", "")) != operation_id:
		return _failure("P1A_NO_RESERVED_MUTATION")
	if not bool(result.get("success", false)):
		return fail_closed("P1A_SUCCESSFUL_MUTATION_REQUIRED")
	if authority_state.is_empty() or replay_state.is_empty():
		return fail_closed("P1A_FROZEN_CHECKPOINT_REQUIRED")
	if _writer.is_busy():
		return fail_closed("P1A_SINGLE_WRITER_CONFLICT")
	var generation := int(_held["generation"])
	var previous_generation := int(_held["previous_generation"])
	var gate_report: Dictionary = _ack_gate.get_report()
	if int(gate_report.get("generation", -1)) != previous_generation:
		return fail_closed("P1A_GATE_GENERATION_CHANGED")
	var staged: Dictionary = _ack_gate.stage(
		operation_id, String(_held["peer_id"]), String(_held["session_id"]),
		String(_held["player_id"]), int(_held["ownership_epoch"]),
		String(_held["command_type"]), result, generation
	)
	if not bool(staged.get("success", false)):
		return fail_closed("P1A_ACK_STAGE_FAILED")
	# ACK/outbound payloads are copied independently of the caller after stage.
	_held["result"] = result.duplicate(true)
	var checkpoint_id := "checkpoint/m6/dedicated/%d" % generation
	var submitted: Dictionary = _writer.submit(
		authority_state, replay_state, checkpoint_id,
		generation, previous_generation, operation_id
	)
	if not bool(submitted.get("success", false)):
		return fail_closed("P1A_WRITER_SUBMISSION_FAILED")
	var marked: Dictionary = _ack_gate.mark_submitted(operation_id, generation)
	if not bool(marked.get("success", false)):
		return fail_closed("P1A_ACK_SUBMISSION_FENCE_FAILED")
	_held["checkpoint_id"] = checkpoint_id
	_phase = PHASE_COMMIT_PENDING
	return _success({"generation": generation, "pending": true})


# Only the owning main thread calls poll_completed(); this function never waits.
func poll_command_completion() -> Dictionary:
	if _phase == PHASE_FATAL:
		return _failure(_fatal_code)
	if _phase != PHASE_COMMIT_PENDING:
		return _failure("P1A_NOT_COMMIT_PENDING")
	var completion: Dictionary = _writer.poll_completed()
	if completion.is_empty():
		return _success({"pending": true, "ack_eligible": false})
	return accept_command_completion(completion)


# Exposed so tests can inject stale/failing completions without fake filesystem
# success. Production caller must provide ONLY this writer's poll result.
func accept_command_completion(completion: Dictionary) -> Dictionary:
	if _phase != PHASE_COMMIT_PENDING:
		return _failure("P1A_NOT_COMMIT_PENDING")
	var details: Dictionary = Dictionary(completion.get("details", {}))
	if not bool(completion.get("success", false)):
		return fail_closed("P1A_ATOMIC_COMMIT_FAILED")
	if (int(details.get("generation", -1)) != int(_held["generation"])
		or String(details.get("operation_id", "")) != String(_held["operation_id"])
		or String(details.get("checkpoint_id", "")) != String(_held["checkpoint_id"])):
		return fail_closed("P1A_COMMIT_IDENTITY_MISMATCH")
	var gate_committed: Dictionary = _ack_gate.complete(
		String(_held["operation_id"]), int(_held["generation"]),
		{"success": true, "generation": int(_held["generation"])}
	)
	if not bool(gate_committed.get("success", false)):
		return fail_closed("P1A_ACK_COMMIT_FENCE_FAILED")
	_successful_commits += 1
	_phase = PHASE_ACK_READY
	if bool(_held.get("stale_session", false)):
		_held.clear()
		_phase = PHASE_IDLE
		return _success({"committed": true, "ack_eligible": false, "stale_session": true})
	return _success({"committed": true, "ack_eligible": true,
		"generation": int(details["generation"])})


# The prior periodic checkpoint belongs to the SAME writer instance. Its
# completion must be observed from the owner runtime and handed off only AFTER
# its repository commit; never poll the same completion in two owners.
func observe_periodic_completion(completion: Dictionary) -> Dictionary:
	# P1-B: a periodic completion arriving while this owner has a reserved or
	# pending durable command is a strict single-writer ordering violation.
	# The caller must never silently discard that completed generation: a lost
	# previous_generation would make the next ACK falsely appear durable.
	if _phase == PHASE_FATAL:
		return _failure(_fatal_code)
	if _phase != PHASE_IDLE:
		return fail_closed("P1B_PERIODIC_COMPLETION_OUT_OF_PHASE")
	var details: Dictionary = Dictionary(completion.get("details", {}))
	if not bool(completion.get("success", false)):
		return fail_closed("P1A_PERIODIC_COMMIT_FAILED")
	if not String(details.get("operation_id", "x")).is_empty():
		return fail_closed("P1A_PERIODIC_IS_COMMAND")
	var expected := int(_ack_gate.get_report().get("generation", -1)) + 1
	if int(details.get("generation", -1)) != expected:
		return fail_closed("P1A_PERIODIC_GENERATION_MISMATCH")
	var observed: Dictionary = _ack_gate.observe_periodic_commit(expected)
	if not bool(observed.get("success", false)):
		return fail_closed("P1A_PERIODIC_GATE_REJECTED")
	_prior_periodic_observed += 1
	return _success({"generation": expected})


# Forensic/transport adapter: successful user-visible publication is only
# available after the exact worker repository commit. No early effects.
func peek_publication(peer_id: String, session_id: String,
		player_id: String, ownership_epoch: int) -> Dictionary:
	if _phase != PHASE_ACK_READY or bool(_held.get("stale_session", false)):
		return {}
	var head: Dictionary = _ack_gate.peek_ack(peer_id, session_id,
		player_id, ownership_epoch)
	if head.is_empty() or String(head.get("operation_id", "")) != String(_held.get("operation_id", "")):
		return {}
	return _success({"operation_id": String(_held["operation_id"]),
		"result": Dictionary(_held["result"]).duplicate(true),
		"generation": int(_held["generation"])})


func mark_enqueued(operation_id: String, peer_id: String, session_id: String,
		player_id: String, ownership_epoch: int, enqueued: bool) -> Dictionary:
	if _phase != PHASE_ACK_READY or operation_id != String(_held.get("operation_id", "")):
		return _failure("P1A_NO_READY_ACK")
	if peek_publication(peer_id, session_id, player_id, ownership_epoch).is_empty():
		return _failure("P1A_ACK_IDENTITY_MISMATCH")
	if not enqueued:
		var discarded: Dictionary = _ack_gate.discard_stale_session(peer_id, session_id)
		if not bool(discarded.get("success", false)):
			return fail_closed("P1A_ACK_QUARANTINE_FAILED")
		_stale_quarantines += 1
		_held.clear()
		_phase = PHASE_IDLE
		return _success({"ack_delivered": false, "replay_required": true})
	var delivered: Dictionary = _ack_gate.mark_delivered(
		operation_id, peer_id, session_id, player_id, ownership_epoch
	)
	if not bool(delivered.get("success", false)):
		return fail_closed("P1A_ACK_OUT_OF_ORDER")
	_held.clear()
	_phase = PHASE_IDLE
	return _success({"ack_delivered": true})


func discard_stale_session(peer_id: String, session_id: String) -> Dictionary:
	if _phase == PHASE_UNCONFIGURED:
		return _failure("P1A_NOT_CONFIGURED")
	var discarded: Dictionary = _ack_gate.discard_stale_session(peer_id, session_id)
	if not bool(discarded.get("success", false)):
		return fail_closed("P1A_ACK_QUARANTINE_FAILED")
	if not _held.is_empty() and String(_held.get("peer_id", "")) == peer_id and String(_held.get("session_id", "")) == session_id:
		_held["stale_session"] = true
		_stale_quarantines += 1
		if _phase == PHASE_ACK_READY:
			_held.clear()
			_phase = PHASE_IDLE
	return _success()


func fail_closed(code: String) -> Dictionary:
	_fatal_code = code if not code.is_empty() else "P1A_FATAL"
	if _ack_gate != null:
		_ack_gate.fail_closed(_fatal_code)
	_phase = PHASE_FATAL
	# Do not erase _held: its bounded metadata proves the failed generation.
	return _failure(_fatal_code)


func get_report() -> Dictionary:
	return {
		"phase": _phase,
		"generation": int(_ack_gate.get_report().get("generation", -1)) if _ack_gate != null else -1,
		"pending": _phase in [PHASE_APPLYING, PHASE_COMMIT_PENDING],
		"ready": _phase == PHASE_ACK_READY,
		"fatal": _phase == PHASE_FATAL,
		"fatal_code": _fatal_code,
		"held_generation": int(_held.get("generation", -1)),
		"successful_commits": _successful_commits,
		"stale_quarantines": _stale_quarantines,
		"prior_periodic_observed": _prior_periodic_observed,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
