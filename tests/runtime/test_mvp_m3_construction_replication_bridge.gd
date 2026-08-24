extends SceneTree

const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const BuildStoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const BuildProcessScript = preload("res://scripts/construction/build/construction_build_process.gd")
const GeometryProcessScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_process.gd")
const GeometryHistoryScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_history_store.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")
const PermissionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const SessionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")
const ExecutorScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command_executor.gd")
const GatewayScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")
const ReplicaScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_replica.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const BridgeScript = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const GraphicalClientScript = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd")
const Fixture = preload("res://tests/construction/fixtures/c12_multiplayer_construction_fixture.gd")
const C3Fixture = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const C9Fixture = preload("res://tests/construction/fixtures/c9_damage_split_repair_fixture.gd")
const C11Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var env := _environment()
	for key in ["setup", "build_store_setup", "build_setup", "build_registration", "geometry_setup", "damage_setup", "executor_setup", "permission_setup", "gateway_setup"]:
		_assert(bool(Dictionary(env[key]).get("success", false)), "environment %s" % key)
	var bridge = BridgeScript.new()
	_assert(bool(bridge.setup(env["gateway"]).get("success", false)), "bridge setup")
	var joined_a: Dictionary = bridge.connect_player("a", 1)
	var joined_b: Dictionary = bridge.connect_player("b", 1)
	_assert(bool(joined_a.get("success", false)) and bool(joined_b.get("success", false)), "two M3 players connect")
	var replica_a = ReplicaScript.new()
	var replica_b = ReplicaScript.new()
	var packet_a: Dictionary = joined_a.get("details", {}).get("snapshot", {})
	var packet_b: Dictionary = joined_b.get("details", {}).get("snapshot", {})
	_assert(String(packet_a.get("type", "")) == "CONSTRUCTION_SNAPSHOT", "A receives construction snapshot")
	_assert(bool(replica_a.initialize(packet_a.get("state_bundle", {}), int(packet_a.get("last_event_index", -2))).get("success", false)), "A replica init")
	_assert(bool(replica_b.initialize(packet_b.get("state_bundle", {}), int(packet_b.get("last_event_index", -2))).get("success", false)), "B replica init")
	var session_a: Dictionary = bridge.get_player_session("a")
	var command: Dictionary = Fixture.build_command(session_a, 0, 0, 0, "")
	var submitted: Dictionary = bridge.submit_player_command("a", command)
	_assert(bool(submitted.get("success", false)), "server accepts canonical construction command")
	var event_packet: Dictionary = submitted.get("details", {}).get("event_packet", {})
	_assert(String(event_packet.get("type", "")) == "CONSTRUCTION_EVENT", "server emits construction delta")
	var event: Dictionary = event_packet.get("event", {})
	_assert(bool(replica_a.apply_event(event).get("success", false)), "A applies server event")
	var canonical: Dictionary = env["gateway"].get_state_bundle()
	_assert(replica_a.converged_with(canonical), "authoring replica converges with canonical gateway")
	var graphical_client = GraphicalClientScript.new()
	graphical_client._construction_replica = ReplicaScript.new()
	graphical_client._accept_construction_snapshot(packet_a)
	_assert(int(graphical_client.get_construction_bundle().get("server_generation", -1)) == 0, "pre-event M3 construction snapshot remains initial")
	graphical_client._accept_construction_event(event)
	_assert(String(graphical_client.get_construction_bundle().get("checksum", "")) == String(canonical.get("checksum", "")), "M3 client accepts authoritative construction event")
	graphical_client.free()
	var spoof := command.duplicate(true)
	spoof["client_id"] = "client/m3/b"
	spoof["checksum"] = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd").compute_checksum(spoof)
	var spoofed: Dictionary = bridge.submit_player_command("a", spoof)
	_assert(not bool(spoofed.get("success", true)) and String(spoofed.get("error_code", "")) == "M3_CONSTRUCTION_COMMAND_OWNERSHIP_MISMATCH", "bridge rejects cross-player construction command")
	_assert(bool(bridge.disconnect_player("b").get("success", false)), "B disconnects")
	var rejoined_b: Dictionary = bridge.connect_player("b", 2, -1)
	_assert(bool(rejoined_b.get("success", false)), "B reconnects with new M3 ownership epoch")
	var missing: Array = rejoined_b.get("details", {}).get("events", [])
	_assert(missing.size() == 1 and bool(replica_b.apply_events(missing).get("success", false)), "B catches up through server event history")
	_assert(replica_b.converged_with(canonical), "reconnected B converges")
	_finish()


func _environment() -> Dictionary:
	var geometry_graph := C11Fixture.graph("mvp-m3")
	var damage_snapshot := C9Fixture.snapshot("mvp-m3")
	var items: Array = C3Fixture.source_projections()
	items.append(geometry_graph["root"])
	items.append(geometry_graph["projection"])
	items.append_array(C9Fixture.items("mvp-m3"))
	var adapter = AdapterScript.new()
	var setup: Dictionary = adapter.setup(items, [geometry_graph["snapshot"], damage_snapshot])
	var build_store = BuildStoreScript.new()
	var build_store_setup: Dictionary = build_store.setup()
	var build_process = BuildProcessScript.new()
	var build_setup: Dictionary = build_process.setup(adapter, build_store)
	var build_registration: Dictionary = build_process.register_plan(C3Fixture.build_plan())
	var geometry_process = GeometryProcessScript.new()
	var geometry_setup: Dictionary = geometry_process.setup(adapter, C11Fixture.catalog(), GeometryHistoryScript.new())
	var damage_process = DamageProcessScript.new()
	var damage_setup: Dictionary = damage_process.setup(adapter)
	var executor = ExecutorScript.new()
	var executor_setup: Dictionary = executor.setup(adapter, build_process, geometry_process, damage_process)
	var permissions = PermissionStoreScript.new()
	var permission_setup: Dictionary = permissions.setup(1)
	permissions.publish(GrantScript.create("permission/mvp-m3/a/build", "client/m3/a", "*", [GrantScript.ACTION_BUILD, GrantScript.ACTION_READ], 1))
	permissions.publish(GrantScript.create("permission/mvp-m3/b/build", "client/m3/b", "*", [GrantScript.ACTION_BUILD, GrantScript.ACTION_READ], 1))
	var gateway = GatewayScript.new()
	var gateway_setup: Dictionary = gateway.setup(executor, permissions, SessionStoreScript.new())
	return {"adapter": adapter, "gateway": gateway, "setup": setup, "build_store_setup": build_store_setup, "build_setup": build_setup, "build_registration": build_registration, "geometry_setup": geometry_setup, "damage_setup": damage_setup, "executor_setup": executor_setup, "permission_setup": permission_setup, "gateway_setup": gateway_setup}


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MVP M3 construction replication bridge: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MVP M3 construction replication bridge: FAIL (%d failures)" % failures.size())
	quit(1)
