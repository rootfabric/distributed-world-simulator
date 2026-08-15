extends SceneTree

const ItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const SlotProjection = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection_p1_slots.gd"
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


func _test_r5_product_controls() -> void:
	var shell = R5Shell.new()
	shell.name = "R5InventoryShellTest"
	get_root().add_child(shell)
	await process_frame
	var profile_result: Dictionary = shell._load_interaction_profile()
	_assert(bool(profile_result.get("success", false)), "R5 shell resolves 7 Days profile")
	shell._build_ui()
	_assert(
		shell.inventory_window.get_node_or_null("Margin/Main/NetworkedActions/PlayerSortButton") != null,
		"7 Days product composition restores Sort button"
	)
	_assert(
		shell.inventory_window.get_node_or_null("Margin/Main/NetworkedActions/ExternalSortButton") != null,
		"external-container sort action is present"
	)
	_assert(shell.has_method("_drop_network_cursor_to_world"), "R5 shell owns carried-item outside-drop presentation path")
	_assert(shell.has_method("_sort_visible_container"), "R5 shell owns authoritative sort trigger")
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
	print("V0-P1 R5 inventory parity: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
