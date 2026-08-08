extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix7.gd"

const FixedTickInputBufferFix10 = preload(
	"res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd"
)

# FIX10 keeps FIX7/FIX6 authority timing, backpressure, persistence and item
# replication unchanged. It adds one bounded movement acknowledgement sidecar to
# snapshots: the authoritative kinematic state immediately after the server first
# consumed the latest input sequence, plus the client prediction tick carried by
# that input. This gives reconciliation a command-stream baseline rather than a
# wall-clock phase comparison.
#
# Accepted FIX7 source-contract compatibility anchors:
# LIGHTWEIGHT_READY_FULL_TERMINAL_V1
# res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix6.gd

const FIX10_PREDICTION_ACK_POLICY: String = "SERVER_ECHOED_POST_INPUT_BASELINE_V1"

var _fix10_prediction_acks: Dictionary = {}
var _fix10_ack_captures: int = 0
var _fix10_ack_capture_mismatches: int = 0
var _fix10_snapshots_with_ack: int = 0
var _fix10_max_input_apply_lag_ticks: int = 0


func setup(config: Dictionary) -> Dictionary:
	_fix10_prediction_acks.clear()
	_fix10_ack_captures = 0
	_fix10_ack_capture_mismatches = 0
	_fix10_snapshots_with_ack = 0
	_fix10_max_input_apply_lag_ticks = 0
	return super.setup(config)


func _ensure_input_buffer(peer_id: String, logical_id: String):
	if _peer_input_buffers.has(peer_id):
		return _peer_input_buffers[peer_id]
	var buffer = FixedTickInputBufferFix10.new()
	var setup_result: Dictionary = buffer.configure(_last_processed_input_sequence(logical_id))
	if not bool(setup_result.get("success", false)):
		return null
	_peer_input_buffers[peer_id] = buffer
	return buffer


func _run_fixed_tick(server_tick: int) -> void:
	super._run_fixed_tick(server_tick)
	if _service == null or _server_tick != server_tick:
		return
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		var logical_id: String = String(_peer_to_player.get(peer_id, ""))
		var buffer = _peer_input_buffers.get(peer_id)
		if logical_id.is_empty() or buffer == null or not buffer.has_method("get_report"):
			continue
		var buffer_report: Dictionary = buffer.get_report(server_tick)
		if int(buffer_report.get("fix10_current_input_applied_server_tick", 0)) != server_tick:
			continue
		var sequence: int = int(buffer_report.get("fix10_current_input_sequence", 0))
		var client_tick: int = int(buffer_report.get("fix10_current_client_tick", 0))
		if sequence < 1 or client_tick < 1:
			_fix10_ack_capture_mismatches += 1
			continue
		var player: Dictionary = _service.get_player(logical_id)
		if player.is_empty() or int(player.get("last_input_sequence", 0)) != sequence:
			_fix10_ack_capture_mismatches += 1
			continue
		_fix10_prediction_acks[logical_id] = {
			"input_sequence": sequence,
			"client_tick": client_tick,
			"applied_server_tick": server_tick,
			"position": Dictionary(player.get("position", {})).duplicate(true),
			"velocity": Dictionary(player.get("velocity", {})).duplicate(true),
			"orientation_yaw": float(player.get("orientation_yaw", 0.0)),
			"state_revision": int(player.get("state_revision", 1)),
		}
		_fix10_ack_captures += 1
		_fix10_max_input_apply_lag_ticks = maxi(
			_fix10_max_input_apply_lag_ticks,
			maxi(server_tick - client_tick, 0)
		)


func _maybe_publish_movement_snapshot() -> void:
	if not _movement_snapshot_dirty or _service == null:
		return
	if _server_tick - _last_movement_snapshot_tick < NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS:
		return
	_last_movement_snapshot_tick = _server_tick
	var compact_result: Dictionary = CompactGameplaySnapshot.encode(_service.create_snapshot())
	if not bool(compact_result.get("success", false)):
		_compact_movement_snapshot_failures += 1
		_last_error_code = String(compact_result.get("error_code", "COMPACT_GAMEPLAY_SNAPSHOT_BUILD_FAILED"))
		return
	var compact_snapshot: Dictionary = Dictionary(
		compact_result.get("details", {}).get("snapshot", {})
	).duplicate(true)
	var all_enqueued := true
	var target_count := 0
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		target_count += 1
		var data: Dictionary = {
			"reason": "MOVEMENT_NETWORK_TICK",
			"snapshot": compact_snapshot,
			"prediction_ack_policy": FIX10_PREDICTION_ACK_POLICY,
		}
		var ack: Dictionary = _fix10_ack_for_peer(peer_id)
		if not ack.is_empty():
			data["prediction_ack"] = ack
			_fix10_snapshots_with_ack += 1
		if _send_on_channel(
			peer_id,
			"COMPACT_GAMEPLAY_SNAPSHOT",
			data,
			RealtimeChannelPolicy.SNAPSHOT,
			"UNRELIABLE_SEQUENCED"
		):
			_broadcasts += 1
			_compact_movement_snapshots_published += 1
		else:
			all_enqueued = false
			_movement_snapshot_enqueue_failures += 1
	_movement_snapshot_dirty = target_count > 0 and not all_enqueued
	if all_enqueued and target_count > 0:
		_movement_snapshots_published += 1


func _broadcast_snapshot(
	reason: String,
	channel: String = RealtimeChannelPolicy.RESYNC,
	delivery_mode: String = "RELIABLE_ORDERED"
) -> void:
	var snapshot: Dictionary = _service.create_snapshot()
	for peer_id_value in _peer_to_player.keys():
		var peer_id: String = String(peer_id_value)
		var data: Dictionary = {
			"reason": reason,
			"snapshot": snapshot,
			"prediction_ack_policy": FIX10_PREDICTION_ACK_POLICY,
		}
		var ack: Dictionary = _fix10_ack_for_peer(peer_id)
		if not ack.is_empty():
			data["prediction_ack"] = ack
			_fix10_snapshots_with_ack += 1
		if _send_on_channel(peer_id, "GAMEPLAY_SNAPSHOT", data, channel, delivery_mode):
			_broadcasts += 1


func _fix10_ack_for_peer(peer_id: String) -> Dictionary:
	var logical_id: String = String(_peer_to_player.get(peer_id, ""))
	if logical_id.is_empty() or not _fix10_prediction_acks.has(logical_id):
		return {}
	return Dictionary(_fix10_prediction_acks[logical_id]).duplicate(true)


func _dispatch_deferred_report() -> void:
	# Keep the FIX7 source boundary explicit; the parent remains the implementation
	# and dynamically calls this leaf's lightweight report builder.
	super._dispatch_deferred_report()


func _build_fix7_ready_report() -> Dictionary:
	var report: Dictionary = super._build_fix7_ready_report()
	var foundation: Dictionary = Dictionary(
		report.get("realtime_foundation", {})
	).duplicate(true)
	foundation["fix10_prediction_ack_policy"] = FIX10_PREDICTION_ACK_POLICY
	foundation["fix10_prediction_ack_captures"] = _fix10_ack_captures
	foundation["fix10_prediction_ack_capture_mismatches"] = _fix10_ack_capture_mismatches
	foundation["fix10_snapshots_with_prediction_ack"] = _fix10_snapshots_with_ack
	foundation["fix10_connected_ack_count"] = _fix10_prediction_acks.size()
	foundation["fix10_max_input_apply_lag_ticks"] = _fix10_max_input_apply_lag_ticks
	report["realtime_foundation"] = foundation
	return report


func get_fix7_ready_report_policy() -> Dictionary:
	var report: Dictionary = super.get_fix7_ready_report_policy()
	report["fix10_prediction_ack_policy"] = FIX10_PREDICTION_ACK_POLICY
	return report


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_prediction_ack"] = {
		"policy": FIX10_PREDICTION_ACK_POLICY,
		"captures": _fix10_ack_captures,
		"capture_mismatches": _fix10_ack_capture_mismatches,
		"snapshots_with_ack": _fix10_snapshots_with_ack,
		"connected_ack_count": _fix10_prediction_acks.size(),
		"max_input_apply_lag_ticks": _fix10_max_input_apply_lag_ticks,
	}
	return report
