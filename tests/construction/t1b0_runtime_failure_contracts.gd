extends SceneTree

const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const FailurePolicyScript = preload("res://scripts/construction/behavior/construction_runtime_failure_policy.gd")

const CONSTRUCT_ID: String = "construct/t1b/failure/d0"
const DOOR_ID: String = "runtime/t1b/failure/door"
const LAMP_ID: String = "runtime/t1b/failure/lamp"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_failure_projection_and_recovery()
	_finish()


func _test_failure_projection_and_recovery() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "store setup")

	var door: Dictionary = SubjectScript.create(
		DOOR_ID,
		CONSTRUCT_ID,
		"item/t1b/failure/door",
		"capability/t1b/failure/door",
		0,
		{"kind": "DOOR", "position": "CLOSED"}
	)
	var lamp: Dictionary = SubjectScript.create(
		LAMP_ID,
		CONSTRUCT_ID,
		"item/t1b/failure/lamp",
		"capability/t1b/failure/lamp",
		0,
		{"kind": "LAMP", "on": false}
	)
	_assert_ok(store.register_subject(door), "register door")
	_assert_ok(store.register_subject(lamp), "register lamp")

	var door_requirements: Dictionary = {"power": "REQUIRED", "data": "REQUIRED", "dependency": "NONE"}
	var lamp_requirements: Dictionary = {"power": "REQUIRED", "data": "OPTIONAL", "dependency": "NONE"}
	var all_available: Dictionary = {"power": true, "data": true, "dependency": true}

	var online_a: Dictionary = FailurePolicyScript.project(store.get_subject(DOOR_ID), door_requirements, all_available)
	var online_b: Dictionary = FailurePolicyScript.project(store.get_subject(DOOR_ID), door_requirements, all_available)
	_assert_ok(online_a, "door online projection")
	_assert(online_a == online_b, "failure projection is not deterministic")
	_assert(String(online_a.get("operability", "")) == "ONLINE", "door should project ONLINE")
	_assert(Array(online_a.get("failure_codes", [])) == [], "online door has failure codes")
	_assert(not bool(online_a.get("mutates_construct_snapshot", true)), "failure policy claims ConstructSnapshot mutation")
	_assert(not bool(online_a.get("requires_new_aggregate", true)), "failure policy claims new aggregate")
	_assert_ok(store.update_subject(DOOR_ID, int(online_a.get("expected_revision", -1)), Dictionary(online_a.get("next_state", {}))), "commit online door state")

	var power_lost: Dictionary = FailurePolicyScript.project(
		store.get_subject(DOOR_ID),
		door_requirements,
		{"power": false, "data": true, "dependency": true}
	)
	_assert_ok(power_lost, "door power loss projection")
	_assert(String(power_lost.get("operability", "")) == "OFFLINE", "required power loss must be OFFLINE")
	_assert(Array(power_lost.get("failure_codes", [])) == ["POWER_UNAVAILABLE"], "door power failure code mismatch")
	_assert_ok(store.update_subject(DOOR_ID, int(power_lost.get("expected_revision", -1)), Dictionary(power_lost.get("next_state", {}))), "commit power loss")
	var offline_door: Dictionary = store.get_subject(DOOR_ID)
	_assert(int(offline_door.get("revision", -1)) == 2, "door failure revision did not advance")
	_assert(String(Dictionary(offline_door.get("state", {})).get("position", "")) == "CLOSED", "failure projection changed door gameplay state")
	_assert(String(Dictionary(offline_door.get("state", {})).get("operability", "")) == "OFFLINE", "door failure not stored")

	var stale_commit: Dictionary = store.update_subject(DOOR_ID, 1, Dictionary(power_lost.get("next_state", {})))
	_assert(not bool(stale_commit.get("success", false)), "stale failure commit unexpectedly succeeded")
	_assert(String(stale_commit.get("error_code", "")) == "CONSTRUCTION_RUNTIME_REVISION_MISMATCH", "stale failure commit error mismatch")

	var recovered: Dictionary = FailurePolicyScript.project(store.get_subject(DOOR_ID), door_requirements, all_available)
	_assert_ok(recovered, "door recovery projection")
	_assert(String(recovered.get("operability", "")) == "ONLINE", "door did not recover ONLINE")
	_assert(Array(recovered.get("failure_codes", [])) == [], "door recovery retained failure codes")
	_assert_ok(store.update_subject(DOOR_ID, int(recovered.get("expected_revision", -1)), Dictionary(recovered.get("next_state", {}))), "commit door recovery")
	var recovered_door: Dictionary = store.get_subject(DOOR_ID)
	_assert(int(recovered_door.get("revision", -1)) == 3, "door recovery revision mismatch")
	_assert(String(Dictionary(recovered_door.get("state", {})).get("position", "")) == "CLOSED", "recovery changed door gameplay state")

	var degraded: Dictionary = FailurePolicyScript.project(
		store.get_subject(LAMP_ID),
		lamp_requirements,
		{"power": true, "data": false, "dependency": true}
	)
	_assert_ok(degraded, "lamp optional data failure projection")
	_assert(String(degraded.get("operability", "")) == "DEGRADED", "optional data loss must be DEGRADED")
	_assert(Array(degraded.get("failure_codes", [])) == ["DATA_UNAVAILABLE"], "degraded failure code mismatch")
	_assert_ok(store.update_subject(LAMP_ID, int(degraded.get("expected_revision", -1)), Dictionary(degraded.get("next_state", {}))), "commit degraded lamp")

	var multi_failure: Dictionary = FailurePolicyScript.project(
		store.get_subject(LAMP_ID),
		{"power": "REQUIRED", "data": "OPTIONAL", "dependency": "REQUIRED"},
		{"power": false, "data": false, "dependency": false}
	)
	_assert_ok(multi_failure, "multi dependency failure projection")
	_assert(String(multi_failure.get("operability", "")) == "OFFLINE", "required multi failure must be OFFLINE")
	_assert(Array(multi_failure.get("failure_codes", [])) == ["DEPENDENCY_UNAVAILABLE", "POWER_UNAVAILABLE", "DATA_UNAVAILABLE"], "failure codes are not deterministic required-first sorted groups")

	var persisted: Dictionary = store.to_dict()
	_assert_ok(StoreScript.validate_state(persisted), "failure-bearing runtime store validates")
	var restored = StoreScript.new()
	_assert_ok(restored.setup(), "restored store setup")
	_assert_ok(restored.load_dict(persisted), "failure-bearing runtime store restores")
	_assert(restored.to_dict() == persisted, "runtime failure state changed across store recovery roundtrip")
	_assert(String(Dictionary(restored.get_subject(LAMP_ID).get("state", {})).get("operability", "")) == "DEGRADED", "restored degraded state missing")

	var invalid_requirements: Dictionary = FailurePolicyScript.project(restored.get_subject(DOOR_ID), {"power": "REQUIRED"}, all_available)
	_assert(not bool(invalid_requirements.get("success", false)), "partial requirements unexpectedly accepted")
	var invalid_availability: Dictionary = FailurePolicyScript.project(restored.get_subject(DOOR_ID), door_requirements, {"power": true, "data": 1, "dependency": true})
	_assert(not bool(invalid_availability.get("success", false)), "non-boolean availability unexpectedly accepted")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1B.0 runtime failure contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("T1B.0 runtime failure contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
