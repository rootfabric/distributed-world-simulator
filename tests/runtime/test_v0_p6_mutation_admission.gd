extends SceneTree

## P6.4 L0: mutation admission boundary — five gates, crash window,
## forbidden writes, replay short-circuit.

const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.4-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _init() -> void:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(256)

	registry.bind("client-session/p64-a", "player/worker", "entity/worker-1")
	registry.bind("client-session/p64-b", "player/second", "entity/second-1")

	var admission = AdmissionScript.new()
	var configured: Dictionary = admission.configure(registry, ledger)
	_assert(bool(configured.get("success", false)), "admission configure failed")

	# Gate 1: unknown player rejected before anything else
	var unknown: Dictionary = admission.admit("player/nobody", "operation/u1", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(_err(unknown) == "UNKNOWN_PLAYER", "unknown player not rejected first")

	# Gate 2: replay short-circuit
	ledger.record_applied("player/worker", "operation/replayed")
	var replay: Dictionary = admission.admit("player/worker", "operation/replayed", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(_err(replay) == "ALREADY_APPLIED", "replay did not short-circuit")

	# Gate 3: undeclared domain rejected
	var undeclared: Dictionary = admission.admit("player/worker", "operation/u2", "p6-domain/not-declared", {"command_kind": "BUILD"})
	_assert(_err(undeclared) == "UNDECLARED_DOMAIN", "undeclared domain not rejected")

	# Gate 4: forbidden write rejected
	var forbidden: Dictionary = admission.admit("player/worker", "operation/f1", "p6-domain/outpost-world-state", {"command_kind": "DIRECT_CANONICAL_OVERWRITE"})
	_assert(_err(forbidden) == "FORBIDDEN_WRITE", "forbidden write admitted")
	_assert(not ledger.is_pending("player/worker", "operation/f1"), "forbidden write left a pending intent")

	# Happy path: admit → handler executes once → complete applies exactly once
	var ok: Dictionary = admission.admit("player/worker", "operation/ok-1", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(bool(ok.get("success", false)) and _err(ok) == "" and String(ok["details"]["operation_id"]) == "operation/ok-1", "happy path admission failed")
	_assert(ledger.is_pending("player/worker", "operation/ok-1"), "crash-window pending intent missing after admission")
	var completion: Dictionary = admission.complete("player/worker", "operation/ok-1")
	_assert(String(completion["details"]["result"]) == "APPLIED", "completion did not apply")
	var repeat_admission: Dictionary = admission.admit("player/worker", "operation/ok-1", "p6-domain/outpost-world-state", {"command_kind": "BUILD"})
	_assert(_err(repeat_admission) == "ALREADY_APPLIED", "replay after completion not short-circuited at the boundary")

	# Crash window: admit → (no completion) → recovery completes exactly once
	var crash: Dictionary = admission.admit("player/worker", "operation/crash-1", "p6-domain/item-inventory", {"command_kind": "BUILD"})
	_assert(bool(crash.get("success", false)), "crash-window admission failed")
	var recovered: Dictionary = admission.complete("player/worker", "operation/crash-1")
	_assert(String(recovered["details"]["result"]) == "APPLIED", "crash-window recovery failed")

	# Counters coherence
	var report: Dictionary = admission.get_report()
	var counters: Dictionary = report["counters"]
	_assert(int(counters["admitted"]) >= 2, "admitted counter wrong")
	_assert(int(counters["forbidden_writes"]) >= 1, "forbidden_writes counter wrong")
	_assert(String(report["forbidden_commands"][0]) == "DIRECT_CANONICAL_OVERWRITE", "forbidden list exposed for fail-closed checks")

	if failures.is_empty():
		print("[p6.4-l0] all %d assertions passed" % assertions)
		print("[p6.4-l0][stage] MUTATION_ADMISSION_BOUNDARY_PASS")
		quit(0)
	else:
		print("[p6.4-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
