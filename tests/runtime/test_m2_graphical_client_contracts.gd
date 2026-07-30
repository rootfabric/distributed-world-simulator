extends SceneTree

const RuntimeRole = preload("res://scripts/runtime/runtime_role.gd")
const LaunchOptions = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptor = preload("res://scripts/runtime/runtime_descriptor.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/transports/m2_process_support.gd")
const CommandTransport = preload("res://scripts/runtime/networked_gameplay/transports/enet_command_transport_adapter.gd")
const DedicatedRuntime = preload("res://scripts/runtime/networked_gameplay/transports/dedicated_gameplay_server_runtime.gd")
const GraphicalRuntime = preload("res://scripts/runtime/networked_gameplay/transports/graphical_game_client_runtime.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

class FakeRemoteRuntime:
	extends RefCounted
	var commands: Array[Dictionary] = []
	func send_command_blocking(command: Dictionary) -> Dictionary:
		commands.append(command.duplicate(true))
		return {"success": true, "error_code": "", "result": {"status": "SUCCEEDED"}}

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_roles()
	_test_launch_options()
	_test_runtime_descriptor()
	_test_command_transport()
	_test_runtime_validation()
	_test_snapshot_normalization_stability()
	_test_manifest()
	_test_source_boundaries()
	_finish()


func _test_roles() -> void:
	_assert(RuntimeRole.is_supported(RuntimeRole.GAME_CLIENT), "game-client role supported")
	_assert(RuntimeRole.is_supported(RuntimeRole.DEDICATED_SERVER), "dedicated-server role supported")
	_assert(RuntimeRole.presentation_enabled(RuntimeRole.GAME_CLIENT), "game-client presentation enabled")
	_assert(RuntimeRole.accepts_local_input(RuntimeRole.GAME_CLIENT), "game-client local input enabled")
	_assert(not RuntimeRole.is_authoritative(RuntimeRole.GAME_CLIENT), "game-client is not authoritative")
	_assert(not RuntimeRole.presentation_enabled(RuntimeRole.DEDICATED_SERVER), "dedicated presentation disabled")
	_assert(not RuntimeRole.accepts_local_input(RuntimeRole.DEDICATED_SERVER), "dedicated input disabled")
	_assert(RuntimeRole.is_authoritative(RuntimeRole.DEDICATED_SERVER), "dedicated server authoritative")
	var client := RuntimeRole.describe(RuntimeRole.GAME_CLIENT)
	_assert(bool(client.get("remote_game_client", false)), "game-client remote descriptor")
	_assert(bool(client.get("client_replica_enabled", false)), "game-client replica enabled")
	_assert(not bool(client.get("embedded_authority", true)), "game-client has no embedded authority")
	_assert(not bool(client.get("direct_client_domain_access_allowed", true)), "game-client direct domain access forbidden")
	var server := RuntimeRole.describe(RuntimeRole.DEDICATED_SERVER)
	_assert(bool(server.get("dedicated_authority", false)), "dedicated authority descriptor")
	_assert(not bool(server.get("client_replica_enabled", true)), "dedicated has no client replica")


func _test_launch_options() -> void:
	var parsed := LaunchOptions.parse(PackedStringArray([
		"--role=game-client",
		"--world=moon",
		"--server-address=10.1.2.3",
		"--server-port=27555",
		"--player-identity=Local-Astronaut",
		"--connect-timeout-ms=45000",
		"--command-timeout-ms=8000",
		"--m2-result-file=C:/temp/m2.json",
		"--m2-phase=2",
		"--m2-expected-state-file=C:/temp/m2-phase1.json",
	]))
	_assert(bool(parsed.get("success", false)), "game-client options parse")
	var options: Dictionary = parsed.get("options", {})
	_assert(String(options.get("role", "")) == RuntimeRole.GAME_CLIENT, "game-client role parsed")
	_assert(String(options.get("server_address", "")) == "10.1.2.3", "server address parsed")
	_assert(int(options.get("server_port", 0)) == 27555, "server port parsed")
	_assert(String(options.get("player_identity", "")) == "local-astronaut", "identity normalized")
	_assert(int(options.get("connect_timeout_ms", 0)) == 45000, "connect timeout parsed")
	_assert(int(options.get("command_timeout_ms", 0)) == 8000, "command timeout parsed")
	_assert(int(options.get("m2_phase", 0)) == 2, "M2 phase parsed")
	_assert(not String(options.get("m2_result_file", "")).is_empty(), "M2 report path parsed")
	_assert(not String(options.get("m2_expected_state_file", "")).is_empty(), "M2 expected state parsed")
	var dedicated := LaunchOptions.parse(PackedStringArray([
		"--role=dedicated-server", "--server-address=127.0.0.1", "--server-port=24580"
	]))
	_assert(bool(dedicated.get("success", false)), "dedicated options parse")
	var invalid_port := LaunchOptions.parse(PackedStringArray([
		"--role=game-client", "--server-port=0"
	]))
	_assert(not bool(invalid_port.get("success", true)), "invalid game-client port rejected")
	var invalid_identity := LaunchOptions.parse(PackedStringArray([
		"--role=game-client", "--player-identity="
	]))
	_assert(not bool(invalid_identity.get("success", true)), "empty graphical identity rejected")


func _test_runtime_descriptor() -> void:
	var client := RuntimeDescriptor.create({
		"role": RuntimeRole.GAME_CLIENT,
		"world": "moon",
		"node_id": "local-game-client",
		"instance_id": "persistent",
		"space_id": "moon",
		"server_address": "127.0.0.1",
		"server_port": 24580,
		"player_identity": "local-astronaut",
	}, {"checkpoint": Support.CHECKPOINT, "build_id": Support.BUILD_ID})
	_assert(bool(RuntimeDescriptor.validate(client).get("success", false)), "game-client descriptor valid")
	_assert(String(client.get("checkpoint", "")) == Support.CHECKPOINT, "descriptor checkpoint")
	_assert(String(client.get("build_id", "")) == Support.BUILD_ID, "descriptor build")
	_assert(bool(client.get("presentation_enabled", false)), "descriptor presentation")
	_assert(bool(client.get("local_input_enabled", false)), "descriptor input")
	_assert(not bool(client.get("authoritative", true)), "descriptor non-authoritative")
	_assert(bool(client.get("remote_game_client", false)), "descriptor remote client")
	_assert(not bool(client.get("embedded_authority", true)), "descriptor no embedded authority")
	var server := RuntimeDescriptor.create({
		"role": RuntimeRole.DEDICATED_SERVER,
		"world": "moon",
		"node_id": "local-dedicated-server",
		"instance_id": "persistent",
		"space_id": "moon",
	}, {"checkpoint": Support.CHECKPOINT, "build_id": Support.BUILD_ID})
	_assert(bool(RuntimeDescriptor.validate(server).get("success", false)), "dedicated descriptor valid")
	_assert(bool(server.get("authoritative", false)), "dedicated descriptor authoritative")
	_assert(bool(server.get("dedicated_authority", false)), "dedicated descriptor flag")
	_assert(not bool(server.get("presentation_enabled", true)), "dedicated descriptor presentation-free")


func _test_command_transport() -> void:
	var transport = CommandTransport.new()
	_assert(not bool(transport.send({}).get("success", true)), "unconfigured ENet command transport rejected")
	_assert(String(transport.setup(null).get("error_code", "")) == "ENET_COMMAND_RUNTIME_REQUIRED", "runtime required")
	var remote := FakeRemoteRuntime.new()
	_assert(bool(transport.setup(remote).get("success", false)), "command transport setup")
	_assert(String(transport.setup(remote).get("error_code", "")) == "ENET_COMMAND_TRANSPORT_ALREADY_CONFIGURED", "double setup rejected")
	var result := transport.send({"operation_id": "operation/m2/contract/1"})
	_assert(bool(result.get("success", false)), "command forwarded")
	_assert(remote.commands.size() == 1, "exactly one remote command")
	_assert(String(remote.commands[0].get("operation_id", "")) == "operation/m2/contract/1", "command payload preserved")
	var report := transport.get_report()
	_assert(int(report.get("commands_sent", 0)) == 1, "command metric")
	_assert(int(report.get("failures", -1)) == 0, "failure metric")
	_assert(int(report.get("direct_authority_references", 1)) == 0, "no authority reference")
	_assert(int(report.get("direct_domain_references", 1)) == 0, "no domain reference")
	transport.invalidate()
	_assert(not bool(transport.get_report().get("configured", true)), "transport invalidated")


func _test_runtime_validation() -> void:
	var server = DedicatedRuntime.new()
	_assert(String(server.setup({"host": "", "port": 1}).get("error_code", "")) == "INVALID_DEDICATED_SERVER_ENDPOINT", "dedicated endpoint validation")
	var client = GraphicalRuntime.new()
	_assert(String(client.setup({"host": "", "port": 1}).get("error_code", "")) == "INVALID_GAME_CLIENT_ENDPOINT", "client endpoint validation")
	_assert(String(client.setup({
		"host": "127.0.0.1", "port": 24580, "logical_player_id": "", "connect_timeout_ms": 15000, "command_timeout_ms": 5000,
	}).get("error_code", "")) == "INVALID_GAME_CLIENT_CONFIGURATION", "client identity validation")
	_assert(Support.CHECKPOINT == "v16.10.1-runtime-m2-dedicated-graphical-client", "M2 checkpoint identity")
	_assert(Support.BUILD_ID == "m2-dedicated-graphical-client", "M2 build identity")
	_assert(String(Support.endpoint("127.0.0.1", 24580).get("transport", "")) == "ENET", "M2 endpoint uses ENet")
	server.free()
	client.free()


func _test_snapshot_normalization_stability() -> void:
	var spatial_ref := {
		"schema": "planet_simulator.spatial_ref.v1",
		"universe_id": "main",
		"instance_id": "persistent",
		"space_id": "moon",
		"frame_id": "body/moon/fixed",
		"position_m": [-131761.90865596333, 1424504.4587210575, 987714.1841480376],
		"rotation_xyzw": [
			0.2972437435055665,
			0.01371774865077593,
			0.04401254223585175,
			0.953688039373824,
		],
		"linear_velocity_mps": [0.0, 0.0, 0.0],
		"angular_velocity_rps": [0.0, 0.0, 0.0],
		"sample_time_s": 0.0,
	}
	var snapshot := EntitySnapshot.create(
		"snapshot/m2/normalization",
		"player/local-astronaut",
		"player",
		0,
		"local-dedicated-server",
		1,
		0,
		spatial_ref,
		{},
		{},
		{"player_state": {
			"schema": "planet_simulator.playable_player_state.v1",
			"spatial_ref": spatial_ref.duplicate(true),
			"interaction_position_m": [513.461682348192, 142.814503222937, -107.948182944674],
			"controller_id": "lunar_humanoid",
			"camera_mode": "first_person",
			"flashlight_enabled": false,
			"last_input_sequence": 0,
		}}
	)
	_assert(bool(EntitySnapshot.validate(snapshot).get("success", false)), "adversarial M2 snapshot starts valid")
	var normalized := EntitySnapshot.normalize(snapshot)
	_assert(bool(EntitySnapshot.validate(normalized).get("success", false)), "normalized M2 snapshot checksum remains valid")
	var normalized_again := EntitySnapshot.normalize(normalized)
	_assert(bool(EntitySnapshot.validate(normalized_again).get("success", false)), "re-normalized M2 snapshot remains valid")
	_assert(normalized_again == normalized, "snapshot normalization is idempotent for arbitrary player orientation")


func _test_manifest() -> void:
	var manifest := _load_json("res://config/network/dedicated-graphical-client.v1.json")
	_assert(String(manifest.get("schema", "")) == "planet_simulator.dedicated_graphical_client.v1", "M2 manifest schema")
	_assert(String(manifest.get("checkpoint", "")) == Support.CHECKPOINT, "M2 manifest checkpoint")
	_assert(String(manifest.get("build_id", "")) == Support.BUILD_ID, "M2 manifest build")
	_assert(String(manifest.get("status", "")) == "accepted_with_gates", "M2 manifest accepted-with-gates status")
	_assert(String(manifest.get("base_checkpoint", "")) == "v16.10.0-runtime-m1-unified-networked-gameplay-core", "M2 manifest M1 base")
	_assert(int(manifest.get("verified_evidence", {}).get("graphical_process_assertions", 0)) == 70, "M2 corrected process assertion count")
	_assert(int(manifest.get("verified_evidence", {}).get("focused_assertions", 0)) == 1052, "M2 corrected focused assertion count")
	var topology: Dictionary = manifest.get("topology", {})
	_assert(String(topology.get("transport", "")) == "ENet", "M2 graphical transport policy")
	_assert(String(topology.get("gameplay_service", "")) == "NetworkedGameplayService", "M2 unified gameplay service")
	_assert(not bool(topology.get("client_process", {}).get("headless", true)), "M2 client process is graphical")
	_assert(not bool(topology.get("client_process", {}).get("embedded_authority", true)), "M2 client has no embedded authority")
	var boundary: Dictionary = manifest.get("client_boundary", {})
	_assert(int(boundary.get("authority_references", 1)) == 0, "M2 manifest authority boundary")
	_assert(int(boundary.get("domain_references", 1)) == 0, "M2 manifest domain boundary")
	_assert(not bool(boundary.get("local_character_physics_authority", true)), "M2 local player is replica-driven")
	var reconnect: Dictionary = manifest.get("reconnect_contract", {})
	_assert(bool(reconnect.get("same_player_entity", false)), "M2 reconnect stable entity")
	_assert(bool(reconnect.get("ownership_epoch_advances", false)), "M2 reconnect ownership fencing")
	_assert(String(manifest.get("next_checkpoint", "")) == "v16.10.2-runtime-m3-dedicated-graphical-multiplayer", "M3 next checkpoint")
	_assert(FileAccess.file_exists("res://docs/architecture/M2_DEDICATED_GRAPHICAL_CLIENT_RU.md"), "M2 architecture document")
	_assert(FileAccess.file_exists("res://docs/architecture/adr/ADR-014-dedicated-graphical-client.md"), "M2 ADR")


func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}


func _test_source_boundaries() -> void:
	var client_source := _read("res://scripts/runtime/networked_gameplay/transports/graphical_game_client_runtime.gd")
	var server_source := _read("res://scripts/runtime/networked_gameplay/transports/dedicated_gameplay_server_runtime.gd")
	var app_source := _read("res://scripts/app/simulator_app.gd")
	var world_source := _read("res://scripts/app/lunar_app.gd")
	var player_source := _read("res://scripts/actors/player/lunar_player.gd")
	var acceptance_source := _read("res://scripts/runtime/networked_gameplay/m2_graphical_acceptance_driver.gd")
	_assert(client_source.contains("enet_multi_peer_transport_port.gd"), "graphical runtime uses ENet port")
	_assert(client_source.contains("playable_client_session.gd"), "graphical runtime composes replica session")
	_assert(client_source.contains("_retry_connection"), "graphical runtime retries initial ENet connection")
	_assert(client_source.contains("direct_authority_references\": 0"), "graphical report forbids authority refs")
	_assert(not client_source.contains("playable_listen_host_authority.gd"), "graphical runtime does not preload H1 authority")
	_assert(not client_source.contains("networked_gameplay_service.gd"), "graphical runtime does not preload gameplay service")
	_assert(server_source.contains("networked_gameplay_service.gd"), "dedicated runtime uses unified M1 service")
	_assert(server_source.contains("topology_adapter\"] = \"ENET\""), "dedicated runtime selects ENet topology")
	_assert(server_source.contains("flush_outbound"), "dedicated results are dispatched")
	_assert(app_source.contains("RuntimeRoleScript.GAME_CLIENT"), "simulator composes game-client")
	_assert(app_source.contains("RuntimeRoleScript.DEDICATED_SERVER"), "simulator composes dedicated server")
	_assert(world_source.contains("set_network_replica_mode(true)"), "world makes graphical player replica-driven")
	_assert(world_source.contains("operation/m2/player/%d/%d"), "graphical movement operation IDs survive reconnect")
	_assert(player_source.contains("network_replica_mode"), "LunarPlayer has replica mode")
	_assert(player_source.contains("not network_replica_mode"), "replica mode disables local physics authority")
	_assert(acceptance_source.contains("DisplayServer.get_name"), "acceptance verifies graphical display")
	_assert(acceptance_source.contains("active_camera"), "acceptance verifies real player camera")
	_assert(acceptance_source.contains("request_graceful_leave"), "acceptance verifies graceful disconnect")


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("M2 graphical client contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("M2 graphical client contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
