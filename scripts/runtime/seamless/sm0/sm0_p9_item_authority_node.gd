extends Node
# SM0 P9 authority-boundary lab. Stores only the bounded authority envelope needed to prove cross-owner transfer semantics.


const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p9_foreign_item_boundary_contract.gd")

var _authority_id := ""
var _active_items: Dictionary = {}
var _outgoing: Dictionary = {}
var _incoming: Dictionary = {}
var _interaction_ledger: Dictionary = {}
var _event_history: Array[Dictionary] = []
var _fail_next_receive_commit := false

func setup(authority_id: String) -> Dictionary:
	var normalized := authority_id.strip_edges()
	if normalized not in Contract.ALL_AUTHORITIES:
		return _failure("SM0_P9_AUTHORITY_ID_INVALID")
	_authority_id = normalized
	_event("SM0_P9_ITEM_AUTHORITY_READY", {"authority_scope": _scope_for_authority(), "writer_count": 0})
	return _success()

func seed_item_for_tests(item: Dictionary) -> Dictionary:
	if _authority_id.is_empty():
		return _failure("SM0_P9_AUTHORITY_NOT_READY")
	var check := Contract.validate_item_envelope(item)
	if not bool(check.get("success", false)):
		return _failure("SM0_P9_SEED_ITEM_INVALID", {"cause": check})
	if String(item.get("owner_authority_id", "")) != _authority_id:
		return _failure("SM0_P9_SEED_OWNER_MISMATCH")
	var item_id := String(item.get("item_id", ""))
	if _active_items.has(item_id):
		return _failure("SM0_P9_SEED_DUPLICATE_ITEM")
	_active_items[item_id] = item.duplicate(true)
	_event("SM0_P9_ITEM_SEEDED", {"item_id": item_id, "ownership_epoch": int(item.get("ownership_epoch", 0)), "item_revision": int(item.get("item_revision", 0)), "authority_scope": String(item.get("authority_scope", ""))})
	return _success({"item": item})

func apply_interaction(request: Dictionary) -> Dictionary:
	var check := Contract.validate_interaction_request(request)
	if not bool(check.get("success", false)):
		return _failure(String(check.get("error_code", "SM0_P9_INTERACTION_INVALID")))
	var operation_id := String(request.get("operation_id", ""))
	var fingerprint := String(request.get("checksum", ""))
	if _interaction_ledger.has(operation_id):
		var existing := Dictionary(_interaction_ledger[operation_id])
		if String(existing.get("request_checksum", "")) != fingerprint:
			return _failure("SM0_P9_INTERACTION_REPLAY_CONFLICT")
		return _success({"replay": true, "item": Dictionary(existing.get("item", {})).duplicate(true)})
	if String(request.get("expected_owner_authority_id", "")) != _authority_id:
		return _failure("SM0_P9_FOREIGN_DIRECT_MUTATION_FORBIDDEN")
	var item_id := String(request.get("item_id", ""))
	if not _active_items.has(item_id):
		return _failure("SM0_P9_FOREIGN_ITEM_NOT_LOCAL")
	var current := Dictionary(_active_items[item_id])
	if String(current.get("owner_authority_id", "")) != _authority_id:
		return _failure("SM0_P9_FOREIGN_DIRECT_MUTATION_FORBIDDEN")
	if _is_item_frozen(item_id):
		return _failure("SM0_P9_ITEM_TRANSFER_FROZEN")
	if int(request.get("expected_ownership_epoch", 0)) != int(current.get("ownership_epoch", 0)) or int(request.get("expected_item_revision", 0)) != int(current.get("item_revision", 0)):
		return _failure("SM0_P9_INTERACTION_REVISION_STALE")
	var updated := Contract.interacted_item(current)
	_active_items[item_id] = updated
	_interaction_ledger[operation_id] = {"request_checksum": fingerprint, "item": updated.duplicate(true)}
	_event("SM0_P9_FOREIGN_INTERACTION_COMMITTED", {
		"operation_id": operation_id,
		"item_id": item_id,
		"actor_authority_id": String(request.get("actor_authority_id", "")),
		"owner_authority_id": _authority_id,
		"ownership_epoch": int(updated.get("ownership_epoch", 0)),
		"item_revision": int(updated.get("item_revision", 0)),
		"interaction_sequence": int(updated.get("interaction_sequence", 0)),
	})
	return _success({"replay": false, "item": updated.duplicate(true)})

func prepare_send(request: Dictionary) -> Dictionary:
	var check := Contract.validate_transfer_request(request)
	if not bool(check.get("success", false)):
		return _failure(String(check.get("error_code", "SM0_P9_TRANSFER_INVALID")))
	if String(request.get("source_authority_id", "")) != _authority_id:
		return _failure("SM0_P9_TRANSFER_WRONG_SOURCE")
	var operation_id := String(request.get("operation_id", ""))
	var request_checksum := String(request.get("checksum", ""))
	if _outgoing.has(operation_id):
		var existing := Dictionary(_outgoing[operation_id])
		if String(existing.get("request_checksum", "")) != request_checksum:
			return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
		return _success({"replay": true, "stage": String(existing.get("stage", ""))})
	var item_id := String(request.get("item_id", ""))
	if not _active_items.has(item_id):
		return _failure("SM0_P9_TRANSFER_SOURCE_ITEM_MISSING")
	if _is_item_frozen(item_id):
		return _failure("SM0_P9_ITEM_TRANSFER_ALREADY_PREPARED")
	var current := Dictionary(_active_items[item_id])
	if String(current.get("checksum", "")) != String(Dictionary(request.get("item", {})).get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_SOURCE_ITEM_STALE")
	_outgoing[operation_id] = {"request_checksum": request_checksum, "stage": "PREPARED", "item": current.duplicate(true)}
	_event("SM0_P9_TRANSFER_SOURCE_PREPARED", {"operation_id": operation_id, "item_id": item_id, "shadow_only": false, "source_authority_id": _authority_id})
	return _success({"replay": false, "stage": "PREPARED"})

func prepare_receive(request: Dictionary) -> Dictionary:
	var check := Contract.validate_transfer_request(request)
	if not bool(check.get("success", false)):
		return _failure(String(check.get("error_code", "SM0_P9_TRANSFER_INVALID")))
	if String(request.get("target_authority_id", "")) != _authority_id:
		return _failure("SM0_P9_TRANSFER_WRONG_TARGET")
	var operation_id := String(request.get("operation_id", ""))
	var request_checksum := String(request.get("checksum", ""))
	if _incoming.has(operation_id):
		var existing := Dictionary(_incoming[operation_id])
		if String(existing.get("request_checksum", "")) != request_checksum:
			return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
		return _success({"replay": true, "stage": String(existing.get("stage", ""))})
	var item_id := String(request.get("item_id", ""))
	if _active_items.has(item_id):
		return _failure("SM0_P9_TRANSFER_TARGET_ALREADY_ACTIVE")
	var shadow := Contract.transferred_item(request)
	_incoming[operation_id] = {"request_checksum": request_checksum, "stage": "SHADOW", "item": shadow.duplicate(true)}
	_event("SM0_P9_TRANSFER_TARGET_PREPARED", {"operation_id": operation_id, "item_id": item_id, "shadow_only": true, "target_authority_id": _authority_id})
	return _success({"replay": false, "stage": "SHADOW", "shadow_item": shadow})

func commit_send(request: Dictionary) -> Dictionary:
	var operation_id := String(request.get("operation_id", ""))
	if not _outgoing.has(operation_id):
		return _failure("SM0_P9_TRANSFER_SOURCE_NOT_PREPARED")
	var state := Dictionary(_outgoing[operation_id])
	if String(state.get("request_checksum", "")) != String(request.get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
	if String(state.get("stage", "")) == "RETIRED":
		return _success({"replay": true, "retirement_proof": Dictionary(state.get("retirement_proof", {})).duplicate(true)})
	if String(state.get("stage", "")) != "PREPARED":
		return _failure("SM0_P9_TRANSFER_SOURCE_STAGE_INVALID")
	var item_id := String(request.get("item_id", ""))
	if not _active_items.has(item_id):
		return _failure("SM0_P9_TRANSFER_SOURCE_ITEM_MISSING")
	var retired := Dictionary(_active_items[item_id]).duplicate(true)
	if String(retired.get("checksum", "")) != String(Dictionary(state.get("item", {})).get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_SOURCE_CHANGED_DURING_PREPARE")
	_active_items.erase(item_id)
	var proof := Contract.create_retirement_proof(request, retired)
	state["stage"] = "RETIRED"
	state["retirement_proof"] = proof.duplicate(true)
	state["item"] = retired
	_outgoing[operation_id] = state
	_event("SM0_P9_TRANSFER_SOURCE_RETIRED", {"operation_id": operation_id, "item_id": item_id, "source_authority_id": _authority_id, "ownership_epoch": int(retired.get("ownership_epoch", 0)), "item_revision": int(retired.get("item_revision", 0))})
	return _success({"replay": false, "retirement_proof": proof})

func commit_receive(request: Dictionary, retirement_proof: Dictionary) -> Dictionary:
	var operation_id := String(request.get("operation_id", ""))
	if not _incoming.has(operation_id):
		return _failure("SM0_P9_TRANSFER_TARGET_NOT_PREPARED")
	var state := Dictionary(_incoming[operation_id])
	if String(state.get("request_checksum", "")) != String(request.get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
	if String(state.get("stage", "")) == "ACTIVE":
		return _success({"replay": true, "item": Dictionary(state.get("item", {})).duplicate(true)})
	if String(state.get("stage", "")) != "SHADOW":
		return _failure("SM0_P9_TRANSFER_TARGET_STAGE_INVALID")
	var proof_check := Contract.validate_retirement_proof(retirement_proof, request)
	if not bool(proof_check.get("success", false)):
		return _failure(String(proof_check.get("error_code", "SM0_P9_RETIREMENT_PROOF_INVALID")))
	if _fail_next_receive_commit:
		_fail_next_receive_commit = false
		return _failure("SM0_P9_INJECTED_TARGET_COMMIT_FAILURE")
	var item := Dictionary(state.get("item", {})).duplicate(true)
	_active_items[String(item.get("item_id", ""))] = item
	state["stage"] = "ACTIVE"
	state["item"] = item.duplicate(true)
	_incoming[operation_id] = state
	_event("SM0_P9_TRANSFER_TARGET_COMMITTED", {"operation_id": operation_id, "item_id": String(item.get("item_id", "")), "target_authority_id": _authority_id, "ownership_epoch": int(item.get("ownership_epoch", 0)), "item_revision": int(item.get("item_revision", 0)), "authority_scope": String(item.get("authority_scope", ""))})
	return _success({"replay": false, "item": item})

func cancel_send(request: Dictionary) -> Dictionary:
	var operation_id := String(request.get("operation_id", ""))
	if not _outgoing.has(operation_id):
		return _success({"replay": true})
	var state := Dictionary(_outgoing[operation_id])
	if String(state.get("request_checksum", "")) != String(request.get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
	if String(state.get("stage", "")) == "CANCELLED":
		return _success({"replay": true})
	if String(state.get("stage", "")) != "PREPARED":
		return _failure("SM0_P9_TRANSFER_CANCEL_STAGE_INVALID")
	state["stage"] = "CANCELLED"
	_outgoing[operation_id] = state
	_event("SM0_P9_TRANSFER_SOURCE_CANCELLED", {"operation_id": operation_id, "item_id": String(request.get("item_id", "")), "source_authority_id": _authority_id})
	return _success({"replay": false})

func rollback_send(request: Dictionary) -> Dictionary:
	var operation_id := String(request.get("operation_id", ""))
	if not _outgoing.has(operation_id):
		return _failure("SM0_P9_TRANSFER_SOURCE_NOT_PREPARED")
	var state := Dictionary(_outgoing[operation_id])
	if String(state.get("request_checksum", "")) != String(request.get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
	if String(state.get("stage", "")) == "ROLLED_BACK":
		return _success({"replay": true})
	if String(state.get("stage", "")) != "RETIRED":
		return _failure("SM0_P9_TRANSFER_ROLLBACK_STAGE_INVALID")
	var item := Dictionary(state.get("item", {})).duplicate(true)
	_active_items[String(item.get("item_id", ""))] = item
	state["stage"] = "ROLLED_BACK"
	_outgoing[operation_id] = state
	_event("SM0_P9_TRANSFER_SOURCE_ROLLED_BACK", {"operation_id": operation_id, "item_id": String(item.get("item_id", "")), "source_authority_id": _authority_id})
	return _success({"replay": false, "item": item})

func abort_receive(request: Dictionary) -> Dictionary:
	var operation_id := String(request.get("operation_id", ""))
	if not _incoming.has(operation_id):
		return _success({"replay": true})
	var state := Dictionary(_incoming[operation_id])
	if String(state.get("request_checksum", "")) != String(request.get("checksum", "")):
		return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
	if String(state.get("stage", "")) == "ACTIVE":
		return _failure("SM0_P9_TRANSFER_ABORT_AFTER_COMMIT_FORBIDDEN")
	_incoming.erase(operation_id)
	_event("SM0_P9_TRANSFER_TARGET_ABORTED", {"operation_id": operation_id, "item_id": String(request.get("item_id", "")), "target_authority_id": _authority_id})
	return _success({"replay": false})

func fail_next_receive_commit_for_tests() -> void:
	_fail_next_receive_commit = true

func get_item(item_id: String) -> Dictionary:
	return Dictionary(_active_items.get(item_id, {})).duplicate(true)

func has_item(item_id: String) -> bool:
	return _active_items.has(item_id)

func status_for_tests() -> Dictionary:
	return {
		"authority_id": _authority_id,
		"authority_scope": _scope_for_authority(),
		"writer_count": 0 if _active_items.is_empty() else 1,
		"active_item_count": _active_items.size(),
		"active_items": _active_items.duplicate(true),
		"outgoing": _outgoing.duplicate(true),
		"incoming": _incoming.duplicate(true),
		"interaction_ledger_count": _interaction_ledger.size(),
		"event_count": _event_history.size(),
		"events": _event_history.duplicate(true),
	}

func _is_item_frozen(item_id: String) -> bool:
	for operation_id in _outgoing.keys():
		var state := Dictionary(_outgoing[operation_id])
		if String(state.get("stage", "")) == "PREPARED" and String(Dictionary(state.get("item", {})).get("item_id", "")) == item_id:
			return true
	return false

func _scope_for_authority() -> String:
	return Contract.SCOPE_SHIP if _authority_id == Contract.SHIP_AUTHORITY else Contract.SCOPE_WORLD

func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {
		"schema": "distributed_world_simulator.sm0_event.v1",
		"event": event_name,
		"severity": "INFO",
		"process_role": "p9-item-authority",
		"process_id": OS.get_process_id(),
		"time_msec": Time.get_ticks_msec(),
		"authority_id": _authority_id,
		"writer_count": 0 if _active_items.is_empty() else 1,
		"authority_scope": _scope_for_authority(),
	}
	for key in details.keys():
		event[key] = details[key]
	_event_history.append(event.duplicate(true))
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}