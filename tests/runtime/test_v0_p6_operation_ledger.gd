extends SceneTree

## P6 R3 regression: OperationId history is fail-closed.
## A bounded guard may reject new work at capacity, but it may never evict an
## old key and later report it as newly APPLIED.

const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-ledger][FAIL] %s" % message)


func _init() -> void:
	var ledger = LedgerScript.new()
	var configured: Dictionary = ledger.configure(4)
	_assert(bool(configured.get("success", false)), "ledger configure failed")
	_assert(String(configured.get("details", {}).get("retirement_policy", "")) == "FAIL_CLOSED_NO_EVICTION", "retirement policy is not fail-closed")

	# Fill the complete bounded history.
	for i in range(4):
		var operation_id := "operation/p6-r3-%04d" % i
		var applied: Dictionary = ledger.record_applied("player/a", operation_id)
		_assert(bool(applied.get("success", false)) and String(applied["details"]["result"]) == "APPLIED", "initial apply failed for %s" % operation_id)

	# New work fails closed; no old key is forgotten to make room.
	var overflow: Dictionary = ledger.record_applied("player/a", "operation/p6-r3-overflow")
	_assert(not bool(overflow.get("success", false)), "capacity overflow was accepted")
	_assert(String(overflow.get("error_code", "")) == "LEDGER_CAPACITY_EXCEEDED", "capacity overflow error mismatch")
	_assert(int(ledger.get_report()["applied_count"]) == 4, "capacity rejection changed applied set")
	_assert(int(ledger.get_report()["counters"]["retired"]) == 0, "an OperationId was retired")

	# The oldest operation remains a replay, never a fresh application.
	var oldest_replay: Dictionary = ledger.record_applied("player/a", "operation/p6-r3-0000")
	_assert(bool(oldest_replay.get("success", false)), "oldest replay failed")
	_assert(String(oldest_replay["details"]["result"]) == "ALREADY_APPLIED", "oldest OperationId became executable again")
	_assert(bool(oldest_replay["details"]["applied_now"]) == false, "oldest replay reported applied_now")

	# PENDING is idempotent as a reservation, not a second admission.
	var pending_ledger = LedgerScript.new()
	pending_ledger.configure(4)
	var pending1: Dictionary = pending_ledger.record_pending("player/b", "operation/pending")
	var pending2: Dictionary = pending_ledger.record_pending("player/b", "operation/pending")
	_assert(bool(pending1.get("success", false)) and not bool(pending1["details"].get("existing", true)), "first pending reservation failed")
	_assert(bool(pending2.get("success", false)) and bool(pending2["details"].get("existing", false)), "repeated pending did not report existing reservation")
	_assert(int(pending_ledger.get_report()["pending_count"]) == 1, "repeated pending duplicated reservation")

	# Snapshot restore preserves the no-forget property and validates ordering.
	var restored = LedgerScript.new()
	restored.configure(4)
	var restore_result: Dictionary = restored.restore(ledger.snapshot())
	_assert(bool(restore_result.get("success", false)), "snapshot restore failed")
	var restored_replay: Dictionary = restored.record_applied("player/a", "operation/p6-r3-0000")
	_assert(String(restored_replay.get("details", {}).get("result", "")) == "ALREADY_APPLIED", "restore forgot oldest OperationId")

	if failures.is_empty():
		print("[p6-r3-ledger] all %d assertions passed" % assertions)
		print("[p6-r3-ledger][stage] OPERATION_ID_RETIREMENT_CANNOT_REEXECUTE_PASS")
		quit(0)
	else:
		print("[p6-r3-ledger] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
