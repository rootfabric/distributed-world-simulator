extends RefCounted

const Adapter = preload("res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd")

const SCHEMA := "planet_simulator.m7_network_item_command_bridge.v1"

var _runtime
var _adapter
var _local_player_id := ""
var _selected_item_provider: Callable
var _submitted := 0
var _accepted := 0
var _rejected := 0
var _last_error_code := ""
var _last_error_message := ""


func setup(runtime, local_player_id: String, selected_item_provider: Callable = Callable()) -> Dictionary:
	if runtime == null or not runtime.has_method("execute_item_command_blocking") or not runtime.has_method("get_item_graph_snapshot"):
		return _failure("M7_INVALID_CLIENT_RUNTIME")
	_runtime = runtime
	_local_player_id = local_player_id.strip_edges().to_lower()
	_selected_item_provider = selected_item_provider
	_adapter = Adapter.new()
	var adapter_setup: Dictionary = _adapter.setup(_local_player_id)
	if not bool(adapter_setup.get("success", false)):
		return adapter_setup
	return _success()


func submit_item_command(command_type: String, payload: Dictionary, operation_id: String) -> Dictionary:
	if _runtime == null or _adapter == null:
		return _failure("M7_ITEM_BRIDGE_NOT_CONFIGURED")
	var normalized := _normalize(command_type, _canonicalize_item_ids(payload))
	if not bool(normalized.get("success", false)):
		_rejected += 1
		_record_rejection(command_type, operation_id, normalized)
		_attach_human_error(normalized)
		return normalized
	_submitted += 1
	var details: Dictionary = Dictionary(normalized.get("details", {}))
	var result: Dictionary = _runtime.execute_item_command_blocking(
		String(details.get("command_type", command_type)),
		Dictionary(details.get("payload", payload)),
		operation_id
	)
	if bool(result.get("success", false)):
		_accepted += 1
		_last_error_code = ""
		_last_error_message = ""
	else:
		_rejected += 1
		_record_rejection(command_type, operation_id, result)
		_attach_human_error(result)
	var canonical: Dictionary = _runtime.get_item_graph_snapshot()
	var converted: Dictionary = _adapter.create_replica_snapshot(canonical)
	if not bool(converted.get("success", false)):
		return _failure("M7_ITEM_REPLICA_CONVERSION_FAILED", converted)
	var converted_details: Dictionary = Dictionary(converted.get("details", {}))
	result["replica_snapshot"] = converted_details.get("replica_snapshot", {})
	return result


func convert_snapshot(canonical_snapshot: Dictionary) -> Dictionary:
	if _adapter == null:
		return _failure("M7_ITEM_BRIDGE_NOT_CONFIGURED")
	return _adapter.convert(canonical_snapshot)


func _normalize(command_type: String, payload: Dictionary) -> Dictionary:
	var normalized_type := command_type
	var normalized_payload := payload.duplicate(true)
	match command_type:
		"item.move_to_container":
			normalized_type = "item.transfer"
			var target_id := String(normalized_payload.get("target_container_id", ""))
			if target_id == "player_inventory":
				target_id = "inventory/%s" % _local_player_id
			elif target_id == "player_hotbar":
				target_id = "hotbar/%s" % _local_player_id
			normalized_payload["target_container_id"] = target_id
		"item.mount":
			var selected_item_id := _selected_item_id()
			if selected_item_id.is_empty():
				return _failure("HOTBAR_SLOT_EMPTY", {"message": "Выберите маяк в панели 1–0"})
			normalized_payload = {
				"item_id": _adapter.to_canonical_item_id(selected_item_id),
				"mount_id": String(payload.get("assembly_id", "")),
			}
		"item.detach":
			normalized_payload = {"mount_id": String(payload.get("assembly_id", ""))}
		"item.drop":
			# World transform is authority-owned. The client may request quantity only.
			normalized_payload.erase("transform")
		"item.place":
			var selected_item_id := _selected_item_id()
			if selected_item_id.is_empty():
				return _failure("HOTBAR_SLOT_EMPTY", {"message": "Выберите монтажное гнездо в панели 1–0"})
			normalized_payload = {"item_id": _adapter.to_canonical_item_id(selected_item_id)}
	return _success({"command_type": normalized_type, "payload": normalized_payload})


func _canonicalize_item_ids(payload: Dictionary) -> Dictionary:
	var normalized := payload.duplicate(true)
	for field in ["item_id", "source_item_id", "target_item_id"]:
		if normalized.has(field):
			normalized[field] = _adapter.to_canonical_item_id(String(normalized.get(field, "")))
	return normalized


func get_adapter():
	return _adapter


func _selected_item_id() -> String:
	if _selected_item_provider.is_valid():
		return String(_selected_item_provider.call())
	return ""


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"local_player_id": _local_player_id,
		"submitted": _submitted,
		"accepted": _accepted,
		"rejected": _rejected,
		"last_error_code": _last_error_code,
		"last_error_message": _last_error_message,
	}


func _record_rejection(command_type: String, operation_id: String, result: Dictionary) -> void:
	_last_error_code = String(result.get("error_code", "M7_ITEM_COMMAND_REJECTED"))
	_last_error_message = _human_error(_last_error_code)
	print("[m7_item_rejected] %s" % JSON.stringify({
		"command_type": command_type,
		"operation_id": operation_id,
		"error_code": _last_error_code,
		"message": _last_error_message,
		"details": result.get("details", {}),
	}, "", true, true))


func _attach_human_error(result: Dictionary) -> void:
	if bool(result.get("success", false)):
		return
	if not result.has("message") or String(result.get("message", "")).strip_edges().is_empty():
		result["message"] = _last_error_message
	if not result.has("output") or String(result.get("output", "")).strip_edges().is_empty():
		result["output"] = _last_error_message


func _human_error(error_code: String) -> String:
	match error_code:
		"ITEM_INTERACTION_OUT_OF_RANGE": return "Предмет находится слишком далеко"
		"ITEM_INTERACTION_NOT_VISIBLE": return "Предмет не находится в прямой видимости"
		"ITEM_NOT_VISIBLE_TO_PLAYER": return "Предмет не находится в прямой видимости"
		"ITEM_INTERACTION_OCCLUDED": return "Путь к предмету перекрыт"
		"ITEM_NOT_FOUND": return "Предмет не найден на сервере"
		"ITEM_ALREADY_CLAIMED": return "Предмет уже подобрал другой игрок"
		"M4_ITEM_COMMAND_TIMEOUT": return "Сервер не ответил на действие с предметом"
		"M4_ITEM_COMMAND_SEND_FAILED": return "Команда предмета не отправлена серверу"
		"STALE_TRANSPORT_SESSION": return "Сетевая сессия устарела"
		_: return "Сервер отклонил действие с предметом: %s" % error_code


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": error_code, "details": details.duplicate(true)}
	if details.has("message"):
		result["message"] = String(details.get("message", ""))
	return result
