extends SceneTree

const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")
const ReplicaScript = preload("res://scripts/runtime/host_client/construction_runtime_replica_store.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_snapshot_and_replica_semantics()
	_finish()


func _test_snapshot_and_replica_semantics() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "runtime store setup")
	var subject: Dictionary = SubjectScript.create(
		"runtime/contracts/replica/door",
		"construct/contracts/replica",
		"item/contracts-replica-door",
		"capability/contracts/replica/door",
		0,
		{"position": "CLOSED"}
	)
	_assert_ok(store.register_subject(subject), "runtime subject registration")
	var state1: Dictionary = store.to_dict()
	var snap1: Dictionary = SnapshotScript.create("construct/contracts/replica", 1, 10, state1)
	_assert_ok(SnapshotScript.validate(snap1), "snapshot1 validation")
	_assert(int(snap1.get("revision", -1)) == 1, "snapshot revision tracks runtime generation")
	_assert(String(snap1.get("state_checksum", "")) == String(state1.get("checksum", "")), "snapshot state checksum mismatch")

	var replica = ReplicaScript.new()
	var first: Dictionary = replica.accept_snapshot(snap1)
	_assert_ok(first, "initial snapshot rejected")
	var first_details: Dictionary = Dictionary(first.get("details", {}))
	_assert(bool(first_details.get("accepted", false)), "initial snapshot not accepted")
	_assert(String(first_details.get("reset_reason", "")) == "INITIAL", "initial reset reason mismatch")

	var replay: Dictionary = replica.accept_snapshot(snap1)
	_assert_ok(replay, "exact replay rejected")
	var replay_details: Dictionary = Dictionary(replay.get("details", {}))
	_assert(bool(replay_details.get("replay", false)), "exact replay not classified")

	var clock_only: Dictionary = SnapshotScript.create("construct/contracts/replica", 1, 11, state1)
	var clock_result: Dictionary = replica.accept_snapshot(clock_only)
	_assert_ok(clock_result, "clock-only update rejected")
	var clock_details: Dictionary = Dictionary(clock_result.get("details", {}))
	_assert(bool(clock_details.get("clock_only", false)), "clock-only update not classified")
	_assert(int(replica.get_snapshot().get("server_tick", -1)) == 11, "clock-only server tick not adopted")

	var stale_clock: Dictionary = SnapshotScript.create("construct/contracts/replica", 1, 9, state1)
	var stale_result: Dictionary = replica.accept_snapshot(stale_clock)
	_assert_ok(stale_result, "stale clock should be harmless")
	var stale_details: Dictionary = Dictionary(stale_result.get("details", {}))
	_assert(bool(stale_details.get("stale", false)), "stale clock not classified")

	_assert_ok(store.update_subject("runtime/contracts/replica/door", 0, {"position": "OPEN"}), "runtime subject update")
	var state2: Dictionary = store.to_dict()
	var snap2: Dictionary = SnapshotScript.create("construct/contracts/replica", 1, 12, state2)
	var second: Dictionary = replica.accept_snapshot(snap2)
	_assert_ok(second, "new revision rejected")
	var second_details: Dictionary = Dictionary(second.get("details", {}))
	_assert(bool(second_details.get("accepted", false)), "new revision not accepted")
	_assert(int(replica.get_snapshot().get("revision", -1)) == 2, "replica revision mismatch")
	var replica_subject: Dictionary = replica.get_subject("runtime/contracts/replica/door")
	var replica_subject_state: Dictionary = Dictionary(replica_subject.get("state", {}))
	_assert(String(replica_subject_state.get("position", "")) == "OPEN", "replica subject state mismatch")

	var conflicting_store = StoreScript.new()
	conflicting_store.setup()
	conflicting_store.register_subject(subject)
	conflicting_store.update_subject("runtime/contracts/replica/door", 0, {"position": "JAMMED"})
	var conflicting: Dictionary = SnapshotScript.create("construct/contracts/replica", 1, 13, conflicting_store.to_dict())
	var conflict_result: Dictionary = replica.accept_snapshot(conflicting)
	_assert_error(conflict_result, "CONSTRUCTION_RUNTIME_SAME_REVISION_MUTATION", "same-revision mutation accepted")

	var authority_reset: Dictionary = SnapshotScript.create("construct/contracts/replica", 2, 1, state1)
	var reset_result: Dictionary = replica.accept_snapshot(authority_reset)
	_assert_ok(reset_result, "authority reset rejected")
	var reset_details: Dictionary = Dictionary(reset_result.get("details", {}))
	_assert(String(reset_details.get("reset_reason", "")) == "AUTHORITY_CHANGED", "authority reset reason mismatch")
	_assert(int(replica.get_snapshot().get("authority_epoch", 0)) == 2, "authority epoch not adopted")

	var report: Dictionary = replica.get_report()
	_assert(int(report.get("replays", 0)) == 1, "replica replay counter mismatch")
	_assert(int(report.get("stale", 0)) >= 1, "replica stale counter mismatch")
	_assert(int(report.get("clock_only", 0)) == 1, "replica clock-only counter mismatch")
	_assert(int(report.get("conflicts", 0)) == 1, "replica conflict counter mismatch")
	_assert(int(report.get("authority_resets", 0)) == 1, "replica authority reset counter mismatch")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("C5C runtime replication contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C5C runtime replication contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
