extends SceneTree

const RuntimeLabScript = preload("res://scripts/labs/t1/t1b/t1b3_recoverable_failure_runtime.gd")
const FailurePolicyScript = preload("res://scripts/construction/behavior/construction_runtime_failure_policy.gd")
const InterestBindingScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_interest_binding.gd")
const ReplicaStoreScript = preload("res://scripts/runtime/host_client/construction_runtime_replica_store.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_failure_checkpoint_restart_reconnect_recovery()
	_finish()


func _test_failure_checkpoint_restart_reconnect_recovery() -> void:
	var root: String = "user://t1b3-recovery-reconnect-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var runtime1 = RuntimeLabScript.new()
	_assert_ok(runtime1.setup(root), "Initial T1B.3 runtime setup failed")
	_assert(not bool(runtime1.get_report().get("recovered_from_m0", false)), "Fresh runtime unexpectedly reported M0 recovery")

	var generator_id: String = String(RuntimeLabScript.RUNTIME_IDS["GENERATOR"])
	var console_id: String = String(RuntimeLabScript.RUNTIME_IDS["CONSOLE"])
	var door_id: String = String(RuntimeLabScript.RUNTIME_IDS["DOOR"])
	var lamp_id: String = String(RuntimeLabScript.RUNTIME_IDS["LAMP"])
	var requirements: Dictionary = {
		generator_id: _requirements(FailurePolicyScript.LEVEL_REQUIRED, FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_NONE),
		console_id: _requirements(FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_REQUIRED),
		door_id: _requirements(FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_REQUIRED),
		lamp_id: _requirements(FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_NONE, FailurePolicyScript.LEVEL_OPTIONAL),
	}
	var outage_availability: Dictionary = {
		generator_id: _availability(false, true),
		console_id: _availability(true, true),
		door_id: _availability(true, true),
		lamp_id: _availability(true, true),
	}
	var recovered_availability: Dictionary = {
		generator_id: _availability(true, true),
		console_id: _availability(true, true),
		door_id: _availability(true, true),
		lamp_id: _availability(true, true),
	}
	var edges: Array = [
		{"from_runtime_id": generator_id, "to_runtime_id": console_id},
		{"from_runtime_id": console_id, "to_runtime_id": door_id},
		{"from_runtime_id": generator_id, "to_runtime_id": lamp_id},
	]

	var outage: Dictionary = runtime1.apply_failure_plan(requirements, outage_availability, edges)
	_assert_ok(outage, "Outage propagation failed")
	_assert(Array(outage.get("applied_runtime_ids", [])).size() == 4, "Outage did not commit all four failure projections")
	_assert_operability(runtime1.get_subject("GENERATOR"), "OFFLINE", ["POWER_UNAVAILABLE"], "Generator outage")
	_assert_operability(runtime1.get_subject("CONSOLE"), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Console dependency outage")
	_assert_operability(runtime1.get_subject("DOOR"), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Door dependency outage")
	_assert_operability(runtime1.get_subject("LAMP"), "DEGRADED", ["DEPENDENCY_UNAVAILABLE"], "Lamp optional dependency outage")

	var door_outage_revision: int = int(runtime1.get_subject("DOOR").get("revision", -1))
	var rejected: Dictionary = runtime1.execute(
		"DOOR",
		"OPEN_DOOR",
		"operation/t1b3/door/offline",
		door_outage_revision
	)
	_assert_error(rejected, "CONSTRUCTION_RUNTIME_SUBJECT_OFFLINE", "OFFLINE door command was not rejected")
	_assert(String(runtime1.get_subject("DOOR").get("state", {}).get("position", "")) == "CLOSED", "Rejected OFFLINE door command changed door position")
	var rejected_canonical: String = UtilsScript.canonical_json(rejected)

	var outage_recovery_state: Dictionary = runtime1.export_recovery_state()
	_assert(not outage_recovery_state.is_empty(), "Outage recovery state was not exportable")
	_assert(not outage_recovery_state.has("client_id") and not outage_recovery_state.has("session_id") and not outage_recovery_state.has("interest_revision"), "Runtime persistence captured client/session/interest transport state")
	var outage_checksum: String = String(outage_recovery_state.get("checksum", ""))
	var checkpoint1: Dictionary = runtime1.checkpoint_runtime("operation/t1b3/checkpoint/outage")
	_assert_ok(checkpoint1, "Outage runtime checkpoint failed")
	_assert(int(checkpoint1.get("runtime_checkpoint_revision", -1)) >= 0, "Outage checkpoint revision missing")

	var snapshot1_result: Dictionary = runtime1.create_runtime_snapshot(1, 100)
	_assert_ok(snapshot1_result, "Outage runtime snapshot creation failed")
	var snapshot1: Dictionary = Dictionary(snapshot1_result.get("snapshot", {}))
	var pre_restart_replica = ReplicaStoreScript.new()
	_assert_ok(pre_restart_replica.accept_snapshot(snapshot1), "Pre-restart replica rejected outage snapshot")
	_assert_operability(pre_restart_replica.get_subject(door_id), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Pre-restart replica door outage")

	var interest1 = InterestBindingScript.new()
	_assert_ok(interest1.configure(1), "Initial interest binding configure failed")
	_assert_ok(interest1.bind_session("peer/t1b3/a1", "session/t1b3/a1", "client/t1b3/a"), "Initial A session bind failed")
	_assert_ok(interest1.update_selection("client/t1b3/a", 1, [RuntimeLabScript.CONSTRUCT_ID]), "Initial A interest selection failed")
	_assert(interest1.is_selected("peer/t1b3/a1", "session/t1b3/a1", RuntimeLabScript.CONSTRUCT_ID), "A did not select construct before restart")
	var retained_interest: Dictionary = interest1.client_state("client/t1b3/a")
	_assert(not retained_interest.is_empty(), "A retained interest state missing")
	_assert_ok(interest1.disconnect_session("peer/t1b3/a1", "session/t1b3/a1"), "A disconnect failed")
	_assert(not interest1.is_selected("peer/t1b3/a1", "session/t1b3/a1", RuntimeLabScript.CONSTRUCT_ID), "Disconnected A session remained active")

	var runtime2 = RuntimeLabScript.new()
	_assert_ok(runtime2.setup(root), "Restarted T1B.3 runtime setup failed")
	_assert(bool(runtime2.get_report().get("recovered_from_m0", false)), "Restarted runtime did not recover from M0")
	_assert(String(runtime2.export_recovery_state().get("checksum", "")) == outage_checksum, "Restarted failure truth checksum differs from checkpointed state")
	_assert_operability(runtime2.get_subject("GENERATOR"), "OFFLINE", ["POWER_UNAVAILABLE"], "Recovered generator outage")
	_assert_operability(runtime2.get_subject("CONSOLE"), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Recovered console outage")
	_assert_operability(runtime2.get_subject("DOOR"), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Recovered door outage")
	_assert_operability(runtime2.get_subject("LAMP"), "DEGRADED", ["DEPENDENCY_UNAVAILABLE"], "Recovered lamp degradation")

	var rejected_replay: Dictionary = runtime2.execute(
		"DOOR",
		"OPEN_DOOR",
		"operation/t1b3/door/offline",
		door_outage_revision
	)
	_assert(UtilsScript.canonical_json(rejected_replay) == rejected_canonical, "Recovered rejected command replay changed terminal result")
	_assert(int(runtime2.get_subject("DOOR").get("revision", -1)) == door_outage_revision, "Recovered rejected command replay advanced door revision")

	var interest2 = InterestBindingScript.new()
	_assert_ok(interest2.configure(1), "Restarted interest binding configure failed")
	_assert_ok(interest2.restore_client_state("client/t1b3/a", retained_interest), "Externally retained A interest projection restore failed")
	var rebound_a: Dictionary = interest2.bind_session("peer/t1b3/a2", "session/t1b3/a2", "client/t1b3/a")
	_assert_ok(rebound_a, "A reconnect session bind failed")
	_assert(bool(Dictionary(rebound_a.get("details", {})).get("reconnect", false)), "A reconnect was not classified as reconnect")
	_assert(interest2.is_selected("peer/t1b3/a2", "session/t1b3/a2", RuntimeLabScript.CONSTRUCT_ID), "A retained selection did not survive session rebind")
	_assert(not interest2.is_selected("peer/t1b3/a1", "session/t1b3/a1", RuntimeLabScript.CONSTRUCT_ID), "Old A session became valid after restart")

	var snapshot2_result: Dictionary = runtime2.create_runtime_snapshot(1, 101)
	_assert_ok(snapshot2_result, "Recovered runtime snapshot creation failed")
	var snapshot2: Dictionary = Dictionary(snapshot2_result.get("snapshot", {}))
	var replica_a = ReplicaStoreScript.new()
	_assert_ok(replica_a.accept_snapshot(snapshot2), "Reconnected A rejected recovered full baseline")
	_assert_operability(replica_a.get_subject(door_id), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Reconnected A recovered door failure truth")

	var replica_b = ReplicaStoreScript.new()
	_assert(replica_b.get_snapshot().is_empty(), "Late client B unexpectedly had a baseline before interest")
	_assert_ok(interest2.bind_session("peer/t1b3/b1", "session/t1b3/b1", "client/t1b3/b"), "B session bind failed")
	_assert(not interest2.is_selected("peer/t1b3/b1", "session/t1b3/b1", RuntimeLabScript.CONSTRUCT_ID), "B was selected before authoritative interest update")
	_assert_ok(interest2.update_selection("client/t1b3/b", 1, [RuntimeLabScript.CONSTRUCT_ID]), "B late-interest selection failed")
	_assert(interest2.is_selected("peer/t1b3/b1", "session/t1b3/b1", RuntimeLabScript.CONSTRUCT_ID), "B late-interest selection did not activate")
	_assert_ok(replica_b.accept_snapshot(snapshot2), "Late-interest B rejected recovered full baseline")
	_assert_operability(replica_b.get_subject(door_id), "OFFLINE", ["DEPENDENCY_UNAVAILABLE"], "Late-interest B recovered door failure truth")

	var recovery: Dictionary = runtime2.apply_failure_plan(requirements, recovered_availability, edges)
	_assert_ok(recovery, "Dependency recovery propagation failed")
	_assert(Array(recovery.get("applied_runtime_ids", [])).size() == 4, "Dependency recovery did not commit all four projections")
	for kind in ["GENERATOR", "CONSOLE", "DOOR", "LAMP"]:
		_assert_operability(runtime2.get_subject(kind), "ONLINE", [], "%s recovery" % kind)

	var snapshot3_result: Dictionary = runtime2.create_runtime_snapshot(1, 102)
	_assert_ok(snapshot3_result, "Recovered-online runtime snapshot creation failed")
	var snapshot3: Dictionary = Dictionary(snapshot3_result.get("snapshot", {}))
	_assert_ok(replica_a.accept_snapshot(snapshot3), "A replica rejected dependency recovery mutation")
	_assert_ok(replica_b.accept_snapshot(snapshot3), "B replica rejected dependency recovery mutation")
	_assert_operability(replica_a.get_subject(door_id), "ONLINE", [], "A replica door recovery")
	_assert_operability(replica_b.get_subject(door_id), "ONLINE", [], "B replica door recovery")

	var door_online_revision: int = int(runtime2.get_subject("DOOR").get("revision", -1))
	var opened: Dictionary = runtime2.execute(
		"DOOR",
		"OPEN_DOOR",
		"operation/t1b3/door/open-after-recovery",
		door_online_revision
	)
	_assert_ok(opened, "Door command was not re-enabled after canonical dependency recovery")
	_assert(String(runtime2.get_subject("DOOR").get("state", {}).get("position", "")) == "OPEN", "Recovered door command did not open door")
	var opened_canonical: String = UtilsScript.canonical_json(opened)
	var opened_revision: int = int(runtime2.get_subject("DOOR").get("revision", -1))

	var checkpoint2: Dictionary = runtime2.checkpoint_runtime("operation/t1b3/checkpoint/recovered")
	_assert_ok(checkpoint2, "Recovered-online runtime checkpoint failed")
	var runtime3 = RuntimeLabScript.new()
	_assert_ok(runtime3.setup(root), "Second restarted T1B.3 runtime setup failed")
	_assert(bool(runtime3.get_report().get("recovered_from_m0", false)), "Second restart did not recover from M0")
	_assert_operability(runtime3.get_subject("DOOR"), "ONLINE", [], "Second restart door operability")
	_assert(String(runtime3.get_subject("DOOR").get("state", {}).get("position", "")) == "OPEN", "Second restart lost recovered door gameplay state")
	_assert(int(runtime3.get_subject("DOOR").get("revision", -1)) == opened_revision, "Second restart changed recovered door revision")

	var opened_replay: Dictionary = runtime3.execute(
		"DOOR",
		"OPEN_DOOR",
		"operation/t1b3/door/open-after-recovery",
		door_online_revision
	)
	_assert(UtilsScript.canonical_json(opened_replay) == opened_canonical, "Recovered successful command replay changed terminal result")
	_assert(int(runtime3.get_subject("DOOR").get("revision", -1)) == opened_revision, "Recovered successful command replay advanced door revision")

	var snapshot4_result: Dictionary = runtime3.create_runtime_snapshot(1, 103)
	_assert_ok(snapshot4_result, "Second-restart current baseline snapshot creation failed")
	var snapshot4: Dictionary = Dictionary(snapshot4_result.get("snapshot", {}))
	_assert_ok(replica_a.accept_snapshot(snapshot4), "A replica rejected second-restart current baseline")
	_assert(String(replica_a.get_subject(door_id).get("state", {}).get("position", "")) == "OPEN", "A replica did not converge to recovered OPEN door state")
	_assert_operability(replica_a.get_subject(door_id), "ONLINE", [], "A replica second-restart operability")

	var interest_report: Dictionary = interest2.report()
	_assert(int(interest_report.get("reconnect_binds", 0)) >= 1, "Reconnect telemetry was not recorded")
	_assert(int(interest_report.get("active_sessions", 0)) == 2, "Unexpected active session count after reconnect + late interest")


func _requirements(power: String, data: String, dependency: String) -> Dictionary:
	return {"power": power, "data": data, "dependency": dependency}


func _availability(power: bool, data: bool) -> Dictionary:
	return {"power": power, "data": data}


func _assert_operability(subject: Dictionary, expected: String, failure_codes: Array, label: String) -> void:
	_assert(not subject.is_empty(), "%s subject missing" % label)
	var state: Dictionary = Dictionary(subject.get("state", {}))
	_assert(String(state.get("operability", "")) == expected, "%s operability mismatch: %s" % [label, state])
	_assert(UtilsScript.canonical_json(Array(state.get("failure_codes", []))) == UtilsScript.canonical_json(failure_codes), "%s failure codes mismatch: %s" % [label, state])


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
		print("T1B.3 recovery/reconnect composition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1B.3 recovery/reconnect composition: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
