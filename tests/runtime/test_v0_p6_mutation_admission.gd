extends SceneTree

## P6 R3 regression: admission is fail-closed across the crash window.

const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-admission][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _init() -> void:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(8)
	registry.bind("client-session/p6-r3-a", "player/worker", "entity/worker-1")

	var admission = AdmissionScript.new()
	_assert(bool(admission.configure(registry, ledger).get("success", false)), "admission configure failed")

	var unknown: Dictionary = admission.admit("player/nobody", "operation/u1", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(_err(unknown) == "UNKNOWN_PLAYER", "unknown player not rejected")

	ledger.record_applied("player/worker", "operation/replayed")
	var replay: Dictionary = admission.admit("player/worker", "operation/replayed", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(_err(replay) == "ALREADY_APPLIED", "applied replay did not short-circuit")

	var forbidden: Dictionary = admission.admit("player/worker", "operation/f1", "p6-domain/outpost-world-state", {"command_kind": "DIRECT_CANONICAL_OVERWRITE"})
	_assert(_err(forbidden) == "FORBIDDEN_WRITE", "forbidden write admitted")
	_assert(not ledger.is_pending("player/worker", "operation/f1"), "forbidden write reserved an operation")

	# First admission reserves PENDING.
	var first: Dictionary = admission.admit("player/worker", "operation/crash-window", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(bool(first.get("success", false)), "first crash-window admission failed")
	_assert(ledger.is_pending("player/worker", "operation/crash-window"), "pending reservation missing")

	# Critical R3 regression: the same operation must not be admitted while it is
	# still PENDING. This is the path that previously invoked the handler twice.
	var retry_pending: Dictionary = admission.admit("player/worker", "operation/crash-window", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(not bool(retry_pending.get("success", false)), "PENDING retry was re-admitted")
	_assert(_err(retry_pending) == "OPERATION_PENDING", "PENDING retry error mismatch")
	_assert(int(admission.get_report()["counters"]["pending_rejections"]) == 1, "pending rejection counter mismatch")

	# Explicit reconciliation completes it once; later calls are replays.
	var completion: Dictionary = admission.complete("player/worker", "operation/crash-window")
	_assert(String(completion.get("details", {}).get("result", "")) == "APPLIED", "explicit completion failed")
	var after: Dictionary = admission.admit("player/worker", "operation/crash-window", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(_err(after) == "ALREADY_APPLIED", "completed operation did not become replay")

	# Read-only digest lookup must not accidentally create an APPLIED record.
	var before_count := int(ledger.get_report()["applied_count"])
	var unknown_digest := admission.applied_digest("player/worker", "operation/never-recorded")
	_assert(unknown_digest.is_empty(), "unknown digest unexpectedly exists")
	_assert(int(ledger.get_report()["applied_count"]) == before_count, "digest lookup mutated replay state")

	if failures.is_empty():
		print("[p6-r3-admission] all %d assertions passed" % assertions)
		print("[p6-r3-admission][stage] PENDING_RETRY_FAIL_CLOSED_PASS")
		quit(0)
	else:
		print("[p6-r3-admission] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
