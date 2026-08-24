extends SceneTree

const ItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")

const PLAYER_A := "player/a"
const PLAYER_B := "player/b"
const SLOT := "tool/main"
const TOOL_DEFINITION := "item/tool/mining"

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph = ItemGraph.new()
	_assert_success(graph.setup("authority/p5/test", 1), "setup")
	graph.ensure_player(PLAYER_A)
	graph.ensure_player(PLAYER_B)

	var first_output := graph.apply_server_output(
		"operation/p5/tool-output-a",
		PLAYER_A,
		TOOL_DEFINITION,
		1,
		"source/p5/test"
	)
	_assert_success(first_output, "create first canonical mining tool")
	var tool_a := String(first_output.get("details", {}).get("output_item_id", ""))
	_assert_true(not tool_a.is_empty(), "tool A has canonical item id")

	var before_equip := graph.create_snapshot()
	var equip := graph.execute(
		PLAYER_A,
		1,
		"operation/p5/equip-a",
		"item.equip",
		{"item_id": tool_a, "slot_id": SLOT}
	)
	_assert_success(equip, "equip owned mining tool")
	_assert_true(int(equip.get("revision", -1)) == int(before_equip.get("revision", -2)) + 1, "equip advances canonical revision once")
	_assert_true(graph.has_equipped_mining_tool(PLAYER_A), "canonical mining tool relation is readable")
	var equipped := graph.get_equipped_item(PLAYER_A, SLOT)
	_assert_true(String(equipped.get("item_id", "")) == tool_a, "equipment keeps exact item identity")
	_assert_true(String(equipped.get("location", {}).get("kind", "")) == "INVENTORY", "equipped item remains in canonical owner inventory")
	_assert_true(String(equipped.get("equipment", {}).get("player_id", "")) == PLAYER_A, "equipment relation owns exact player")
	_assert_true(String(equipped.get("equipment", {}).get("slot_id", "")) == SLOT, "equipment relation owns exact slot")

	var equip_replay := graph.execute(
		PLAYER_A,
		1,
		"operation/p5/equip-a",
		"item.equip",
		{"item_id": tool_a, "slot_id": SLOT}
	)
	_assert_success(equip_replay, "exact equip operation replays")
	_assert_true(bool(equip_replay.get("replay", false)), "equip replay is marked")
	_assert_true(int(graph.create_snapshot().get("revision", -1)) == int(equip.get("revision", -2)), "equip replay does not advance revision")

	var foreign := graph.execute(
		PLAYER_B,
		1,
		"operation/p5/foreign-equip",
		"item.equip",
		{"item_id": tool_a, "slot_id": SLOT}
	)
	_assert_error(foreign, "PLAYER_PERMISSION_DENIED", "foreign player cannot equip owned item")

	var invalid_slot := graph.execute(
		PLAYER_A,
		1,
		"operation/p5/invalid-slot",
		"item.equip",
		{"item_id": tool_a, "slot_id": "armor/head"}
	)
	_assert_error(invalid_slot, "INVALID_EQUIPMENT_SLOT", "invalid equipment slot rejects")

	var second_output := graph.apply_server_output(
		"operation/p5/tool-output-b",
		PLAYER_A,
		TOOL_DEFINITION,
		1,
		"source/p5/test-b"
	)
	_assert_success(second_output, "create second canonical mining tool")
	var tool_b := String(second_output.get("details", {}).get("output_item_id", ""))
	var occupied := graph.execute(
		PLAYER_A,
		1,
		"operation/p5/equip-b",
		"item.equip",
		{"item_id": tool_b, "slot_id": SLOT}
	)
	_assert_error(occupied, "EQUIPMENT_SLOT_OCCUPIED", "one canonical item owns one equipment slot")

	var durable := graph.export_durable_state()
	_assert_true(not durable.is_empty(), "equipped relation exports through existing durable state")
	var restored = ItemGraph.new()
	var restore := restored.restore_durable_state(durable)
	_assert_success(restore, "equipment relation restores through existing durable state")
	_assert_true(restored.has_equipped_mining_tool(PLAYER_A), "restored graph preserves mining tool relation")
	_assert_true(String(restored.get_equipped_item(PLAYER_A, SLOT).get("item_id", "")) == tool_a, "restore preserves exact equipped item id")

	var conflict := restored.execute(
		PLAYER_A,
		1,
		"operation/p5/equip-a",
		"item.equip",
		{"item_id": tool_b, "slot_id": SLOT}
	)
	# Durable state intentionally does not carry replay ledger; replay durability
	# is a separate existing aggregate channel. The relation itself must still
	# reject a second occupant after reconnect.
	_assert_error(conflict, "EQUIPMENT_SLOT_OCCUPIED", "restored relation blocks second slot occupant")

	var unequip := restored.execute(
		PLAYER_A,
		1,
		"operation/p5/unequip-a",
		"item.unequip",
		{"item_id": tool_a, "slot_id": SLOT}
	)
	_assert_success(unequip, "unequip canonical tool")
	_assert_true(not restored.has_equipped_mining_tool(PLAYER_A), "unequip clears canonical relation")
	var unequipped := _find_item(restored.create_snapshot(), tool_a)
	_assert_true(String(unequipped.get("item_id", "")) == tool_a, "unequip preserves exact item identity")
	_assert_true(not unequipped.has("equipment"), "unequip removes only equipment relation")
	_assert_true(_inventory_reference_count(restored.create_snapshot(), PLAYER_A, tool_a) == 1, "item identity remains exactly once in owning inventory")

	print("V0-P5 canonical equipment relation: %d assertions, %d failures" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value)
	return {}


func _inventory_reference_count(snapshot: Dictionary, player_id: String, item_id: String) -> int:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {}).get(player_id, {}))
	var count := 0
	for value in inventory.get("inventory", []):
		if String(value) == item_id:
			count += 1
	return count


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert_true(not bool(result.get("success", false)), "%s rejects" % message)
	_assert_true(String(result.get("error_code", "")) == error_code, "%s error=%s" % [message, error_code])


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P5] %s" % message)
