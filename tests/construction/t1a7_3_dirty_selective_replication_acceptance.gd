extends SceneTree

const PlannerScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_selective_replication_planner.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")

const D0: String = "construct/t1/selective/d0"
const D1: String = "construct/t1/selective/d1"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_dirty_selective_planning()
	_finish()


func _test_dirty_selective_planning() -> void:
	var planner = PlannerScript.new()
	_assert_ok(planner.configure(1), "planner configure")
	_assert_ok(planner.update_selection("client/a", [D0, D0]), "A selects D0")
	_assert_ok(planner.update_selection("client/b", [D1]), "B selects D1")
	_assert_ok(planner.update_selection("client/c", [D1, D0]), "C selects D0+D1")
	_assert_ok(planner.update_selection("client/d", []), "D selects nothing")
	_assert(Array(planner.selected_clients(D0)) == ["client/a", "client/c"], "D0 reverse selection index mismatch")
	_assert(Array(planner.selected_clients(D1)) == ["client/b", "client/c"], "D1 reverse selection index mismatch")

	var d0_pair: Dictionary = _snapshot_pair(D0, "d0")
	var d1_pair: Dictionary = _snapshot_pair(D1, "d1")
	_assert(not d0_pair.is_empty() and not d1_pair.is_empty(), "snapshot pair fixture failed")
	var routes: Dictionary = {
		"client/a": _route("client/a", "peer/a", "session/a"),
		"client/b": _route("client/b", "peer/b", "session/b"),
		"client/c": _route("client/c", "peer/c", "session/c"),
		"client/d": _route("client/d", "peer/d", "session/d"),
	}

	var d0_plan: Dictionary = planner.plan_mutation(
		Dictionary(d0_pair["before"]), Dictionary(d0_pair["after"]), routes, 4
	)
	_assert_ok(d0_plan, "D0 mutation plan")
	var d0_details: Dictionary = Dictionary(d0_plan.get("details", {}))
	_assert(Array(d0_details.get("dirty_runtime_ids", [])) == ["runtime/t1a7-3/d0/door"], "D0 dirty runtime ids mismatch")
	_assert(int(d0_details.get("target_count", -1)) == 2, "D0 target count mismatch")
	_assert(int(d0_details.get("avoided_peer_deliveries", -1)) == 2, "D0 avoided delivery count mismatch")
	_assert(_route_clients(Array(d0_details.get("target_routes", []))) == ["client/a", "client/c"], "D0 targeted clients mismatch")

	var d1_plan: Dictionary = planner.plan_mutation(
		Dictionary(d1_pair["before"]), Dictionary(d1_pair["after"]), routes, 4
	)
	_assert_ok(d1_plan, "D1 mutation plan")
	var d1_details: Dictionary = Dictionary(d1_plan.get("details", {}))
	_assert(Array(d1_details.get("dirty_runtime_ids", [])) == ["runtime/t1a7-3/d1/door"], "D1 dirty runtime ids mismatch")
	_assert(_route_clients(Array(d1_details.get("target_routes", []))) == ["client/b", "client/c"], "D1 targeted clients mismatch")

	var replay: Dictionary = planner.plan_mutation(
		Dictionary(d0_pair["after"]), Dictionary(d0_pair["after"]), routes, 4
	)
	_assert_ok(replay, "same snapshot replay")
	_assert(bool(Dictionary(replay.get("details", {})).get("replay", false)), "same snapshot was not classified replay")

	var stale: Dictionary = planner.plan_mutation(
		Dictionary(d0_pair["after"]), Dictionary(d0_pair["before"]), routes, 4
	)
	_assert_error(stale, "T1A7_3_REPLICATION_STALE_RUNTIME_REVISION", "stale runtime revision accepted")

	var same_revision_mutation: Dictionary = planner.plan_mutation(
		Dictionary(d0_pair["before"]), Dictionary(d0_pair["same_revision_conflict"]), routes, 4
	)
	_assert_error(same_revision_mutation, "T1A7_3_REPLICATION_SAME_REVISION_MUTATION", "same-revision mutation accepted")

	_assert_ok(planner.update_selection("client/a", []), "A leaves D0")
	_assert(Array(planner.selected_clients(D0)) == ["client/c"], "reverse index retained A after leave")
	_assert_ok(planner.update_selection("client/a", [D0]), "A re-enters D0")
	_assert(Array(planner.selected_clients(D0)) == ["client/a", "client/c"], "reverse index failed A re-entry")

	var report: Dictionary = planner.report()
	_assert(int(report.get("plans", 0)) == 2, "planner successful plan telemetry mismatch")
	_assert(int(report.get("plan_replays", 0)) == 1, "planner replay telemetry mismatch")
	_assert(int(report.get("dirty_runtime_ids_total", 0)) == 2, "dirty runtime telemetry mismatch")
	_assert(int(report.get("targeted_deliveries", 0)) == 4, "targeted delivery telemetry mismatch")
	_assert(int(report.get("avoided_peer_deliveries", 0)) == 4, "avoided delivery telemetry mismatch")
	_assert(int(report.get("plan_failures", 0)) == 2, "plan failure telemetry mismatch")


func _snapshot_pair(construct_id: String, suffix: String) -> Dictionary:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "%s store setup" % suffix)
	var door_id := "runtime/t1a7-3/%s/door" % suffix
	var lamp_id := "runtime/t1a7-3/%s/lamp" % suffix
	_assert_ok(store.register_subject(SubjectScript.create(
		door_id, construct_id, "item/t1a7-3/%s/door" % suffix,
		"capability/t1a7-3/%s/door" % suffix, 0,
		{"kind": "DOOR", "position": "CLOSED"}
	)), "%s door register" % suffix)
	_assert_ok(store.register_subject(SubjectScript.create(
		lamp_id, construct_id, "item/t1a7-3/%s/lamp" % suffix,
		"capability/t1a7-3/%s/lamp" % suffix, 0,
		{"kind": "LAMP", "on": false}
	)), "%s lamp register" % suffix)
	var before: Dictionary = SnapshotScript.create(construct_id, 1, 10, store.to_dict())
	_assert_ok(store.update_subject(door_id, 0, {"kind": "DOOR", "position": "OPEN"}), "%s door mutate" % suffix)
	var after: Dictionary = SnapshotScript.create(construct_id, 1, 11, store.to_dict())

	var conflict_store = StoreScript.new()
	_assert_ok(conflict_store.setup(), "%s conflict store setup" % suffix)
	_assert_ok(conflict_store.register_subject(SubjectScript.create(
		door_id, construct_id, "item/t1a7-3/%s/door" % suffix,
		"capability/t1a7-3/%s/door" % suffix, 0,
		{"kind": "DOOR", "position": "OPEN"}
	)), "%s conflict door register" % suffix)
	_assert_ok(conflict_store.register_subject(SubjectScript.create(
		lamp_id, construct_id, "item/t1a7-3/%s/lamp" % suffix,
		"capability/t1a7-3/%s/lamp" % suffix, 0,
		{"kind": "LAMP", "on": false}
	)), "%s conflict lamp register" % suffix)
	var same_revision_conflict: Dictionary = SnapshotScript.create(construct_id, 1, 12, conflict_store.to_dict())
	return {
		"before": before,
		"after": after,
		"same_revision_conflict": same_revision_conflict,
	}


func _route(client_id: String, peer_id: String, session_id: String) -> Dictionary:
	return {"client_id": client_id, "peer_id": peer_id, "session_id": session_id}


func _route_clients(routes: Array) -> Array:
	var clients: Array = []
	for route_value in routes:
		if route_value is Dictionary:
			clients.append(String(Dictionary(route_value).get("client_id", "")))
	return clients


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
		print("T1A.7.3 dirty selective replication: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("T1A.7.3 dirty selective replication: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
