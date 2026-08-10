extends SceneTree

const BindingScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_interest_binding.gd")

const D0: String = "construct/t1/lunar-outpost/d0"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_revision_and_reconnect_contract()
	_finish()


func _test_revision_and_reconnect_contract() -> void:
	var binding = BindingScript.new()
	_assert_ok(binding.configure(3), "interest binding configure")
	var first_bind: Dictionary = binding.bind_session(
		"peer/t1a7/client/1", "session/t1a7/client/1", "client/t1a7/client"
	)
	_assert_ok(first_bind, "initial session bind")
	_assert(not bool(first_bind.get("details", {}).get("reconnect", true)), "initial bind incorrectly classified as reconnect")
	_assert(not binding.is_selected("peer/t1a7/client/1", "session/t1a7/client/1", D0), "fresh client unexpectedly selected D0")

	var rev1: Dictionary = binding.update_selection(
		"client/t1a7/client", 1, [D0, D0]
	)
	_assert_ok(rev1, "interest revision 1")
	_assert(binding.is_selected("peer/t1a7/client/1", "session/t1a7/client/1", D0), "revision 1 did not select D0")
	var rev1_state: Dictionary = binding.client_state("client/t1a7/client")
	_assert(Array(rev1_state.get("selected_construct_ids", [])).size() == 1, "selection normalization did not deduplicate construct ids")

	var replay: Dictionary = binding.update_selection("client/t1a7/client", 1, [D0])
	_assert_ok(replay, "same revision replay")
	_assert(bool(replay.get("details", {}).get("replay", false)), "same revision same selection was not replay")
	var conflict: Dictionary = binding.update_selection(
		"client/t1a7/client", 1, ["construct/t1/other"]
	)
	_assert_error(conflict, "SAME_REVISION_CONSTRUCTION_RUNTIME_INTEREST_CONFLICT", "same revision different selection accepted")

	var rev2: Dictionary = binding.update_selection("client/t1a7/client", 2, [])
	_assert_ok(rev2, "interest revision 2 leave")
	_assert(not binding.is_selected("peer/t1a7/client/1", "session/t1a7/client/1", D0), "revision 2 did not leave D0")
	var stale: Dictionary = binding.update_selection("client/t1a7/client", 1, [D0])
	_assert_error(stale, "STALE_CONSTRUCTION_RUNTIME_INTEREST_REVISION", "stale interest revision accepted")

	var wrong_disconnect: Dictionary = binding.disconnect_session(
		"peer/t1a7/client/1", "session/t1a7/client/stale"
	)
	_assert_error(wrong_disconnect, "STALE_CONSTRUCTION_RUNTIME_INTEREST_SESSION", "stale disconnect session accepted")
	_assert(binding.active_peer_id("client/t1a7/client") == "peer/t1a7/client/1", "stale disconnect removed active peer")
	_assert_ok(binding.disconnect_session("peer/t1a7/client/1", "session/t1a7/client/1"), "current disconnect")
	_assert(binding.active_peer_id("client/t1a7/client").is_empty(), "disconnect retained active transport peer")
	_assert(int(binding.client_state("client/t1a7/client").get("interest_revision", 0)) == 2, "disconnect lost logical interest state")

	var reconnect: Dictionary = binding.bind_session(
		"peer/t1a7/client/2", "session/t1a7/client/2", "client/t1a7/client"
	)
	_assert_ok(reconnect, "reconnect session bind")
	_assert(bool(reconnect.get("details", {}).get("reconnect", false)), "retained client state did not classify reconnect")
	_assert(not binding.is_selected("peer/t1a7/client/1", "session/t1a7/client/1", D0), "old transport session remained selected")
	_assert(not binding.is_selected("peer/t1a7/client/2", "session/t1a7/client/2", D0), "reconnect changed retained out-of-interest state")

	var rev3: Dictionary = binding.update_selection("client/t1a7/client", 3, [D0])
	_assert_ok(rev3, "interest revision 3 re-enter")
	_assert(binding.is_selected("peer/t1a7/client/2", "session/t1a7/client/2", D0), "re-enter did not select D0 on new session")
	_assert(not binding.is_selected("peer/t1a7/client/2", "session/t1a7/client/1", D0), "old session id bypassed selection fence")

	var before_rev4: Dictionary = binding.client_state("client/t1a7/client")
	var rev4: Dictionary = binding.update_selection("client/t1a7/client", 4, [])
	_assert_ok(rev4, "interest revision 4")
	_assert_ok(binding.restore_client_state("client/t1a7/client", before_rev4), "selection rollback")
	_assert(binding.is_selected("peer/t1a7/client/2", "session/t1a7/client/2", D0), "selection rollback did not restore D0")

	var report: Dictionary = binding.report()
	_assert(int(report.get("selection_updates", 0)) >= 4, "interest update telemetry missing")
	_assert(int(report.get("selection_replays", 0)) == 1, "interest replay telemetry changed")
	_assert(int(report.get("selection_conflicts", 0)) == 1, "interest conflict telemetry changed")
	_assert(int(report.get("stale_revisions", 0)) == 1, "stale revision telemetry changed")
	_assert(int(report.get("reconnect_binds", 0)) == 1, "reconnect telemetry changed")
	_assert(int(report.get("active_sessions", 0)) == 1, "active session telemetry changed")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code,
		"%s: %s" % [message, result]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1A.7.2 runtime interest binding: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("T1A.7.2 runtime interest binding: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
