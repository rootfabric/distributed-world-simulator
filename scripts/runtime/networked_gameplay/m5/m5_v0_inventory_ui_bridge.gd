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
# to canonical slot_index. R6 also preserves the displaced item as transient
# cursor state after an authoritative atomic swap and restores rev6 merge->sort.


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
		var accepted: Dictionary = _accept_snapshot(Dictionary(initial_value))
		if not bool(accepted.get("success", false)):
			stop()
			return accepted
	return _success({"ready": not _projection.get_snapshot().is_empty()})


func place_cursor_blocking(
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = "",
	quantity_mode: String = "ALL",
	operation_id: String = ""
) -> Dictionary:
	var result: Dictionary = super.place_cursor_blocking(
		target_container_id,
		target_slot_index,
		target_item_id,
		quantity_mode,
		operation_id
	)
	if not bool(result.get("success", false)):
		return result
	var canonical_details: Dictionary = _canonical_command_details(result)
	if not bool(canonical_details.get("swapped", false)):
		return result
	var displaced_item_id := String(canonical_details.get("displaced_item_id", ""))
	var displaced_quantity := int(canonical_details.get("displaced_quantity", 0))
	var displaced_container_id := String(canonical_details.get("displaced_container_id", ""))
	var displaced_slot_index := int(canonical_details.get("displaced_slot_index", -1))
	var replacement: Dictionary = _transient.replace_cursor_after_operation(
		String(result.get("operation_id", "")),
		displaced_item_id,
		displaced_quantity,
		displaced_container_id,
		displaced_slot_index,
		int(_projection.get_report().get("revision", -1))
	)
	if not bool(replacement.get("success", false)):
		result["transient_error_code"] = String(
			replacement.get("error_code", "SWAP_CURSOR_REPLACEMENT_FAILED")
		)
		return result
	result["cursor_swapped"] = true
	result["canonical_details"] = canonical_details.duplicate(true)
	_refresh_view()
	return result


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
	var result: Dictionary = submit_ui_action_blocking("drop", {
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
	var initial_model: Dictionary = _model_for_container(container_id)
	if initial_model.is_empty():
		return _failure("SORT_CONTAINER_NOT_VISIBLE", {"container_id": container_id})
	var merge_result: Dictionary = _merge_compatible_stacks_for_sort(container_id)
	if not bool(merge_result.get("success", false)):
		return merge_result
	var merged_count := int(merge_result.get("details", {}).get("merged", 0))
	var model: Dictionary = _model_for_container(container_id)
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
		return _success({
			"container_id": container_id,
			"moved": 0,
			"merged": merged_count,
			"already_sorted": true,
		})
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
			var displaced_move: Dictionary = _move_for_sort(
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
		var desired_move: Dictionary = _move_for_sort(
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
	return _success({
		"container_id": container_id,
		"moved": moved_count,
		"merged": merged_count,
		"already_sorted": moved_count == 0,
	})


func _merge_compatible_stacks_for_sort(container_id: String) -> Dictionary:
	var merged_count: int = 0
	for _iteration in range(2048):
		var model: Dictionary = _model_for_container(container_id)
		if model.is_empty():
			return _failure("SORT_CONTAINER_NOT_VISIBLE", {"container_id": container_id})
		var candidate: Dictionary = _find_sort_merge_candidate(model)
		if candidate.is_empty():
			return _success({"container_id": container_id, "merged": merged_count})
		var source: Dictionary = Dictionary(candidate.get("source", {}))
		var target: Dictionary = Dictionary(candidate.get("target", {}))
		var amount: int = int(candidate.get("quantity", 0))
		if amount < 1:
			return _failure("SORT_STACK_MERGE_INVALID")
		var merge: Dictionary = submit_ui_action_blocking("transfer", {
			"item_id": String(source.get("item_id", "")),
			"quantity": amount,
			"source_quantity": int(source.get("quantity", amount)),
			"source_container_id": container_id,
			"source_slot_index": int(source.get("source_slot_index", -1)),
			"target_container_id": container_id,
			"target_slot_index": int(target.get("source_slot_index", -1)),
			"target_item_id": String(target.get("item_id", "")),
		})
		if not bool(merge.get("success", false)):
			return merge
		merged_count += 1
	return _failure("SORT_STACK_MERGE_LIMIT", {"container_id": container_id})


func _find_sort_merge_candidate(model: Dictionary) -> Dictionary:
	var cells: Array = Array(model.get("cells", []))
	for target_index in range(cells.size()):
		if not cells[target_index] is Dictionary:
			continue
		var target: Dictionary = cells[target_index]
		var target_item_id := String(target.get("item_id", ""))
		var definition_id := String(target.get("definition_id", ""))
		var max_stack := int(target.get("max_stack", 1))
		var target_quantity := int(target.get("quantity", 0))
		if (
			target_item_id.is_empty()
			or definition_id.is_empty()
			or max_stack <= 1
			or target_quantity >= max_stack
		):
			continue
		for source_index in range(target_index + 1, cells.size()):
			if not cells[source_index] is Dictionary:
				continue
			var source: Dictionary = cells[source_index]
			if (
				String(source.get("item_id", "")).is_empty()
				or String(source.get("definition_id", "")) != definition_id
			):
				continue
			var source_quantity := int(source.get("quantity", 0))
			var moved := mini(max_stack - target_quantity, source_quantity)
			if moved > 0:
				return {
					"source": source.duplicate(true),
					"target": target.duplicate(true),
					"quantity": moved,
				}
	return {}


func _canonical_command_details(result: Dictionary) -> Dictionary:
	var outer_details: Dictionary = Dictionary(result.get("details", {}))
	var wire_result_value = outer_details.get("result", {})
	if wire_result_value is Dictionary:
		var wire_result: Dictionary = Dictionary(wire_result_value)
		var wire_details_value = wire_result.get("details", {})
		if wire_details_value is Dictionary:
			return Dictionary(wire_details_value).duplicate(true)
	return outer_details.duplicate(true)


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
