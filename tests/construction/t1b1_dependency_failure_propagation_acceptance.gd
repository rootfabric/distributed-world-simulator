extends SceneTree

const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const PropagatorScript = preload("res://scripts/construction/behavior/construction_runtime_dependency_failure_propagator.gd")

const CONSTRUCT_ID: String = "construct/t1b/dependency/d0"
const GENERATOR_ID: String = "runtime/t1b/dependency/generator"
const BUS_ID: String = "runtime/t1b/dependency/bus"
const CONSOLE_ID: String = "runtime/t1b/dependency/console"
const DOOR_ID: String = "runtime/t1b/dependency/door"
const LAMP_ID: String = "runtime/t1b/dependency/lamp"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_dependency_failure_propagation()
	_finish()


func _test_dependency_failure_propagation() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "store setup")
	for subject in _subjects():
		_assert_ok(store.register_subject(subject), "register %s" % String(subject.get("runtime_id", "")))

	var requirements: Dictionary = _requirements()
	var available: Dictionary = _all_available()
	var edges: Array = _edges()

	var initial: Dictionary = PropagatorScript.plan(store.list_subjects(), requirements, available, edges)
	_assert_ok(initial, "initial propagation plan")
	_assert(String(initial.get("schema", "")) == PropagatorScript.SCHEMA, "propagator schema mismatch")
	_assert(String(initial.get("construct_id", "")) == CONSTRUCT_ID, "construct id mismatch")
	_assert(int(initial.get("node_count", 0)) == 5, "node count mismatch")
	_assert(int(initial.get("edge_count", 0)) == 4, "edge count mismatch")
	_assert(bool(initial.get("bounded", false)), "plan is not marked bounded")
	_assert(not bool(initial.get("requires_global_dependency_identity", true)), "plan claims global dependency identity")
	_assert(not bool(initial.get("commits_runtime_state", true)), "pure plan claims runtime commit")
	_assert(Array(initial.get("order", [])) == [GENERATOR_ID, BUS_ID, CONSOLE_ID, DOOR_ID, LAMP_ID], "topological order is not deterministic")
	_assert(_operability(initial, GENERATOR_ID) == "ONLINE", "generator initial operability")
	_assert(_operability(initial, BUS_ID) == "ONLINE", "bus initial operability")
	_assert(_operability(initial, CONSOLE_ID) == "ONLINE", "console initial operability")
	_assert(_operability(initial, DOOR_ID) == "ONLINE", "door initial operability")
	_assert(_operability(initial, LAMP_ID) == "ONLINE", "lamp initial operability")
	_assert_ok(_commit_changed(store, initial), "commit initial operability")

	var reversed_subjects: Array = store.list_subjects()
	reversed_subjects.reverse()
	var reversed_edges: Array = edges.duplicate(true)
	reversed_edges.reverse()
	var deterministic_a: Dictionary = PropagatorScript.plan(store.list_subjects(), requirements, available, edges)
	var deterministic_b: Dictionary = PropagatorScript.plan(reversed_subjects, requirements, available, reversed_edges)
	_assert_ok(deterministic_a, "deterministic plan A")
	_assert_ok(deterministic_b, "deterministic plan B")
	_assert(deterministic_a == deterministic_b, "input ordering changed dependency propagation output")
	_assert(Array(deterministic_a.get("changed_runtime_ids", [])) == [], "stable online plan unexpectedly changes state")

	var degraded_requirements: Dictionary = requirements.duplicate(true)
	degraded_requirements[BUS_ID] = {"power": "NONE", "data": "OPTIONAL", "dependency": "REQUIRED"}
	var bus_data_loss: Dictionary = available.duplicate(true)
	bus_data_loss[BUS_ID] = {"power": true, "data": false}
	var degraded_plan: Dictionary = PropagatorScript.plan(store.list_subjects(), degraded_requirements, bus_data_loss, edges)
	_assert_ok(degraded_plan, "degraded upstream plan")
	_assert(_operability(degraded_plan, BUS_ID) == "DEGRADED", "bus optional data loss should degrade")
	_assert(_operability(degraded_plan, CONSOLE_ID) == "ONLINE", "degraded upstream must remain dependency-available")
	_assert(_operability(degraded_plan, DOOR_ID) == "ONLINE", "degraded upstream incorrectly cascaded OFFLINE")
	_assert(bool(degraded_plan.get("degraded_upstream_counts_as_available", false)), "degraded-upstream policy not explicit")

	var outage: Dictionary = available.duplicate(true)
	outage[GENERATOR_ID] = {"power": false, "data": true}
	var outage_plan: Dictionary = PropagatorScript.plan(store.list_subjects(), requirements, outage, edges)
	_assert_ok(outage_plan, "generator outage propagation")
	_assert(_operability(outage_plan, GENERATOR_ID) == "OFFLINE", "generator power loss must be OFFLINE")
	_assert(_failure_codes(outage_plan, GENERATOR_ID) == ["POWER_UNAVAILABLE"], "generator failure code mismatch")
	_assert(_operability(outage_plan, BUS_ID) == "OFFLINE", "bus did not follow generator failure")
	_assert(_failure_codes(outage_plan, BUS_ID) == ["DEPENDENCY_UNAVAILABLE"], "bus dependency failure code mismatch")
	_assert(_operability(outage_plan, CONSOLE_ID) == "OFFLINE", "console did not follow bus failure")
	_assert(_operability(outage_plan, DOOR_ID) == "OFFLINE", "door did not follow console failure")
	_assert(_operability(outage_plan, LAMP_ID) == "DEGRADED", "optional lamp dependency should degrade")
	_assert(_failure_codes(outage_plan, LAMP_ID) == ["DEPENDENCY_UNAVAILABLE"], "lamp dependency failure code mismatch")
	_assert(Array(outage_plan.get("changed_runtime_ids", [])) == [GENERATOR_ID, BUS_ID, CONSOLE_ID, DOOR_ID, LAMP_ID], "outage changed ids mismatch")
	_assert_ok(_commit_changed(store, outage_plan), "commit outage propagation")
	_assert(_stored_operability(store, GENERATOR_ID) == "OFFLINE", "stored generator outage missing")
	_assert(_stored_operability(store, BUS_ID) == "OFFLINE", "stored bus outage missing")
	_assert(_stored_operability(store, CONSOLE_ID) == "OFFLINE", "stored console outage missing")
	_assert(_stored_operability(store, DOOR_ID) == "OFFLINE", "stored door outage missing")
	_assert(_stored_operability(store, LAMP_ID) == "DEGRADED", "stored lamp degradation missing")

	var persisted: Dictionary = store.to_dict()
	_assert_ok(StoreScript.validate_state(persisted), "failure-propagated store validates")
	var restored = StoreScript.new()
	_assert_ok(restored.setup(), "restored store setup")
	_assert_ok(restored.load_dict(persisted), "restore propagated failure state")
	_assert(restored.to_dict() == persisted, "propagated failure state changed across recovery roundtrip")

	var recovery_plan: Dictionary = PropagatorScript.plan(restored.list_subjects(), requirements, available, edges)
	_assert_ok(recovery_plan, "dependency recovery propagation")
	_assert(_operability(recovery_plan, GENERATOR_ID) == "ONLINE", "generator did not recover")
	_assert(_operability(recovery_plan, BUS_ID) == "ONLINE", "bus did not recover")
	_assert(_operability(recovery_plan, CONSOLE_ID) == "ONLINE", "console did not recover")
	_assert(_operability(recovery_plan, DOOR_ID) == "ONLINE", "door did not recover")
	_assert(_operability(recovery_plan, LAMP_ID) == "ONLINE", "lamp did not recover")
	_assert_ok(_commit_changed(restored, recovery_plan), "commit dependency recovery")
	for runtime_id in [GENERATOR_ID, BUS_ID, CONSOLE_ID, DOOR_ID, LAMP_ID]:
		_assert(_stored_operability(restored, runtime_id) == "ONLINE", "%s stored recovery missing" % runtime_id)

	var cycle_edges: Array = edges.duplicate(true)
	cycle_edges.append({"from_runtime_id": DOOR_ID, "to_runtime_id": GENERATOR_ID})
	_assert_error(PropagatorScript.plan(restored.list_subjects(), requirements, available, cycle_edges), "CONSTRUCTION_RUNTIME_DEPENDENCY_CYCLE", "cycle accepted")

	var duplicate_edges: Array = edges.duplicate(true)
	duplicate_edges.append(edges[0].duplicate(true))
	_assert_error(PropagatorScript.plan(restored.list_subjects(), requirements, available, duplicate_edges), "DUPLICATE_CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE", "duplicate edge accepted")

	var self_edges: Array = edges.duplicate(true)
	self_edges.append({"from_runtime_id": BUS_ID, "to_runtime_id": BUS_ID})
	_assert_error(PropagatorScript.plan(restored.list_subjects(), requirements, available, self_edges), "CONSTRUCTION_RUNTIME_DEPENDENCY_SELF_EDGE", "self edge accepted")

	var missing_edges: Array = edges.duplicate(true)
	missing_edges.append({"from_runtime_id": "runtime/t1b/dependency/missing", "to_runtime_id": DOOR_ID})
	_assert_error(PropagatorScript.plan(restored.list_subjects(), requirements, available, missing_edges), "CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE_SUBJECT_NOT_FOUND", "missing subject edge accepted")

	_assert_error(PropagatorScript.plan(restored.list_subjects(), requirements, available, edges, 4, 4096), "CONSTRUCTION_RUNTIME_DEPENDENCY_NODE_BOUND_EXCEEDED", "node bound ignored")
	_assert_error(PropagatorScript.plan(restored.list_subjects(), requirements, available, edges, 1024, 3), "CONSTRUCTION_RUNTIME_DEPENDENCY_EDGE_BOUND_EXCEEDED", "edge bound ignored")

	var mixed_subjects: Array = restored.list_subjects()
	mixed_subjects.append(SubjectScript.create("runtime/t1b/dependency/foreign", "construct/t1b/dependency/other", "item/t1b/dependency/foreign", "capability/t1b/dependency/foreign", 0, {"kind": "FOREIGN"}))
	_assert_error(PropagatorScript.plan(mixed_subjects, requirements, available, edges), "CONSTRUCTION_RUNTIME_DEPENDENCY_CROSS_CONSTRUCT_SUBJECT_SET", "cross-construct subject set accepted")


func _subjects() -> Array:
	return [
		SubjectScript.create(GENERATOR_ID, CONSTRUCT_ID, "item/t1b/dependency/generator", "capability/t1b/dependency/generator", 0, {"kind": "GENERATOR", "running": true}),
		SubjectScript.create(BUS_ID, CONSTRUCT_ID, "item/t1b/dependency/bus", "capability/t1b/dependency/bus", 0, {"kind": "BUS"}),
		SubjectScript.create(CONSOLE_ID, CONSTRUCT_ID, "item/t1b/dependency/console", "capability/t1b/dependency/console", 0, {"kind": "CONSOLE", "active": true}),
		SubjectScript.create(DOOR_ID, CONSTRUCT_ID, "item/t1b/dependency/door", "capability/t1b/dependency/door", 0, {"kind": "DOOR", "position": "CLOSED"}),
		SubjectScript.create(LAMP_ID, CONSTRUCT_ID, "item/t1b/dependency/lamp", "capability/t1b/dependency/lamp", 0, {"kind": "LAMP", "on": true}),
	]


func _requirements() -> Dictionary:
	return {
		GENERATOR_ID: {"power": "REQUIRED", "data": "NONE", "dependency": "NONE"},
		BUS_ID: {"power": "NONE", "data": "NONE", "dependency": "REQUIRED"},
		CONSOLE_ID: {"power": "NONE", "data": "NONE", "dependency": "REQUIRED"},
		DOOR_ID: {"power": "NONE", "data": "NONE", "dependency": "REQUIRED"},
		LAMP_ID: {"power": "NONE", "data": "NONE", "dependency": "OPTIONAL"},
	}


func _all_available() -> Dictionary:
	return {
		GENERATOR_ID: {"power": true, "data": true},
		BUS_ID: {"power": true, "data": true},
		CONSOLE_ID: {"power": true, "data": true},
		DOOR_ID: {"power": true, "data": true},
		LAMP_ID: {"power": true, "data": true},
	}


func _edges() -> Array:
	return [
		{"from_runtime_id": GENERATOR_ID, "to_runtime_id": BUS_ID},
		{"from_runtime_id": BUS_ID, "to_runtime_id": CONSOLE_ID},
		{"from_runtime_id": CONSOLE_ID, "to_runtime_id": DOOR_ID},
		{"from_runtime_id": BUS_ID, "to_runtime_id": LAMP_ID},
	]


func _proposal(plan: Dictionary, runtime_id: String) -> Dictionary:
	for raw in Array(plan.get("proposals", [])):
		var proposal: Dictionary = Dictionary(raw)
		if String(proposal.get("runtime_id", "")) == runtime_id:
			return proposal
	return {}


func _operability(plan: Dictionary, runtime_id: String) -> String:
	return String(_proposal(plan, runtime_id).get("operability", ""))


func _failure_codes(plan: Dictionary, runtime_id: String) -> Array:
	return Array(_proposal(plan, runtime_id).get("failure_codes", [])).duplicate()


func _stored_operability(store, runtime_id: String) -> String:
	return String(Dictionary(store.get_subject(runtime_id).get("state", {})).get("operability", ""))


func _commit_changed(store, plan: Dictionary) -> Dictionary:
	for raw in Array(plan.get("proposals", [])):
		var proposal: Dictionary = Dictionary(raw)
		if not bool(proposal.get("changed", false)):
			continue
		var commit: Dictionary = store.update_subject(
			String(proposal.get("runtime_id", "")),
			int(proposal.get("expected_revision", -1)),
			Dictionary(proposal.get("next_state", {}))
		)
		if not bool(commit.get("success", false)):
			return commit
	return {"success": true, "error_code": "", "message": ""}


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)
	_assert(String(result.get("error_code", "")) == error_code, "%s: expected %s got %s" % [message, error_code, result])


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1B.1 dependency failure propagation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("T1B.1 dependency failure propagation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
