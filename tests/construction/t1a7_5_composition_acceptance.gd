extends SceneTree

const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")
const ReplicaScript = preload("res://scripts/runtime/host_client/construction_runtime_replica_store.gd")
const InterestScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_interest_binding.gd")
const PlannerScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_selective_replication_planner.gd")

const D0: String = "construct/t1/composition/d0"
const DOOR: String = "runtime/t1a7-5/d0/door"
const LAMP: String = "runtime/t1a7-5/d0/lamp"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_composition()
	_finish()


func _test_composition() -> void:
	var source_store = StoreScript.new()
	_assert_ok(source_store.setup(), "source store setup")
	_assert_ok(source_store.register_subject(SubjectScript.create(
		DOOR, D0, "item/t1a7-5/d0/door", "capability/t1a7-5/d0/door", 0,
		{"kind": "DOOR", "position": "CLOSED"}
	)), "register door")
	_assert_ok(source_store.register_subject(SubjectScript.create(
		LAMP, D0, "item/t1a7-5/d0/lamp", "capability/t1a7-5/d0/lamp", 0,
		{"kind": "LAMP", "on": false}
	)), "register lamp")

	var before: Dictionary = SnapshotScript.create(D0, 1, 10, source_store.to_dict())
	_assert_ok(SnapshotScript.validate(before), "before snapshot validates")
	_assert_ok(source_store.update_subject(DOOR, 0, {"kind": "DOOR", "position": "OPEN"}), "open door")
	var opened: Dictionary = SnapshotScript.create(D0, 1, 11, source_store.to_dict())
	_assert_ok(SnapshotScript.validate(opened), "opened snapshot validates")

	# Recovery composition boundary: canonical state survives a serialize/load round trip.
	var persisted_state: Dictionary = source_store.to_dict()
	var recovered_store = StoreScript.new()
	_assert_ok(recovered_store.setup(), "recovered store setup")
	_assert_ok(recovered_store.load_dict(persisted_state), "recovered store load")
	_assert(String(recovered_store.to_dict().get("checksum", "")) == String(persisted_state.get("checksum", "")), "recovered canonical checksum mismatch")
	var recovered_opened: Dictionary = SnapshotScript.create(D0, 1, 20, recovered_store.to_dict())
	_assert_ok(SnapshotScript.validate(recovered_opened), "recovered snapshot validates")
	_assert(String(recovered_opened.get("state_checksum", "")) == String(opened.get("state_checksum", "")), "recovered runtime semantic checksum mismatch")
	var recovered_door: Dictionary = recovered_store.get_subject(DOOR)
	var recovered_door_state: Dictionary = Dictionary(recovered_door.get("state", {}))
	_assert(String(recovered_door_state.get("position", "")) == "OPEN", "recovered door is not OPEN")

	# Interest/session and reverse selective projection are composed over recovered truth.
	var interest = InterestScript.new()
	_assert_ok(interest.configure(1), "interest configure")
	_assert_ok(interest.bind_session("peer/a", "session/a1", "client/a"), "bind A")
	_assert_ok(interest.bind_session("peer/b", "session/b1", "client/b"), "bind B")
	_assert_ok(interest.update_selection("client/a", 1, [D0]), "A selects D0")
	_assert_ok(interest.update_selection("client/b", 1, []), "B selects nothing")
	_assert(interest.is_selected("peer/a", "session/a1", D0), "A selection missing")
	_assert(not interest.is_selected("peer/b", "session/b1", D0), "B incorrectly selected D0")

	var planner = PlannerScript.new()
	_assert_ok(planner.configure(1), "planner configure")
	_assert_ok(planner.update_selection("client/a", [D0]), "planner A selection")
	_assert_ok(planner.update_selection("client/b", []), "planner B selection")
	var routes: Dictionary = {
		"client/a": {"client_id": "client/a", "peer_id": "peer/a", "session_id": "session/a1"},
		"client/b": {"client_id": "client/b", "peer_id": "peer/b", "session_id": "session/b1"},
	}
	var open_plan: Dictionary = planner.plan_mutation(before, recovered_opened, routes, 2)
	_assert_ok(open_plan, "open mutation selective plan")
	var open_details: Dictionary = Dictionary(open_plan.get("details", {}))
	_assert(Array(open_details.get("dirty_runtime_ids", [])) == [DOOR], "open dirty set mismatch")
	_assert(int(open_details.get("target_count", -1)) == 1, "open target count mismatch")
	_assert(int(open_details.get("avoided_peer_deliveries", -1)) == 1, "open avoided peer count mismatch")
	_assert(_route_clients(Array(open_details.get("target_routes", []))) == ["client/a"], "open targeted client mismatch")

	var replica_a = ReplicaScript.new()
	var replica_b = ReplicaScript.new()
	_assert_ok(replica_a.accept_snapshot(before), "A initial baseline")
	_assert_ok(replica_a.accept_snapshot(recovered_opened), "A recovered OPEN mutation")
	var replica_a_door: Dictionary = replica_a.get_subject(DOOR)
	var replica_a_door_state: Dictionary = Dictionary(replica_a_door.get("state", {}))
	_assert(String(replica_a_door_state.get("position", "")) == "OPEN", "A replica did not converge OPEN")
	_assert(not bool(replica_b.get_report().get("has_snapshot", false)), "out-of-interest B received runtime state")

	# A leaves interest. A later re-enters and receives a full current baseline.
	_assert_ok(interest.update_selection("client/a", 2, []), "A leaves interest")
	_assert_ok(planner.update_selection("client/a", []), "planner A leaves interest")
	_assert_ok(recovered_store.update_subject(LAMP, 0, {"kind": "LAMP", "on": true}), "toggle lamp while A out of interest")
	var lamp_on: Dictionary = SnapshotScript.create(D0, 1, 21, recovered_store.to_dict())
	var no_target_plan: Dictionary = planner.plan_mutation(recovered_opened, lamp_on, routes, 2)
	_assert_ok(no_target_plan, "out-of-interest mutation plan")
	var no_target_details: Dictionary = Dictionary(no_target_plan.get("details", {}))
	_assert(Array(no_target_details.get("dirty_runtime_ids", [])) == [LAMP], "lamp dirty set mismatch")
	_assert(int(no_target_details.get("target_count", -1)) == 0, "out-of-interest mutation targeted a client")
	_assert(int(no_target_details.get("avoided_peer_deliveries", -1)) == 2, "out-of-interest avoided peer count mismatch")

	_assert_ok(interest.update_selection("client/a", 3, [D0]), "A re-enters interest")
	_assert_ok(planner.update_selection("client/a", [D0]), "planner A re-enters")
	_assert_ok(replica_a.accept_snapshot(lamp_on), "A re-entry full baseline")
	var replica_a_lamp: Dictionary = replica_a.get_subject(LAMP)
	var replica_a_lamp_state: Dictionary = Dictionary(replica_a_lamp.get("state", {}))
	_assert(bool(replica_a_lamp_state.get("on", false)), "A re-entry baseline did not converge lamp")

	# Logical interest survives transport reconnect; old session fence must no longer select.
	_assert_ok(interest.disconnect_session("peer/a", "session/a1"), "disconnect A old session")
	var reconnect: Dictionary = interest.bind_session("peer/a2", "session/a2", "client/a")
	_assert_ok(reconnect, "bind A reconnect")
	var reconnect_details: Dictionary = Dictionary(reconnect.get("details", {}))
	_assert(bool(reconnect_details.get("reconnect", false)), "A reconnect not classified reconnect")
	_assert(not interest.is_selected("peer/a", "session/a1", D0), "old A session remained selected")
	_assert(interest.is_selected("peer/a2", "session/a2", D0), "A retained interest missing on reconnect")
	var a_client_state: Dictionary = interest.client_state("client/a")
	_assert(int(a_client_state.get("interest_revision", 0)) == 3, "A reconnect lost interest revision")

	var reconnect_replica = ReplicaScript.new()
	_assert_ok(reconnect_replica.accept_snapshot(lamp_on), "A reconnect current full baseline")
	_assert(reconnect_replica.state_semantically_equals(lamp_on), "A reconnect replica does not equal authoritative baseline")
	_assert(not bool(replica_b.get_report().get("has_snapshot", false)), "B received state during re-entry/reconnect composition")

	var interest_report: Dictionary = interest.report()
	var planner_report: Dictionary = planner.report()
	_assert(int(interest_report.get("reconnect_binds", 0)) >= 1, "reconnect telemetry missing")
	_assert(int(interest_report.get("active_sessions", 0)) == 2, "active session cardinality mismatch")
	_assert(int(planner_report.get("plan_failures", 0)) == 0, "planner failure occurred in composition")
	_assert(int(planner_report.get("targeted_deliveries", 0)) == 1, "composition targeted delivery telemetry mismatch")
	_assert(int(planner_report.get("avoided_peer_deliveries", 0)) == 3, "composition avoided delivery telemetry mismatch")


func _route_clients(routes: Array) -> Array:
	var clients: Array = []
	for route_value in routes:
		if route_value is Dictionary:
			clients.append(String(Dictionary(route_value).get("client_id", "")))
	clients.sort()
	return clients


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1A.7.5 recovery/interest/selective composition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("T1A.7.5 recovery/interest/selective composition: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
