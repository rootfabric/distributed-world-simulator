extends SceneTree

const GameplayP5 = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"
)
const SM1Coordinator = preload(
	"res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd"
)
const P7Gate = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd"
)
const MW5Fixture = preload(
	"res://tests/matter/persistence/mw5_test_fixture.gd"
)
const MW7Fixture = preload(
	"res://tests/matter/interest/mw7_test_fixture.gd"
)
const AuthorityScript = preload(
	"res://scripts/simulation/matter/network/matter_authoritative_server.gd"
)
const ReplicaScript = preload(
	"res://scripts/simulation/matter/network/matter_replica_client.gd"
)
const GatewayScript = preload(
	"res://scripts/network/loopback/network_command_gateway.gd"
)
const CommandTransportScript = preload(
	"res://scripts/network/loopback/loopback_command_transport.gd"
)
const DirectoryScript = preload(
	"res://scripts/simulation/matter/handoff/matter_authority_directory.gd"
)
const RegionScript = preload(
	"res://scripts/simulation/matter/handoff/matter_authority_region.gd"
)
const RegionalGateScript = preload(
	"res://scripts/simulation/matter/handoff/matter_regional_authority_gate.gd"
)

const PLAYER := "b"
const PLAYER_ENTITY := "player/b"
const GAMEPLAY_SESSION := "transport-session/p7/gameplay/b/1"
const MATTER_SESSION := "session/p7/matter/b/1"
const PEER := "peer/p7/b/1"
const CLIENT := "client/p7/b"
const SLOT := "tool/main"
const TOOL_DEFINITION := "item/tool/mining"
const AUTHORITY_ID := "authority/p7/matter-a"
const TARGET_AUTHORITY_ID := "authority/p7/matter-b"
const AUTHORITY_EPOCH := 1
const REGION_ID := "region/p7/positive"
const CELL_LEVEL := 5

var _assertions := 0
var _failures := 0
var _root_path := ""
var _projection_calls := 0
var _authority = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root_path = ProjectSettings.globalize_path(
		"user://v0-p7-1-tool-mw4-%d" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(_root_path)
	_test_real_p5_sm1_mw8_mw6_mw4_chain()
	if _authority != null and _authority.has_method("shutdown"):
		_assert_success(_authority.shutdown(), "Matter authority shutdown")
	print("V0-P7.1 Tool->MW4 integration: PASS (%d assertions, %d failures)" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _test_real_p5_sm1_mw8_mw6_mw4_chain() -> void:
	var gameplay = GameplayP5.new()
	_assert_success(
		gameplay.setup(AUTHORITY_ID, AUTHORITY_EPOCH),
		"real P5 gameplay setup"
	)
	var joined: Dictionary = gameplay.join(
		PLAYER,
		GAMEPLAY_SESSION,
		"operation/p7/join-b"
	)
	_assert_success(joined, "join real canonical player")
	var player: Dictionary = gameplay.get_player(PLAYER)
	_assert_true(
		String(player.get("player_entity_id", "")) == PLAYER_ENTITY,
		"existing player_entity_id projection"
	)

	var graph = gameplay.get_canonical_item_graph_port()
	_assert_true(graph != null, "real canonical Item Graph port")
	var output: Dictionary = graph.apply_server_output(
		"operation/p7/tool-output-b",
		PLAYER,
		TOOL_DEFINITION,
		1,
		"source/p7/mining-tool"
	)
	_assert_success(output, "create real canonical mining tool")
	var tool_id: String = String(output.get("details", {}).get("output_item_id", ""))
	_assert_true(not tool_id.is_empty(), "real tool item_id exists")
	var ownership_epoch: int = int(
		joined.get("details", {}).get("player", {}).get("ownership_epoch", 1)
	)
	var equip: Dictionary = gameplay.handle_canonical_item_command(
		PLAYER,
		GAMEPLAY_SESSION,
		ownership_epoch,
		"operation/p7/equip-tool",
		"item.equip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(equip, "equip real canonical mining tool")
	_assert_true(
		String(graph.get_equipped_item(PLAYER, SLOT).get("item_id", "")) == tool_id,
		"P7 sees exact equipped item identity"
	)

	var sm1 = SM1Coordinator.new()
	_assert_success(
		sm1.configure(
			AUTHORITY_ID,
			AUTHORITY_EPOCH,
			{
				"logical_player_id": PLAYER,
				"player_entity_id": PLAYER_ENTITY,
				"last_input_sequence": 0,
				"last_operation_id": "",
			}
		),
		"real SM1 one-writer coordinator"
	)

	var matter: Dictionary = _create_matter_authority(gameplay, graph, sm1)
	_assert_success(matter, "compose one real MW6 command gate around MW8")
	if not bool(matter.get("success", false)):
		return
	_authority = matter["authority"]
	var service = matter["context"]["service"]
	var fixtures: Array = matter["fixtures"]
	var replica = matter["replica"]
	var transport = matter["command_transport"]
	var journal = service.mutation_journal()

	var journal_before: int = int(journal.size())
	var stream_before: int = int(_authority.stream_sequence())
	var request: Dictionary = _request(
		service,
		Dictionary(fixtures[0]),
		"operation/p7/matter/committed",
		tool_id
	)
	var committed: Dictionary = _send(replica, transport, request, "message/p7/matter/committed")
	_assert_true(
		String(committed.get("status", "")) == "SUCCEEDED",
		"MW6 accepts P7-authorized command"
	)
	_assert_true(
		int(journal.size()) == journal_before + 1,
		"existing MW4 owns exactly one journal mutation"
	)
	_assert_true(
		int(_authority.stream_sequence()) == stream_before + 1,
		"existing MW6 publishes exactly one Matter outcome"
	)
	_assert_true(_projection_calls == 1, "product position projector called before MW4")

	var unequip: Dictionary = gameplay.handle_canonical_item_command(
		PLAYER,
		GAMEPLAY_SESSION,
		ownership_epoch,
		"operation/p7/unequip-tool",
		"item.unequip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(unequip, "unequip real canonical tool")
	var journal_after_commit: int = int(journal.size())
	var stream_after_commit: int = int(_authority.stream_sequence())
	var missing_request: Dictionary = _request(
		service,
		Dictionary(fixtures[0]),
		"operation/p7/matter/missing-tool",
		tool_id
	)
	var missing: Dictionary = _send(
		replica,
		transport,
		missing_request,
		"message/p7/matter/missing-tool"
	)
	_assert_true(
		String(missing.get("status", "")) == "REJECTED",
		"MW6 rejects missing-tool P7 command"
	)
	_assert_true(
		String(missing.get("error_code", "")) == "P7_MINING_TOOL_REQUIRED",
		"P7 tool error survives MW6 boundary"
	)
	_assert_true(
		int(journal.size()) == journal_after_commit,
		"tool rejection occurs before MW4 journal"
	)
	_assert_true(
		int(_authority.stream_sequence()) == stream_after_commit,
		"tool rejection publishes no Matter delta"
	)

	var reequip: Dictionary = gameplay.handle_canonical_item_command(
		PLAYER,
		GAMEPLAY_SESSION,
		ownership_epoch,
		"operation/p7/reequip-tool",
		"item.equip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(reequip, "re-equip real canonical tool")
	_assert_success(
		sm1.begin_transfer(
			"transfer/p7/freeze",
			AUTHORITY_ID,
			TARGET_AUTHORITY_ID,
			AUTHORITY_EPOCH
		),
		"enter real SM1 transfer gap"
	)
	var frozen_request: Dictionary = _request(
		service,
		Dictionary(fixtures[0]),
		"operation/p7/matter/sm1-frozen",
		tool_id
	)
	var frozen: Dictionary = _send(
		replica,
		transport,
		frozen_request,
		"message/p7/matter/sm1-frozen"
	)
	_assert_true(
		String(frozen.get("status", "")) == "REJECTED",
		"MW6 rejects SM1-frozen P7 command"
	)
	_assert_true(
		String(frozen.get("error_code", "")) == "SM1_AUTHORITY_TRANSFER_WRITE_FENCED",
		"SM1 one-writer error survives MW6 boundary"
	)
	_assert_true(
		int(journal.size()) == journal_after_commit,
		"SM1 rejection occurs before MW4 journal"
	)
	_assert_true(
		int(_authority.stream_sequence()) == stream_after_commit,
		"SM1 rejection publishes no Matter delta"
	)

	var report: Dictionary = matter["gate"].contract_report()
	_assert_true(
		not bool(report.get("canonical_state_owned", true)),
		"P7 gate owns zero canonical state"
	)
	_assert_true(
		not bool(report.get("replay_ledger_owned", true)),
		"P7 gate owns zero replay ledger"
	)


func _create_matter_authority(gameplay, graph, sm1) -> Dictionary:
	var context: Dictionary = MW5Fixture.create_context(_root_path.path_join("matter"))
	if not bool(context.get("success", false)):
		return context
	var fixtures: Array[Dictionary] = MW7Fixture.nearby_fixtures(
		{"context": context},
		Vector3.RIGHT,
		1,
		6
	)
	if fixtures.is_empty():
		return _failure("P7_TEST_MATTER_FIXTURE_MISSING")

	var region: Dictionary = RegionScript.create(
		REGION_ID,
		String(context["body"]["body_id"]),
		CELL_LEVEL,
		fixtures[0]["address"]["cell_address"],
		1
	)
	var directory = DirectoryScript.new()
	var directory_setup: Dictionary = directory.configure(
		String(context["body"]["body_id"]),
		context["grid_profile"]
	)
	if not bool(directory_setup.get("success", false)):
		return directory_setup
	var registered: Dictionary = directory.register_region(
		region,
		AUTHORITY_ID,
		AUTHORITY_EPOCH
	)
	if not bool(registered.get("success", false)):
		return registered

	var regional_gate = RegionalGateScript.new()
	var regional_setup: Dictionary = regional_gate.configure(
		AUTHORITY_ID,
		AUTHORITY_EPOCH,
		directory
	)
	if not bool(regional_setup.get("success", false)):
		return regional_setup

	var authority = AuthorityScript.new()
	var authority_setup: Dictionary = authority.configure(
		context["body"],
		context["grid_profile"],
		context["service"],
		AUTHORITY_ID,
		AUTHORITY_EPOCH,
		64
	)
	if not bool(authority_setup.get("success", false)):
		return authority_setup

	var gate = P7Gate.new()
	var gate_setup: Dictionary = gate.configure(
		gameplay,
		graph,
		sm1,
		regional_gate,
		AUTHORITY_ID,
		AUTHORITY_EPOCH,
		5.0,
		Callable(self, "_project_player_into_matter_frame")
	)
	if not bool(gate_setup.get("success", false)):
		return gate_setup
	var gate_registered: Dictionary = authority.set_command_authority_gate(gate)
	if not bool(gate_registered.get("success", false)):
		return gate_registered

	var gateway = GatewayScript.new()
	gateway.setup(AUTHORITY_EPOCH)
	var gateway_registered: Dictionary = authority.register_gateway(gateway)
	if not bool(gateway_registered.get("success", false)):
		return gateway_registered
	var command_transport = CommandTransportScript.new()
	command_transport.setup(gateway)

	var replica = ReplicaScript.new()
	var replica_setup: Dictionary = replica.configure(
		context["body"],
		context["grid_profile"],
		AUTHORITY_ID,
		AUTHORITY_EPOCH,
		CLIENT
	)
	if not bool(replica_setup.get("success", false)):
		return replica_setup
	var activated: Dictionary = replica.activate_session(PEER, MATTER_SESSION)
	if not bool(activated.get("success", false)):
		return activated
	var sync_request: Dictionary = replica.create_sync_request()
	var connected: Dictionary = authority.connect_peer(
		PEER,
		CLIENT,
		MATTER_SESSION,
		PLAYER_ENTITY,
		sync_request
	)
	if not bool(connected.get("success", false)):
		return connected

	return {
		"success": true,
		"error_code": "",
		"context": context,
		"fixtures": fixtures,
		"directory": directory,
		"regional_gate": regional_gate,
		"authority": authority,
		"gate": gate,
		"gateway": gateway,
		"command_transport": command_transport,
		"replica": replica,
	}


func _request(
	service,
	fixture: Dictionary,
	operation_id: String,
	tool_id: String
) -> Dictionary:
	return service.create_excavation_request(
		operation_id,
		PLAYER_ENTITY,
		tool_id,
		fixture["start_m"],
		fixture["end_m"],
		float(fixture["radius_m"]),
		MW5Fixture.JSON_SAFE_ENERGY_BUDGET_J,
		701
	)


func _send(
	replica,
	command_transport,
	request: Dictionary,
	message_id: String
) -> Dictionary:
	var command: Dictionary = replica.create_mutation_command(request, message_id)
	if command.is_empty():
		return {"status": "REJECTED", "error_code": "P7_TEST_COMMAND_BUILD_FAILED"}
	var wire: Dictionary = command_transport.send(command)
	if not bool(wire.get("success", false)):
		return {
			"status": "REJECTED",
			"error_code": String(wire.get("error_code", "P7_TEST_TRANSPORT_FAILED")),
		}
	return Dictionary(wire.get("result", {}))


func _project_player_into_matter_frame(
	player: Dictionary,
	request: Dictionary
) -> Dictionary:
	_projection_calls += 1
	_assert_true(
		String(player.get("player_entity_id", "")) == PLAYER_ENTITY,
		"projector receives canonical player"
	)
	var shape: Dictionary = request.get("shape", {})
	return {
		"success": true,
		"error_code": "",
		"position_m": Array(shape.get("start_position_m", [])).duplicate(),
	}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.1 integration] %s" % message)
