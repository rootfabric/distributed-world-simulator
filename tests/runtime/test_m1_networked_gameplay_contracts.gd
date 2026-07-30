extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const EntityDelta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const JoinCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_join_command.gd")
const LeaveCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_leave_command.gd")
const InputCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const OwnershipSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_ownership_snapshot.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const PlayerDelta = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")
const ItemCommand = preload("res://scripts/runtime/networked_gameplay/contracts/item_command.gd")
const ItemGraphSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_snapshot.gd")
const ItemGraphDelta = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_delta.gd")
const CommandResult = preload("res://scripts/runtime/networked_gameplay/contracts/command_result.gd")
const OwnershipService = preload("res://scripts/runtime/networked_gameplay/services/player_ownership_service.gd")
const GameplayService = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_command_contracts()
	_test_state_contracts()
	_test_item_graph_contracts()
	_test_contract_independence()
	_finish()

func _test_command_contracts() -> void:
	var join: Dictionary = JoinCommand.create("message/m1/join/1", "operation/m1/join/1", "player-a", "transport-session/m1/a/1", 7)
	_assert(_ok(JoinCommand.validate(join)), "valid PlayerJoinCommand rejected")
	var join_extra: Dictionary = join.duplicate(true); join_extra["authority_object"] = "forbidden"; join_extra.erase("checksum"); join_extra["checksum"] = Utils.payload_hash(join_extra)
	_assert(_error(JoinCommand.validate(join_extra)) == "INVALID_PLAYER_JOIN_COMMAND", "extra join field accepted")
	var join_tampered: Dictionary = join.duplicate(true); join_tampered["logical_player_id"] = "player-b"
	_assert(_error(JoinCommand.validate(join_tampered)) == "INVALID_PLAYER_JOIN_COMMAND", "tampered join checksum accepted")
	var leave: Dictionary = LeaveCommand.create("message/m1/leave/1", "operation/m1/leave/1", "player-a", "transport-session/m1/a/1", 7, 2)
	_assert(_ok(LeaveCommand.validate(leave)), "valid PlayerLeaveCommand rejected")
	var input_delta: Dictionary = InputCommand.create("message/m1/input/1", "operation/m1/input/1", "player-a", "transport-session/m1/a/1", 7, 2, 4, "MOVEMENT_DELTA", {"delta_x": 1.0, "delta_z": -0.5})
	_assert(_ok(InputCommand.validate(input_delta)), "valid movement PlayerInputCommand rejected")
	var input_state: Dictionary = InputCommand.create("message/m1/input/2", "operation/m1/input/2", "player-a", "transport-session/m1/a/1", 7, 2, 5, "AUTHORITATIVE_STATE", {"player_state": {"safe": true}, "delta_seconds": 0.1})
	_assert(_ok(InputCommand.validate(input_state)), "valid authoritative-state PlayerInputCommand rejected")
	var node := Node.new()
	var unsafe_input: Dictionary = InputCommand.create("message/m1/input/3", "operation/m1/input/3", "player-a", "transport-session/m1/a/1", 7, 2, 6, "AUTHORITATIVE_STATE", {"player_state": {"node": node}, "delta_seconds": 0.1})
	_assert(not _ok(InputCommand.validate(unsafe_input)), "Node crossed PlayerInputCommand wire boundary")
	node.free()
	var item: Dictionary = ItemCommand.create("message/m1/item/1", "operation/m1/item/1", "player-a", "transport-session/m1/a/1", 7, 2, 0, "item.pickup_shared_fixture", {"item_id": GameplayService.SHARED_ITEM_ID})
	_assert(_ok(ItemCommand.validate(item)), "valid ItemCommand rejected")
	var result: Dictionary = CommandResult.create("message/m1/result/1", "operation/m1/item/1", "SUCCEEDED", "", 7, 4, {"accepted": true})
	_assert(_ok(CommandResult.validate(result)), "valid CommandResult rejected")
	var result_error: Dictionary = result.duplicate(true); result_error["error_code"] = "MUST_BE_EMPTY"; result_error.erase("checksum"); result_error["checksum"] = Utils.payload_hash(result_error)
	_assert(_error(CommandResult.validate(result_error)) == "INVALID_GAMEPLAY_COMMAND_RESULT", "successful result with error accepted")

func _test_state_contracts() -> void:
	var ownership := OwnershipService.new()
	_assert(_ok(ownership.setup("simulation/m1/contracts", 7, 100)), "ownership setup failed")
	_assert(_ok(ownership.join("player-a", "transport-session/m1/a/1", "operation/m1/ownership/join/1")), "ownership join failed")
	var ownership_snapshot: Dictionary = ownership.create_snapshot()
	_assert(_ok(OwnershipSnapshot.validate(ownership_snapshot)), "PlayerOwnershipSnapshot rejected")
	var ownership_extra: Dictionary = ownership_snapshot.duplicate(true); ownership_extra["repository"] = "forbidden"; ownership_extra.erase("checksum"); ownership_extra["checksum"] = Utils.payload_hash(ownership_extra)
	_assert(not _ok(OwnershipSnapshot.validate(ownership_extra)), "ownership snapshot accepted extra field")
	var service := GameplayService.new()
	_assert(_ok(service.setup("simulation/m1/contracts", 7, 100, {"topology_adapter": "LOOPBACK", "region_id": "region/m1/contracts"})), "gameplay service setup failed")
	var join: Dictionary = service.join("player-a", "transport-session/m1/a/1", "operation/m1/player/join/1")
	_assert(_ok(join), "service join failed")
	var snapshot: Dictionary = service.create_snapshot()
	_assert(_ok(PlayerSnapshot.validate(snapshot)), "PlayerStateSnapshot rejected")
	var move: Dictionary = service.move_player("player-a", "transport-session/m1/a/1", 1, 1, 1.0, 0.5, "operation/m1/player/move/1")
	_assert(_ok(move), "service movement failed")
	_assert(_ok(PlayerDelta.validate(move.get("details", {}).get("delta", {}))), "PlayerStateDelta rejected")
	var delta_tampered: Dictionary = move.get("details", {}).get("delta", {}).duplicate(true); delta_tampered["player"]["position"]["x"] = 999.0
	_assert(_error(PlayerDelta.validate(delta_tampered)) == "MULTIPLAYER_DELTA_CHECKSUM_MISMATCH", "tampered player delta accepted")
	var routed: Dictionary = service.create_targeted_command_result("message/m1/routed/1", "operation/m1/player/move/1", move)
	_assert(_ok(CommandResult.validate(routed)), "service CommandResultRouter emitted invalid result")
	_assert(int(service.get_report().get("command_result_router", {}).get("routed", 0)) == 1, "command result router was bypassed")

func _test_item_graph_contracts() -> void:
	var spatial: Dictionary = SpatialRef.create("body/moon/fixed", Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, 0.0, "main", "moon", "m1-contracts")
	var snapshot: Dictionary = EntitySnapshot.create("snapshot/m1/item-graph/1", "item-graph/m1", "item_graph", 0, "simulation/m1", 3, 10, spatial, {}, {}, {"item_graph": {"schema": "fixture", "items": []}})
	_assert(_ok(ItemGraphSnapshot.validate(snapshot)), "ItemGraphSnapshot rejected")
	var delta: Dictionary = EntityDelta.create("delta/m1/item-graph/1", "item-graph/m1", "item_graph", 0, 1, "simulation/m1", 3, 11, {"domain_components": {"item_graph": {"schema": "fixture", "items": [{"id": "item/1"}]}}})
	_assert(_ok(ItemGraphDelta.validate(delta)), "ItemGraphDelta rejected")
	var wrong_type: Dictionary = snapshot.duplicate(true); wrong_type["entity_type"] = "player"; wrong_type.erase("checksum"); wrong_type["checksum"] = EntitySnapshot.compute_checksum(wrong_type)
	_assert(not _ok(ItemGraphSnapshot.validate(wrong_type)), "non-item snapshot accepted as ItemGraphSnapshot")
	var network_item: Dictionary = NetworkCommand.create("message/m1/network-item/1", "operation/m1/network-item/1", "item-graph/m1", "item.save", {"session_id": "session/m1/1"}, 0, 3, 10, 1)
	_assert(_ok(ItemCommand.validate_network_envelope(network_item)), "canonical network item envelope rejected")

func _test_contract_independence() -> void:
	var paths: Array[String] = [
		"player_join_command.gd", "player_leave_command.gd", "player_input_command.gd",
		"player_ownership_snapshot.gd", "player_state_snapshot.gd", "player_state_delta.gd",
		"item_command.gd", "item_graph_snapshot.gd", "item_graph_delta.gd", "command_result.gd",
	]
	for file_name in paths:
		var text: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/contracts/%s" % file_name)
		_assert(not text.contains("playable_listen_host_authority.gd"), "%s depends on H1 authority" % file_name)
		_assert(not text.contains("multiplayer_gameplay_authority.gd"), "%s depends on H3 authority" % file_name)
		_assert(not text.contains("extends Node"), "%s is Node-dependent" % file_name)
		_assert(not text.contains("SceneTree"), "%s is SceneTree-dependent" % file_name)

func _ok(value: Dictionary) -> bool: return bool(value.get("success", false))
func _error(value: Dictionary) -> String: return String(value.get("error_code", ""))
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("M1 networked gameplay wire contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("M1 networked gameplay wire contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
