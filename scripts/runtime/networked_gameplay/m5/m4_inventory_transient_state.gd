extends RefCounted

const SCHEMA := "planet_simulator.m5_inventory_transient_state.v1"

var _cursor: Dictionary = {}
var _pending: Dictionary = {}
var _result_history: Array[Dictionary] = []
var _last_snapshot_revision := -1


func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	var revision := int(snapshot.get("revision", -1))
	if revision < _last_snapshot_revision:
		return _failure("TRANSIENT_SNAPSHOT_REVISION_ROLLBACK")
	_last_snapshot_revision = revision
	var completed: Array[String] = []
	var preserve_cursor := false
	for operation_id_value in _pending.keys():
		var operation_id := String(operation_id_value)
		var record: Dictionary = _pending[operation_id]
		if String(record.get("status", "")) == "SUCCEEDED" and revision > int(record.get("base_revision", -1)):
			completed.append(operation_id)
			preserve_cursor = preserve_cursor or bool(record.get("preserve_cursor", false))
	for operation_id in completed:
		_pending.erase(operation_id)
	if not _cursor.is_empty() and not completed.is_empty() and not preserve_cursor:
		_cursor.clear()
	return _success({"revision": revision, "completed_operations": completed})


func begin_cursor_carry(
	item_id: String,
	quantity: int,
	source_container_id: String,
	source_slot_index: int,
	base_revision: int
) -> Dictionary:
	if not _cursor.is_empty():
		return _failure("CURSOR_ALREADY_ACTIVE")
	return replace_cursor_carry(
		item_id,
		quantity,
		source_container_id,
		source_slot_index,
		base_revision
	)


func replace_cursor_carry(
	item_id: String,
	quantity: int,
	source_container_id: String,
	source_slot_index: int,
	base_revision: int
) -> Dictionary:
	if item_id.strip_edges().is_empty() or quantity < 1:
		return _failure("INVALID_CURSOR_CARRY")
	if source_container_id.strip_edges().is_empty() or source_slot_index < 0:
		return _failure("INVALID_CURSOR_SOURCE")
	_cursor = {
		"item_id": item_id,
		"quantity": quantity,
		"source_container_id": source_container_id,
		"source_slot_index": source_slot_index,
		"base_revision": base_revision,
		"canonical_mutation": false,
	}
	return _success({"cursor": _cursor.duplicate(true)})


func replace_cursor_after_operation(
	operation_id: String,
	item_id: String,
	quantity: int,
	source_container_id: String,
	source_slot_index: int,
	base_revision: int
) -> Dictionary:
	var replaced := replace_cursor_carry(
		item_id,
		quantity,
		source_container_id,
		source_slot_index,
		base_revision
	)
	if not bool(replaced.get("success", false)):
		return replaced
	var normalized_operation_id := operation_id.strip_edges()
	if _pending.has(normalized_operation_id):
		var record: Dictionary = _pending[normalized_operation_id]
		if String(record.get("status", "")) == "SUCCEEDED":
			record["preserve_cursor"] = true
			_pending[normalized_operation_id] = record
	return replaced


func cancel_cursor() -> Dictionary:
	var previous := _cursor.duplicate(true)
	_cursor.clear()
	return _success({"cancelled": previous})


func register_pending(operation_id: String, command: Dictionary, base_revision: int) -> Dictionary:
	var normalized_id := operation_id.strip_edges()
	if normalized_id.is_empty():
		return _failure("OPERATION_ID_REQUIRED")
	if _pending.has(normalized_id):
		return _failure("PENDING_OPERATION_EXISTS")
	_pending[normalized_id] = {
		"operation_id": normalized_id,
		"command": command.duplicate(true),
		"base_revision": base_revision,
		"status": "PENDING",
		"canonical_mutation": false,
	}
	return _success({"pending": Dictionary(_pending[normalized_id]).duplicate(true)})


func accept_command_result(result: Dictionary) -> Dictionary:
	var operation_id := String(result.get("operation_id", "")).strip_edges()
	if operation_id.is_empty() or not _pending.has(operation_id):
		return _failure("PENDING_OPERATION_NOT_FOUND")
	var record: Dictionary = _pending[operation_id]
	var succeeded := bool(result.get("success", false))
	record["status"] = "SUCCEEDED" if succeeded else "REJECTED"
	record["result"] = result.duplicate(true)
	var ui_context: Dictionary = Dictionary(result.get("ui_context", {}))
	var remaining_quantity := int(ui_context.get("cursor_remaining_quantity", 0))
	record["preserve_cursor"] = succeeded and remaining_quantity > 0
	if succeeded and remaining_quantity > 0 and not _cursor.is_empty():
		_cursor["quantity"] = remaining_quantity
	_pending[operation_id] = record
	_result_history.append(record.duplicate(true))
	if not succeeded:
		# Rejection means authority consumed nothing. Keep the presentation-only
		# carry so the user can choose another target or cancel explicitly.
		_pending.erase(operation_id)
	return _success({"status": record["status"], "operation_id": operation_id})


func has_cursor() -> bool:
	return not _cursor.is_empty()


func get_cursor() -> Dictionary:
	return _cursor.duplicate(true)


func update_cursor_quantity(quantity: int) -> Dictionary:
	if _cursor.is_empty():
		return _failure("CURSOR_NOT_ACTIVE")
	if quantity < 1:
		_cursor.clear()
		return _success({"cursor": {}})
	_cursor["quantity"] = quantity
	return _success({"cursor": _cursor.duplicate(true)})


func create_overlay() -> Dictionary:
	var pending_item_ids := PackedStringArray()
	for record_value in _pending.values():
		var command: Dictionary = Dictionary(Dictionary(record_value).get("command", {}))
		var payload: Dictionary = command.get("payload", {})
		for field in ["item_id", "source_item_id"]:
			var item_id := String(payload.get(field, ""))
			if not item_id.is_empty() and not pending_item_ids.has(item_id):
				pending_item_ids.append(item_id)
	var hidden_item_ids := PackedStringArray()
	var cursor_item_id := String(_cursor.get("item_id", ""))
	if not cursor_item_id.is_empty():
		hidden_item_ids.append(cursor_item_id)
	return {
		"schema": SCHEMA,
		"cursor": _cursor.duplicate(true),
		"pending_operations": _pending.duplicate(true),
		"pending_item_ids": Array(pending_item_ids),
		"hidden_item_ids": Array(hidden_item_ids),
		"canonical_mutation": false,
	}


func get_report() -> Dictionary:
	return {
		"schema": "planet_simulator.m5_inventory_transient_state_report.v1",
		"cursor_active": not _cursor.is_empty(),
		"pending_count": _pending.size(),
		"result_history_count": _result_history.size(),
		"last_snapshot_revision": _last_snapshot_revision,
		"canonical_mutation_count": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
