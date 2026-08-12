class_name FirstPersonHotbarNetworkAdapter
extends RefCounted

const RealtimeChannelPolicy = preload("res://scripts/network/realtime/realtime_channel_policy.gd")

const COMMAND_TYPE := "inventory.select_hotbar"
const HOTBAR_SIZE := 10
const DEFAULT_CONFIRM_TIMEOUT_MS := 2000

var _runtime
var _logical_player_id := ""
var _confirm_timeout_ms := DEFAULT_CONFIRM_TIMEOUT_MS
var _pending_operation_id := ""
var _pending_index := -1
var _pending_started_ms := 0
var _submitted := 0
var _confirmed := 0
var _rolled_back := 0
var _send_failures := 0
var _last_error_code := ""


func setup(runtime, logical_player_id: String, confirm_timeout_ms: int = DEFAULT_CONFIRM_TIMEOUT_MS) -> Dictionary:
	_runtime = runtime
	_logical_player_id = logical_player_id.strip_edges().to_lower()
	_confirm_timeout_ms = confirm_timeout_ms
	if _runtime == null:
		return _failure("FPE_HOTBAR_RUNTIME_REQUIRED")
	if _logical_player_id.is_empty():
		return _failure("FPE_HOTBAR_PLAYER_ID_REQUIRED")
	if _confirm_timeout_ms < 100 or _confirm_timeout_ms > 30000:
		return _failure("FPE_HOTBAR_CONFIRM_TIMEOUT_INVALID")
	if not _runtime.has_method("is_ready"):
		return _failure("FPE_HOTBAR_RUNTIME_READY_PORT_REQUIRED")
	if not _runtime.has_method("get_item_graph_snapshot"):
		return _failure("FPE_HOTBAR_RUNTIME_ITEM_GRAPH_PORT_REQUIRED")
	if not _runtime.has_method("_send_on_channel"):
		return _failure("FPE_HOTBAR_RUNTIME_NONBLOCKING_SEND_PORT_REQUIRED")
	return _success({"confirm_timeout_ms": _confirm_timeout_ms})


func submit(index: int) -> Dictionary:
	if _runtime == null:
		return _failure("FPE_HOTBAR_ADAPTER_NOT_CONFIGURED")
	if index < 0 or index >= HOTBAR_SIZE:
		return _failure("FPE_HOTBAR_INDEX_INVALID", {"index": index})
	if not bool(_runtime.call("is_ready")):
		return _failure("FPE_HOTBAR_RUNTIME_NOT_READY")

	var ownership_epoch := _ownership_epoch()
	if ownership_epoch < 1:
		return _failure("FPE_HOTBAR_OWNERSHIP_EPOCH_UNAVAILABLE")

	var operation_id := "operation/fpe/%s/select-hotbar/%d/%d" % [
		_logical_player_id,
		OS.get_process_id(),
		Time.get_ticks_usec(),
	]
	var command_payload := {
		"logical_player_id": _logical_player_id,
		"ownership_epoch": ownership_epoch,
		"operation_id": operation_id,
		"command_type": COMMAND_TYPE,
		"payload": {"selected_hotbar_index": index},
	}
	var sent_value: Variant = _runtime.call(
		"_send_on_channel",
		"ITEM_COMMAND",
		command_payload,
		RealtimeChannelPolicy.ITEM,
		"RELIABLE_ORDERED",
		true
	)
	if not bool(sent_value):
		_send_failures += 1
		_last_error_code = "FPE_HOTBAR_COMMAND_SEND_FAILED"
		return _failure(_last_error_code, {"index": index})

	_pending_operation_id = operation_id
	_pending_index = index
	_pending_started_ms = Time.get_ticks_msec()
	_submitted += 1
	_last_error_code = ""
	return _success({
		"pending": true,
		"predicted": true,
		"authoritative": true,
		"operation_id": operation_id,
		"selected_hotbar_index": index,
	})


func poll() -> Dictionary:
	var canonical_index := canonical_selected_index()
	if _pending_operation_id.is_empty():
		return _success({
			"pending": false,
			"canonical_selected_hotbar_index": canonical_index,
		})

	if canonical_index == _pending_index:
		var confirmed_operation_id := _pending_operation_id
		var confirmed_index := _pending_index
		_clear_pending()
		_confirmed += 1
		_last_error_code = ""
		return _success({
			"pending": false,
			"confirmed": true,
			"operation_id": confirmed_operation_id,
			"canonical_selected_hotbar_index": confirmed_index,
		})

	var age_ms := Time.get_ticks_msec() - _pending_started_ms
	if age_ms <= _confirm_timeout_ms:
		return _success({
			"pending": true,
			"operation_id": _pending_operation_id,
			"predicted_selected_hotbar_index": _pending_index,
			"canonical_selected_hotbar_index": canonical_index,
			"age_ms": age_ms,
		})

	var timed_out_operation_id := _pending_operation_id
	var timed_out_index := _pending_index
	_clear_pending()
	_rolled_back += 1
	_last_error_code = "FPE_HOTBAR_AUTHORITY_CONFIRM_TIMEOUT"
	return _failure(_last_error_code, {
		"rollback_required": true,
		"operation_id": timed_out_operation_id,
		"predicted_selected_hotbar_index": timed_out_index,
		"canonical_selected_hotbar_index": canonical_index,
		"age_ms": age_ms,
	})


func canonical_selected_index() -> int:
	if _runtime == null or not _runtime.has_method("get_item_graph_snapshot"):
		return -1
	var snapshot_value: Variant = _runtime.call("get_item_graph_snapshot")
	if not snapshot_value is Dictionary:
		return -1
	var inventories_value: Variant = Dictionary(snapshot_value).get("inventories", {})
	if not inventories_value is Dictionary:
		return -1
	var player_value: Variant = Dictionary(inventories_value).get(_logical_player_id, {})
	if not player_value is Dictionary:
		return -1
	return int(Dictionary(player_value).get("selected_hotbar_index", -1))


func has_pending() -> bool:
	return not _pending_operation_id.is_empty()


func get_report() -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_hotbar_network_adapter.v1",
		"logical_player_id": _logical_player_id,
		"confirm_timeout_ms": _confirm_timeout_ms,
		"pending": has_pending(),
		"pending_operation_id": _pending_operation_id,
		"pending_index": _pending_index,
		"canonical_index": canonical_selected_index(),
		"submitted": _submitted,
		"confirmed": _confirmed,
		"rolled_back": _rolled_back,
		"send_failures": _send_failures,
		"last_error_code": _last_error_code,
		"blocking_waits": 0,
		"owns_item_state": false,
		"owns_network_state": false,
	}


func _ownership_epoch() -> int:
	if _runtime == null:
		return 0
	var player_value: Variant = {}
	if _runtime.has_method("get_local_player_record"):
		player_value = _runtime.call("get_local_player_record")
	elif _runtime.has_method("get_player"):
		player_value = _runtime.call("get_player", _logical_player_id)
	if not player_value is Dictionary:
		return 0
	return int(Dictionary(player_value).get("ownership_epoch", 0))


func _clear_pending() -> void:
	_pending_operation_id = ""
	_pending_index = -1
	_pending_started_ms = 0


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
