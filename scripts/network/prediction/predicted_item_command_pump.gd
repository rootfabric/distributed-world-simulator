extends Node

signal item_command_completed(operation_id: String, result: Dictionary, canonical_snapshot: Dictionary)

const RealtimeChannelPolicy = preload("res://scripts/network/realtime/realtime_channel_policy.gd")

const SCHEMA := "planet_simulator.predicted_item_command_pump.v2"
const DEFAULT_TIMEOUT_MS := 8000

var _runtime
var _local_player_id := ""
var _timeout_ms := DEFAULT_TIMEOUT_MS
var _pending: Dictionary = {}
var _configured := false
var _submitted := 0
var _completed := 0
var _rejected := 0
var _timed_out := 0
var _send_failures := 0


func setup(runtime, local_player_id: String, timeout_ms: int = DEFAULT_TIMEOUT_MS) -> Dictionary:
	if _configured:
		return _failure("NX6_ITEM_COMMAND_PUMP_ALREADY_CONFIGURED")
	if (
		runtime == null
		or not runtime.has_method("is_ready")
		or not runtime.has_method("get_item_graph_snapshot")
		or not runtime.has_method("_send_on_channel")
	):
		return _failure("NX6_ITEM_COMMAND_PUMP_RUNTIME_REQUIRED")
	var awaited_value = runtime.get("_awaited_command_ids")
	var results_value = runtime.get("_command_results")
	if not awaited_value is Dictionary or not results_value is Dictionary:
		return _failure("NX6_ITEM_COMMAND_PUMP_RESULT_MAILBOX_REQUIRED")
	_local_player_id = local_player_id.strip_edges().to_lower()
	_timeout_ms = timeout_ms
	if _local_player_id.is_empty() or _timeout_ms < 100 or _timeout_ms > 120000:
		return _failure("INVALID_NX6_ITEM_COMMAND_PUMP_CONFIG")
	_runtime = runtime
	_configured = true
	set_process(true)
	return _success()


func submit(
	command_type: String,
	payload: Dictionary,
	operation_id: String,
	ownership_epoch_override: int = 0
) -> Dictionary:
	if not _configured or _runtime == null:
		return _failure("NX6_ITEM_COMMAND_PUMP_NOT_CONFIGURED")
	if not bool(_runtime.is_ready()):
		return _failure("M4_CLIENT_NOT_READY")
	var op := operation_id.strip_edges()
	if op.is_empty() or command_type.strip_edges().is_empty():
		return _failure("INVALID_NX6_ITEM_COMMAND")
	if _pending.has(op):
		var existing: Dictionary = _pending[op]
		var fingerprint := _fingerprint(command_type, payload)
		if String(existing.get("fingerprint", "")) != fingerprint:
			return _failure("NX6_ITEM_COMMAND_REPLAY_CONFLICT")
		return _success({"operation_id": op, "duplicate": true, "expect_result": true})
	var awaited: Dictionary = Dictionary(_runtime.get("_awaited_command_ids"))
	var results: Dictionary = Dictionary(_runtime.get("_command_results"))
	results.erase(op)
	awaited[op] = true
	_runtime.set("_command_results", results)
	_runtime.set("_awaited_command_ids", awaited)
	var epoch := ownership_epoch_override
	if epoch < 1:
		epoch = int(_runtime.get("_ownership_epoch"))
	var sent_value = _runtime.call(
		"_send_on_channel",
		"ITEM_COMMAND",
		{
			"logical_player_id": _local_player_id,
			"ownership_epoch": epoch,
			"operation_id": op,
			"command_type": command_type,
			"payload": payload.duplicate(true),
		},
		RealtimeChannelPolicy.ITEM,
		"RELIABLE_ORDERED",
		true
	)
	if not bool(sent_value):
		if _runtime.has_method("_discard_operation_timer"):
			_runtime.call("_discard_operation_timer", op)
		awaited.erase(op)
		_runtime.set("_awaited_command_ids", awaited)
		_send_failures += 1
		return _failure("M4_ITEM_COMMAND_SEND_FAILED")
	var started_at_ms := Time.get_ticks_msec()
	_pending[op] = {
		"operation_id": op,
		"command_type": command_type,
		"fingerprint": _fingerprint(command_type, payload),
		"started_at_ms": started_at_ms,
		"deadline_ms": started_at_ms + _timeout_ms,
	}
	_submitted += 1
	return _success({"operation_id": op, "duplicate": false, "expect_result": true})


func _process(_delta: float) -> void:
	if not _configured or _runtime == null or _pending.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var results: Dictionary = Dictionary(_runtime.get("_command_results"))
	var awaited: Dictionary = Dictionary(_runtime.get("_awaited_command_ids"))
	for operation_id_value in _pending.keys().duplicate():
		var operation_id := String(operation_id_value)
		var entry: Dictionary = _pending[operation_id]
		if results.has(operation_id):
			var wire_result: Dictionary = Dictionary(results[operation_id]).duplicate(true)
			results.erase(operation_id)
			awaited.erase(operation_id)
			_pending.erase(operation_id)
			var result := _normalize_wire_result(wire_result)
			_completed += 1
			if not bool(result.get("success", false)):
				_rejected += 1
			item_command_completed.emit(
				operation_id,
				result,
				_runtime.get_item_graph_snapshot()
			)
			continue
		if now_ms > int(entry.get("deadline_ms", 0)):
			if _runtime.has_method("_discard_operation_timer"):
				_runtime.call("_discard_operation_timer", operation_id)
			awaited.erase(operation_id)
			_pending.erase(operation_id)
			_timed_out += 1
			item_command_completed.emit(
				operation_id,
				_failure("M4_ITEM_COMMAND_TIMEOUT"),
				_runtime.get_item_graph_snapshot()
			)
	_runtime.set("_command_results", results)
	_runtime.set("_awaited_command_ids", awaited)


func stop(error_code: String = "NX6_ITEM_COMMAND_PUMP_STOPPED") -> void:
	if _runtime != null:
		var awaited: Dictionary = Dictionary(_runtime.get("_awaited_command_ids"))
		var results: Dictionary = Dictionary(_runtime.get("_command_results"))
		for operation_id_value in _pending.keys().duplicate():
			var operation_id := String(operation_id_value)
			if _runtime.has_method("_discard_operation_timer"):
				_runtime.call("_discard_operation_timer", operation_id)
			awaited.erase(operation_id)
			results.erase(operation_id)
			item_command_completed.emit(
				operation_id,
				_failure(error_code, {"operation_id": operation_id}),
				_runtime.get_item_graph_snapshot()
			)
		_runtime.set("_awaited_command_ids", awaited)
		_runtime.set("_command_results", results)
	_pending.clear()
	_configured = false
	_runtime = null
	set_process(false)


func is_pending(operation_id: String) -> bool:
	return _pending.has(operation_id.strip_edges())


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"pending_count": _pending.size(),
		"submitted": _submitted,
		"completed": _completed,
		"rejected": _rejected,
		"timed_out": _timed_out,
		"send_failures": _send_failures,
		"timeout_ms": _timeout_ms,
	}


func _normalize_wire_result(wire_result: Dictionary) -> Dictionary:
	if String(wire_result.get("status", "")) == "SUCCEEDED":
		return _success({"wire_result": wire_result.duplicate(true)})
	return _failure(
		String(wire_result.get("error_code", "M4_ITEM_COMMAND_REJECTED")),
		{"wire_result": wire_result.duplicate(true)}
	)


func _fingerprint(command_type: String, payload: Dictionary) -> String:
	return JSON.stringify({
		"command_type": command_type,
		"payload": payload,
	}, "", true, true).sha256_text()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
