extends "res://scripts/runtime/networked_gameplay/m5/m5_inventory_ui_bridge.gd"

const P1SlotProjection = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection_p1_slots.gd"
)
const P1CommandAdapter = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_item_command_adapter.gd"
)
const P1TransientState = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_inventory_transient_state.gd"
)

# P1 keeps the accepted M5 bridge boundary but swaps only its derived projection
# to canonical slot_index and adds two UI transactions: confirmed cursor drop
# and serial authoritative sort. Neither path mutates Item Graph locally.


func setup(runtime, logical_player_id: String) -> Dictionary:
	if _configured:
		return _failure("M5_UI_BRIDGE_ALREADY_CONFIGURED")
	if runtime == null:
		return _failure("INVALID_M5_CLIENT_RUNTIME")
	for method_name in ["get_item_graph_snapshot", "execute_item_command_blocking"]:
		if not runtime.has_method(method_name):
			return _failure("M5_CLIENT_RUNTIME_METHOD_MISSING", {"method": method_name})
	if not runtime.has_signal("item_graph_updated"):
		return _failure("M5_CLIENT_RUNTIME_SIGNAL_MISSING")
	_logical_player_id = logical_player_id.strip_edges().to_lower()
	if _logical_player_id.is_empty():
		return _failure("PLAYER_ID_REQUIRED")
	_runtime = runtime
	_projection = P1SlotProjection.new()
	_commands = P1CommandAdapter.new()
	_transient = P1TransientState.new()
	var command_setup: Dictionary = _commands.setup(runtime, _logical_player_id)
	if not bool(command_setup.get("success", false)):
		return command_setup
	_commands.command_started.connect(_on_command_started)
	_commands.command_finished.connect(_on_command_finished)
	_runtime.item_graph_updated.connect(_on_item_graph_updated)
	_configured = true
	var initial_value = _runtime.call("get_item_graph_snapshot")
	if initial_value is Dictionary and not Dictionary(initial_value).is_empty():
		var accepted := _accept_snapshot(Dictionary(initial_value))
		if not bool(accepted.get("success", false)):
			stop()
			return accepted
	return _success({"ready": not _projection.get_snapshot().is_empty()})


func drop_cursor_blocking(quantity_mode: String = "ALL", operation_id: String = "") -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	if not _transient.has_cursor():
		return _failure("CURSOR_NOT_ACTIVE")
	var cursor: Dictionary = _transient.get_cursor()
	var cursor_quantity := int(cursor.get("quantity", 0))
	if cursor_quantity < 1:
		return _failure("INVALID_CURSOR_CARRY")
	var drop_quantity := 1 if quantity_mode.strip_edges().to_upper() == "ONE" else cursor_quantity
	var remaining_quantity := maxi(0, cursor_quantity - drop_quantity)
	var result := submit_ui_action_blocking("drop", {
		"item_id": String(cursor.get("item_id", "")),
		"quantity": drop_quantity,
		"source_container_id": String(cursor.get("source_container_id", "")),
		"source_slot_index": int(cursor.get("source_slot_index", -1)),
		"cursor_remaining_quantity": remaining_quantity,
	}, operation_id)
	if bool(result.get("success", false)):
		_transient.update_cursor_quantity(remaining_quantity)
		_refresh_view()
	return result


func sort_container_blocking(container_id: String) -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	if has_cursor():
		return _failure("SORT_CURSOR_ACTIVE")
	var model := _model_for_container(container_id)
	if model.is_empty():
		return _failure("SORT_CONTAINER_NOT_VISIBLE", {"container_id": container_id})
	var slot_count := int(model.get("slot_count", 0))
	if slot_count < 1:
		return _failure("SORT_CONTAINER_EMPTY")
	var occupancy: Array = []
	for _index in range(slot_count):
		occupancy.append("")
	var metadata: Dictionary = {}
	var desired: Array[String] = []
	for cell_value in model.get("cells", []):
		if not cell_value is Dictionary:
			continue
		var cell: Dictionary = cell_value
		var item_id := String(cell.get("item_id", ""))
		var slot_index := int(cell.get("source_slot_index", -1))
		if item_id.is_empty() or slot_index < 0 or slot_index >= slot_count:
			continue
		occupancy[slot_index] = item_id
		metadata[item_id] = cell.duplicate(true)
		desired.append(item_id)
	if desired.size() < 2:
		return _success({"container_id": container_id, "moved": 0, "already_sorted": true})
	desired.sort_custom(func(a: String, b: String) -> bool:
		var ca: Dictionary = metadata[a]
		var cb: Dictionary = metadata[b]
		var name_compare := String(ca.get("display_name", "")).naturalnocasecmp_to(
			String(cb.get("display_name", ""))
		)
		if name_compare != 0:
			return name_compare < 0
		var def_compare := String(ca.get("definition_id", "")).naturalnocasecmp_to(
			String(cb.get("definition_id", ""))
		)
		return def_compare < 0 if def_compare != 0 else a < b
	)
	var moved_count := 0
	for target_slot in range(desired.size()):
		var desired_id := desired[target_slot]
		if String(occupancy[target_slot]) == desired_id:
			continue
		var desired_slot := occupancy.find(desired_id)
		if desired_slot < 0:
			return _failure("SORT_ITEM_LOST", {"item_id": desired_id})
		var displaced_id := String(occupancy[target_slot])
		if not displaced_id.is_empty():
			var temp_slot := occupancy.find("")
			if temp_slot < 0:
				return _failure("SORT_REQUIRES_FREE_SLOT", {"container_id": container_id})
			var displaced_move := _move_for_sort(
				displaced_id,
				container_id,
				target_slot,
				temp_slot,
				metadata
			)
			if not bool(displaced_move.get("success", false)):
				return displaced_move
			occupancy[temp_slot] = displaced_id
			occupancy[target_slot] = ""
			moved_count += 1
		var desired_move := _move_for_sort(
			desired_id,
			container_id,
			desired_slot,
			target_slot,
			metadata
		)
		if not bool(desired_move.get("success", false)):
			return desired_move
		occupancy[target_slot] = desired_id
		occupancy[desired_slot] = ""
		moved_count += 1
	return _success({"container_id": container_id, "moved": moved_count, "already_sorted": moved_count == 0})


func _move_for_sort(
	item_id: String,
	container_id: String,
	from_slot: int,
	to_slot: int,
	metadata: Dictionary
) -> Dictionary:
	var cell: Dictionary = Dictionary(metadata.get(item_id, {}))
	return submit_ui_action_blocking("transfer", {
		"item_id": item_id,
		"quantity": -1,
		"source_quantity": int(cell.get("quantity", 1)),
		"source_container_id": container_id,
		"source_slot_index": from_slot,
		"target_container_id": container_id,
		"target_slot_index": to_slot,
		"target_item_id": "",
	})


func _model_for_container(container_id: String) -> Dictionary:
	var player: Dictionary = Dictionary(_last_view.get("player", {}))
	if String(player.get("container_id", "")) == container_id:
		return player
	var external: Dictionary = Dictionary(_last_view.get("external", {}))
	if String(external.get("container_id", "")) == container_id:
		return external
	return {}
