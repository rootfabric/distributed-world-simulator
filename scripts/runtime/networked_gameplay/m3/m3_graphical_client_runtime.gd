extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"

# INT0 composition boundary:
# - the inherited script remains the accepted NX6 transport, fixed-tick,
#   prediction, reconciliation and predicted-item runtime;
# - this adapter adds bounded recovery from out-of-order gameplay state and FIX6
#   observability throttling without changing authority or prediction semantics.
# Full and compact snapshots may cross channels with the same semantic revision
# but different fixed server ticks. Those clock-only reorderings are not state
# mutations; true same-revision semantic mutations remain rejected.

const M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS: int = 250
const M7_CLIENT_TELEMETRY_HOT_PATH_POLICY: String = "RING_BUFFER_OBSERVE_THROTTLED_PEER_STATS_V1"
const M7_CLIENT_SLOW_PROCESS_FRAME_MS: float = 50.0

var _pending_replica_resync := false
var _delta_base_mismatches := 0
var _snapshot_resyncs := 0
var _last_prediction_health_ms := 0
var _full_snapshot_clock_updates := 0
var _full_snapshot_clock_replays := 0
var _compact_snapshot_clock_replays := 0
var _fix6_last_peer_telemetry_sample_ms: int = 0
var _fix6_peer_telemetry_samples: int = 0
var _fix6_peer_telemetry_skips: int = 0
var _fix6_peer_telemetry_last_duration_ms: float = 0.0
var _fix6_peer_telemetry_max_duration_ms: float = 0.0
var _fix6_process_last_duration_ms: float = 0.0
var _fix6_process_max_duration_ms: float = 0.0
var _fix6_slow_process_frames: int = 0


func _process(delta: float) -> void:
	var fix6_process_started_us: int = Time.get_ticks_usec()
	# M5 keeps this transport-session binding visible at the production source
	# boundary. The inherited NX6 process sends JOIN with the same value; this
	# assignment makes the composed adapter explicitly preserve that contract.
	if _handshake_verified and not _join_sent and not _transport_session_id.is_empty():
		_join_operation_id = Support.transport_bound_operation_id(_logical_player_id, "join", _transport_session_id)
	super._process(delta)
	_fix6_process_last_duration_ms = float(Time.get_ticks_usec() - fix6_process_started_us) / 1000.0
	_fix6_process_max_duration_ms = maxf(
		_fix6_process_max_duration_ms, _fix6_process_last_duration_ms
	)
	if _fix6_process_last_duration_ms >= M7_CLIENT_SLOW_PROCESS_FRAME_MS:
		_fix6_slow_process_frames += 1
	_emit_prediction_health_if_due()


func _update_runtime_telemetry() -> void:
	if _telemetry == null:
		return
	# Keep cheap client gauges current every frame. The inherited implementation
	# rebuilt the complete transport boundary snapshot every process frame only to
	# read one peer's RTT/jitter/loss. That duplicates queues/session/runtime state
	# on both graphical clients and compounds server-side allocation pressure during
	# item stress, so FIX6 samples the diagnostic transport snapshot at 4 Hz.
	_telemetry.set_gauge("pending_blocking_commands", float(_awaited_command_ids.size()))
	_telemetry.set_gauge("buffered_command_results", float(_command_results.size()))
	_telemetry.set_gauge("pending_operation_timers", float(_operation_started_ms.size()))
	_telemetry.set_gauge("handshake_verified", 1.0 if _handshake_verified else 0.0)
	if _prediction_reconciler != null and _prediction_reconciler.is_configured():
		var prediction_report: Dictionary = _prediction_reconciler.get_report()
		_telemetry.set_gauge("prediction_buffer_size", float(prediction_report.get("history_size", 0)))
		_telemetry.set_gauge("prediction_visual_offset_m", float(prediction_report.get("visual_offset_m", 0.0)))
		_telemetry.set_gauge("prediction_tick", float(prediction_report.get("prediction_tick", 0)))

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _fix6_last_peer_telemetry_sample_ms < M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS:
		_fix6_peer_telemetry_skips += 1
		return
	_fix6_last_peer_telemetry_sample_ms = now_ms
	var sample_started_us: int = Time.get_ticks_usec()
	var boundary_snapshot: Dictionary = _boundary.get_snapshot() if _boundary != null else {}
	var port_runtime: Dictionary = boundary_snapshot.get("port_runtime", {})
	var peer_statistics: Dictionary = port_runtime.get("peer_statistics", {})
	var server_stats: Dictionary = {}
	if peer_statistics.has(SERVER_PEER_ID) and peer_statistics[SERVER_PEER_ID] is Dictionary:
		server_stats = peer_statistics[SERVER_PEER_ID]
	if not server_stats.is_empty():
		_telemetry.set_gauge("rtt_ms", float(server_stats.get("rtt_ms", 0)))
		_telemetry.set_gauge("jitter_ms", float(server_stats.get("rtt_variance_ms", 0)))
		_telemetry.set_gauge("packet_loss_percent", float(server_stats.get("packet_loss_percent", 0.0)))
	_fix6_peer_telemetry_last_duration_ms = float(Time.get_ticks_usec() - sample_started_us) / 1000.0
	_fix6_peer_telemetry_max_duration_ms = maxf(
		_fix6_peer_telemetry_max_duration_ms, _fix6_peer_telemetry_last_duration_ms
	)
	_fix6_peer_telemetry_samples += 1


func _emit_prediction_health_if_due() -> void:
	if (
		not _debug_logging
		or not _joined
		or _prediction_reconciler == null
		or not _prediction_reconciler.is_configured()
	):
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_prediction_health_ms < 2000:
		return
	_last_prediction_health_ms = now_ms
	var prediction: Dictionary = _prediction_reconciler.get_report()
	var prediction_tick: int = int(prediction.get("prediction_tick", 0))
	var authoritative_tick: int = int(prediction.get("last_authoritative_tick", 0))
	_debug_event("PREDICTION_HEALTH", {
		"prediction_tick": prediction_tick,
		"authoritative_tick": authoritative_tick,
		"lead_ticks": maxi(prediction_tick - authoritative_tick, 0),
		"current_input_sequence": int(prediction.get("current_input_sequence", 0)),
		"authoritative_input_sequence": int(prediction.get("last_authoritative_sequence", 0)),
		"history_size": int(prediction.get("history_size", 0)),
		"history_overflows": int(prediction.get("history_overflows", 0)),
		"history_miss_resets": int(prediction.get("history_miss_resets", 0)),
		"corrections": int(prediction.get("corrections", 0)),
		"hard_corrections": int(prediction.get("hard_corrections", 0)),
		"last_error_m": float(prediction.get("last_error_m", 0.0)),
		"maximum_error_m": float(prediction.get("maximum_error_m", 0.0)),
		"visual_offset_m": float(prediction.get("visual_offset_m", 0.0)),
		"client_process_duration_ms": _fix6_process_last_duration_ms,
		"client_process_max_duration_ms": _fix6_process_max_duration_ms,
		"client_slow_process_frames": _fix6_slow_process_frames,
		"peer_telemetry_samples": _fix6_peer_telemetry_samples,
		"peer_telemetry_skips": _fix6_peer_telemetry_skips,
		"peer_telemetry_last_duration_ms": _fix6_peer_telemetry_last_duration_ms,
		"peer_telemetry_max_duration_ms": _fix6_peer_telemetry_max_duration_ms,
	})


func _handle_join_ack(payload: Dictionary) -> void:
	super._handle_join_ack(payload)
	if _joined:
		_pending_replica_resync = false


func _accept_snapshot(snapshot: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		var error_code := String(accepted.get("error_code", "M3_SNAPSHOT_REJECTED"))
		if error_code == "MULTIPLAYER_SAME_REVISION_MUTATION":
			var current: Dictionary = _replica.get_snapshot()
			if _same_snapshot_semantics_except_clock(current, snapshot):
				var incoming_tick := int(snapshot.get("server_tick", -1))
				var current_tick := int(current.get("server_tick", -1))
				if incoming_tick > current_tick:
					# Match the accepted compact-snapshot policy: advance prediction from
					# the newer authoritative clock without rewriting semantic replica
					# state at the same revision.
					_full_snapshot_clock_updates += 1
					_reconcile_prediction_from_snapshot(snapshot)
					_prune_acknowledged_inputs()
				else:
					# A reliable full snapshot may arrive after a newer compact snapshot
					# on another ENet channel. It is a superseded replay, not mutation.
					_full_snapshot_clock_replays += 1
				if _last_error_code == "MULTIPLAYER_SAME_REVISION_MUTATION":
					_last_error_code = ""
				return
		_last_error_code = error_code
		return
	if _pending_replica_resync:
		_pending_replica_resync = false
		_snapshot_resyncs += 1
	_last_error_code = ""
	if not bool(accepted.get("details", {}).get("replay", false)):
		_snapshot_updates += 1
	_reconcile_prediction_from_snapshot(_replica.get_snapshot())
	_prune_acknowledged_inputs()
	replica_updated.emit(_replica.get_snapshot())


func _accept_compact_snapshot(snapshot: Dictionary) -> void:
	var decoded: Dictionary = CompactGameplaySnapshot.decode(snapshot)
	if not bool(decoded.get("success", false)):
		_compact_snapshot_rejections += 1
		_last_error_code = String(decoded.get("error_code", "COMPACT_GAMEPLAY_SNAPSHOT_REJECTED"))
		return
	var decoded_snapshot: Dictionary = Dictionary(decoded.get("details", {}).get("snapshot", {}))
	var accepted: Dictionary = _replica.accept_snapshot(decoded_snapshot)
	if not bool(accepted.get("success", false)):
		var error_code := String(accepted.get("error_code", "M3_COMPACT_SNAPSHOT_REJECTED"))
		if (
			error_code == "MULTIPLAYER_SAME_REVISION_MUTATION"
			and _same_snapshot_semantics_except_clock(_replica.get_snapshot(), decoded_snapshot)
		):
			var current_tick := int(_replica.get_snapshot().get("server_tick", -1))
			var incoming_tick := int(decoded_snapshot.get("server_tick", -1))
			if incoming_tick > current_tick:
				_compact_snapshot_clock_updates += 1
				_reconcile_prediction_from_snapshot(decoded_snapshot)
				_prune_acknowledged_inputs()
			else:
				_compact_snapshot_clock_replays += 1
			if _last_error_code == "MULTIPLAYER_SAME_REVISION_MUTATION":
				_last_error_code = ""
			return
		_compact_snapshot_rejections += 1
		_last_error_code = error_code
		return
	if not bool(accepted.get("details", {}).get("replay", false)):
		_snapshot_updates += 1
		_compact_snapshot_updates += 1
	_reconcile_prediction_from_snapshot(_replica.get_snapshot())
	_prune_acknowledged_inputs()
	replica_updated.emit(_replica.get_snapshot())


func _same_snapshot_semantics_except_clock(current: Dictionary, incoming: Dictionary) -> bool:
	if current.is_empty() or incoming.is_empty():
		return false
	if int(incoming.get("revision", -1)) != int(current.get("revision", -2)):
		return false
	if String(incoming.get("authority_owner_id", "")) != String(current.get("authority_owner_id", "")):
		return false
	if int(incoming.get("authority_epoch", 0)) != int(current.get("authority_epoch", 0)):
		return false
	var current_state: Dictionary = current.duplicate(true)
	var incoming_state: Dictionary = incoming.duplicate(true)
	for key in ["server_tick", "checksum"]:
		current_state.erase(key)
		incoming_state.erase(key)
	return current_state == incoming_state


func _accept_delta(delta: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_delta(delta)
	if not bool(accepted.get("success", false)):
		var error_code := String(
			accepted.get("error_code", "M3_DELTA_REJECTED")
		)
		if error_code == "MULTIPLAYER_DELTA_BASE_MISMATCH":
			_pending_replica_resync = true
			_delta_base_mismatches += 1
			return
		_last_error_code = error_code
		return
	if not _pending_replica_resync:
		_last_error_code = ""
	if not bool(accepted.get("details", {}).get("replay", false)):
		_delta_updates += 1
	replica_updated.emit(_replica.get_snapshot())


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["pending_replica_resync"] = _pending_replica_resync
	report["delta_base_mismatches"] = _delta_base_mismatches
	report["snapshot_resyncs"] = _snapshot_resyncs
	report["full_snapshot_clock_updates"] = _full_snapshot_clock_updates
	report["full_snapshot_clock_replays"] = _full_snapshot_clock_replays
	report["compact_snapshot_clock_replays"] = _compact_snapshot_clock_replays
	report["client_realtime_foundation"] = {
		"telemetry_hot_path_policy": M7_CLIENT_TELEMETRY_HOT_PATH_POLICY,
		"peer_telemetry_interval_ms": M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS,
		"peer_telemetry_samples": _fix6_peer_telemetry_samples,
		"peer_telemetry_skips": _fix6_peer_telemetry_skips,
		"peer_telemetry_last_duration_ms": _fix6_peer_telemetry_last_duration_ms,
		"peer_telemetry_max_duration_ms": _fix6_peer_telemetry_max_duration_ms,
		"process_last_duration_ms": _fix6_process_last_duration_ms,
		"process_max_duration_ms": _fix6_process_max_duration_ms,
		"slow_process_frame_threshold_ms": M7_CLIENT_SLOW_PROCESS_FRAME_MS,
		"slow_process_frames": _fix6_slow_process_frames,
		"telemetry_storage": _telemetry.get_report() if _telemetry != null else {},
	}
	return report
