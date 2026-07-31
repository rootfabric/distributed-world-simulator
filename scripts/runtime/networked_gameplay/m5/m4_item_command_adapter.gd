extends RefCounted

signal command_started(operation: Dictionary)
signal command_finished(result: Dictionary)

const SCHEMA := "planet_simulator.m5_m4_item_command_adapter.v1"

var _runtime
var _logical_player_id := ""
var _operation_sequence := 0
var _submitted_count := 0
var _rejected_count := 0
var _last_command: Dictionary = {}
var _last_result: Dictionary = {}


func setup(runtime, logical_player_id: String) -> Dictionary:
	if runtime == null or not runtime.has_method("execute_item_command_blocking"):
		return _failure("INVALID_M4_CLIENT_RUNTIME")
	var normalized_player_id := logical_player_id.strip_edges().to_lower()
	if normalized_player_id.is_empty():
		return _failure("PLAYER_ID_REQUIRED")
	_runtime = runtime
	_logical_player_id = normalized_player_id
	return _success()


func preview_action(action_id: String, ui_payload: Dictionary) -> Dictionary:
	var normalized := _normalize_action(action_id, ui_payload)
	if not bool(normalized.get("success", false)):
		return normalized
	return _success({
		"command_type": String(normalized.get("details", {}).get("command_type", "")),
		"payload": Dictionary(normalized.get("details", {}).get("payload", {})).duplicate(true),
		"ui_context": Dictionary(normalized.get("details", {}).get("ui_context", {})).duplicate(true),
		"canonical_mutation": false,
	})


func submit_action_blocking(
	action_id: String,
	ui_payload: Dictionary,
	operation_id: String = ""
) -> Dictionary:
	if _runtime == null:
		return _failure("M4_COMMAND_ADAPTER_NOT_CONFIGURED")
	var normalized := _normalize_action(action_id, ui_payload)
	if not bool(normalized.get("success", false)):
		_rejected_count += 1
		_last_result = normalized.duplicate(true)
		return normalized
	var details: Dictionary = normalized.get("details", {})
	var command_type := String(details.get("command_type", ""))
	var payload: Dictionary = Dictionary(details.get("payload", {})).duplicate(true)
	var resolved_operation_id := operation_id.strip_edges()
	if resolved_operation_id.is_empty():
		_operation_sequence += 1
		resolved_operation_id = "operation/m5-ui/%s/%d/%d" % [
			_logical_player_id,
			OS.get_process_id(),
			_operation_sequence,
		]
	_last_command = {
		"schema": SCHEMA,
		"action_id": action_id,
		"command_type": command_type,
		"payload": payload.duplicate(true),
		"ui_context": Dictionary(details.get("ui_context", {})).duplicate(true),
		"operation_id": resolved_operation_id,
	}
	command_started.emit(_last_command.duplicate(true))
	_submitted_count += 1
	var runtime_result_value = _runtime.call(
		"execute_item_command_blocking",
		command_type,
		payload.duplicate(true),
		resolved_operation_id
	)
	if not runtime_result_value is Dictionary:
		_last_result = _failure("INVALID_M4_COMMAND_RESULT")
		_rejected_count += 1
		command_finished.emit(_last_result.duplicate(true))
		return _last_result.duplicate(true)
	_last_result = Dictionary(runtime_result_value).duplicate(true)
	_last_result["operation_id"] = resolved_operation_id
	_last_result["action_id"] = action_id
	_last_result["command_type"] = command_type
	_last_result["ui_context"] = Dictionary(details.get("ui_context", {})).duplicate(true)
	if not bool(_last_result.get("success", false)):
		_rejected_count += 1
	command_finished.emit(_last_result.duplicate(true))
	return _last_result.duplicate(true)


func preview_transfer(
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	var action := "transfer"
	var payload := {
		"item_id": item_id,
		"quantity": quantity,
		"target_container_id": target_container_id,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id,
	}
	var preview := preview_action(action, payload)
	if bool(preview.get("success", false)):
		preview["maximum_quantity"] = quantity if quantity > 0 else 2147483647
		preview["whole_stack_fits"] = true
	return preview


func get_report() -> Dictionary:
	return {
		"schema": "planet_simulator.m5_m4_item_command_adapter_report.v1",
		"configured": _runtime != null,
		"logical_player_id": _logical_player_id,
		"submitted_count": _submitted_count,
		"rejected_count": _rejected_count,
		"last_command": _last_command.duplicate(true),
		"last_result": _last_result.duplicate(true),
		"authority_references": 0,
		"domain_references": 0,
	}


func _normalize_action(action_id: String, ui_payload: Dictionary) -> Dictionary:
	var action := action_id.strip_edges().to_lower()
	var context := ui_payload.duplicate(true)
	match action:
		"pickup", "item.pickup":
			return _command("item.pickup", {"item_id": _required_id(ui_payload, "item_id")}, context)
		"drop", "item.drop":
			var drop_payload := {"item_id": _required_id(ui_payload, "item_id")}
			var quantity := int(ui_payload.get("quantity", -1))
			if quantity != -1:
				drop_payload["quantity"] = quantity
			else:
				drop_payload["quantity"] = -1
			return _command("item.drop", drop_payload, context)
		"split", "item.split":
			return _command("item.split", {
				"item_id": _required_id(ui_payload, "item_id"),
				"quantity": int(ui_payload.get("quantity", 0)),
			}, context)
		"stack", "item.stack":
			return _command("item.stack", {
				"source_item_id": _required_id(ui_payload, "source_item_id", "item_id"),
				"target_item_id": _required_id(ui_payload, "target_item_id"),
			}, context)
		"select_hotbar", "inventory.select_hotbar":
			return _command("inventory.select_hotbar", {
				"selected_hotbar_index": int(ui_payload.get("selected_hotbar_index", ui_payload.get("slot_index", -1))),
			}, context)
		"assign_hotbar", "inventory.assign_hotbar":
			return _command("inventory.assign_hotbar", {
				"item_id": _required_id(ui_payload, "item_id"),
				"slot_index": int(ui_payload.get("slot_index", ui_payload.get("target_slot_index", -1))),
			}, context)
		"open_container", "container.open":
			return _command("container.open", {
				"container_id": _required_id(ui_payload, "container_id", "target_container_id"),
			}, context)
		"close_container", "container.close":
			return _command("container.close", {
				"container_id": _required_id(ui_payload, "container_id", "target_container_id"),
			}, context)
		"move_to_container", "item.move_to_container":
			return _command("item.move_to_container", {
				"item_id": _required_id(ui_payload, "item_id"),
				"container_id": _required_id(ui_payload, "container_id", "target_container_id"),
			}, context)
		"transfer":
			var item_id := _required_id(ui_payload, "item_id")
			var source_container_id := String(ui_payload.get("source_container_id", "")).strip_edges()
			var target_container_id := String(ui_payload.get("target_container_id", "")).strip_edges()
			var target_item_id := String(ui_payload.get("target_item_id", "")).strip_edges()
			var quantity := int(ui_payload.get("quantity", -1))
			var source_quantity := int(ui_payload.get("source_quantity", quantity))
			if target_container_id.begins_with("mount/"):
				return _command("item.mount", {
					"item_id": item_id,
					"mount_id": target_container_id,
				}, context)
			if source_container_id.begins_with("mount/") and target_container_id.begins_with("inventory/"):
				return _command("item.detach", {"mount_id": source_container_id}, context)
			if source_container_id.begins_with("world/") and target_container_id.begins_with("inventory/") and (quantity < 0 or quantity == source_quantity):
				return _command("item.pickup", {"item_id": item_id}, context)
			if (
				target_container_id.begins_with("container/")
				or target_container_id.begins_with("inventory/")
				or target_container_id.begins_with("hotbar/")
			):
				var transfer_payload := {
					"item_id": item_id,
					"quantity": quantity,
					"target_container_id": target_container_id,
					"target_slot_index": int(ui_payload.get("target_slot_index", -1)),
				}
				if not target_item_id.is_empty():
					transfer_payload["target_item_id"] = target_item_id
				return _command("item.transfer", transfer_payload, context)
			return _failure("M5_TRANSFER_TARGET_NOT_SUPPORTED", {
				"source_container_id": source_container_id,
				"target_container_id": target_container_id,
			})
		"mount", "item.mount":
			return _command("item.mount", {
				"item_id": _required_id(ui_payload, "item_id"),
				"mount_id": _required_id(ui_payload, "mount_id", "socket_id"),
			}, context)
		"detach", "item.detach":
			return _command("item.detach", {
				"mount_id": _required_id(ui_payload, "mount_id", "socket_id"),
			}, context)
		"permission_probe", "inventory.permission_probe":
			return _command("inventory.permission_probe", {
				"target_player_id": _required_id(ui_payload, "target_player_id"),
			}, context)
		_:
			return _failure("UNSUPPORTED_M5_UI_ACTION", {"action_id": action_id})


func _command(command_type: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	for value in payload.values():
		if value is String and String(value).strip_edges().is_empty():
			return _failure("M5_UI_ACTION_FIELD_REQUIRED", {"command_type": command_type})
	if command_type == "item.split" and int(payload.get("quantity", 0)) < 1:
		return _failure("INVALID_SPLIT_QUANTITY")
	if command_type == "inventory.select_hotbar":
		var index := int(payload.get("selected_hotbar_index", -1))
		if index < 0 or index > 7:
			return _failure("INVALID_HOTBAR_INDEX")
	if command_type == "inventory.assign_hotbar":
		var slot_index := int(payload.get("slot_index", -1))
		if slot_index < 0 or slot_index > 7:
			return _failure("INVALID_HOTBAR_INDEX")
	if command_type == "item.transfer" and int(payload.get("quantity", -1)) == 0:
		return _failure("INVALID_TRANSFER_QUANTITY")
	return _success({
		"command_type": command_type,
		"payload": payload.duplicate(true),
		"ui_context": context.duplicate(true),
	})


func _required_id(payload: Dictionary, primary: String, fallback: String = "") -> String:
	var value := String(payload.get(primary, "")).strip_edges()
	if value.is_empty() and not fallback.is_empty():
		value = String(payload.get(fallback, "")).strip_edges()
	return value


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
