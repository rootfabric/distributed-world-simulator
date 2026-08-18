extends SceneTree

const GameplayP5 = preload(
	"res://scripts/runtime/networked_gameplay/p5/networked_gameplay_service_p5.gd"
)
const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)

const PLAYER := "b"
const SESSION := "transport-session/p5/b/1"
const NODE_ID := "resource/earth/ore-demo/1"
const TOOL_DEFINITION := "item/tool/mining"
const SLOT := "tool/main"

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gameplay = GameplayP5.new()
	_assert_success(gameplay.setup("authority/p5/test", 1), "setup P5 gameplay")
	var join := gameplay.join(PLAYER, SESSION, "operation/p5/join-b")
	_assert_success(join, "join player near ore node")
	var ownership_epoch := int(join.get("details", {}).get("player", {}).get("ownership_epoch", 1))
	_assert_true(ownership_epoch == 1, "initial ownership epoch is canonical")
	var resolver = EarthResourceSpatialResolver.new()
	_assert_success(resolver.setup(), "configure Earth resource resolver")
	var resource_port = gameplay.get_resource_mining_port()
	var node: Dictionary = resource_port.get_node(NODE_ID)
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	_assert_success(resolved, "resolve canonical ore position")
	var target: Dictionary = Dictionary(resolved.get("details", {}).get("planar_position", {}))
	_assert_true(_move_to(gameplay, SESSION, ownership_epoch, target), "move authoritative player into resource range")

	var graph = gameplay.get_canonical_item_graph_port()
	_assert_true(graph != null, "P5 reuses canonical Item Graph port")
	var tool_output: Dictionary = graph.apply_server_output(
		"operation/p5/tool-output-b",
		PLAYER,
		TOOL_DEFINITION,
		1,
		"source/p5/mining-tool"
	)
	_assert_success(tool_output, "create canonical mining tool")
	var tool_id := String(tool_output.get("details", {}).get("output_item_id", ""))
	_assert_true(not tool_id.is_empty(), "tool has canonical item identity")

	var initial_resource := gameplay.create_resource_mining_snapshot()
	var initial_remaining := _remaining_units(initial_resource)
	_assert_true(initial_remaining == 8, "resource starts with expected canonical quantity")
	var graph_revision_before_gate := int(graph.create_snapshot().get("revision", -1))

	var missing := gameplay.handle_resource_mine(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/mine-without-tool",
		{"resource_node_id": NODE_ID, "requested_units": 1}
	)
	_assert_error(missing, "MINING_TOOL_REQUIRED", "mining without equipped tool")
	_assert_true(_remaining_units(gameplay.create_resource_mining_snapshot()) == initial_remaining, "tool rejection does not mutate resource")
	_assert_true(int(graph.create_snapshot().get("revision", -1)) == graph_revision_before_gate, "tool rejection does not mutate Item Graph")

	var equip := gameplay.handle_canonical_item_command(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/equip-mining-tool",
		"item.equip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(equip, "equip canonical mining tool through gameplay command path")
	_assert_true(graph.has_equipped_mining_tool(PLAYER), "canonical equipment relation gates mining")

	var missing_replay := gameplay.handle_resource_mine(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/mine-without-tool",
		{"resource_node_id": NODE_ID, "requested_units": 1}
	)
	_assert_error(missing_replay, "MINING_TOOL_REQUIRED", "pre-equip rejection replays after equip")
	_assert_true(bool(missing_replay.get("replay", false)), "pre-equip rejection is exact-once replay")
	_assert_true(_remaining_units(gameplay.create_resource_mining_snapshot()) == initial_remaining, "replayed rejection remains mutation-free")

	var mine := gameplay.handle_resource_mine(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/mine-with-tool",
		{"resource_node_id": NODE_ID, "requested_units": 1}
	)
	_assert_success(mine, "equipped tool authorizes canonical mining")
	_assert_true(not bool(mine.get("replay", false)), "first equipped mining operation is fresh")
	_assert_true(String(mine.get("details", {}).get("output_definition_id", "")) == "item/ore", "existing canonical P3 output definition is preserved")
	_assert_true(int(mine.get("details", {}).get("output_quantity", 0)) == 1, "existing canonical P3 output quantity is preserved")
	_assert_true(_remaining_units(gameplay.create_resource_mining_snapshot()) == initial_remaining - 1, "successful equipped mining decrements resource exactly once")
	var output_item_id := String(mine.get("details", {}).get("output_item_id", ""))
	_assert_true(not output_item_id.is_empty(), "successful mining produces canonical Item Graph item")
	_assert_true(_find_item_definition(graph.create_snapshot(), output_item_id) == "item/ore", "mining output lives in the same canonical Item Graph")

	var resource_after_first := gameplay.create_resource_mining_snapshot()
	var graph_after_first: Dictionary = graph.create_snapshot()
	var mine_replay := gameplay.handle_resource_mine(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/mine-with-tool",
		{"resource_node_id": NODE_ID, "requested_units": 1}
	)
	_assert_success(mine_replay, "equipped mining replay succeeds")
	_assert_true(bool(mine_replay.get("replay", false)), "equipped mining replay is marked")
	_assert_true(gameplay.create_resource_mining_snapshot() == resource_after_first, "mining replay does not decrement resource again")
	_assert_true(graph.create_snapshot() == graph_after_first, "mining replay does not duplicate Item Graph output")

	var unequip := gameplay.handle_canonical_item_command(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/unequip-mining-tool",
		"item.unequip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(unequip, "unequip canonical mining tool")
	var after_unequip := gameplay.handle_resource_mine(
		PLAYER,
		SESSION,
		ownership_epoch,
		"operation/p5/mine-after-unequip",
		{"resource_node_id": NODE_ID, "requested_units": 1}
	)
	_assert_error(after_unequip, "MINING_TOOL_REQUIRED", "unequipped player cannot start a new mining operation")
	_assert_true(_remaining_units(gameplay.create_resource_mining_snapshot()) == initial_remaining - 1, "post-unequip rejection is mutation-free")

	var replay_state: Dictionary = gameplay.get_resource_mining_port().export_replay_state()
	_assert_true(int(replay_state.get("records", {}).size()) == 3, "resource ledger owns gate failure, success and post-unequip failure")

	print("V0-P5 mining tool gate: %d assertions, %d failures" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _move_to(gameplay, session_id: String, ownership_epoch: int, target: Dictionary) -> bool:
	var sequence := 0
	for step in range(6):
		var player: Dictionary = gameplay.get_player(PLAYER)
		var position: Dictionary = Dictionary(player.get("position", {}))
		var remaining_x := float(target.get("x", 0.0)) - float(position.get("x", 0.0))
		var remaining_z := float(target.get("z", 0.0)) - float(position.get("z", 0.0))
		if sqrt(remaining_x * remaining_x + remaining_z * remaining_z) <= 0.25:
			return true
		sequence += 1
		var moved: Dictionary = gameplay.move_player(
			PLAYER,
			session_id,
			ownership_epoch,
			sequence,
			clampf(remaining_x, -9.0, 9.0),
			clampf(remaining_z, -9.0, 9.0),
			"operation/p5/move-%d" % step
		)
		if not bool(moved.get("success", false)):
			return false
	var final_player: Dictionary = gameplay.get_player(PLAYER)
	var final_position: Dictionary = Dictionary(final_player.get("position", {}))
	var final_x := float(target.get("x", 0.0)) - float(final_position.get("x", 0.0))
	var final_z := float(target.get("z", 0.0)) - float(final_position.get("z", 0.0))
	return sqrt(final_x * final_x + final_z * final_z) <= 0.25


func _remaining_units(snapshot: Dictionary) -> int:
	for node_value in snapshot.get("nodes", []):
		if node_value is Dictionary and String(node_value.get("resource_node_id", "")) == NODE_ID:
			return int(node_value.get("remaining_units", -1))
	return -1


func _find_item_definition(snapshot: Dictionary, item_id: String) -> String:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return String(item_value.get("definition_id", ""))
	return ""


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert_true(not bool(result.get("success", false)), "%s rejects" % message)
	_assert_true(String(result.get("error_code", "")) == error_code, "%s error=%s actual=%s" % [message, error_code, String(result.get("error_code", ""))])


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P5 mining] %s" % message)
