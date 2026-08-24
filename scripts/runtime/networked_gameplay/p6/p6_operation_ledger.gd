extends RefCounted

## P6 operation guard.
##
## This class is deliberately fail-closed. It is NOT a persistence owner and
## MUST NOT forget an OperationId in a way that permits re-execution.
## `_history_cap` is therefore a capacity bound, not an eviction/LRU bound:
## once capacity is reached, a NEW operation is rejected until the caller
## rotates to a canonical durable replay owner with an explicit retirement
## protocol. Existing APPLIED/PENDING operations remain queryable forever for
## the lifetime/snapshot of this guard.
##
## PENDING is an in-flight reservation. Re-recording a PENDING key never
## creates a second reservation and admission code must treat it as blocked.

const SCHEMA := "planet_simulator.p6_operation_ledger.v1"
const DEFAULT_HISTORY_CAP: int = 256

var _applied: Dictionary = {}
var _pending: Dictionary = {}
var _order: Array = []
var _history_cap: int = DEFAULT_HISTORY_CAP
var _counters := {
	"records": 0,
	"applied": 0,
	"already_applied": 0,
	"pendings": 0,
	"pending_replays": 0,
	"recovered": 0,
	"retired": 0,
	"capacity_rejections": 0,
}


func configure(history_cap: int = DEFAULT_HISTORY_CAP) -> Dictionary:
	if history_cap < 1:
		return {"success": false, "error_code": "INVALID_HISTORY_CAP", "details": {}}
	_history_cap = int(history_cap)
	if _tracked_count() > _history_cap:
		return {"success": false, "error_code": "LEDGER_CAPACITY_BELOW_TRACKED_COUNT", "details": {"tracked": _tracked_count()}}
	return {"success": true, "details": {"history_cap": _history_cap, "retirement_policy": "FAIL_CLOSED_NO_EVICTION"}}


static func key(logical_player_id: String, operation_id: String) -> String:
	return logical_player_id + "|" + operation_id


func _digest(logical_player_id: String, operation_id: String, outcome: String) -> String:
	var payload := {
		"logical_player_id": logical_player_id,
		"operation_id": operation_id,
		"outcome": outcome,
	}
	return str(hash(JSON.stringify(payload, "", false)))


func record_applied(logical_player_id: String, operation_id: String) -> Dictionary:
	_counters["records"] = int(_counters["records"]) + 1
	var k := key(logical_player_id, operation_id)
	if _applied.has(k):
		_counters["already_applied"] = int(_counters["already_applied"]) + 1
		return {"success": true, "details": {"result": "ALREADY_APPLIED", "outcome_digest": String(_applied[k]), "applied_now": false}}
	# Completing an existing PENDING reservation does not consume another slot.
	if not _pending.has(k) and not _has_capacity_for_new_key():
		return _capacity_reject(k)
	_pending.erase(k)
	var digest := _digest(logical_player_id, operation_id, "APPLIED")
	_applied[k] = digest
	_touch_order(k)
	_counters["applied"] = int(_counters["applied"]) + 1
	return {"success": true, "details": {"result": "APPLIED", "outcome_digest": digest, "applied_now": true}}


func record_pending(logical_player_id: String, operation_id: String) -> Dictionary:
	_counters["records"] = int(_counters["records"]) + 1
	var k := key(logical_player_id, operation_id)
	if _applied.has(k):
		_counters["already_applied"] = int(_counters["already_applied"]) + 1
		return {"success": true, "details": {"result": "ALREADY_APPLIED", "outcome_digest": String(_applied[k]), "applied_now": false}}
	if _pending.has(k):
		_counters["pending_replays"] = int(_counters["pending_replays"]) + 1
		return {"success": true, "details": {"result": "PENDING", "pending_digest": String(_pending[k]), "existing": true}}
	if not _has_capacity_for_new_key():
		return _capacity_reject(k)
	_pending[k] = _digest(logical_player_id, operation_id, "PENDING")
	_touch_order(k)
	_counters["pendings"] = int(_counters["pendings"]) + 1
	return {"success": true, "details": {"result": "PENDING", "pending_digest": String(_pending[k]), "existing": false}}


func complete_pending(logical_player_id: String, operation_id: String) -> Dictionary:
	var k := key(logical_player_id, operation_id)
	if _applied.has(k):
		_counters["already_applied"] = int(_counters["already_applied"]) + 1
		return {"success": true, "details": {"result": "ALREADY_APPLIED", "outcome_digest": String(_applied[k]), "applied_now": false}}
	if not _pending.has(k):
		return {"success": false, "error_code": "NO_PENDING_OPERATION", "details": {"key": k}}
	_counters["recovered"] = int(_counters["recovered"]) + 1
	return record_applied(logical_player_id, operation_id)


func is_applied(logical_player_id: String, operation_id: String) -> bool:
	return _applied.has(key(logical_player_id, operation_id))


func is_pending(logical_player_id: String, operation_id: String) -> bool:
	return _pending.has(key(logical_player_id, operation_id))


func get_applied_digest(logical_player_id: String, operation_id: String) -> String:
	return String(_applied.get(key(logical_player_id, operation_id), ""))


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"applied": _applied.duplicate(true),
		"pending": _pending.duplicate(true),
		"order": _order.duplicate(true),
	}


func restore(snap: Dictionary) -> Dictionary:
	if str(snap.get("schema", "")) != SCHEMA:
		return {"success": false, "error_code": "SCHEMA_MISMATCH", "details": {}}
	var applied_value: Variant = snap.get("applied", null)
	var pending_value: Variant = snap.get("pending", null)
	var order_value: Variant = snap.get("order", null)
	if typeof(applied_value) != TYPE_DICTIONARY or typeof(pending_value) != TYPE_DICTIONARY or typeof(order_value) != TYPE_ARRAY:
		return {"success": false, "error_code": "INVALID_LEDGER_SNAPSHOT", "details": {}}
	var staged_applied := Dictionary(applied_value).duplicate(true)
	var staged_pending := Dictionary(pending_value).duplicate(true)
	for k in staged_applied.keys():
		if staged_pending.has(k):
			return {"success": false, "error_code": "LEDGER_STATE_OVERLAP", "details": {"key": String(k)}}
	var staged_order := (order_value as Array).duplicate(true)
	var seen: Dictionary = {}
	for raw_key in staged_order:
		var k := String(raw_key)
		if seen.has(k) or (not staged_applied.has(k) and not staged_pending.has(k)):
			return {"success": false, "error_code": "INVALID_LEDGER_ORDER", "details": {"key": k}}
		seen[k] = true
	if seen.size() != staged_applied.size() + staged_pending.size():
		return {"success": false, "error_code": "INCOMPLETE_LEDGER_ORDER", "details": {}}
	if seen.size() > _history_cap:
		return {"success": false, "error_code": "LEDGER_CAPACITY_EXCEEDED", "details": {"tracked": seen.size(), "capacity": _history_cap}}
	_applied = staged_applied
	_pending = staged_pending
	_order = staged_order
	return {"success": true, "details": {"applied": _applied.size(), "pending": _pending.size()}}


func pending_keys() -> Array:
	return _pending.keys()


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"applied_count": _applied.size(),
		"pending_count": _pending.size(),
		"tracked_count": _tracked_count(),
		"history_cap": _history_cap,
		"retirement_policy": "FAIL_CLOSED_NO_EVICTION",
		"counters": _counters.duplicate(true),
	}


func _touch_order(k: String) -> void:
	if not _order.has(k):
		_order.append(k)


func _tracked_count() -> int:
	return _applied.size() + _pending.size()


func _has_capacity_for_new_key() -> bool:
	return _tracked_count() < _history_cap


func _capacity_reject(k: String) -> Dictionary:
	_counters["capacity_rejections"] = int(_counters["capacity_rejections"]) + 1
	return {
		"success": false,
		"error_code": "LEDGER_CAPACITY_EXCEEDED",
		"details": {"key": k, "tracked": _tracked_count(), "capacity": _history_cap},
	}
