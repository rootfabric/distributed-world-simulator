extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_p2.gd"

signal resource_mining_updated(snapshot: Dictionary)

const ResourceMiningSnapshot = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd"
)
const ResourceMiningDelta = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_delta.gd"
)

var _resource_mining_snapshot: Dictionary = {}
var _resource_snapshot_updates := 0
var _resource_delta_updates := 0
var _resource_rejections := 0
var _resource_resync_pending := false
var _resource_resync_requests_sent := 0


func setup(config: Dictionary) -> Dictionary:
	_resource_mining_snapshot.clear()
	_resource_snapshot_updates = 0
	_resource_delta_updates = 0
	_resource_rejections = 0
	_resource_resync_pending = false
	_resource_resync_requests_sent = 0
	return super.setup(config)


func _handle_message(payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	match message_type:
		"RESOURCE_SNAPSHOT":
			_accept_resource_snapshot(Dictionary(payload.get("snapshot", {})))
			return
		"RESOURCE_DELTA":
			_accept_resource_delta(Dictionary(payload.get("delta", {})))
			return
		_:
			super._handle_message(payload)


func _accept_resource_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var validation := ResourceMiningSnapshot.validate(snapshot)
	if not bool(validation.get("success", false)):
		_resource_rejections += 1
		_last_error_code = String(validation.get("error_code", "RESOURCE_SNAPSHOT_REJECTED"))
		return
	if not _resource_mining_snapshot.is_empty():
		var current_generation := int(_resource_mining_snapshot.get("generation", -1))
		var incoming_generation := int(snapshot.get("generation", -1))
		if incoming_generation < current_generation:
			_resource_rejections += 1
			_last_error_code = "RESOURCE_STALE_SNAPSHOT"
			return
		if incoming_generation == current_generation:
			if String(snapshot.get("checksum", "")) != String(_resource_mining_snapshot.get("checksum", "")):
				_resource_rejections += 1
				_last_error_code = "RESOURCE_SAME_GENERATION_MUTATION"
				_request_resource_resync(_last_error_code)
				return
			_resource_resync_pending = false
			return
	_resource_mining_snapshot = snapshot.duplicate(true)
	_resource_snapshot_updates += 1
	_resource_resync_pending = false
	if _last_error_code.begins_with("RESOURCE_"):
		_last_error_code = ""
	resource_mining_updated.emit(_resource_mining_snapshot.duplicate(true))


func _accept_resource_delta(delta: Dictionary) -> void:
	if delta.is_empty() or _resource_mining_snapshot.is_empty():
		_resource_rejections += 1
		_last_error_code = "RESOURCE_DELTA_WITHOUT_BASE"
		_request_resource_resync(_last_error_code)
		return
	var applied := ResourceMiningDelta.apply(_resource_mining_snapshot, delta)
	if not bool(applied.get("success", false)):
		_resource_rejections += 1
		_last_error_code = String(applied.get("error_code", "RESOURCE_DELTA_REJECTED"))
		_request_resource_resync(_last_error_code)
		return
	_resource_mining_snapshot = Dictionary(
		applied.get("details", {}).get("snapshot", {})
	).duplicate(true)
	_resource_delta_updates += 1
	_resource_resync_pending = false
	if _last_error_code.begins_with("RESOURCE_"):
		_last_error_code = ""
	resource_mining_updated.emit(_resource_mining_snapshot.duplicate(true))


func _request_resource_resync(reason: String) -> void:
	if _resource_resync_pending or not _joined:
		return
	var operation_id := "operation/v0-p3/%s/resource-resync/%d" % [
		_logical_player_id,
		Time.get_ticks_msec(),
	]
	if _send_on_channel(
		"RESOURCE_RESYNC_REQUEST",
		{
			"operation_id": operation_id,
			"logical_player_id": _logical_player_id,
			"current_generation": int(_resource_mining_snapshot.get("generation", 0)),
			"current_checksum": String(_resource_mining_snapshot.get("checksum", "")),
			"reason": reason,
		},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED",
		false
	):
		_resource_resync_pending = true
		_resource_resync_requests_sent += 1


func execute_resource_mine_blocking(
	resource_node_id: String,
	requested_units: int = 1,
	operation_id: String = ""
) -> Dictionary:
	if not is_ready():
		return _failure("V0_P3_CLIENT_NOT_READY")
	var op := operation_id.strip_edges()
	if op.is_empty():
		op = "operation/v0-p3/%s/mine/%d/%d" % [
			_logical_player_id,
			OS.get_process_id(),
			Time.get_ticks_msec(),
		]
	_command_results.erase(op)
	_awaited_command_ids[op] = true
	if not _send_on_channel(
		"RESOURCE_COMMAND",
		{
			"logical_player_id": _logical_player_id,
			"ownership_epoch": _ownership_epoch,
			"operation_id": op,
			"payload": {
				"resource_node_id": resource_node_id.strip_edges().to_lower(),
				"requested_units": requested_units,
			},
		},
		RealtimeChannelPolicy.CONTROL,
		"RELIABLE_ORDERED",
		true
	):
		_awaited_command_ids.erase(op)
		return _failure("V0_P3_RESOURCE_COMMAND_SEND_FAILED")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= _command_timeout_ms:
		_poll_blocking_once()
		if _command_results.has(op):
			var result: Dictionary = _command_results[op]
			_command_results.erase(op)
			_awaited_command_ids.erase(op)
			if String(result.get("status", "")) != "SUCCEEDED":
				return _failure(String(result.get("error_code", "RESOURCE_MINE_REJECTED")), result)
			return _success({"operation_id": op, "result": result})
		OS.delay_msec(2)
	_awaited_command_ids.erase(op)
	_discard_operation_timer(op)
	return _failure("V0_P3_RESOURCE_COMMAND_TIMEOUT")


func get_resource_mining_snapshot() -> Dictionary:
	return _resource_mining_snapshot.duplicate(true)


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["v0_p3_resource_mining"] = {
		"snapshot_updates": _resource_snapshot_updates,
		"delta_updates": _resource_delta_updates,
		"rejections": _resource_rejections,
		"resync_pending": _resource_resync_pending,
		"resync_requests_sent": _resource_resync_requests_sent,
		"generation": int(_resource_mining_snapshot.get("generation", 0)),
		"checksum": String(_resource_mining_snapshot.get("checksum", "")),
	}
	return report
