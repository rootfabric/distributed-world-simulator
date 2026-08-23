extends SceneTree

## P6.3 L0: per-player operation ledger — exactly-once, crash recovery,
## cross-transport continuity (identity rebind), bounded history.

const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.3-l0][FAIL] %s" % message)


func _init() -> void:
	var ledger = LedgerScript.new()
	var configured: Dictionary = ledger.configure(256)
	_assert(bool(configured.get("success", false)), "ledger configure failed")

	# --- exactly-once happy path ---
	var first: Dictionary = ledger.record_applied("player/a", "operation/p6.3-0001")
	_assert(bool(first.get("success", false)) and String(first["details"]["result"]) == "APPLIED", "first apply failed")
	var digest: String = String(first["details"]["outcome_digest"])
	_assert(not digest.is_empty(), "digest empty on apply")
	var replay: Dictionary = ledger.record_applied("player/a", "operation/p6.3-0001")
	_assert(String(replay["details"]["result"]) == "ALREADY_APPLIED", "replay did not report ALREADY_APPLIED")
	_assert(String(replay["details"]["outcome_digest"]) == digest, "replay digest diverged")
	_assert(bool(replay["details"].get("applied_now", true)) == false, "replay claimed applied_now")

	# --- pending -> crash -> restore -> complete exactly once ---
	ledger.record_pending("player/b", "operation/p6.3-crash")
	_assert(ledger.is_pending("player/b", "operation/p6.3-crash"), "pending not recorded")
	var snap: Dictionary = ledger.snapshot()
	var fresh = LedgerScript.new()
	fresh.configure(256)
	var restored: Dictionary = fresh.restore(snap)
	_assert(bool(restored.get("success", false)), "restore failed")
	_assert(fresh.is_pending("player/b", "operation/p6.3-crash"), "pending lost across crash")
	var completed: Dictionary = fresh.complete_pending("player/b", "operation/p6.3-crash")
	_assert(String(completed["details"]["result"]) == "APPLIED", "crash recovery did not complete")
	var repeat: Dictionary = fresh.complete_pending("player/b", "operation/p6.3-crash")
	_assert(String(repeat["details"]["result"]) == "ALREADY_APPLIED", "double recovery applied twice")

	# --- unknown key rejected ---
	var unknown: Dictionary = fresh.complete_pending("player/b", "operation/p6.3-unknown")
	_assert(not bool(unknown.get("success", false)) and String(unknown["error_code"]) == "NO_PENDING_OPERATION", "unknown completion accepted")

	# --- cross-transport continuity via identity rebind (P6.2 integration) ---
	var registry = RegistryScript.new()
	registry.bind("client-session/pre-rebind", "player/traveler", "entity/traveler-1")
	registry.rebind_on_transport_change("client-session/pre-rebind", "client-session/post-rebind")
	var binding: Dictionary = registry.resolve_by_session("client-session/post-rebind")["details"]["binding"]
	var traveler: String = String(binding["logical_player_id"])
	_assert(traveler == "player/traveler", "traveler identity mismatch after rebind")
	var t_first: Dictionary = ledger.record_applied(traveler, "operation/p6.3-travel-1")
	_assert(String(t_first["details"]["result"]) == "APPLIED", "traveler op apply failed")
	var t_replay: Dictionary = ledger.record_applied(traveler, "operation/p6.3-travel-1")
	_assert(String(t_replay["details"]["result"]) == "ALREADY_APPLIED", "traveler replay broke continuity")

	# --- bounded history retires oldest but keeps recent ---
	var small = LedgerScript.new()
	small.configure(4)
	for i in range(8):
		small.record_applied("player/rotator", "operation/p6.3-rot-%04d" % i)
	_assert(bool(small.is_applied("player/rotator", "operation/p6.3-rot-0007")), "most recent retired unexpectedly")
	_assert(int(small.get_report()["applied_count"]) <= 4, "bounded cap exceeded")

	# --- schema gate on restore ---
	var bad_restore: Dictionary = fresh.restore({"schema": "wrong"})
	_assert(not bool(bad_restore.get("success", false)), "wrong-schema restore accepted")

	if failures.is_empty():
		print("[p6.3-l0] all %d assertions passed" % assertions)
		print("[p6.3-l0][stage] OPERATION_CONTINUITY_PASS")
		quit(0)
	else:
		print("[p6.3-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
