extends SceneTree

const ItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const SlotProjection = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection_p1_slots.gd"
)
const TransientState = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_inventory_transient_state.gd"
)
const P1Bridge = preload(
	"res://scripts/runtime/networked_gameplay/m5/m5_v0_inventory_ui_bridge.gd"
)
const R5Shell = preload(
	"res://scripts/ui/inventory/networked/m5_v0_modern_inventory_shell_r5.gd"
)

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_canonical_slot_move_and_projection()
	_test_atomic_occupied_slot_swap()
	_test_rejected_cursor_preservation()
	await _test_r5_product_controls()
	_finish()


func _test_canonical_slot_move_and_projection() -> void:
	var service = ItemGraph.new()
	var setup: Dictionary = service.setup("authority/r5", 1, {"playable_sandbox": true})
	_assert(bool(setup.get("success", false)), "R5 canonical Item Graph configures")
	service.ensure_player("a")
	var before: Dictionary = service.create_snapshot()
	var battery_id := "item/player/a/battery"
	var before_item := _find_item(before, battery_id)
	_assert(not before_item.is_empty(), "starter battery exists before slot move")
	var move: Dictionary = service.execute(
		"a",
		1,
		"operation/r5/slot-move",
		"item.transfer",
		{
			"item_id": battery_id,
			"quantity": -1,
			"target_container_id": "inventory/a",
			"target_slot_index": 7,
		},
		{}
	)
	_assert(bool(move.get("success", false)), "same-inventory canonical slot move succeeds")
	var after: Dictionary = move.get("snapshot", {})
	var after_item := _find_item(after, battery_id)
	_assert(
		int(after_item.get("location", {}).get("slot_index", -1)) == 7,
		"canonical item location records target slot 7"
	)
	var projection = SlotProjection.new()
	var accepted: Dictionary = projection.accept_snapshot(after)
	_assert(bool(accepted.get("success", false)), "slot-aware M5 projection accepts canonical snapshot")
	var view: Dictionary = projection.build_screen("a")
	var player: Dictionary = Dictionary(view.get("player", {}))
	var cells: Array = Array(player.get("cells", []))
	_assert(cells.size() >= 8, "P1 player projection exposes target slot")
	_assert(
		cells.size() > 7 and String(Dictionary(cells[7]).get("item_id", "")) == battery_id,
		"M5 projection renders battery at canonical slot 7"
	)
	var durable: Dictionary = service.export_durable_state()
	var restored = ItemGraph.new()
	var restored_setup: Dictionary = restored.setup(
		"authority/r5-restore",
		2,
		{"playable_sandbox": true}
	)
	_assert(bool(restored_setup.get("success", false)), "restore fixture configures with sandbox hotbar contract")
	var restore: Dictionary = restored.restore_durable_state(durable)
	_assert(bool(restore.get("success", false)), "slot-aware canonical state restores durably")
	var restored_item := _find_item(restored.create_snapshot(), battery_id)
	_assert(
		int(restored_item.get("location", {}).get("slot_index", -1)) == 7,
		"reconnect/durable reconstruction preserves canonical slot identity"
	)


func _test_atomic_occupied_slot_swap() -> void:
	var service = ItemGraph.new()
	var setup: Dictionary = service.setup("authority/r6-swap", 1, {"playable_sandbox": true})
	_assert(bool(setup.get("success", false)), "R6 swap fixture configures")
	service.ensure_player("a")
	var battery_id := "item/player/a/battery"
	var beacons_id := "item/player/a/beacons"

	# Starter beacons begin assigned to hotbar. Move the whole stack into a
	# canonical backpack slot first; R6 intentionally does not reinterpret
	# hotbar assignment as occupied backpack-slot swap semantics.
	var unassign_hotbar: Dictionary = service.execute(
		"a",
		1,
		"operation/r6/beacons-to-bag",
		"item.transfer",
		{
			"item_id": beacons_id,
			"quantity": -1,
			"target_container_id": "inventory/a",
			"target_slot_index": 5,
		},
		{}
	)
	_assert(bool(unassign_hotbar.get("success", false)), "whole beacon stack moves from hotbar assignment to bag slot 5")
	var before_swap: Dictionary = unassign_hotbar.get("snapshot", {})
	var battery_before := _find_item(before_swap, battery_id)
	var beacons_before := _find_item(before_swap, beacons_id)
	var battery_slot := int(battery_before.get("location", {}).get("slot_index", -1))
	var beacons_slot := int(beacons_before.get("location", {}).get("slot_index", -1))
	_assert(battery_slot >= 0 and beacons_slot == 5, "swap fixture has two authoritative occupied slots")

	var stale: Dictionary = service.execute(
		"a",
		1,
		"operation/r6/stale-target",
		"item.transfer",
		{
			"item_id": battery_id,
			"quantity": -1,
			"target_container_id": "inventory/a",
			"target_slot_index": 6,
			"target_item_id": beacons_id,
		},
		{}
	)
	_assert(not bool(stale.get("success", false)), "stale occupied-slot target is rejected")
	_assert(String(stale.get("error_code", "")) == "SWAP_TARGET_MISMATCH", "stale target has precise swap mismatch error")
	var after_stale: Dictionary = service.create_snapshot()
	_assert(
		int(_find_item(after_stale, battery_id).get("location", {}).get("slot_index", -1)) == battery_slot
		and int(_find_item(after_stale, beacons_id).get("location", {}).get("slot_index", -1)) == beacons_slot,
		"stale swap rejection does not mutate canonical slots"
	)

	var partial: Dictionary = service.execute(
		"a",
		1,
		"operation/r6/partial-swap",
		"item.transfer",
		{
			"item_id": beacons_id,
			"quantity": 1,
			"target_container_id": "inventory/a",
			"target_slot_index": battery_slot,
			"target_item_id": battery_id,
		},
		{}
	)
	_assert(not bool(partial.get("success", false)), "partial incompatible occupied-slot transfer is rejected")
	_assert(String(partial.get("error_code", "")) == "SWAP_REQUIRES_FULL_STACK", "partial swap requires the whole carried stack")

	var swap: Dictionary = service.execute(
		"a",
		1,
		"operation/r6/atomic-swap",
		"item.transfer",
		{
			"item_id": battery_id,
			"quantity": -1,
			"target_container_id": "inventory/a",
			"target_slot_index": beacons_slot,
			"target_item_id": beacons_id,
		},
		{}
	)
	_assert(bool(swap.get("success", false)), "whole incompatible occupied-slot transfer swaps atomically")
	var swap_details: Dictionary = Dictionary(swap.get("details", {}))
	_assert(bool(swap_details.get("swapped", false)), "canonical result identifies atomic swap")
	_assert(String(swap_details.get("displaced_item_id", "")) == beacons_id, "canonical result identifies displaced item")
	_assert(int(swap_details.get("displaced_slot_index", -1)) == battery_slot, "displaced item source for cursor is original carried slot")
	var after_swap: Dictionary = swap.get("snapshot", {})
	_assert(
		int(_find_item(after_swap, battery_id).get("location", {}).get("slot_index", -1)) == beacons_slot,
		"carried item occupies requested target slot"
	)
	_assert(
		int(_find_item(after_swap, beacons_id).get("location", {}).get("slot_index", -1)) == battery_slot,
		"displaced item atomically occupies original carried slot"
	)

	var durable: Dictionary = service.export_durable_state()
	var restored = ItemGraph.new()
	_assert(bool(restored.setup("authority/r6-restore", 2, {"playable_sandbox": true}).get("success", false)), "R6 restore fixture configures")
	_assert(bool(restored.restore_durable_state(durable).get("success", false)), "R6 swapped state restores durably")
	var restored_snapshot: Dictionary = restored.create_snapshot()
	_assert(
		int(_find_item(restored_snapshot, battery_id).get("location", {}).get("slot_index", -1)) == beacons_slot
		and int(_find_item(restored_snapshot, beacons_id).get("location", {}).get("slot_index", -1)) == battery_slot,
		"durable reconstruction preserves both sides of atomic swap"
	)


func _test_rejected_cursor_preservation() -> void:
	var transient = TransientState.new()
	var begin: Dictionary = transient.begin_cursor_carry("item/test/a", 3, "inventory/a", 4, 10)
	_assert(bool(begin.get("success", false)), "transient cursor fixture starts")
	_assert(
		bool(transient.register_pending(
			"operation/r6/rejected",
			{"payload": {"item_id": "item/test/a"}},
			10
		).get("success", false)),
		"rejected-command fixture registers pending operation"
	)
	var rejected: Dictionary = transient.accept_command_result({
		"success": false,
		"error_code": "TARGET_SLOT_OCCUPIED",
		"operation_id": "operation/r6/rejected",
		"ui_context": {"cursor_remaining_quantity": 0},
	})
	_assert(bool(rejected.get("success", false)), "transient accepts authoritative rejection result")
	_assert(transient.has_cursor(), "authoritative rejection preserves presentation carry")
	_assert(String(transient.get_cursor().get("item_id", "")) == "item/test/a", "rejected carry keeps the original item identity")
	var replaced: Dictionary = transient.replace_cursor_after_operation(
		"",
		"item/test/displaced",
		2,
		"inventory/a",
		7,
		11
	)
	_assert(bool(replaced.get("success", false)), "successful swap can replace transient cursor identity")
	_assert(
		String(transient.get_cursor().get("item_id", "")) == "item/test/displaced"
		and int(transient.get_cursor().get("source_slot_index", -1)) == 7,
		"replacement cursor points at displaced canonical source slot"
	)


func _test_r5_product_controls() -> void:
	var shell = R5Shell.new()
	shell.name = "R5InventoryShellTest"
	get_root().add_child(shell)
	await process_frame
	var profile_result: Dictionary = shell._load_interaction_profile()
	_assert(bool(profile_result.get("success", false)), "R5 shell resolves 7 Days profile")
	shell._build_ui()
	var player_sort = shell.inventory_window.get_node_or_null("Margin/Main/NetworkedActions/PlayerSortButton")
	var external_sort = shell.inventory_window.get_node_or_null("Margin/Main/NetworkedActions/ExternalSortButton")
	_assert(player_sort != null, "7 Days product composition restores Sort button")
	_assert(external_sort != null, "external-container sort action is present")
	_assert(
		player_sort != null and player_sort.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS,
		"Sort activates on button press like accepted rev6 fallback path"
	)
	_assert(shell.has_method("_drop_network_cursor_to_world"), "R5 shell owns carried-item outside-drop presentation path")
	_assert(shell.has_method("_sort_visible_container"), "R5 shell owns authoritative sort trigger")
	var bridge = P1Bridge.new()
	_assert(bridge.has_method("_merge_compatible_stacks_for_sort"), "R6 bridge restores merge-before-sort transaction")
	var extracted: Dictionary = bridge._canonical_command_details({
		"success": true,
		"details": {
			"operation_id": "operation/r6/wire-shape",
			"result": {
				"status": "SUCCEEDED",
				"details": {
					"swapped": true,
					"displaced_item_id": "item/test/displaced",
				},
			},
		},
	})
	_assert(bool(extracted.get("swapped", false)), "R6 bridge unwraps canonical swap details from M3 wire result")
	_assert(String(extracted.get("displaced_item_id", "")) == "item/test/displaced", "R6 wire unwrapping preserves displaced identity")
	bridge.free()
	shell.free()


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value)
	return {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0-P1 R6 inventory parity: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
