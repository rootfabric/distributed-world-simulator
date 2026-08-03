extends RefCounted

signal projected_item_graph_updated(snapshot: Dictionary)
signal authoritative_item_command_completed(operation_id: String, result: Dictionary, canonical_snapshot: Dictionary)

const Adapter = preload("res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd")
const PredictionJournal = preload("res://scripts/network/prediction/predicted_item_interaction_journal.gd")
const CommandPump = preload("res://scripts/network/prediction/predicted_item_command_pump.gd")

const SCHEMA := "planet_simulator.m7_network_item_command_bridge.v3"
const DEFAULT_PREDICTION_TIMEOUT_MS := 8000

var _runtime
var _adapter
var _prediction_journal
var _command_pump
var _rewired_item_graph_consumers: Array[Dictionary] = []
var _completion_results: Dictionary = {}
var _completion_order: Array[String] = []
var _prediction_setup_error := ""
var _stopped := false
var _stop_count := 0
var _restored_item_graph_consumers := 0
var _local_player_id := ""
var _selected_item_provider: Callable
var _submitted := 0
var _accepted := 0
var _rejected := 0
var _predicted_submitted := 0
var _predicted_send_failures := 0
var _predicted_completions := 0
var _projector_failures := 0
var _last_error_code := ""
var _last_error_message := ""


func setup(runtime, local_player_id: String, selected_item_provider: Callable = Callable()) -> Dictionary:
	if _runtime != null and not _stopped:
		return _failure("M7_ITEM_BRIDGE_ALREADY_CONFIGURED")
	_stopped = false
	if (
		runtime == null
		or not runtime.has_method("get_item_graph_snapshot")
		or not runtime.has_method("execute_item_command_blocking")
	):
		return _failure("M7_INVALID_CLIENT_RUNTIME")
	_runtime = runtime
	_local_player_id = local_player_id.strip_edges().to_lower()
	_selected_item_provider = selected_item_provider
	_adapter = Adapter.new()
	var adapter_setup: Dictionary = _adapter.setup(_local_player_id)
	if not bool(adapter_setup.get("success", false)):
		return adapter_setup
	_prediction_journal = PredictionJournal.new()
	var journal_setup: Dictionary = _prediction_journal.setup(_local_player_id, {
		"timeout_ms": DEFAULT_PREDICTION_TIMEOUT_MS,
		"max_pending": 32,
	})
	if not bool(journal_setup.get("success", false)):
		return journal_setup
	var canonical: Dictionary = _runtime.get_item_graph_snapshot()
	if not canonical.is_empty():
		var adopted: Dictionary = _prediction_journal.adopt_authoritative(canonical)
		if not bool(adopted.get("success", false)):
			return adopted
	var signal_setup: Dictionary = _rewire_item_graph_consumers()
	if not bool(signal_setup.get("success", false)):
		return signal_setup
	if _runtime_supports_nonblocking_prediction():
		_command_pump = CommandPump.new()
		_command_pump.name = "NX6PredictedItemCommandPump"
		var runtime_node: Node = _runtime as Node
		runtime_node.add_child(_command_pump)
		var pump_setup: Dictionary = _command_pump.setup(
			_runtime, _local_player_id, DEFAULT_PREDICTION_TIMEOUT_MS
		)
		if bool(pump_setup.get("success", false)):
			_command_pump.item_command_completed.connect(_on_item_command_completed)
		else:
			_prediction_setup_error = String(pump_setup.get(
				"error_code", "NX6_ITEM_COMMAND_PUMP_SETUP_FAILED"
			))
			_command_pump.queue_free()
			_command_pump = null
	return _success({
		"prediction_enabled": _prediction_enabled(),
		"prediction": _prediction_journal.get_report(),
	})


func wait_for_authoritative_completion(
	operation_id: String,
	timeout_ms: int = DEFAULT_PREDICTION_TIMEOUT_MS + 2000
) -> Dictionary:
	var normalized_id := operation_id.strip_edges()
	if normalized_id.is_empty():
		return _failure("NX6_AUTHORITATIVE_OPERATION_ID_REQUIRED")
	if timeout_ms < 100 or timeout_ms > 120000:
		return _failure("INVALID_NX6_AUTHORITATIVE_WAIT_TIMEOUT")
	var main_loop = Engine.get_main_loop()
	if not main_loop is SceneTree:
		return _failure("NX6_SCENE_TREE_REQUIRED_FOR_AUTHORITATIVE_WAIT")
	var started_at_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at_ms <= timeout_ms:
		var polled: Dictionary = poll_authoritative_completion(normalized_id)
		if bool(polled.get("completed", false)):
			return Dictionary(polled.get("result", {})).duplicate(true)
		if not bool(polled.get("success", false)):
			return polled
		if _stopped:
			return _failure("NX6_ITEM_BRIDGE_STOPPED", {"operation_id": normalized_id})
		await (main_loop as SceneTree).process_frame
	return _failure("NX6_AUTHORITATIVE_COMPLETION_TIMEOUT", {
		"operation_id": normalized_id,
		"timeout_ms": timeout_ms,
	})


func poll_authoritative_completion(operation_id: String) -> Dictionary:
	var normalized_id := operation_id.strip_edges()
	if normalized_id.is_empty():
		return _failure("NX6_AUTHORITATIVE_OPERATION_ID_REQUIRED")
	if _completion_results.has(normalized_id):
		return {
			"success": true,
			"error_code": "",
			"completed": true,
			"pending": false,
			"operation_id": normalized_id,
			"result": Dictionary(_completion_results[normalized_id]).duplicate(true),
		}
	if _is_operation_pending(normalized_id):
		return {
			"success": true,
			"error_code": "",
			"completed": false,
			"pending": true,
			"operation_id": normalized_id,
		}
	return _failure("NX6_AUTHORITATIVE_OPERATION_NOT_FOUND", {"operation_id": normalized_id})


func take_authoritative_completion(operation_id: String) -> Dictionary:
	var polled: Dictionary = poll_authoritative_completion(operation_id)
	if not bool(polled.get("completed", false)):
		return polled
	var normalized_id := operation_id.strip_edges()
	var result: Dictionary = Dictionary(polled.get("result", {})).duplicate(true)
	_completion_results.erase(normalized_id)
	_completion_order.erase(normalized_id)
	return result


func stop(error_code: String = "NX6_ITEM_BRIDGE_STOPPED") -> Dictionary:
	if _stopped:
		return _success({
			"already_stopped": true,
			"restored_item_graph_consumers": _restored_item_graph_consumers,
		})
	_stopped = true
	_stop_count += 1
	if _command_pump != null and is_instance_valid(_command_pump):
		_command_pump.stop(error_code)
		if _command_pump.item_command_completed.is_connected(_on_item_command_completed):
			_command_pump.item_command_completed.disconnect(_on_item_command_completed)
		_command_pump.queue_free()
		_command_pump = null
	if _prediction_journal != null:
		var authoritative: Dictionary = (
			_runtime.get_item_graph_snapshot()
			if _runtime != null and _runtime.has_method("get_item_graph_snapshot")
			else _prediction_journal.get_authoritative_snapshot()
		)
		for entry_value in _prediction_journal.get_pending_predictions():
			if not entry_value is Dictionary:
				continue
			var pending_id := String(Dictionary(entry_value).get("prediction_id", ""))
			if pending_id.is_empty():
				continue
			var cancelled := _failure(error_code, {"operation_id": pending_id})
			_prediction_journal.resolve_prediction(pending_id, cancelled, authoritative)
			_store_completion(pending_id, cancelled, authoritative)
	_emit_projected_snapshot()
	_restore_item_graph_consumers()
	_runtime = null
	_selected_item_provider = Callable()
	return _success({
		"already_stopped": false,
		"restored_item_graph_consumers": _restored_item_graph_consumers,
		"pending_count": 0,
	})


func uses_server_authoritative_persistence() -> bool:
	return true


func submit_item_command(command_type: String, payload: Dictionary, operation_id: String) -> Dictionary:
	if _runtime == null or _adapter == null or _prediction_journal == null:
		return _failure("M7_ITEM_BRIDGE_NOT_CONFIGURED")
	var canonicalized_payload := _canonicalize_item_ids(payload)
	var normalized := _normalize(command_type, canonicalized_payload)
	if not bool(normalized.get("success", false)):
		_rejected += 1
		_record_rejection(command_type, operation_id, normalized)
		_attach_human_error(normalized)
		return normalized
	var details: Dictionary = Dictionary(normalized.get("details", {}))
	var normalized_type := String(details.get("command_type", command_type))
	var server_payload := Dictionary(details.get("payload", payload)).duplicate(true)
	if _prediction_enabled() and _prediction_journal.supports_command(normalized_type):
		return _submit_predicted(
			normalized_type,
			server_payload,
			_prediction_payload(normalized_type, server_payload, canonicalized_payload),
			operation_id
		)
	return _submit_blocking(command_type, normalized_type, server_payload, operation_id)


func project_canonical_snapshot(canonical_snapshot: Dictionary) -> Dictionary:
	if _prediction_journal == null:
		return canonical_snapshot.duplicate(true)
	var projected: Dictionary = _prediction_journal.project_authoritative(canonical_snapshot)
	if not bool(projected.get("success", false)):
		_projector_failures += 1
		_last_error_code = String(projected.get("error_code", "NX6_ITEM_PROJECTION_FAILED"))
		return canonical_snapshot.duplicate(true)
	return Dictionary(projected.get("details", {}).get(
		"presentation_snapshot", canonical_snapshot
	)).duplicate(true)


func convert_snapshot(canonical_snapshot: Dictionary) -> Dictionary:
	if _adapter == null:
		return _failure("M7_ITEM_BRIDGE_NOT_CONFIGURED")
	return _adapter.convert(canonical_snapshot)


func _submit_predicted(
	command_type: String,
	server_payload: Dictionary,
	prediction_payload: Dictionary,
	operation_id: String
) -> Dictionary:
	if operation_id.strip_edges().is_empty():
		return _failure("NX6_PREDICTION_OPERATION_ID_REQUIRED")
	var canonical: Dictionary = _runtime.get_item_graph_snapshot()
	var adopted: Dictionary = _prediction_journal.adopt_authoritative(canonical)
	if not bool(adopted.get("success", false)):
		return adopted
	var prediction: Dictionary = _prediction_journal.begin_prediction(
		command_type,
		prediction_payload,
		operation_id
	)
	if not bool(prediction.get("success", false)):
		_rejected += 1
		_record_rejection(command_type, operation_id, prediction)
		_attach_human_error(prediction)
		return prediction
	_submitted += 1
	_predicted_submitted += 1
	var sent_value = _command_pump.submit(
		command_type,
		server_payload.duplicate(true),
		operation_id
	)
	if not sent_value is Dictionary or not bool(Dictionary(sent_value).get("success", false)):
		_predicted_send_failures += 1
		_rejected += 1
		var send_result: Dictionary = (
			Dictionary(sent_value).duplicate(true)
			if sent_value is Dictionary
			else _failure("INVALID_NONBLOCKING_ITEM_COMMAND_RESULT")
		)
		_prediction_journal.resolve_prediction(operation_id, send_result)
		_record_rejection(command_type, operation_id, send_result)
		_attach_human_error(send_result)
		var rollback_replica := _replica_from_projection(
			_prediction_journal.get_presentation_snapshot()
		)
		if bool(rollback_replica.get("success", false)):
			send_result["replica_snapshot"] = rollback_replica.get("details", {}).get("replica_snapshot", {})
		return send_result
	var projected_snapshot: Dictionary = Dictionary(prediction.get("details", {}).get(
		"presentation_snapshot", {}
	))
	var converted: Dictionary = _replica_from_projection(projected_snapshot)
	if not bool(converted.get("success", false)):
		_prediction_journal.resolve_prediction(operation_id, converted)
		return converted
	_last_error_code = ""
	_last_error_message = ""
	return {
		"success": true,
		"error_code": "",
		"pending": true,
		"predicted": true,
		"prediction_id": operation_id,
		"operation_id": operation_id,
		"base_revision": int(prediction.get("details", {}).get("base_revision", -1)),
		"replica_snapshot": converted.get("details", {}).get("replica_snapshot", {}),
		"details": {
			"pending": true,
			"predicted": true,
			"prediction_id": operation_id,
		},
	}


func _submit_blocking(
	original_command_type: String,
	command_type: String,
	payload: Dictionary,
	operation_id: String
) -> Dictionary:
	if not _runtime.has_method("execute_item_command_blocking"):
		return _failure("M7_BLOCKING_ITEM_COMMAND_UNAVAILABLE")
	_submitted += 1
	var result: Dictionary = _runtime.execute_item_command_blocking(
		command_type,
		payload,
		operation_id
	)
	if bool(result.get("success", false)):
		_accepted += 1
		_last_error_code = ""
		_last_error_message = ""
	else:
		_rejected += 1
		_record_rejection(original_command_type, operation_id, result)
		_attach_human_error(result)
	var canonical: Dictionary = _runtime.get_item_graph_snapshot()
	var projected: Dictionary = project_canonical_snapshot(canonical)
	var converted: Dictionary = _replica_from_projection(projected)
	if not bool(converted.get("success", false)):
		return converted
	result["replica_snapshot"] = converted.get("details", {}).get("replica_snapshot", {})
	return result


func _on_item_command_completed(
	operation_id: String,
	result: Dictionary,
	canonical_snapshot: Dictionary
) -> void:
	if _prediction_journal == null:
		return
	var resolved: Dictionary = _prediction_journal.resolve_prediction(
		operation_id,
		result,
		canonical_snapshot
	)
	if not bool(resolved.get("success", false)):
		if String(resolved.get("error_code", "")) != "ITEM_PREDICTION_NOT_FOUND":
			_last_error_code = String(resolved.get("error_code", "NX6_ITEM_COMPLETION_FAILED"))
		return
	_predicted_completions += 1
	if bool(result.get("success", false)):
		_accepted += 1
		_last_error_code = ""
		_last_error_message = ""
	else:
		_rejected += 1
		_record_rejection("predicted", operation_id, result)
	var completion := result.duplicate(true)
	completion["pending"] = false
	completion["predicted"] = true
	completion["prediction_id"] = operation_id
	completion["operation_id"] = operation_id
	completion["canonical_snapshot"] = canonical_snapshot.duplicate(true)
	var converted: Dictionary = _replica_from_projection(
		_prediction_journal.get_presentation_snapshot()
	)
	if bool(converted.get("success", false)):
		completion["replica_snapshot"] = converted.get("details", {}).get("replica_snapshot", {})
	_store_completion(operation_id, completion, canonical_snapshot)
	_emit_projected_snapshot()


func _store_completion(
	operation_id: String,
	result: Dictionary,
	canonical_snapshot: Dictionary
) -> void:
	var normalized_id := operation_id.strip_edges()
	if normalized_id.is_empty():
		return
	var stored := result.duplicate(true)
	stored["operation_id"] = normalized_id
	stored["canonical_snapshot"] = canonical_snapshot.duplicate(true)
	_completion_results[normalized_id] = stored
	_completion_order.erase(normalized_id)
	_completion_order.append(normalized_id)
	while _completion_order.size() > 64:
		var expired_id: String = String(_completion_order.pop_front())
		_completion_results.erase(expired_id)
	authoritative_item_command_completed.emit(
		normalized_id, stored.duplicate(true), canonical_snapshot.duplicate(true)
	)


func _is_operation_pending(operation_id: String) -> bool:
	if _command_pump != null and is_instance_valid(_command_pump):
		if _command_pump.has_method("is_pending") and bool(_command_pump.is_pending(operation_id)):
			return true
	if _prediction_journal != null:
		for entry_value in _prediction_journal.get_pending_predictions():
			if entry_value is Dictionary and String(Dictionary(entry_value).get("prediction_id", "")) == operation_id:
				return true
	return false


func _restore_item_graph_consumers() -> void:
	var callback := Callable(self, "_on_runtime_item_graph_updated")
	if _runtime != null and _runtime.has_signal("item_graph_updated"):
		if _runtime.item_graph_updated.is_connected(callback):
			_runtime.item_graph_updated.disconnect(callback)
	for connection_value in _rewired_item_graph_consumers:
		if not connection_value is Dictionary:
			continue
		var consumer_value = Dictionary(connection_value).get("callable", Callable())
		if not consumer_value is Callable:
			continue
		var consumer: Callable = consumer_value
		if not consumer.is_valid():
			continue
		if projected_item_graph_updated.is_connected(consumer):
			projected_item_graph_updated.disconnect(consumer)
		if (
			_runtime != null
			and _runtime.has_signal("item_graph_updated")
			and not _runtime.item_graph_updated.is_connected(consumer)
		):
			_runtime.item_graph_updated.connect(
				consumer, int(Dictionary(connection_value).get("flags", 0))
			)
			_restored_item_graph_consumers += 1
	_rewired_item_graph_consumers.clear()


func _prediction_enabled() -> bool:
	return not _stopped and _runtime != null and _command_pump != null and is_instance_valid(_command_pump)


func _runtime_supports_nonblocking_prediction() -> bool:
	if not _runtime is Node:
		return false
	for method_name in ["is_ready", "get_item_graph_snapshot", "_send_on_channel"]:
		if not _runtime.has_method(method_name):
			return false
	for property_name in ["_awaited_command_ids", "_command_results", "_ownership_epoch"]:
		if not _has_runtime_property(property_name):
			return false
	return (
		_runtime.get("_awaited_command_ids") is Dictionary
		and _runtime.get("_command_results") is Dictionary
	)


func _has_runtime_property(property_name: String) -> bool:
	for property_value in _runtime.get_property_list():
		if property_value is Dictionary and String(property_value.get("name", "")) == property_name:
			return true
	return false


func _rewire_item_graph_consumers() -> Dictionary:
	if _runtime == null or not _runtime.has_signal("item_graph_updated"):
		return _success({"rewired_consumers": 0})
	var callback := Callable(self, "_on_runtime_item_graph_updated")
	for connection_value in _runtime.get_signal_connection_list("item_graph_updated"):
		if not connection_value is Dictionary:
			continue
		var connection: Dictionary = connection_value
		var consumer_value = connection.get("callable", Callable())
		if not consumer_value is Callable:
			continue
		var consumer: Callable = consumer_value
		if not consumer.is_valid() or consumer == callback:
			continue
		var flags := int(connection.get("flags", 0))
		if _runtime.item_graph_updated.is_connected(consumer):
			_runtime.item_graph_updated.disconnect(consumer)
		if not projected_item_graph_updated.is_connected(consumer):
			projected_item_graph_updated.connect(consumer, flags)
		_rewired_item_graph_consumers.append({
			"callable": consumer,
			"flags": flags,
		})
	if not _runtime.item_graph_updated.is_connected(callback):
		_runtime.item_graph_updated.connect(callback)
	return _success({"rewired_consumers": _rewired_item_graph_consumers.size()})


func _on_runtime_item_graph_updated(canonical_snapshot: Dictionary) -> void:
	if _prediction_journal == null:
		return
	var projected: Dictionary = project_canonical_snapshot(canonical_snapshot)
	projected_item_graph_updated.emit(projected.duplicate(true))


func _emit_projected_snapshot() -> void:
	if _prediction_journal == null:
		return
	var projected: Dictionary = _prediction_journal.get_presentation_snapshot()
	if projected.is_empty() and _runtime != null:
		projected = _runtime.get_item_graph_snapshot()
	if not projected.is_empty():
		projected_item_graph_updated.emit(projected.duplicate(true))


func _prediction_payload(
	command_type: String,
	server_payload: Dictionary,
	original_payload: Dictionary
) -> Dictionary:
	var result := server_payload.duplicate(true)
	if command_type in ["item.drop", "item.place"]:
		var transform_value = original_payload.get("transform", {})
		if transform_value is Dictionary and not Dictionary(transform_value).is_empty():
			result["transform"] = Dictionary(transform_value).duplicate(true)
	return result


func _replica_from_projection(projected_snapshot: Dictionary) -> Dictionary:
	var converted: Dictionary = _adapter.create_replica_snapshot(projected_snapshot)
	if not bool(converted.get("success", false)):
		return _failure("M7_ITEM_REPLICA_CONVERSION_FAILED", converted)
	return converted


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
			# World transform remains presentation-only until authority confirms it.
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
		"prediction_enabled": _prediction_enabled(),
		"predicted_submitted": _predicted_submitted,
		"predicted_send_failures": _predicted_send_failures,
		"predicted_completions": _predicted_completions,
		"projector_failures": _projector_failures,
		"prediction_setup_error": _prediction_setup_error,
		"rewired_item_graph_consumers": _rewired_item_graph_consumers.size(),
		"restored_item_graph_consumers": _restored_item_graph_consumers,
		"completed_result_count": _completion_results.size(),
		"stopped": _stopped,
		"stop_count": _stop_count,
		"prediction": _prediction_journal.get_report() if _prediction_journal != null else {},
		"command_pump": _command_pump.get_report() if _command_pump != null else {},
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
		"ITEM_PREDICTION_TIMEOUT": return "Сервер не подтвердил действие с предметом вовремя"
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
