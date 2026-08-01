extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const BuildStoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const BuildProcessScript = preload("res://scripts/construction/build/construction_build_process.gd")
const GeometryProcessScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_process.gd")
const GeometryHistoryScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_history_store.gd")
const GeometryRequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")
const PermissionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const SessionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")
const ExecutorScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command_executor.gd")
const GatewayScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")
const MultiplayerPersistenceScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_persistence.gd")
const ReplicaScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_replica.gd")
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const Fixture = preload("res://tests/construction/fixtures/c12_multiplayer_construction_fixture.gd")
const C3Fixture = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const C9Fixture = preload("res://tests/construction/fixtures/c9_damage_split_repair_fixture.gd")
const C11Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")

class MemoryStore:
	extends RefCounted
	var states: Dictionary = {}
	func save_state(key: String, state: Dictionary) -> Dictionary: states[key] = state.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not states.has(key): return {"success": false, "error_code": "MISSING", "message": "MISSING"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_two_client_contention_reconnect_and_convergence()
	_finish()

func _environment() -> Dictionary:
	var geometry_graph := C11Fixture.graph("c12")
	var damage_snapshot := C9Fixture.snapshot("c12")
	var items: Array = C3Fixture.source_projections()
	items.append(geometry_graph["root"]); items.append(geometry_graph["projection"])
	items.append_array(C9Fixture.items("c12"))
	var adapter = AdapterScript.new()
	var setup: Dictionary = adapter.setup(items, [geometry_graph["snapshot"], damage_snapshot])
	var build_store = BuildStoreScript.new(); var build_store_setup := build_store.setup()
	var build_process = BuildProcessScript.new(); var build_setup := build_process.setup(adapter, build_store)
	var build_registration := build_process.register_plan(C3Fixture.build_plan()) if bool(build_setup.get("success", false)) else {}
	var geometry_history = GeometryHistoryScript.new(); var geometry_process = GeometryProcessScript.new(); var geometry_setup := geometry_process.setup(adapter, C11Fixture.catalog(), geometry_history)
	var damage_process = DamageProcessScript.new(); var damage_setup := damage_process.setup(adapter)
	var executor = ExecutorScript.new(); var executor_setup := executor.setup(adapter, build_process, geometry_process, damage_process)
	var permissions = PermissionStoreScript.new(); var permission_setup := permissions.setup(1)
	for grant in Fixture.grants(1): permissions.publish(grant)
	var sessions = SessionStoreScript.new(); var gateway = GatewayScript.new(); var gateway_setup := gateway.setup(executor, permissions, sessions)
	return {"adapter": adapter, "geometry_graph": geometry_graph, "damage_snapshot": damage_snapshot, "build_store": build_store, "build_process": build_process, "geometry_history": geometry_history, "geometry_process": geometry_process, "damage_process": damage_process, "executor": executor, "permissions": permissions, "sessions": sessions, "gateway": gateway, "setup": setup, "build_store_setup": build_store_setup, "build_setup": build_setup, "build_registration": build_registration, "geometry_setup": geometry_setup, "damage_setup": damage_setup, "executor_setup": executor_setup, "permission_setup": permission_setup, "gateway_setup": gateway_setup}

func _test_two_client_contention_reconnect_and_convergence() -> void:
	var env := _environment()
	for key in ["setup", "build_store_setup", "build_setup", "build_registration", "geometry_setup", "damage_setup", "executor_setup", "permission_setup", "gateway_setup"]: _assert_ok(env[key], "Environment failed: %s" % key)
	var gateway = env["gateway"]; var adapter = env["adapter"]
	var connect_a: Dictionary = gateway.connect_client(Fixture.CLIENT_A, Fixture.SESSION_A, -1); _assert_ok(connect_a, "Client A connect failed")
	var connect_b: Dictionary = gateway.connect_client(Fixture.CLIENT_B, Fixture.SESSION_B, -1); _assert_ok(connect_b, "Client B connect failed")
	var session_a: Dictionary = connect_a["session"]; var session_b: Dictionary = connect_b["session"]
	var replica_a = ReplicaScript.new(); var replica_b = ReplicaScript.new()
	_assert_ok(replica_a.initialize(connect_a["state_bundle"], -1), "Replica A init failed")
	_assert_ok(replica_b.initialize(connect_b["state_bundle"], -1), "Replica B init failed")
	_assert(replica_a.get_checksum() == replica_b.get_checksum(), "Initial replicas diverged")

	var denied_damage := Fixture.damage_command(session_b, 0, "c12", env["damage_snapshot"], adapter.get_generation())
	var denied_result: Dictionary = gateway.submit(denied_damage)
	_assert_error(denied_result, "CONSTRUCTION_MULTIPLAYER_PERMISSION_DENIED", "Client B damage permission was not enforced")
	_assert(gateway.get_last_event_index() == -1 and adapter.get_generation() == 0, "Denied command emitted event or mutated authority")
	var denied_replay: Dictionary = gateway.submit(denied_damage); _assert_error(denied_replay, "CONSTRUCTION_MULTIPLAYER_PERMISSION_DENIED", "Denied command replay changed result"); _assert(bool(denied_replay["replay"]), "Denied command replay not marked")

	var build_command := Fixture.build_command(session_a, 0, 0, 0, "")
	var built: Dictionary = gateway.submit(build_command); _assert_ok(built, "Multiplayer build stage failed")
	_assert(int(built["event_index"]) == 0 and adapter.get_generation() == 1, "Build event/generation mismatch")
	_assert(adapter.get_construct_snapshot(C3Fixture.CONSTRUCT_ID).get("build_state") == "PARTIAL", "Build command did not create partial construct")
	_assert_ok(replica_a.apply_event(built["event"]), "Replica A build event failed")
	_assert_ok(replica_b.apply_event(built["event"]), "Replica B build event failed")
	_assert(replica_a.converged_with(gateway.get_state_bundle()) and replica_b.converged_with(gateway.get_state_bundle()), "Replicas did not converge after build")

	var edit_a := Fixture.edit_command(session_a, 1, "c12", env["geometry_graph"], 1, 6.0, 1)
	var edit_b := Fixture.edit_command(session_b, 1, "c12", env["geometry_graph"], 1, 7.0, 2)
	var edited_a: Dictionary = gateway.submit(edit_a); _assert_ok(edited_a, "Client A edit failed")
	_assert(adapter.get_generation() == 2 and int(edited_a["event_index"]) == 1, "Client A edit generation/event mismatch")
	_assert_ok(replica_a.apply_event(edited_a["event"]), "Replica A edit event failed")
	var stale_b: Dictionary = gateway.submit(edit_b)
	_assert_error(stale_b, "CONSTRUCTION_MULTIPLAYER_SERVER_GENERATION_PRECONDITION_MISMATCH", "Concurrent stale edit was accepted")
	_assert(adapter.get_generation() == 2 and gateway.get_last_event_index() == 1, "Rejected stale edit changed authority/event stream")
	var replay_a: Dictionary = gateway.submit(edit_a); _assert_ok(replay_a, "Accepted edit replay failed"); _assert(bool(replay_a["replay"]), "Accepted edit replay not marked")
	_assert(adapter.get_generation() == 2 and gateway.get_last_event_index() == 1, "Accepted replay duplicated commit/event")
	var conflict := edit_a.duplicate(true); conflict["payload"]["failure_mode"] = "BEFORE_COMMIT"; conflict["checksum"] = CommandScript.compute_checksum(conflict)
	_assert_error(gateway.submit(conflict), "CONSTRUCTION_MULTIPLAYER_COMMAND_ID_CONFLICT", "Command ID conflict was accepted")

	var current_graph := _current_geometry_graph(env, "c12")
	var crash_command := _current_edit_command(session_a, 2, current_graph, adapter.get_generation(), 8.0, 2)
	var generation_before_crash: int = adapter.get_generation()
	var crashed: Dictionary = gateway.submit(crash_command, GatewayScript.FAILURE_AFTER_EXECUTION_BEFORE_EVENT)
	_assert_error(crashed, "INJECTED_CONSTRUCTION_MULTIPLAYER_GATEWAY_FAILURE_AFTER_EXECUTION", "Gateway crash injection did not fail")
	_assert(adapter.get_generation() == generation_before_crash + 1, "Crash injection did not commit authority first")
	_assert(gateway.get_last_event_index() == 1, "Crash injection published event")
	var recovered: Dictionary = gateway.submit(crash_command); _assert_ok(recovered, "Gateway crash recovery replay failed")
	_assert(adapter.get_generation() == generation_before_crash + 1, "Gateway recovery duplicated authoritative edit")
	_assert(int(recovered["event_index"]) == 2 and gateway.get_last_event_index() == 2, "Gateway recovery did not publish exactly one event")
	_assert(bool(recovered["execution_result"].get("replay", false)), "Recovered domain execution not marked replay")
	_assert_ok(replica_a.apply_event(recovered["event"]), "Replica A recovery event failed")

	var current_damage_snapshot: Dictionary = adapter.get_construct_snapshot(String(env["damage_snapshot"]["construct_id"]))
	var damage_command := Fixture.damage_command(session_a, 3, "c12", current_damage_snapshot, adapter.get_generation())
	var damaged: Dictionary = gateway.submit(damage_command); _assert_ok(damaged, "Authorized multiplayer damage failed")
	_assert(int(damaged["event_index"]) == 3 and adapter.get_generation() == 4, "Damage event/generation mismatch")
	_assert(damaged["execution_result"]["split_construct_ids"].size() == 1, "Damage did not create split construct")
	_assert_ok(replica_a.apply_event(damaged["event"]), "Replica A damage event failed")
	var repair_plan: Dictionary = damaged["execution_result"]["repair_plan"]
	var damaged_snapshot: Dictionary = adapter.get_construct_snapshot(String(repair_plan["target_construct_id"]))
	var repair_command := Fixture.repair_command(session_a, 4, "c12", repair_plan, String(damaged_snapshot["checksum"]), adapter.get_generation())
	var repaired: Dictionary = gateway.submit(repair_command); _assert_ok(repaired, "Authorized multiplayer repair failed")
	_assert(int(repaired["event_index"]) == 4 and adapter.get_generation() == 5, "Repair event/generation mismatch")
	_assert(adapter.get_construct_snapshot(String(repair_plan["target_construct_id"]))["parts"].size() == 6, "Repair did not restore all parts")
	_assert_ok(replica_a.apply_event(repaired["event"]), "Replica A repair event failed")

	_assert_ok(gateway.disconnect_client(Fixture.SESSION_B, int(session_b["session_epoch"])), "Client B disconnect failed")
	var reconnect_b: Dictionary = gateway.connect_client(Fixture.CLIENT_B, Fixture.SESSION_B, 0); _assert_ok(reconnect_b, "Client B reconnect failed")
	_assert(bool(reconnect_b["reconnect"]) and reconnect_b["events"].size() == 4, "Reconnect did not return missing event range")
	_assert_ok(replica_b.apply_events(reconnect_b["events"]), "Replica B catch-up failed")
	_assert(replica_b.get_last_event_index() == 4, "Replica B catch-up index mismatch")
	_assert(replica_b.converged_with(gateway.get_state_bundle()) and replica_a.converged_with(gateway.get_state_bundle()), "Clients did not converge after reconnect")
	var old_epoch_command := _current_edit_command(session_b, 2, _current_geometry_graph(env, "c12"), adapter.get_generation(), 9.0, 3)
	_assert_error(gateway.submit(old_epoch_command), "CONSTRUCTION_MULTIPLAYER_SESSION_EPOCH_MISMATCH", "Old session epoch command was accepted")

	var beta_grant: Dictionary = env["permissions"].get_grant("permission/c12/beta/edit-build")
	_assert_ok(env["permissions"].revoke(String(beta_grant["grant_id"]), String(beta_grant["checksum"])), "Beta permission revoke failed")
	_assert_ok(env["permissions"].set_epoch(2), "Permission epoch advance failed")
	var session_b2: Dictionary = reconnect_b["session"]
	var stale_permission := _current_edit_command(session_b2, 2, _current_geometry_graph(env, "c12"), adapter.get_generation(), 9.0, 3)
	var stale_permission_result: Dictionary = gateway.submit(stale_permission)
	_assert_error(stale_permission_result, "CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH_MISMATCH", "Stale permission epoch was accepted")
	var reconnect_b2: Dictionary = gateway.connect_client(Fixture.CLIENT_B, Fixture.SESSION_B, 4); _assert_ok(reconnect_b2, "Client B permission reconnect failed")
	var session_b3: Dictionary = reconnect_b2["session"]
	var revoked_edit := _current_edit_command(session_b3, 3, _current_geometry_graph(env, "c12"), adapter.get_generation(), 9.0, 4)
	_assert_error(gateway.submit(revoked_edit), "CONSTRUCTION_MULTIPLAYER_PERMISSION_DENIED", "Revoked client retained edit permission")
	_assert(adapter.get_generation() == 5 and gateway.get_last_event_index() == 4, "Permission failures changed authority")

	var gateway_state: Dictionary = gateway.export_state(); _assert_ok(GatewayScript.validate_state(gateway_state), "Gateway state rejected")
	var storage = MemoryStore.new()
	_assert_ok(MultiplayerPersistenceScript.save(storage, gateway), "Gateway persistence save failed")
	var restored_permissions = PermissionStoreScript.new(); var restored_sessions = SessionStoreScript.new(); var restored_gateway = GatewayScript.new()
	_assert_ok(restored_gateway.setup(env["executor"], restored_permissions, restored_sessions), "Restored gateway setup failed")
	_assert_ok(MultiplayerPersistenceScript.load(storage, restored_gateway), "Gateway persistence load failed")
	var repair_replay := restored_gateway.submit(repair_command); _assert_ok(repair_replay, "Restored gateway terminal replay failed")
	_assert(bool(repair_replay["replay"]), "Restored gateway replay not marked")
	_assert(restored_gateway.get_last_event_index() == 4 and adapter.get_generation() == 5, "Restored replay duplicated event/commit")
	_assert(String(restored_gateway.get_state_bundle()["checksum"]) == replica_a.get_checksum(), "Restored gateway checksum diverged from client")
	var tampered_state: Dictionary = gateway_state.duplicate(true)
	tampered_state["events"][0]["event_index"] = 9
	tampered_state["events"][0]["checksum"] = preload("res://scripts/construction/multiplayer/construction_multiplayer_event.gd").compute_checksum(tampered_state["events"][0])
	tampered_state["checksum"] = GatewayScript.compute_state_checksum(tampered_state)
	_assert_error(restored_gateway.load_state(tampered_state), "NON_CONTIGUOUS_CONSTRUCTION_MULTIPLAYER_EVENTS", "Gateway accepted event-order tamper")

func _current_geometry_graph(env: Dictionary, key: String) -> Dictionary:
	var projection: Dictionary = env["adapter"].get_item_projection(String(env["geometry_graph"]["projection"]["item_instance_id"]))
	return {"instance": projection["components"]["parametric_member"], "projection": projection, "snapshot": env["adapter"].get_construct_snapshot(String(env["geometry_graph"]["snapshot"]["construct_id"])), "root": env["geometry_graph"]["root"], "part_id": env["geometry_graph"]["part_id"]}

func _current_edit_command(session: Dictionary, sequence: int, graph: Dictionary, expected_generation: int, length_m: float, edit_index: int) -> Dictionary:
	var instance: Dictionary = graph["instance"]; var projection: Dictionary = graph["projection"]; var snapshot: Dictionary = graph["snapshot"]
	var state: Dictionary = instance.get("provenance", {}).get("local_geometry_edit_state", {})
	var expected_edit_revision := int(state.get("edit_revision", 0))
	var request := GeometryRequestScript.create("geometry-edit/c12/%d" % edit_index, "operation/geometry-edit/c12/%d" % edit_index, String(instance["member_instance_id"]), String(instance["item_instance_id"]), String(snapshot["construct_id"]), String(graph["part_id"]), String(instance["checksum"]), int(projection["revision"]), String(snapshot["checksum"]), expected_edit_revision, [C11Fixture.move_end(0, [length_m, 0.0, 0.0])], [C11Fixture.min_segment(0.5)], {"actor": String(session["client_id"])})
	return CommandScript.create("multiplayer-command/c12/edit/current/%d" % edit_index, String(session["client_id"]), String(session["session_id"]), int(session["session_epoch"]), sequence, GrantScript.ACTION_EDIT, String(snapshot["construct_id"]), String(snapshot["checksum"]), expected_generation, int(session["permission_epoch"]), {"plan_id": "plan/c12/edit/current/%d" % edit_index, "request": request, "failure_mode": ""})

func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, expected: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C12 multiplayer construction integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C12 multiplayer construction integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
