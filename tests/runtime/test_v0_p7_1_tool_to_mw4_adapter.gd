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
const MW8Fixture = preload(
	"res://tests/matter/handoff/mw8_test_fixture.gd"
)
const MatterUtils = preload(
	"res://scripts/simulation/matter/matter_contract_utils.gd"
)

const PLAYER := "b"
const PLAYER_ENTITY := "player/b"
const SESSION := "transport-session/p7/b/1"
const PEER := "peer/p7/b/1"
const CLIENT := "client/p7/b"
const SLOT := "tool/main"
const TOOL_DEFINITION := "item/tool/mining"

var _assertions := 0
var _failures := 0
var _root_path := ""
var _cluster: Dictionary = {}
var _projection_calls := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root_path = ProjectSettings.globalize_path(
		"user://v0-p7-1-tool-mw4-%d" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(_root_path)
	_test_real_p5_sm1_mw8_mw6_mw4_chain()
	if not _cluster.is_empty():
		var shutdown := MW8Fixture.shutdown_cluster(_cluster)
		_assert_success(shutdown, "MW8 cluster shutdown")
	print("V0-P7.1 Tool->MW4 integration: PASS (%d assertions, %d failures)" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _test_real_p5_sm1_mw8_mw6_mw4_chain() -> void:
	_cluster = MW8Fixture.create_cluster(_root_path)
	_assert_success(_cluster, "MW8 real cluster")
	if not bool(_cluster.get("success", false)):
		return

	var gameplay = GameplayP5.new()
	_assert_success(
		gameplay.setup(MW8Fixture.SOURCE_OWNER_ID, MW8Fixture.SOURCE_EPOCH),
		"real P5 gameplay setup"
	)
	var joined: Dictionary = gameplay.join(
		PLAYER,
		SESSION,
		"operation/p7/join-b"
	)
	_assert_success(joined, "join real canonical player")
	var player: Dictionary = gameplay.get_player(PLAYER)
	_assert_true(String(player.get("player_entity_id", "")) == PLAYER_ENTITY, "existing player_entity_id projection")

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
	var tool_id := String(output.get("details", {}).get("output_item_id", ""))
	_assert_true(not tool_id.is_empty(), "real tool item_id exists")
	var ownership_epoch := int(joined.get("details", {}).get("player", {}).get("ownership_epoch", 1))
	var equip: Dictionary = gameplay.handle_canonical_item_command(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p7/equip-tool",
		"item.equip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(equip, "equip real canonical mining tool")
	_assert_true(String(graph.get_equipped_item(PLAYER, SLOT).get("item_id", "")) == tool_id, "P7 sees exact equipped item identity")

	var sm1 = SM1Coordinator.new()
	_assert_success(
		sm1.configure(
			MW8Fixture.SOURCE_OWNER_ID,
			MW8Fixture.SOURCE_EPOCH,
			{
				"logical_player_id": PLAYER,
				"player_entity_id": PLAYER_ENTITY,
				"last_input_sequence": 0,
				"last_operation_id": "",
			}
		),
		"real SM1 one-writer coordinator"
	)

	var gate = P7Gate.new()
	_assert_success(
		gate.configure(
			gameplay,
			graph,
			sm1,
			_cluster["source"]["gate"],
			MW8Fixture.SOURCE_OWNER_ID,
			MW8Fixture.SOURCE_EPOCH,
			5.0,
			Callable(self, "_project_player_into_matter_frame")
		),
		"configure P7 gate over real owners"
	)
	_assert_success(
		_cluster["source"]["authority"].set_command_authority_gate(gate),
		"bind P7 gate to real MW6 Matter authority"
	)

	var replica = MW8Fixture.create_replica(_cluster, "source", CLIENT)
	_assert_true(replica != null, "create real MW8/MW7 Matter replica")
	if replica == null:
		return
	_assert_success(
		MW8Fixture.connect_replica(
			_cluster, "source", replica, PEER, "session/p7/matter/b/1", PLAYER_ENTITY
		),
		"connect Matter replica with canonical player_entity_id"
	)

	var fixture: Dictionary = _cluster["fixtures"][0]
	var journal = _cluster["source_context"]["service"].mutation_journal()
	var journal_before: int = int(journal.size())
	var stream_before: int = int(_cluster["source"]["authority"].stream_sequence())
	var request := _request_with_tool(
		fixture,
		"operation/p7/matter/committed",
		tool_id
	)
	var committed := _send(replica, request, "message/p7/matter/committed")
	_assert_true(String(committed.get("status", "")) == "SUCCEEDED", "MW6 accepts P7-authorized command")
	_assert_true(journal.size() == journal_before + 1, "existing MW4 owns exactly one journal mutation")
	_assert_true(_cluster["source"]["authority"].stream_sequence() == stream_before + 1, "existing MW6 publishes exactly one Matter outcome")
	_assert_true(_projection_calls == 1, "product position projector called before MW4")

	var unequip := gameplay.handle_canonical_item_command(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p7/unequip-tool",
		"item.unequip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(unequip, "unequip real canonical tool")
	var journal_after_commit: int = int(journal.size())
	var stream_after_commit: int = int(_cluster["source"]["authority"].stream_sequence())
	var missing_request := _request_with_tool(
		fixture,
		"operation/p7/matter/missing-tool",
		tool_id
	)
	var missing := _send(replica, missing_request, "message/p7/matter/missing-tool")
	_assert_true(String(missing.get("status", "")) == "REJECTED", "MW6 rejects missing-tool P7 command")
	_assert_true(String(missing.get("error_code", "")) == "P7_MINING_TOOL_REQUIRED", "P7 tool error survives MW6 boundary")
	_assert_true(journal.size() == journal_after_commit, "tool rejection occurs before MW4 journal")
	_assert_true(_cluster["source"]["authority"].stream_sequence() == stream_after_commit, "tool rejection publishes no Matter delta")

	var reequip := gameplay.handle_canonical_item_command(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p7/reequip-tool",
		"item.equip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(reequip, "re-equip real canonical tool")
	_assert_success(
		sm1.begin_transfer(
			"transfer/p7/freeze",
			MW8Fixture.SOURCE_OWNER_ID,
			MW8Fixture.TARGET_OWNER_ID,
			MW8Fixture.SOURCE_EPOCH
		),
		"enter real SM1 transfer gap"
	)
	var frozen_request := _request_with_tool(
		fixture,
		"operation/p7/matter/sm1-frozen",
		tool_id
	)
	var frozen := _send(replica, frozen_request, "message/p7/matter/sm1-frozen")
	_assert_true(String(frozen.get("status", "")) == "REJECTED", "MW6 rejects SM1-frozen P7 command")
	_assert_true(String(frozen.get("error_code", "")) == "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "SM1 one-writer error survives MW6 boundary")
	_assert_true(journal.size() == journal_after_commit, "SM1 rejection occurs before MW4 journal")
	_assert_true(_cluster["source"]["authority"].stream_sequence() == stream_after_commit, "SM1 rejection publishes no Matter delta")

	var report: Dictionary = gate.contract_report()
	_assert_true(not bool(report.get("canonical_state_owned", true)), "P7 gate owns zero canonical state")
	_assert_true(not bool(report.get("replay_ledger_owned", true)), "P7 gate owns zero replay ledger")


func _request_with_tool(
	fixture: Dictionary,
	operation_id: String,
	tool_id: String
) -> Dictionary:
	var request: Dictionary = MW8Fixture.request(
		_cluster,
		"source",
		fixture,
		operation_id,
		PLAYER_ENTITY
	)
	request["tool_id"] = tool_id
	request["checksum"] = MatterUtils.compute_checksum(request)
	return request


func _send(replica, request: Dictionary, message_id: String) -> Dictionary:
	var command: Dictionary = replica.create_mutation_command(request, message_id)
	if command.is_empty():
		return {"status": "FAILED", "error_code": "P7_TEST_COMMAND_BUILD_FAILED"}
	var wire: Dictionary = _cluster["source"]["command_transport"].send(command)
	if not bool(wire.get("success", false)):
		return {"status": "FAILED", "error_code": String(wire.get("error_code", "P7_TEST_TRANSPORT_FAILED"))}
	return Dictionary(wire.get("result", {}))


func _project_player_into_matter_frame(
	player: Dictionary,
	request: Dictionary
) -> Dictionary:
	_projection_calls += 1
	_assert_true(String(player.get("player_entity_id", "")) == PLAYER_ENTITY, "projector receives canonical player")
	var shape: Dictionary = request.get("shape", {})
	return {
		"success": true,
		"error_code": "",
		"position_m": Array(shape.get("start_position_m", [])).duplicate(),
	}


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
