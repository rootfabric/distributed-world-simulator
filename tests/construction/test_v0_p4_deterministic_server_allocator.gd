extends SceneTree

const ItemGraphScript = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const AllocatorScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_construction_material_allocator.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_one_stack_and_exact_boundary()
	_test_multistack_slot_order()
	_test_input_item_order_does_not_change_allocation()
	_test_same_slot_tie_breaks_by_item_id()
	_test_foreign_player_ore_is_excluded_and_insufficient_is_pure()
	_test_missing_player_fails_closed()
	_test_invalid_requirement_fails_closed()
	_test_hotbar_ore_is_not_implicitly_spendable()
	_finish()


func _test_one_stack_and_exact_boundary() -> void:
	var graph = _graph_with_players(["a"])
	var output := _output(graph, "operation/v0-p4/allocator/a/one", "a", 4, "resource/test/one")
	_assert_ok(output, "one-stack server output")
	var before: Dictionary = graph.create_snapshot()
	var result: Dictionary = AllocatorScript.allocate_r1(graph, "A", 4)
	_assert_ok(result, "one-stack exact allocation")
	if not bool(result.get("success", false)):
		return
	var details: Dictionary = result.get("details", {})
	var allocations: Array = details.get("allocations", [])
	_assert(allocations.size() == 1, "exact boundary must select one stack")
	if allocations.size() == 1:
		_assert(int(allocations[0].get("quantity", -1)) == 4, "exact boundary quantity mismatch")
		_assert(int(allocations[0].get("slot_index", -1)) == 0, "first output must occupy canonical slot zero")
	_assert(String(details.get("definition_id", "")) == "item/ore", "R1 allocator must be item/ore only")
	_assert(String(details.get("allocation_checksum", "")).length() == 64, "allocation checksum missing")
	_assert(String(before.get("checksum", "")) == String(graph.create_snapshot().get("checksum", "")), "allocator mutated canonical Item Graph")


func _test_multistack_slot_order() -> void:
	var graph = _graph_with_players(["a"])
	_assert_ok(_output(graph, "operation/v0-p4/allocator/a/s0", "a", 1, "resource/test/s0"), "slot0 ore")
	_assert_ok(_output_definition(graph, "operation/v0-p4/allocator/a/filler", "a", "item/beacon", 1, "fixture/filler"), "slot1 filler")
	_assert_ok(_output(graph, "operation/v0-p4/allocator/a/s2", "a", 2, "resource/test/s2"), "slot2 ore")
	_assert_ok(_output(graph, "operation/v0-p4/allocator/a/s3", "a", 5, "resource/test/s3"), "slot3 ore")
	var result: Dictionary = AllocatorScript.allocate_r1(graph, "a", 3)
	_assert_ok(result, "multi-stack allocation")
	if not bool(result.get("success", false)):
		return
	var allocations: Array = Dictionary(result.get("details", {})).get("allocations", [])
	_assert(allocations.size() == 2, "multi-stack request must select exactly two ore stacks")
	if allocations.size() == 2:
		_assert(int(allocations[0].get("slot_index", -1)) == 0, "allocator did not select lowest slot first")
		_assert(int(allocations[0].get("quantity", -1)) == 1, "slot0 allocation quantity mismatch")
		_assert(int(allocations[1].get("slot_index", -1)) == 2, "allocator did not advance to next eligible slot")
		_assert(int(allocations[1].get("quantity", -1)) == 2, "slot2 allocation quantity mismatch")


func _test_input_item_order_does_not_change_allocation() -> void:
	var graph = _graph_with_players(["a"])
	_assert_ok(_output(graph, "operation/v0-p4/allocator/order/a", "a", 2, "resource/test/order-a"), "order stack a")
	_assert_ok(_output(graph, "operation/v0-p4/allocator/order/b", "a", 2, "resource/test/order-b"), "order stack b")
	var snapshot: Dictionary = graph.create_snapshot()
	var canonical := AllocatorScript.allocate_r1_from_snapshot(snapshot, "a", 3)
	_assert_ok(canonical, "canonical order allocation")
	var reversed := snapshot.duplicate(true)
	var reversed_items: Array = reversed.get("items", []).duplicate(true)
	reversed_items.reverse()
	reversed["items"] = reversed_items
	var reordered := AllocatorScript.allocate_r1_from_snapshot(reversed, "a", 3)
	_assert_ok(reordered, "reordered item-array allocation")
	if bool(canonical.get("success", false)) and bool(reordered.get("success", false)):
		_assert(
			Dictionary(canonical.get("details", {})).get("allocations", [])
			== Dictionary(reordered.get("details", {})).get("allocations", []),
			"Dictionary/array input order changed deterministic allocation"
		)



func _test_same_slot_tie_breaks_by_item_id() -> void:
	var snapshot := {
		"revision": 7,
		"tick": 9,
		"checksum": "fixture",
		"items": [
			{"item_id": "item/z", "definition_id": "item/ore", "quantity": 1, "location": {"kind": "INVENTORY", "player_id": "a", "slot_index": 4}, "mounted": false},
			{"item_id": "item/a", "definition_id": "item/ore", "quantity": 1, "location": {"kind": "INVENTORY", "player_id": "a", "slot_index": 4}, "mounted": false},
		],
		"inventories": {"a": {"inventory": ["item/z", "item/a"], "hotbar": [], "selected_hotbar_index": 0}},
	}
	var result: Dictionary = AllocatorScript.allocate_r1_from_snapshot(snapshot, "a", 1)
	_assert_ok(result, "same-slot tie-break allocation")
	if not bool(result.get("success", false)):
		return
	var allocations: Array = Dictionary(result.get("details", {})).get("allocations", [])
	_assert(allocations.size() == 1, "same-slot tie-break should select one stack")
	if allocations.size() == 1:
		_assert(String(allocations[0].get("item_id", "")) == "item/a", "same-slot tie must resolve by item_id ascending")


func _test_foreign_player_ore_is_excluded_and_insufficient_is_pure() -> void:
	var graph = _graph_with_players(["a", "b"])
	_assert_ok(_output(graph, "operation/v0-p4/allocator/foreign/a", "a", 1, "resource/test/foreign-a"), "A ore")
	_assert_ok(_output(graph, "operation/v0-p4/allocator/foreign/b", "b", 8, "resource/test/foreign-b"), "B ore")
	var before: Dictionary = graph.create_snapshot()
	var result: Dictionary = AllocatorScript.allocate_r1(graph, "a", 2)
	_assert(not bool(result.get("success", false)), "foreign player's ore must not satisfy A request")
	_assert(String(result.get("error_code", "")) == "CONSTRUCTION_MATERIAL_INSUFFICIENT", "foreign exclusion must report insufficient resources")
	var details: Dictionary = result.get("details", {})
	_assert(int(details.get("available_quantity", -1)) == 1, "foreign ore leaked into available quantity")
	var after: Dictionary = graph.create_snapshot()
	_assert(String(before.get("checksum", "")) == String(after.get("checksum", "")), "insufficient allocation mutated Item Graph")
	_assert(int(before.get("revision", -1)) == int(after.get("revision", -2)), "insufficient allocation advanced Item Graph revision")


func _test_missing_player_fails_closed() -> void:
	var graph = ItemGraphScript.new()
	_assert_ok(graph.setup("authority/v0-p4/allocator", 1), "missing-player graph setup")
	var result: Dictionary = AllocatorScript.allocate_r1(graph, "missing", 1)
	_assert(not bool(result.get("success", false)), "missing player inventory must fail closed")
	_assert(String(result.get("error_code", "")) == "CONSTRUCTION_MATERIAL_PLAYER_INVENTORY_NOT_FOUND", "missing-player error code mismatch")



func _test_invalid_requirement_fails_closed() -> void:
	var graph = _graph_with_players(["a"])
	var before: Dictionary = graph.create_snapshot()
	var result: Dictionary = AllocatorScript.allocate_r1(graph, "a", 0)
	_assert(not bool(result.get("success", false)), "zero material requirement must fail closed")
	_assert(String(result.get("error_code", "")) == "CONSTRUCTION_MATERIAL_REQUIREMENT_INVALID", "zero requirement error mismatch")
	_assert(String(before.get("checksum", "")) == String(graph.create_snapshot().get("checksum", "")), "invalid requirement mutated Item Graph")


func _test_hotbar_ore_is_not_implicitly_spendable() -> void:
	var graph = _graph_with_players(["a"])
	var output := _output(graph, "operation/v0-p4/allocator/hotbar", "a", 3, "resource/test/hotbar")
	_assert_ok(output, "hotbar ore output")
	if not bool(output.get("success", false)):
		return
	var item_id := String(Dictionary(output.get("details", {})).get("item_id", ""))
	var assigned: Dictionary = graph.execute(
		"a",
		1,
		"operation/v0-p4/allocator/hotbar/assign",
		"inventory.assign_hotbar",
		{"item_id": item_id, "slot_index": 0}
	)
	_assert_ok(assigned, "hotbar assignment")
	var result: Dictionary = AllocatorScript.allocate_r1(graph, "a", 1)
	_assert(not bool(result.get("success", false)), "hotbar-only ore must not be implicitly spendable in R1")
	_assert(String(result.get("error_code", "")) == "CONSTRUCTION_MATERIAL_INSUFFICIENT", "hotbar exclusion error mismatch")
	_assert(int(Dictionary(result.get("details", {})).get("available_quantity", -1)) == 0, "hotbar ore leaked into spendable quantity")


func _graph_with_players(players: Array[String]):
	var graph = ItemGraphScript.new()
	var setup: Dictionary = graph.setup("authority/v0-p4/allocator", 1)
	_assert_ok(setup, "item graph setup")
	for player_id in players:
		graph.ensure_player(player_id)
	return graph


func _output(graph, operation_id: String, player_id: String, quantity: int, source_id: String) -> Dictionary:
	return _output_definition(graph, operation_id, player_id, "item/ore", quantity, source_id)


func _output_definition(graph, operation_id: String, player_id: String, definition_id: String, quantity: int, source_id: String) -> Dictionary:
	return graph.apply_server_output(operation_id, player_id, definition_id, quantity, source_id)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P4 deterministic allocator: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-P4 deterministic allocator: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
