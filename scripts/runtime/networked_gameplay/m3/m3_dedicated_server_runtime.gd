extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"

const ResourceMiningDelta = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_delta.gd"
)

var _resource_commands := 0
var _resource_rejections := 0
var _resource_deltas_published := 0
var _resource_snapshots_published := 0
var _resource_delta_build_failures := 0
var _resource_resync_requests := 0


func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	if message_type == "RESOURCE_COMMAND" or message_type == "RESOURCE_RESYNC_REQUEST":
		if not _is_peer_compatible(peer_id, session_id):
			_reject_pre_handshake_message(peer_id, payload)
			return
		if message_type == "RESOURCE_COMMAND":
			_handle_resource_command(peer_id, session_id, payload)
		else:
			_handle_resource_resync_request(peer_id, session_id, payload)
		return

	super._handle_message(peer_id, session_id, payload)
	# JOIN_ACK already carries gameplay and Item Graph state. Publish the P3
	# resource snapshot on the same reliable RESYNC stream immediately after a
	# successful join so old P2 message ordering remains untouched.
	if (
		message_type == "JOIN"
		and _peer_to_player.has(peer_id)
		and String(_peer_to_session.get(peer_id, "")) == session_id
	):
		_send_resource_snapshot(peer_id, "PLAYER_JOINED")


func _handle_resource_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_resource_commands += 1
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "resource.mine", _failure("STALE_TRANSPORT_SESSION"))
		_resource_rejections += 1
		return
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id,
			operation_id,
			"resource.mine",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		_resource_rejections += 1
		return
	var command_payload_value = payload.get("payload", {})
	if not command_payload_value is Dictionary:
		_reject_uncommitted_command(
			peer_id,
			operation_id,
			"resource.mine",
			"INVALID_RESOURCE_COMMAND"
		)
		_resource_rejections += 1
		return
	if _service == null or not _service.has_method("handle_resource_mine"):
		_send_result(peer_id, operation_id, "resource.mine", _failure("RESOURCE_MINING_NOT_READY"))
		_resource_rejections += 1
		return

	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var before_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var before_resource_snapshot: Dictionary = _service.create_resource_mining_snapshot()
	var result: Dictionary = _service.handle_resource_mine(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		operation_id,
		Dictionary(command_payload_value)
	)
	if not _persist_command_result(operation_id, "resource.mine", logical_id, result):
		_send_result(peer_id, operation_id, "resource.mine", _failure("M6_DURABLE_COMMIT_FAILED"))
		return

	var item_delta: Dictionary = {}
	var item_fallback_required := false
	var resource_delta: Dictionary = {}
	var resource_fallback_required := false
	if bool(result.get("success", false)) and not _is_replay_result(result):
		var after_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
		var item_delta_result: Dictionary = CanonicalItemGraphDelta.create(
			before_item_snapshot,
			after_item_snapshot
		)
		if not bool(item_delta_result.get("success", false)):
			item_fallback_required = true
			_item_graph_delta_build_failures += 1
			_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
		else:
			item_delta = Dictionary(item_delta_result.get("details", {}).get("delta", {})).duplicate(true)

		var after_resource_snapshot: Dictionary = _service.create_resource_mining_snapshot()
		var resource_delta_result: Dictionary = ResourceMiningDelta.create(
			before_resource_snapshot,
			after_resource_snapshot
		)
		if not bool(resource_delta_result.get("success", false)):
			resource_fallback_required = true
			_resource_delta_build_failures += 1
			_last_error_code = "RESOURCE_DELTA_BUILD_FAILED"
		else:
			resource_delta = Dictionary(
				resource_delta_result.get("details", {}).get("delta", {})
			).duplicate(true)

	var result_sent := _send_result(peer_id, operation_id, "resource.mine", result, item_delta)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			if item_fallback_required:
				_broadcast_item_snapshot("RESOURCE_MINE_ITEM_DELTA_FALLBACK")
			else:
				_broadcast_item_delta(item_delta, peer_id, "resource.mine")
			if resource_fallback_required:
				_broadcast_resource_snapshot("RESOURCE_DELTA_BUILD_FALLBACK")
			else:
				_broadcast_resource_delta(resource_delta)
			_broadcast_snapshot("RESOURCE_MINED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
		_resource_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_resource_resync_request(
	peer_id: String,
	session_id: String,
	_payload: Dictionary
) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		return
	_resource_resync_requests += 1
	_send_resource_snapshot(peer_id, "EXPLICIT_RESYNC")


func _send_resource_snapshot(peer_id: String, reason: String) -> bool:
	if _service == null or not _service.has_method("create_resource_mining_snapshot"):
		return false
	var snapshot: Dictionary = _service.create_resource_mining_snapshot()
	if snapshot.is_empty():
		return false
	var sent := _send_on_channel(
		peer_id,
		"RESOURCE_SNAPSHOT",
		{"reason": reason, "snapshot": snapshot},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED"
	)
	if sent:
		_resource_snapshots_published += 1
	return sent


func _broadcast_resource_snapshot(reason: String) -> void:
	for peer_id_value in _peer_to_player.keys():
		if _send_resource_snapshot(String(peer_id_value), reason):
			_broadcasts += 1


func _broadcast_resource_delta(delta: Dictionary) -> void:
	if delta.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(
			String(peer_id_value),
			"RESOURCE_DELTA",
			{"delta": delta},
			RealtimeChannelPolicy.ITEM,
			"RELIABLE_ORDERED"
		):
			_broadcasts += 1
			_resource_deltas_published += 1


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["v0_p3_resource_mining"] = {
		"resource_commands": _resource_commands,
		"resource_rejections": _resource_rejections,
		"resource_deltas_published": _resource_deltas_published,
		"resource_snapshots_published": _resource_snapshots_published,
		"resource_delta_build_failures": _resource_delta_build_failures,
		"resource_resync_requests": _resource_resync_requests,
		"snapshot": (
			_service.create_resource_mining_snapshot()
			if _service != null and _service.has_method("create_resource_mining_snapshot")
			else {}
		),
	}
	return report
