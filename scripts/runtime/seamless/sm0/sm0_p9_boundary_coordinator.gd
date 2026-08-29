extends RefCounted
# Coordinates the bounded SM0 P9 authority-envelope transaction; it is not a production Item Graph owner or persistence owner.


const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p9_foreign_item_boundary_contract.gd")

var _current_outer_authority_id := Contract.AUTHORITY_A
var _outer_authority_epoch := 1
var _operation_ledger: Dictionary = {}
var _failure_ledger: Dictionary = {}
var _event_history: Array[Dictionary] = []

func observe_outer_owner(authority_id: String, outer_epoch: int) -> Dictionary:
	if authority_id not in Contract.WORLD_AUTHORITIES or outer_epoch < 1:
		return _failure("SM0_P9_OUTER_OWNER_INVALID")
	if outer_epoch < _outer_authority_epoch:
		return _failure("SM0_P9_OUTER_OWNER_STALE")
	if outer_epoch == _outer_authority_epoch:
		if authority_id != _current_outer_authority_id:
			return _failure("SM0_P9_OUTER_OWNER_SAME_EPOCH_MUTATION")
		return _success({"replay": true})
	if outer_epoch != _outer_authority_epoch + 1:
		return _failure("SM0_P9_OUTER_OWNER_EPOCH_GAP")
	var previous := _current_outer_authority_id
	_current_outer_authority_id = authority_id
	_outer_authority_epoch = outer_epoch
	_event("SM0_P9_OUTER_OWNER_OBSERVED", {"previous_outer_owner_authority_id": previous, "outer_owner_authority_id": authority_id, "outer_authority_epoch": outer_epoch})
	return _success({"replay": false})

func route_interaction(actor_authority, owner_authority, request: Dictionary) -> Dictionary:
	var check := Contract.validate_interaction_request(request)
	if not bool(check.get("success", false)):
		return _failure(String(check.get("error_code", "SM0_P9_INTERACTION_INVALID")))
	if String(actor_authority.status_for_tests().get("authority_id", "")) != String(request.get("actor_authority_id", "")):
		return _failure("SM0_P9_INTERACTION_ACTOR_MISMATCH")
	if String(owner_authority.status_for_tests().get("authority_id", "")) != String(request.get("expected_owner_authority_id", "")):
		return _failure("SM0_P9_INTERACTION_ROUTE_OWNER_MISMATCH")
	var result: Dictionary = owner_authority.apply_interaction(request)
	if not bool(result.get("success", false)):
		return result
	var item := Dictionary(Dictionary(result.get("details", {})).get("item", {}))
	_event("SM0_P9_FOREIGN_INTERACTION_ROUTED", {"operation_id": String(request.get("operation_id", "")), "item_id": String(request.get("item_id", "")), "actor_authority_id": String(request.get("actor_authority_id", "")), "owner_authority_id": String(request.get("expected_owner_authority_id", "")), "item_revision": int(item.get("item_revision", 0)), "replay": bool(Dictionary(result.get("details", {})).get("replay", false))})
	return result

func transfer(source_authority, target_authority, request: Dictionary) -> Dictionary:
	var check := Contract.validate_transfer_request(request)
	if not bool(check.get("success", false)):
		return _failure(String(check.get("error_code", "SM0_P9_TRANSFER_INVALID")))
	var operation_id := String(request.get("operation_id", ""))
	var request_checksum := String(request.get("checksum", ""))
	if _operation_ledger.has(operation_id):
		var existing := Dictionary(_operation_ledger[operation_id])
		if String(existing.get("request_checksum", "")) != request_checksum:
			return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
		return _success({"replay": true, "item": Dictionary(existing.get("item", {})).duplicate(true)})
	if _failure_ledger.has(operation_id):
		var failed := Dictionary(_failure_ledger[operation_id])
		if String(failed.get("request_checksum", "")) != request_checksum:
			return _failure("SM0_P9_TRANSFER_REPLAY_CONFLICT")
		return _failure(String(failed.get("error_code", "SM0_P9_TRANSFER_FAILED")), {"replay": true})
	if String(source_authority.status_for_tests().get("authority_id", "")) != String(request.get("source_authority_id", "")):
		return _failure("SM0_P9_TRANSFER_SOURCE_ROUTE_MISMATCH")
	if String(target_authority.status_for_tests().get("authority_id", "")) != String(request.get("target_authority_id", "")):
		return _failure("SM0_P9_TRANSFER_TARGET_ROUTE_MISMATCH")
	var source_prepare: Dictionary = source_authority.prepare_send(request)
	if not bool(source_prepare.get("success", false)):
		return source_prepare
	var target_prepare: Dictionary = target_authority.prepare_receive(request)
	if not bool(target_prepare.get("success", false)):
		source_authority.cancel_send(request)
		_failure_ledger[operation_id] = {"request_checksum": request_checksum, "error_code": String(target_prepare.get("error_code", "SM0_P9_TRANSFER_TARGET_PREPARE_FAILED"))}
		return target_prepare
	var source_commit: Dictionary = source_authority.commit_send(request)
	if not bool(source_commit.get("success", false)):
		target_authority.abort_receive(request)
		source_authority.cancel_send(request)
		_failure_ledger[operation_id] = {"request_checksum": request_checksum, "error_code": String(source_commit.get("error_code", "SM0_P9_TRANSFER_SOURCE_COMMIT_FAILED"))}
		return source_commit
	var proof := Dictionary(Dictionary(source_commit.get("details", {})).get("retirement_proof", {}))
	var target_commit: Dictionary = target_authority.commit_receive(request, proof)
	if not bool(target_commit.get("success", false)):
		var rollback: Dictionary = source_authority.rollback_send(request)
		var abort: Dictionary = target_authority.abort_receive(request)
		if not bool(rollback.get("success", false)) or not bool(abort.get("success", false)):
			return _failure("SM0_P9_TRANSFER_ROLLBACK_FAILED", {"target_error": String(target_commit.get("error_code", "")), "rollback": rollback, "abort": abort})
		var target_error := String(target_commit.get("error_code", "SM0_P9_TRANSFER_TARGET_COMMIT_FAILED"))
		_failure_ledger[operation_id] = {"request_checksum": request_checksum, "error_code": target_error}
		_event("SM0_P9_TRANSFER_ROLLED_BACK", {"operation_id": operation_id, "item_id": String(request.get("item_id", "")), "target_error": target_error})
		return target_commit
	var item := Dictionary(Dictionary(target_commit.get("details", {})).get("item", {})).duplicate(true)
	_operation_ledger[operation_id] = {"request_checksum": request_checksum, "item": item.duplicate(true)}
	_event("SM0_P9_BOUNDARY_TRANSFER_COMMITTED", {
		"operation_id": operation_id,
		"item_id": String(request.get("item_id", "")),
		"source_authority_id": String(request.get("source_authority_id", "")),
		"target_authority_id": String(request.get("target_authority_id", "")),
		"source_scope": String(request.get("source_scope", "")),
		"target_scope": String(request.get("target_scope", "")),
		"ownership_epoch": int(item.get("ownership_epoch", 0)),
		"item_revision": int(item.get("item_revision", 0)),
	})
	return _success({"replay": false, "item": item})

func create_export_request(operation_id: String, ship_item: Dictionary) -> Dictionary:
	return Contract.create_transfer_request(operation_id, ship_item, _current_outer_authority_id, Contract.SCOPE_WORLD)

func current_outer_authority_id() -> String:
	return _current_outer_authority_id

func outer_authority_epoch() -> int:
	return _outer_authority_epoch

func status_for_tests() -> Dictionary:
	return {"current_outer_authority_id": _current_outer_authority_id, "outer_authority_epoch": _outer_authority_epoch, "operation_ledger_count": _operation_ledger.size(), "failure_ledger_count": _failure_ledger.size(), "event_count": _event_history.size(), "events": _event_history.duplicate(true)}

func _event(event_name: String, details: Dictionary = {}) -> void:
	var event := {"schema": "distributed_world_simulator.sm0_event.v1", "event": event_name, "severity": "INFO", "process_role": "p9-boundary-coordinator", "process_id": OS.get_process_id(), "time_msec": Time.get_ticks_msec(), "authority_id": "coordinator/sm0/p9", "writer_count": 0, "authority_scope": "boundary/world-ship"}
	for key in details.keys():
		event[key] = details[key]
	_event_history.append(event.duplicate(true))
	print("[SM0_EVENT] %s" % JSON.stringify(event, "", false, true))

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}