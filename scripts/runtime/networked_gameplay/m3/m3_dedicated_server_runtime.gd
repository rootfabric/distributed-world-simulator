extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix7.gd"

const FixedTickInputBufferFix10 = preload(
	"res://scripts/network/simulation/fixed_tick_input_buffer_fix10.gd"
)
const NetworkUtilsFix10 = preload("res://scripts/network/contracts/network_contract_utils.gd")

# FIX10 keeps FIX7/FIX6 authority timing, backpressure, persistence and item
# replication unchanged. It adds one bounded movement acknowledgement sidecar to
# snapshots: the authoritative kinematic state immediately after the server first
# consumed the latest input sequence, plus the client prediction tick carried by
# that input. This gives reconciliation a command-stream baseline rather than a
# wall-clock phase comparison.
#
# Fix1 compacted the ACK sidecar because a verbose dictionary pushed one exact
# Windows two-client movement frame to 1418 bytes, above Godot ENet's reported
# 1392-byte unreliable MTU. Fix2 adds a hard preflight invariant on top of that:
# the exact canonical ProtocolFrame bytes are measured before transport queue
# commit. Oversized realtime snapshots first retry without the optional ACK; if
# the no-ACK compact frame is still over the conservative budget, that realtime
# snapshot is skipped rather than fragmented.
#
# FIX10 fix3 closes the coverage hole exposed by the long two-client run: when the
# ACK must be omitted from the movement snapshot to preserve its MTU, the same
# compact ACK is emitted as a tiny independent UNRELIABLE_SEQUENCED packet on the
# TELEMETRY ENet channel. Snapshot traffic therefore never competes with its own
# ACK in the same sequenced stream, and the prediction baseline is no longer lost
# simply because a two-player snapshot is near the packet budget. This fallback
# is best-effort metadata only; failure to enqueue it never fails or delays the
# authoritative movement snapshot.
#
# Accepted FIX7/FIX6 source-contract compatibility anchors. The actual behavior
# remains inherited; keep the fixed-simulation anchor before the network-drain
# anchor because the accepted regression verifies that source ordering:
# _advance_fixed_simulation(delta)
# _boundary.poll_events(M7_NETWORK_EVENT_BUDGET_PER_FRAME)
# M7_FIXED_TICK_MAX_CATCH_UP_TICKS
# M7_STALL_SNAPSHOT_GUARD_SECONDS
# _movement_snapshot_recovery_suppressions
# M7_PEER_TELEMETRY_INTERVAL_MS
# _peer_telemetry_skips
# server_process_max_duration_ms
# report_max_snapshot_build_duration_ms
# Thread.new()
# _report_requests_coalesced
# _broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
# _broadcast_item_delta(item_delta, peer_id, command_type)
# LIGHTWEIGHT_READY_FULL_TERMINAL_V1
# res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix6.gd

const FIX10_PREDICTION_ACK_POLICY: String = "SERVER_ECHOED_POST_INPUT_BASELINE_V1"
const FIX10_PREDICTION_ACK_WIRE_POLICY: String = "COMPACT_ARRAY_V1"
const FIX10_UNRELIABLE_MTU_POLICY: String = "OPTIONAL_ACK_OMISSION_THEN_DROP_OVERSIZE_V1"
const FIX10_UNRELIABLE_SAFE_PACKET_BYTES: int = 1350
const FIX10_UNRELIABLE_DECISION_SEND: String = "SEND"
const FIX10_UNRELIABLE_DECISION_RETRY_WITHOUT_ACK: String = "RETRY_WITHOUT_ACK"
const FIX10_UNRELIABLE_DECISION_DROP: String = "DROP"
const FIX10_FIX3_ACK_FALLBACK_POLICY: String = "SEPARATE_TELEMETRY_CHANNEL_WHEN_SNAPSHOT_ACK_OMITTED_V1"

var _fix10_prediction_acks: Dictionary = {}
var _fix10_ack_captures: int = 0
var _fix10_ack_capture_mismatches: int = 0
var _fix10_snapshots_with_ack: int = 0
var _fix10_max_input_apply_lag_ticks: int = 0
var _fix10_ack_omitted_for_mtu: int = 0
var _fix10_oversized_unreliable_frames_prevented: int = 0
var _fix10_movement_snapshots_dropped_for_mtu: int = 0
var _fix10_max_unreliable_candidate_bytes: int = 0
var _fix10_max_unreliable_sent_bytes: int = 0
var _fix10_max_without_ack_bytes: int = 0
var _fix10_fix3_standalone_ack_attempts: int = 0
var _fix10_fix3_standalone_ack_sent: int = 0
var _fix10_fix3_standalone_ack_failures: int = 0
var _fix10_fix3_max_standalone_ack_bytes: int = 0


func setup(config: Dictionary) -> Dictionary:
	_fix10_prediction_acks.clear()
	_fix10_ack_captures = 0
	_fix10_ack_capture_mismatches = 0
	_fix10_snapshots_with_ack = 0
	_fix10_max_input_apply_lag_ticks = 0
	_fix10_ack_omitted_for_mtu = 0
	_fix10_oversized_unreliable_frames_prevented = 0
	_fix10_movement_snapshots_dropped_for_mtu = 0
	_fix10_max_unreliable_candidate_bytes = 0
	_fix10_max_unreliable_sent_bytes = 0
	_fix10_max_without_ack_bytes = 0
	_fix10_fix3_standalone_ack_attempts = 0
	_fix10_fix3_standalone_ack_sent = 0
	_fix10_fix3_standalone_ack_failures = 0
	_fix10_fix3_max_standalone_ack_bytes = 0
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
		}
		var ack_wire: Array = _fix10_ack_wire_for_peer(peer_id)
		if not ack_wire.is_empty():
			data["prediction_ack"] = ack_wire
		var sent: Dictionary = _fix10_send_mtu_safe_movement_snapshot(peer_id, data)
		if bool(sent.get("success", false)):
			_broadcasts += 1
			_compact_movement_snapshots_published += 1
			if bool(sent.get("included_prediction_ack", false)):
				_fix10_snapshots_with_ack += 1
		else:
			all_enqueued = false
			_movement_snapshot_enqueue_failures += 1
	_movement_snapshot_dirty = target_count > 0 and not all_enqueued
	if all_enqueued and target_count > 0:
		_movement_snapshots_published += 1


func _fix10_send_mtu_safe_movement_snapshot(peer_id: String, data: Dictionary) -> Dictionary:
	if _boundary == null or peer_id.is_empty():
		return {"success": false, "error_code": "FIX10_BOUNDARY_NOT_READY"}
	if not _ensure_peer_ready(peer_id):
		return {"success": false, "error_code": "FIX10_PEER_NOT_READY"}
	var payload: Dictionary = data.duplicate(true)
	payload["type"] = "COMPACT_GAMEPLAY_SNAPSHOT"
	payload["server_sent_at_ms"] = Time.get_ticks_msec()
	var candidate: Dictionary = _fix10_build_unreliable_frame(peer_id, payload)
	if not bool(candidate.get("success", false)):
		_last_error_code = String(candidate.get("error_code", "FRAME_CREATE_FAILED"))
		return candidate
	var frame: Dictionary = Dictionary(candidate.get("frame", {})).duplicate(true)
	var packet_bytes: int = int(candidate.get("packet_bytes", 0))
	_fix10_max_unreliable_candidate_bytes = maxi(_fix10_max_unreliable_candidate_bytes, packet_bytes)
	var included_ack: bool = payload.has("prediction_ack")
	var omitted_ack_wire: Array = []
	var decision: String = _fix10_unreliable_budget_decision(packet_bytes, included_ack)
	if decision == FIX10_UNRELIABLE_DECISION_RETRY_WITHOUT_ACK:
		_fix10_oversized_unreliable_frames_prevented += 1
		_fix10_ack_omitted_for_mtu += 1
		omitted_ack_wire = Array(payload.get("prediction_ack", [])).duplicate(true)
		payload.erase("prediction_ack")
		candidate = _fix10_build_unreliable_frame(peer_id, payload)
		if not bool(candidate.get("success", false)):
			_last_error_code = String(candidate.get("error_code", "FRAME_CREATE_FAILED"))
			return candidate
		frame = Dictionary(candidate.get("frame", {})).duplicate(true)
		packet_bytes = int(candidate.get("packet_bytes", 0))
		_fix10_max_without_ack_bytes = maxi(_fix10_max_without_ack_bytes, packet_bytes)
		included_ack = false
		decision = _fix10_unreliable_budget_decision(packet_bytes, false)
	if decision == FIX10_UNRELIABLE_DECISION_DROP:
		_fix10_oversized_unreliable_frames_prevented += 1
		_fix10_movement_snapshots_dropped_for_mtu += 1
		return {
			"success": false,
			"error_code": "FIX10_UNRELIABLE_FRAME_EXCEEDS_SAFE_MTU",
			"packet_bytes": packet_bytes,
			"safe_packet_bytes": FIX10_UNRELIABLE_SAFE_PACKET_BYTES,
		}
	var queued: Dictionary = _boundary.send_to_peer(peer_id, frame)
	if not bool(queued.get("success", false)):
		_last_error_code = String(queued.get("error_code", "SEND_FAILED"))
		return queued
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_last_error_code = String(flushed.get("error_code", "FLUSH_FAILED"))
		return flushed
	_messages_sent += 1
	_fix10_max_unreliable_sent_bytes = maxi(_fix10_max_unreliable_sent_bytes, packet_bytes)

	# Preserve snapshot success even if the best-effort ACK fallback is lost. The
	# client can reconcile from a later ACK; a metadata failure must never create a
	# gameplay snapshot retransmission/backpressure loop.
	if not omitted_ack_wire.is_empty():
		var compact_snapshot: Dictionary = Dictionary(data.get("snapshot", {}))
		_fix10_fix3_send_standalone_prediction_ack(
			peer_id,
			omitted_ack_wire,
			int(compact_snapshot.get("t", -1))
		)
	return {
		"success": true,
		"included_prediction_ack": included_ack,
		"standalone_ack_attempted": not omitted_ack_wire.is_empty(),
		"packet_bytes": packet_bytes,
	}


func _fix10_fix3_send_standalone_prediction_ack(
	peer_id: String,
	ack_wire: Array,
	snapshot_server_tick: int
) -> bool:
	if (
		_boundary == null
		or peer_id.is_empty()
		or ack_wire.is_empty()
		or snapshot_server_tick < 0
		or not _ensure_peer_ready(peer_id)
	):
		_fix10_fix3_standalone_ack_failures += 1
		return false
	_fix10_fix3_standalone_ack_attempts += 1
	var payload: Dictionary = {
		"type": "PREDICTION_ACK",
		"server_sent_at_ms": Time.get_ticks_msec(),
		"prediction_ack": ack_wire.duplicate(true),
		"snapshot_server_tick": snapshot_server_tick,
	}
	var candidate: Dictionary = _fix10_build_unreliable_frame(
		peer_id,
		payload,
		RealtimeChannelPolicy.TELEMETRY
	)
	if not bool(candidate.get("success", false)):
		_fix10_fix3_standalone_ack_failures += 1
		return false
	var packet_bytes: int = int(candidate.get("packet_bytes", 0))
	_fix10_fix3_max_standalone_ack_bytes = maxi(
		_fix10_fix3_max_standalone_ack_bytes,
		packet_bytes
	)
	if packet_bytes > FIX10_UNRELIABLE_SAFE_PACKET_BYTES:
		_fix10_fix3_standalone_ack_failures += 1
		return false
	var frame: Dictionary = Dictionary(candidate.get("frame", {})).duplicate(true)
	var queued: Dictionary = _boundary.send_to_peer(peer_id, frame)
	if not bool(queued.get("success", false)):
		_fix10_fix3_standalone_ack_failures += 1
		return false
	var flushed: Dictionary = _boundary.flush_outbound(32, peer_id)
	if not bool(flushed.get("success", false)):
		_fix10_fix3_standalone_ack_failures += 1
		return false
	_messages_sent += 1
	_fix10_fix3_standalone_ack_sent += 1
	return true


func _fix10_build_unreliable_frame(
	peer_id: String,
	payload: Dictionary,
	channel: String = RealtimeChannelPolicy.SNAPSHOT
) -> Dictionary:
	var frame_result: Dictionary = _boundary.create_frame_for_peer(
		peer_id,
		channel,
		Support.MESSAGE_SCHEMA,
		payload,
		"UNRELIABLE_SEQUENCED"
	)
	if not bool(frame_result.get("success", false)):
		return {
			"success": false,
			"error_code": String(frame_result.get("error_code", "FRAME_CREATE_FAILED")),
		}
	var frame: Dictionary = Dictionary(
		frame_result.get("details", {}).get("frame", {})
	).duplicate(true)
	var encoded: String = NetworkUtilsFix10.canonical_json(frame)
	if encoded.is_empty():
		return {"success": false, "error_code": "FIX10_FRAME_SERIALIZATION_FAILED"}
	return {
		"success": true,
		"frame": frame,
		"packet_bytes": encoded.to_utf8_buffer().size(),
	}


func _fix10_unreliable_budget_decision(packet_bytes: int, has_prediction_ack: bool) -> String:
	if packet_bytes <= FIX10_UNRELIABLE_SAFE_PACKET_BYTES:
		return FIX10_UNRELIABLE_DECISION_SEND
	if has_prediction_ack:
		return FIX10_UNRELIABLE_DECISION_RETRY_WITHOUT_ACK
	return FIX10_UNRELIABLE_DECISION_DROP


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
		}
		var ack_wire: Array = _fix10_ack_wire_for_peer(peer_id)
		if not ack_wire.is_empty():
			data["prediction_ack"] = ack_wire
			_fix10_snapshots_with_ack += 1
		if _send_on_channel(peer_id, "GAMEPLAY_SNAPSHOT", data, channel, delivery_mode):
			_broadcasts += 1


func _fix10_ack_for_peer(peer_id: String) -> Dictionary:
	var logical_id: String = String(_peer_to_player.get(peer_id, ""))
	if logical_id.is_empty() or not _fix10_prediction_acks.has(logical_id):
		return {}
	return Dictionary(_fix10_prediction_acks[logical_id]).duplicate(true)


func _fix10_ack_wire_for_peer(peer_id: String) -> Array:
	var ack: Dictionary = _fix10_ack_for_peer(peer_id)
	if ack.is_empty():
		return []
	var position: Dictionary = Dictionary(ack.get("position", {}))
	var velocity: Dictionary = Dictionary(ack.get("velocity", {}))
	# Positional contract COMPACT_ARRAY_V1:
	# [sequence, client_tick, applied_server_tick,
	#  px, py, pz, vx, vy, vz, orientation_yaw, state_revision]
	return [
		int(ack.get("input_sequence", 0)),
		int(ack.get("client_tick", 0)),
		int(ack.get("applied_server_tick", 0)),
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0)),
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0)),
		float(ack.get("orientation_yaw", 0.0)),
		int(ack.get("state_revision", 1)),
	]


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
	foundation["fix10_prediction_ack_wire_policy"] = FIX10_PREDICTION_ACK_WIRE_POLICY
	foundation["fix10_prediction_ack_captures"] = _fix10_ack_captures
	foundation["fix10_prediction_ack_capture_mismatches"] = _fix10_ack_capture_mismatches
	foundation["fix10_snapshots_with_prediction_ack"] = _fix10_snapshots_with_ack
	foundation["fix10_connected_ack_count"] = _fix10_prediction_acks.size()
	foundation["fix10_max_input_apply_lag_ticks"] = _fix10_max_input_apply_lag_ticks
	foundation["fix10_unreliable_mtu_policy"] = FIX10_UNRELIABLE_MTU_POLICY
	foundation["fix10_unreliable_safe_packet_bytes"] = FIX10_UNRELIABLE_SAFE_PACKET_BYTES
	foundation["fix10_ack_omitted_for_mtu"] = _fix10_ack_omitted_for_mtu
	foundation["fix10_oversized_unreliable_frames_prevented"] = _fix10_oversized_unreliable_frames_prevented
	foundation["fix10_movement_snapshots_dropped_for_mtu"] = _fix10_movement_snapshots_dropped_for_mtu
	foundation["fix10_max_unreliable_candidate_bytes"] = _fix10_max_unreliable_candidate_bytes
	foundation["fix10_max_unreliable_sent_bytes"] = _fix10_max_unreliable_sent_bytes
	foundation["fix10_max_without_ack_bytes"] = _fix10_max_without_ack_bytes
	foundation["fix10_fix3_ack_fallback_policy"] = FIX10_FIX3_ACK_FALLBACK_POLICY
	foundation["fix10_fix3_standalone_ack_attempts"] = _fix10_fix3_standalone_ack_attempts
	foundation["fix10_fix3_standalone_ack_sent"] = _fix10_fix3_standalone_ack_sent
	foundation["fix10_fix3_standalone_ack_failures"] = _fix10_fix3_standalone_ack_failures
	foundation["fix10_fix3_max_standalone_ack_bytes"] = _fix10_fix3_max_standalone_ack_bytes
	report["realtime_foundation"] = foundation
	return report


func get_fix7_ready_report_policy() -> Dictionary:
	var report: Dictionary = super.get_fix7_ready_report_policy()
	report["fix10_prediction_ack_policy"] = FIX10_PREDICTION_ACK_POLICY
	report["fix10_prediction_ack_wire_policy"] = FIX10_PREDICTION_ACK_WIRE_POLICY
	report["fix10_unreliable_mtu_policy"] = FIX10_UNRELIABLE_MTU_POLICY
	report["fix10_unreliable_safe_packet_bytes"] = FIX10_UNRELIABLE_SAFE_PACKET_BYTES
	report["fix10_fix3_ack_fallback_policy"] = FIX10_FIX3_ACK_FALLBACK_POLICY
	return report


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_prediction_ack"] = {
		"policy": FIX10_PREDICTION_ACK_POLICY,
		"wire_policy": FIX10_PREDICTION_ACK_WIRE_POLICY,
		"captures": _fix10_ack_captures,
		"capture_mismatches": _fix10_ack_capture_mismatches,
		"snapshots_with_ack": _fix10_snapshots_with_ack,
		"connected_ack_count": _fix10_prediction_acks.size(),
		"max_input_apply_lag_ticks": _fix10_max_input_apply_lag_ticks,
		"unreliable_mtu_policy": FIX10_UNRELIABLE_MTU_POLICY,
		"unreliable_safe_packet_bytes": FIX10_UNRELIABLE_SAFE_PACKET_BYTES,
		"ack_omitted_for_mtu": _fix10_ack_omitted_for_mtu,
		"oversized_unreliable_frames_prevented": _fix10_oversized_unreliable_frames_prevented,
		"movement_snapshots_dropped_for_mtu": _fix10_movement_snapshots_dropped_for_mtu,
		"max_unreliable_candidate_bytes": _fix10_max_unreliable_candidate_bytes,
		"max_unreliable_sent_bytes": _fix10_max_unreliable_sent_bytes,
		"max_without_ack_bytes": _fix10_max_without_ack_bytes,
		"fix3_ack_fallback_policy": FIX10_FIX3_ACK_FALLBACK_POLICY,
		"fix3_standalone_ack_attempts": _fix10_fix3_standalone_ack_attempts,
		"fix3_standalone_ack_sent": _fix10_fix3_standalone_ack_sent,
		"fix3_standalone_ack_failures": _fix10_fix3_standalone_ack_failures,
		"fix3_max_standalone_ack_bytes": _fix10_fix3_max_standalone_ack_bytes,
	}
	return report