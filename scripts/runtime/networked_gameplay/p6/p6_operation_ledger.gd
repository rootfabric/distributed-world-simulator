extends RefCounted

## P6.3 per-player operation ledger with exactly-once semantics and
## crash-recovery. Keys are (logical_player_id, operation_id) so operations
## FOLLOW THE PLAYER across transport changes (P6.2 rebinds) — the ledger
## never sees session ids.
##
## States per operation: APPLIED (terminal, digest recorded) or PENDING
## (crash-recovery: recorded intent without outcome; a fresh ledger restored
## from the same serialized snapshot must complete it exactly once).

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
	"recovered": 0,
	"retired": 0,
}


func configure(history_cap: int = DEFAULT_HISTORY_CAP) -> Dictionary:
	if history_cap < 1:
		return {"success": false, "error_code": "INVALID_HISTORY_CAP", "details": {}}
	_history_cap = int(history_cap)
	return {"success": true, "details": {"history_cap": _history_cap}}


static func key(logical_player_id: String, operation_id: String) -> String:
	return logical_player_id + "|" + operation_id


func _digest(logical_player_id: String, operation_id: String, outcome: String) -> String:
	var payload := {
		"logical_player_id": logical_player_id,
		"operation_id": operation_id,
		"outcome": outcome,
	}
	return str(hash(JSON.stringify(payload, "", false)))


## Record a terminal outcome. First call APPLIES; any repeat of the same
## (player, operation) replays ALREADY_APPLIED with the prior digest and
## does not touch state.
func record_applied(logical_player_id: String, operation_id: String) -> Dictionary:
	_counters["records"] = int(_counters["records"]) + 1
	var k := key(logical_player_id, operation_id)
	if _applied.has(k):
		_counters["already_applied"] = int(_counters["already_applied"]) + 1
		return {"success": true, "details": {"result": "ALREADY_APPLIED", "outcome_digest": String(_applied[k]), "applied_now": false}}
	_pending.erase(k)
	var digest := _digest(logical_player_id, operation_id, "APPLIED")
	_applied[k] = digest
	_touch_order(k)
	_counters["applied"] = int(_counters["applied"]) + 1
	_retire_overflow()
	return {"success": true, "details": {"result": "APPLIED", "outcome_digest": digest, "applied_now": true}}


## Record an intent whose outcome is not yet known (crash window).
func record_pending(logical_player_id: String, operation_id: String) -> Dictionary:
	_counters["records"] = int(_counters["records"]) + 1
	var k := key(logical_player_id, operation_id)
	if _applied.has(k):
		_counters["already_applied"] = int(_counters["already_applied"]) + 1
		return {"success": true, "details": {"result": "ALREADY_APPLIED", "outcome_digest": String(_applied[k]), "applied_now": false}}
	if not _pending.has(k):
		_pending[k] = _digest(logical_player_id, operation_id, "PENDING")
		_touch_order(k)
		_counters["pendings"] = int(_counters["pendings"]) + 1
	return {"success": true, "details": {"result": "PENDING", "pending_digest": String(_pending[k])}}


## Complete a pending operation after crash recovery. Exactly-once: completing
## an already-applied key replays; completing an unknown key is rejected.
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


## Serialize the durable snapshot (what a persistence owner would write).
func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"applied": _applied.duplicate(true),
		"pending": _pending.duplicate(true),
		"order": _order.duplicate(true),
	}


## Restore from a snapshot produced by snapshot() — the crash-recovery path.
func restore(snap: Dictionary) -> Dictionary:
	if str(snap.get("schema", "")) != SCHEMA:
		return {"success": false, "error_code": "SCHEMA_MISMATCH", "details": {}}
	_applied = Dictionary(snap.get("applied", {})).duplicate(true)
	_pending = Dictionary(snap.get("pending", {})).duplicate(true)
	_order = (snap.get("order", []) as Array).duplicate(true)
	return {"success": true, "details": {"applied": _applied.size(), "pending": _pending.size()}}


func pending_keys() -> Array:
	return _pending.keys()


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"applied_count": _applied.size(),
		"pending_count": _pending.size(),
		"counters": _counters.duplicate(true),
	}


func _touch_order(k: String) -> void:
	_order.erase(k)
	_order.append(k)
	_retire_overflow()


func _retire_overflow() -> void:
	while _order.size() > _history_cap:
		var oldest: String = String(_order.pop_front())
		_applied.erase(oldest)
		_pending.erase(oldest)
		_counters["retired"] = int(_counters["retired"]) + 1
