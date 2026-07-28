extends RefCounted

const TicketScript = preload("res://scripts/network/contracts/handoff_ticket.gd")
const ResultScript = preload("res://scripts/network/contracts/handoff_result.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")


const ALLOWED_TRANSITIONS: Dictionary = {
	"REQUESTED": ["PREPARING", "ABORTED", "EXPIRED"],
	"PREPARING": ["FROZEN", "ABORTED", "EXPIRED"],
	"FROZEN": ["SNAPSHOT_READY", "ABORTED", "EXPIRED"],
	"SNAPSHOT_READY": ["TARGET_PREPARED", "ABORTED", "EXPIRED"],
	"TARGET_PREPARED": ["COMMITTED", "ABORTED", "EXPIRED"],
	"COMMITTED": [],
	"ABORTED": [],
	"EXPIRED": [],
}

var ticket: Dictionary = {}
var transition_history: Array[Dictionary] = []


func setup(ticket_value: Dictionary) -> Dictionary:
	var validation: Dictionary = TicketScript.validate(ticket_value)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_TICKET")), String(validation.get("message", "")))
	ticket = TicketScript.normalize(ticket_value)
	transition_history = [{
		"state": String(ticket["state"]),
		"transition_revision": int(ticket["transition_revision"]),
		"tick": int(ticket["created_at_tick"]),
	}]
	return {"success": true, "ticket": ticket.duplicate(true)}


func prepare_transition(next_state: String, context: Dictionary = {}) -> Dictionary:
	if ticket.is_empty():
		return _failure("HANDOFF_NOT_INITIALIZED")
	if not TicketScript.STATES.has(next_state):
		return _failure("INVALID_HANDOFF_STATE")
	var allowed_context_fields: Array[String] = ["expected_transition_revision", "tick"]
	if next_state == "SNAPSHOT_READY":
		allowed_context_fields.append_array(["snapshot_id", "snapshot_hash"])
	if next_state in ["ABORTED", "EXPIRED"]:
		allowed_context_fields.append("reason")
	for context_key in context.keys():
		if typeof(context_key) != TYPE_STRING or not allowed_context_fields.has(String(context_key)):
			return _failure("UNEXPECTED_TRANSITION_CONTEXT")
	var current_state: String = String(ticket["state"])
	if context.has("expected_transition_revision") and not UtilsScript.is_json_integer(context["expected_transition_revision"]):
		return _failure("INVALID_TRANSITION_REVISION_TYPE")
	var expected_revision: int = int(context.get("expected_transition_revision", int(ticket["transition_revision"])))
	if expected_revision != int(ticket["transition_revision"]):
		return _failure("TRANSITION_REVISION_CONFLICT", "", {
			"expected": expected_revision,
			"actual": int(ticket["transition_revision"]),
		})
	if current_state == next_state:
		var replay_ticket: Dictionary = ticket.duplicate(true)
		var replay_hash: String = TicketScript.ticket_hash(replay_ticket)
		return {
			"success": true,
			"changed": false,
			"replay": true,
			"source_ticket_hash": replay_hash,
			"candidate_hash": replay_hash,
			"prepared_token": _prepared_token(replay_hash, replay_hash, int(transition_history.back().get("tick", ticket["created_at_tick"]))),
			"candidate": replay_ticket,
		}
	if TicketScript.TERMINAL_STATES.has(current_state):
		return _failure("HANDOFF_TERMINAL", "Cannot leave terminal handoff state")
	var current_allowed: Array = ALLOWED_TRANSITIONS.get(current_state, [])
	if not current_allowed.has(next_state):
		return _failure("ILLEGAL_HANDOFF_TRANSITION", "%s -> %s" % [current_state, next_state])
	if context.has("tick") and not UtilsScript.is_json_integer(context["tick"]):
		return _failure("INVALID_TRANSITION_TICK_TYPE")
	var tick: int = int(context.get("tick", int(ticket["created_at_tick"])))
	var last_transition_tick: int = int(transition_history.back().get("tick", ticket["created_at_tick"])) if not transition_history.is_empty() else int(ticket["created_at_tick"])
	if tick < int(ticket["created_at_tick"]) or tick < last_transition_tick:
		return _failure("INVALID_TRANSITION_TICK")
	if next_state == "EXPIRED" and tick < int(ticket["expires_at_tick"]):
		return _failure("HANDOFF_NOT_EXPIRED")
	if tick >= int(ticket["expires_at_tick"]) and next_state != "EXPIRED":
		return _failure("HANDOFF_EXPIRED")
	var candidate: Dictionary = ticket.duplicate(true)
	candidate["state"] = next_state
	candidate["transition_revision"] = int(ticket["transition_revision"]) + 1
	if next_state == "SNAPSHOT_READY":
		if typeof(context.get("snapshot_id")) != TYPE_STRING or typeof(context.get("snapshot_hash")) != TYPE_STRING:
			return _failure("INVALID_SNAPSHOT_REFERENCE_TYPE")
		candidate["snapshot_id"] = String(context["snapshot_id"])
		candidate["snapshot_hash"] = String(context["snapshot_hash"])
	if next_state == "ABORTED" or next_state == "EXPIRED":
		if context.has("reason") and typeof(context["reason"]) != TYPE_STRING:
			return _failure("INVALID_HANDOFF_REASON_TYPE")
		candidate["reason"] = String(context.get("reason", next_state.to_lower()))
	var validation: Dictionary = TicketScript.validate(candidate)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_TICKET")), String(validation.get("message", "")))
	var normalized_candidate: Dictionary = TicketScript.normalize(candidate)
	var source_hash: String = TicketScript.ticket_hash(ticket)
	var candidate_hash: String = TicketScript.ticket_hash(normalized_candidate)
	return {
		"success": true,
		"changed": true,
		"replay": false,
		"source_ticket_hash": source_hash,
		"candidate_hash": candidate_hash,
		"prepared_token": _prepared_token(source_hash, candidate_hash, tick),
		"candidate": normalized_candidate,
		"tick": tick,
	}


func commit_prepared(prepared: Dictionary) -> Dictionary:
	if not bool(prepared.get("success", false)):
		return _failure("INVALID_PREPARED_TRANSITION")
	var candidate_value = prepared.get("candidate", {})
	if typeof(candidate_value) != TYPE_DICTIONARY:
		return _failure("INVALID_PREPARED_TRANSITION")
	var candidate: Dictionary = candidate_value
	var validation: Dictionary = TicketScript.validate(candidate)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_TICKET")), String(validation.get("message", "")))
	if String(prepared.get("source_ticket_hash", "")) != TicketScript.ticket_hash(ticket):
		return _failure("PREPARED_SOURCE_MISMATCH")
	if String(prepared.get("candidate_hash", "")) != TicketScript.ticket_hash(candidate):
		return _failure("PREPARED_CANDIDATE_MISMATCH")
	var prepared_tick_value = prepared.get("tick", transition_history.back().get("tick", ticket["created_at_tick"]))
	if not UtilsScript.is_json_integer(prepared_tick_value):
		return _failure("INVALID_TRANSITION_TICK_TYPE")
	var expected_token: String = _prepared_token(
		String(prepared.get("source_ticket_hash", "")),
		String(prepared.get("candidate_hash", "")),
		int(prepared_tick_value)
	)
	if String(prepared.get("prepared_token", "")) != expected_token:
		return _failure("PREPARED_TOKEN_MISMATCH")
	if not _candidate_preserves_identity(candidate):
		return _failure("PREPARED_IDENTITY_MUTATION")
	if not bool(prepared.get("changed", false)):
		if candidate != ticket:
			return _failure("INVALID_REPLAY_CANDIDATE")
		return {"success": true, "changed": false, "replay": true, "ticket": ticket.duplicate(true)}
	var allowed: Array = ALLOWED_TRANSITIONS.get(String(ticket.get("state", "")), [])
	if not allowed.has(String(candidate.get("state", ""))):
		return _failure("ILLEGAL_HANDOFF_TRANSITION")
	if int(candidate["transition_revision"]) < int(ticket.get("transition_revision", -1)):
		return _failure("STALE_PREPARED_TRANSITION")
	if int(candidate["transition_revision"]) != int(ticket["transition_revision"]) + 1:
		return _failure("TRANSITION_REVISION_CONFLICT")
	ticket = TicketScript.normalize(candidate)
	transition_history.append({
		"state": String(ticket["state"]),
		"transition_revision": int(ticket["transition_revision"]),
		"tick": int(prepared.get("tick", ticket["created_at_tick"])),
	})
	return {"success": true, "changed": true, "replay": false, "ticket": ticket.duplicate(true)}


func transition(next_state: String, context: Dictionary = {}) -> Dictionary:
	var prepared: Dictionary = prepare_transition(next_state, context)
	if not bool(prepared.get("success", false)):
		return prepared
	return commit_prepared(prepared)


func expire(tick: int, reason: String = "lease_timeout") -> Dictionary:
	if ticket.is_empty():
		return _failure("HANDOFF_NOT_INITIALIZED")
	if tick < int(ticket["expires_at_tick"]):
		return _failure("HANDOFF_NOT_EXPIRED")
	return transition("EXPIRED", {"tick": tick, "reason": reason})


func create_result(completed_at_tick: int, state_revision: int) -> Dictionary:
	if ticket.is_empty():
		return {}
	var state: String = String(ticket["state"])
	var status: String = state if state in ["COMMITTED", "ABORTED", "EXPIRED"] else "REJECTED"
	var error_code: String = "" if status == "COMMITTED" else (String(ticket["reason"]) if not String(ticket["reason"]).is_empty() else "HANDOFF_NOT_COMMITTED")
	var owner: String = String(ticket["target_node_id"]) if status == "COMMITTED" else String(ticket["source_node_id"])
	var epoch: int = int(ticket["target_authority_epoch"]) if status == "COMMITTED" else int(ticket["source_authority_epoch"])
	return ResultScript.create(
		String(ticket["ticket_id"]), String(ticket["entity_id"]), status, error_code,
		String(ticket["source_node_id"]), String(ticket["target_node_id"]), owner,
		epoch, state_revision, completed_at_tick,
		{"transition_revision": int(ticket["transition_revision"])}
	)


func create_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.handoff_state_machine.v1",
		"ticket": ticket.duplicate(true),
		"transition_history": transition_history.duplicate(true),
	}


func _prepared_token(source_hash: String, candidate_hash: String, tick: int) -> String:
	return UtilsScript.payload_hash({
		"source_ticket_hash": source_hash,
		"candidate_hash": candidate_hash,
		"tick": tick,
	})


func _candidate_preserves_identity(candidate: Dictionary) -> bool:
	for field in [
		"schema", "protocol_version", "ticket_id", "entity_id", "source_node_id",
		"target_node_id", "source_authority_epoch", "target_authority_epoch",
		"expected_state_revision", "region_id", "created_at_tick", "expires_at_tick",
	]:
		if candidate.get(field) != ticket.get(field):
			return false
	return true


func _failure(error_code: String, message: String = "", details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"message": message,
		"details": details.duplicate(true),
	}
