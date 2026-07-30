extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const H1Authority = preload("res://scripts/runtime/listen_host/playable_listen_host_authority.gd")
const H2Registry = preload("res://scripts/runtime/host_client/player_ownership_registry.gd")
const H3Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")
const StateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_manifest()
	_test_topology_neutral_canonical_state()
	_test_compatibility_adapters()
	_test_source_convergence()
	_finish()


func _test_manifest() -> void:
	var text: String = FileAccess.get_file_as_string("res://config/network/networked-gameplay-core.v1.json")
	var manifest = JSON.parse_string(text)
	_assert(manifest is Dictionary, "M1 manifest is invalid")
	if not manifest is Dictionary:
		return
	_assert(String(manifest.get("schema", "")) == "planet_simulator.networked_gameplay_core.v1", "M1 manifest schema mismatch")
	_assert(String(manifest.get("checkpoint", "")) == "v16.10.0-runtime-m1-unified-networked-gameplay-core", "M1 checkpoint mismatch")
	_assert(String(manifest.get("build_id", "")) == "m1-unified-networked-gameplay-core", "M1 build ID mismatch")
	_assert(String(manifest.get("status", "")) == "candidate", "M1 status must remain candidate before independent acceptance")
	_assert(String(manifest.get("decision", "")) == "UNIFIED_NETWORKED_GAMEPLAY_CORE", "M1 decision mismatch")
	var component_names: Array[String] = []
	for value in manifest.get("components", []):
		if value is Dictionary:
			component_names.append(String(value.get("name", "")))
	for required in ["PlayerRegistry", "PlayerOwnershipService", "PlayerMovementService", "ItemGraphService", "ContainerInteractionService", "MountInteractionService", "CommandResultRouter", "ReplicationPublisher"]:
		_assert(required in component_names, "M1 component missing from manifest: %s" % required)
	var contract_names: Array[String] = []
	for value in manifest.get("wire_contracts", []):
		if value is Dictionary:
			contract_names.append(String(value.get("name", "")))
	_assert(contract_names.size() == 10, "M1 must publish ten shared wire contracts")
	for required in ["PlayerJoinCommand", "PlayerLeaveCommand", "PlayerInputCommand", "PlayerOwnershipSnapshot", "PlayerStateSnapshot", "PlayerStateDelta", "ItemCommand", "ItemGraphSnapshot", "ItemGraphDelta", "CommandResult"]:
		_assert(required in contract_names, "M1 wire contract missing from manifest: %s" % required)
	var closure: Dictionary = manifest.get("debt_closure", {})
	for debt_id in ["A2-D01", "A2-D02"]:
		_assert(String(closure.get(debt_id, {}).get("status", "")) == "closed", "%s is not closed by M1" % debt_id)
	for debt_id in ["A2-D03", "A2-D04"]:
		_assert(String(closure.get(debt_id, {}).get("status", "")) == "open", "%s must remain open after M1" % debt_id)
	_assert(String(manifest.get("next_checkpoint", "")) == "v16.10.1-runtime-m2-dedicated-graphical-client", "M2 next checkpoint mismatch")

func _test_topology_neutral_canonical_state() -> void:
	var loopback := Service.new()
	var enet := Service.new()
	var common: Dictionary = {"profile": Service.PROFILE_MULTIPLAYER_CORE, "region_id": "region/m1/convergence"}
	var loopback_config: Dictionary = common.duplicate(true); loopback_config["topology_adapter"] = "LOOPBACK"
	var enet_config: Dictionary = common.duplicate(true); enet_config["topology_adapter"] = "ENET"
	_assert(_ok(loopback.setup("simulation/m1/convergence", 9, 500, loopback_config)), "loopback service setup")
	_assert(_ok(enet.setup("simulation/m1/convergence", 9, 500, enet_config)), "ENet service setup")
	_run_common_scenario(loopback)
	_run_common_scenario(enet)
	var loopback_snapshot: Dictionary = loopback.create_snapshot()
	var enet_snapshot: Dictionary = enet.create_snapshot()
	_assert(String(loopback_snapshot.get("checksum", "")) == String(enet_snapshot.get("checksum", "")), "topology changed canonical checksum")
	_assert(Utils.canonical_json(loopback_snapshot) == Utils.canonical_json(enet_snapshot), "topology changed canonical state")
	_assert(String(loopback.get_report().get("topology_adapter", "")) == "LOOPBACK", "loopback adapter identity missing")
	_assert(String(enet.get_report().get("topology_adapter", "")) == "ENET", "ENet adapter identity missing")
	_assert(String(loopback.get_report().get("schema", "")) == Service.SCHEMA, "loopback did not use NetworkedGameplayService")
	_assert(String(enet.get_report().get("schema", "")) == Service.SCHEMA, "ENet did not use NetworkedGameplayService")
	var replay: Dictionary = loopback.move_player("a", "transport-session/m1/a/2", 2, 2, 0.0, 1.0, "operation/m1/a/move/2")
	_assert(_ok(replay) and bool(replay.get("details", {}).get("replay", false)), "common service exact replay failed")
	var conflict: Dictionary = loopback.move_player("b", "transport-session/m1/b/1", 1, 3, 1.0, 0.0, "operation/m1/a/move/2")
	_assert(_error(conflict) == "OPERATION_REPLAY_CONFLICT", "common service replay conflict not fenced")

func _run_common_scenario(service) -> void:
	_assert(_ok(service.join("a", "transport-session/m1/a/1", "operation/m1/a/join/1")), "player A join")
	_assert(_ok(service.join("b", "transport-session/m1/b/1", "operation/m1/b/join/1")), "player B join")
	_assert(_ok(service.move_player("a", "transport-session/m1/a/1", 1, 1, 1.0, 0.5, "operation/m1/a/move/1")), "player A move")
	_assert(_ok(service.move_player("b", "transport-session/m1/b/1", 1, 1, -1.0, -0.5, "operation/m1/b/move/1")), "player B move")
	_assert(_ok(service.pickup_shared_item("a", "transport-session/m1/a/1", 1, Service.SHARED_ITEM_ID, "operation/m1/a/pickup/1")), "shared item pickup")
	_assert(_error(service.pickup_shared_item("b", "transport-session/m1/b/1", 1, Service.SHARED_ITEM_ID, "operation/m1/b/pickup/1")) == "ITEM_ALREADY_CLAIMED", "contention rejection")
	_assert(_ok(service.leave("a", "transport-session/m1/a/1", "operation/m1/a/leave/1")), "player A leave")
	_assert(_ok(service.move_player("b", "transport-session/m1/b/1", 1, 2, 0.0, 1.0, "operation/m1/b/move/2")), "player B continues")
	var rejoin: Dictionary = service.join("a", "transport-session/m1/a/2", "operation/m1/a/join/2")
	_assert(_ok(rejoin), "player A rejoin")
	_assert(int(rejoin.get("details", {}).get("player", {}).get("ownership_epoch", 0)) == 2, "ownership epoch did not increment")
	_assert(_ok(service.move_player("a", "transport-session/m1/a/2", 2, 2, 0.0, 1.0, "operation/m1/a/move/2")), "player A post-reconnect move")

func _test_compatibility_adapters() -> void:
	var h2 := H2Registry.new()
	_assert(_ok(h2.setup("simulation/m1/h2", 2, 10)), "H2 adapter setup")
	_assert(_ok(h2.join("remote", "transport-session/m1/h2/remote/1", "operation/m1/h2/join/1")), "H2 adapter join")
	_assert(String(h2.get_player_ownership_service_for_tests().get_report().get("schema", "")) == "planet_simulator.player_ownership_service.v1", "H2 adapter bypasses common ownership service")
	var h3 := H3Authority.new()
	_assert(_ok(h3.setup("simulation/m1/h3", 3, 20)), "H3 adapter setup")
	_assert(_ok(h3.join("a", "transport-session/m1/h3/a/1", "operation/m1/h3/join/1")), "H3 adapter join")
	_assert(String(h3.get_networked_gameplay_service_for_tests().get_report().get("schema", "")) == Service.SCHEMA, "H3 adapter bypasses common gameplay service")
	var h1 := H1Authority.new()
	var h1_setup: Dictionary = h1.setup({
		"authority_owner_id": "simulation/m1/h1", "authority_epoch": 4, "server_tick": 30,
		"session_id": "session/m1/h1/1", "player_state": _initial_player_state(),
		"item_persistence_enabled": false, "include_demo_world": false,
	})
	_assert(_ok(h1_setup), "H1 adapter setup")
	var h1_service = h1.get_networked_gameplay_service_for_tests()
	_assert(h1_service != null, "H1 adapter did not expose common service in test boundary")
	_assert(String(h1_service.get_report().get("schema", "")) == Service.SCHEMA, "H1 adapter bypasses common gameplay service")
	_assert(String(h1_service.get_report().get("profile", "")) == Service.PROFILE_CANONICAL_PLAYABLE, "H1 canonical profile missing")
	_assert(h1.create_initial_snapshots().size() == 2, "H1 adapter lost canonical snapshots")
	var report: Dictionary = h1_service.get_report()
	_assert(String(report.get("item_graph_service", {}).get("schema", "")) == "planet_simulator.item_graph_service.v1", "ItemGraphService is not active in canonical profile")
	_assert(String(report.get("container_interaction_service", {}).get("schema", "")) == "planet_simulator.container_interaction_service.v1", "ContainerInteractionService is not active in canonical profile")
	_assert(String(report.get("mount_interaction_service", {}).get("schema", "")) == "planet_simulator.mount_interaction_service.v1", "MountInteractionService is not active in canonical profile")
	h1.shutdown(); h1.free()

func _test_source_convergence() -> void:
	var h1_source: String = FileAccess.get_file_as_string("res://scripts/runtime/listen_host/playable_listen_host_authority.gd")
	var h2_source: String = FileAccess.get_file_as_string("res://scripts/runtime/host_client/player_ownership_registry.gd")
	var h3_source: String = FileAccess.get_file_as_string("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")
	for source in [h1_source, h3_source]:
		_assert(source.contains("networked_gameplay_service.gd"), "authority adapter does not preload NetworkedGameplayService")
		_assert(not source.contains("var _players: Dictionary"), "authority adapter retains independent player state")
		_assert(not source.contains("_operation_ledger"), "authority adapter retains independent operation ledger")
	_assert(h2_source.contains("player_ownership_service.gd"), "H2 adapter does not use common PlayerOwnershipService")
	var service_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
	for component in ["PlayerRegistry", "OwnershipService", "MovementService", "ItemGraphService", "ContainerInteractionService", "MountInteractionService", "ResultRouter", "ReplicationPublisher"]:
		_assert(service_source.contains(component), "NetworkedGameplayService missing component %s" % component)
	_assert(service_source.contains("CanonicalPlayableBackend"), "canonical Item Graph backend not composed by common service")

func _initial_player_state() -> Dictionary:
	return StateCodec.create_player_state(Vector3(0.0, 1737401.0, 0.0), Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, "lunar_humanoid", "first_person", false, 0, "body/moon/fixed", "main", "moon", "m1-service", 0.0)

func _ok(value: Dictionary) -> bool: return bool(value.get("success", false))
func _error(value: Dictionary) -> String: return String(value.get("error_code", ""))
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("M1 unified NetworkedGameplayService: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("M1 unified NetworkedGameplayService: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
