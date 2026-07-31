extends Node

signal view_updated(view: Dictionary)
signal command_completed(result: Dictionary)

const ItemGraphProjection = preload("res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection.gd")
const CommandAdapter = preload("res://scripts/runtime/networked_gameplay/m5/m4_item_command_adapter.gd")
const TransientState = preload("res://scripts/runtime/networked_gameplay/m5/m4_inventory_transient_state.gd")

const SCHEMA := "planet_simulator.m5_inventory_ui_bridge.v1"

var _runtime
var _logical_player_id := ""
var _projection
var _commands
var _transient
var _external_container_id := ""
var _selected_item_id := ""
var _last_view: Dictionary = {}
var _configured := false
var _view_updates := 0
var _command_count := 0
var _rejection_count := 0


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
	_projection = ItemGraphProjection.new()
	_commands = CommandAdapter.new()
	_transient = TransientState.new()
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


func submit_ui_action_blocking(
	action_id: String,
	ui_payload: Dictionary,
	operation_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	var preview: Dictionary = _commands.preview_action(action_id, ui_payload)
	if not bool(preview.get("success", false)):
		_rejection_count += 1
		return preview
	var base_revision := int(_projection.get_report().get("revision", -1))
	var result: Dictionary = _commands.submit_action_blocking(action_id, ui_payload, operation_id)
	_command_count += 1
	if not bool(result.get("success", false)):
		_rejection_count += 1
	return result


func preview_transfer(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	var source := find_cell(item_id)
	return _commands.preview_action("transfer", {
		"item_id": item_id,
		"quantity": quantity,
		"source_quantity": int(source.get("quantity", quantity)),
		"source_container_id": String(source.get("source_container_id", "")),
		"source_slot_index": int(source.get("source_slot_index", -1)),
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id,
	})


func begin_cursor_carry(
	item_id: String,
	quantity: int,
	source_container_id: String,
	source_slot_index: int
) -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	var revision := int(_projection.get_report().get("revision", -1))
	var result: Dictionary = _transient.begin_cursor_carry(
		item_id,
		quantity,
		source_container_id,
		source_slot_index,
		revision
	)
	if bool(result.get("success", false)):
		_refresh_view()
	return result


func begin_cursor_from_cell(cell_data: Dictionary, quantity_mode: String = "ALL") -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	var item_id := String(cell_data.get("item_id", "")).strip_edges()
	var total_quantity := int(cell_data.get("quantity", 0))
	if item_id.is_empty() or total_quantity < 1:
		return _failure("INVALID_CURSOR_SOURCE")
	var quantity := total_quantity
	if quantity_mode == "HALF_CEIL":
		quantity = maxi(1, int(ceil(float(total_quantity) * 0.5)))
	return begin_cursor_carry(
		item_id,
		quantity,
		String(cell_data.get("source_container_id", "")),
		int(cell_data.get("source_slot_index", -1))
	)


func place_cursor_blocking(
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = "",
	quantity_mode: String = "ALL",
	operation_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("M5_UI_BRIDGE_NOT_CONFIGURED")
	if not _transient.has_cursor():
		return _failure("CURSOR_NOT_ACTIVE")
	var cursor: Dictionary = _transient.get_cursor()
	var cursor_quantity := int(cursor.get("quantity", 0))
	var transfer_quantity := cursor_quantity if quantity_mode != "ONE" else 1
	var remaining_quantity := maxi(0, cursor_quantity - transfer_quantity)
	return submit_ui_action_blocking("transfer", {
		"item_id": String(cursor.get("item_id", "")),
		"quantity": transfer_quantity,
		"source_quantity": cursor_quantity,
		"source_container_id": String(cursor.get("source_container_id", "")),
		"source_slot_index": int(cursor.get("source_slot_index", -1)),
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id,
		"cursor_remaining_quantity": remaining_quantity,
	}, operation_id)


func has_cursor() -> bool:
	return _transient != null and _transient.has_cursor()


func get_cursor() -> Dictionary:
	return _transient.get_cursor() if _transient != null else {}


func find_cell(item_id: String) -> Dictionary:
	for key in ["player", "hotbar", "external", "world", "mounts_view"]:
		var container: Dictionary = Dictionary(_last_view.get(key, {}))
		for cell_value in container.get("cells", []):
			if cell_value is Dictionary and String(cell_value.get("item_id", "")) == item_id:
				return Dictionary(cell_value).duplicate(true)
	return {}


func cancel_cursor() -> Dictionary:
	var result: Dictionary = _transient.cancel_cursor()
	_refresh_view()
	return result


func set_external_container(container_id: String) -> void:
	_external_container_id = container_id.strip_edges()
	_refresh_view()


func set_selected_item(item_id: String) -> void:
	_selected_item_id = item_id.strip_edges()
	_refresh_view()


func build_view() -> Dictionary:
	if not _configured:
		return {
			"schema": SCHEMA,
			"success": false,
			"error_code": "M5_UI_BRIDGE_NOT_CONFIGURED",
		}
	return _projection.build_screen(
		_logical_player_id,
		_external_container_id,
		_selected_item_id,
		_transient.create_overlay()
	)


func get_last_view() -> Dictionary:
	return _last_view.duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"logical_player_id": _logical_player_id,
		"external_container_id": _external_container_id,
		"selected_item_id": _selected_item_id,
		"view_updates": _view_updates,
		"command_count": _command_count,
		"rejection_count": _rejection_count,
		"projection": _projection.get_report() if _projection != null else {},
		"commands": _commands.get_report() if _commands != null else {},
		"transient": _transient.get_report() if _transient != null else {},
		"authority_references": 0,
		"domain_references": 0,
	}


func stop() -> void:
	if _runtime != null and _runtime.has_signal("item_graph_updated"):
		if _runtime.item_graph_updated.is_connected(_on_item_graph_updated):
			_runtime.item_graph_updated.disconnect(_on_item_graph_updated)
	if _commands != null:
		if _commands.command_started.is_connected(_on_command_started):
			_commands.command_started.disconnect(_on_command_started)
		if _commands.command_finished.is_connected(_on_command_finished):
			_commands.command_finished.disconnect(_on_command_finished)
	_runtime = null
	_configured = false


func _on_item_graph_updated(snapshot: Dictionary) -> void:
	_accept_snapshot(snapshot)


func _accept_snapshot(snapshot: Dictionary) -> Dictionary:
	var accepted: Dictionary = _projection.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_rejection_count += 1
		return accepted
	_transient.accept_snapshot(snapshot)
	var open_container := String(snapshot.get("open_containers", {}).get(_logical_player_id, ""))
	_external_container_id = open_container
	_refresh_view()
	return accepted


func _on_command_started(command: Dictionary) -> void:
	var operation_id := String(command.get("operation_id", ""))
	_transient.register_pending(
		operation_id,
		command,
		int(_projection.get_report().get("revision", -1))
	)
	_refresh_view()


func _on_command_finished(result: Dictionary) -> void:
	_transient.accept_command_result(result)
	var snapshot: Dictionary = _projection.get_snapshot()
	if not snapshot.is_empty():
		_transient.accept_snapshot(snapshot)
	_refresh_view()
	command_completed.emit(result.duplicate(true))


func _refresh_view() -> void:
	if not _configured or _projection == null:
		return
	_last_view = build_view()
	_view_updates += 1
	view_updated.emit(_last_view.duplicate(true))


func _exit_tree() -> void:
	stop()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
