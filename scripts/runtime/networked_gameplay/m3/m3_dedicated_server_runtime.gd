extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_base.gd"

# M7 composition correction: a successful player JOIN must materialize the
# canonical sandbox inventory before durable commit and before JOIN_ACK captures
# the ItemGraph. Non-playable M3/M5/M6 behavior remains inherited unchanged.

var _join_item_materializations: int = 0
var _join_item_materialization_failures: int = 0


func _handle_join(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var logical_id := String(payload.get("logical_player_id", "")).strip_edges().to_lower()
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if logical_id.is_empty() or not _is_canonical_operation_id(operation_id):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "INVALID_JOIN_PAYLOAD"})
		return
	var result: Dictionary = _service.join(logical_id, session_id, operation_id)
	if bool(result.get("success", false)) and _playable_sandbox:
		var materialized := _materialize_join_item_inventory(logical_id)
		if not bool(materialized.get("success", false)):
			_join_item_materialization_failures += 1
			_rejections += 1
			_send(peer_id, "JOIN_REJECTED", {
				"operation_id": operation_id,
				"error_code": String(materialized.get("error_code", "M7_JOIN_ITEM_MATERIALIZATION_FAILED")),
			})
			_write_report("READY", false)
			return
		if bool(materialized.get("details", {}).get("created", false)):
			_join_item_materializations += 1
	if not _persist_command_result(operation_id, "JOIN", logical_id, result):
		_send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": "M6_DURABLE_COMMIT_FAILED"})
		return
	if not bool(result.get("success", false)):
		_rejections += 1
		var rejection_sent := _send(peer_id, "JOIN_REJECTED", {"operation_id": operation_id, "error_code": String(result.get("error_code", "JOIN_REJECTED"))})
		if rejection_sent:
			_mark_operation_delivered(operation_id)
		_write_report("READY", false)
		return
	_peer_to_player[peer_id] = logical_id
	_peer_to_session[peer_id] = session_id
	_peer_input_buffers.erase(peer_id)
	_ensure_input_buffer(peer_id, logical_id)
	_debug_event("PLAYER_JOINED", {"peer_id":peer_id,"session_id":session_id,"logical_player_id":logical_id})
	var replay := _is_replay_result(result)
	if not replay:
		_joins += 1
	var join_sent := _send_on_channel(peer_id, "JOIN_ACK", {
		"operation_id": operation_id,
		"player": result.get("details", {}).get("player", {}),
		"snapshot": result.get("details", {}).get("snapshot", {}),
		"item_graph_snapshot": _service.create_canonical_item_graph_snapshot(),
	}, RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
	if join_sent:
		_item_graph_full_snapshots_published += 1
	if not replay:
		_broadcast_delta(result.get("details", {}).get("delta", {}), peer_id)
		_broadcast_snapshot("PLAYER_JOINED")
		_broadcast_item_snapshot("PLAYER_JOINED", peer_id)
		_capture_two_connected_checksum()
	if join_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _materialize_join_item_inventory(logical_player_id: String) -> Dictionary:
	if _service == null:
		return {"success": false, "error_code": "M7_JOIN_ITEM_SERVICE_MISSING", "details": {}}
	var item_graph = _service.get("_canonical_multiplayer_items")
	if item_graph == null or not item_graph.has_method("ensure_player_for_join"):
		return {"success": false, "error_code": "M7_JOIN_ITEM_MATERIALIZER_MISSING", "details": {}}
	var result_value = item_graph.call("ensure_player_for_join", logical_player_id)
	if not result_value is Dictionary:
		return {"success": false, "error_code": "M7_JOIN_ITEM_MATERIALIZER_INVALID_RESULT", "details": {}}
	return Dictionary(result_value).duplicate(true)


func get_join_item_materialization_report() -> Dictionary:
	return {
		"join_item_materializations": _join_item_materializations,
		"join_item_materialization_failures": _join_item_materialization_failures,
	}
