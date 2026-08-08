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
const FIX9_CLIENT_FRAME_BUDGET_POLICY: String = "PHASE_ACCOUNTING_NO_GAMEPLAY_SEMANTICS_V1"
const FIX9_PHASE_BUDGET_MS: float = 16.667

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
var _fix9_phase_stats: Dictionary = {}
var _fix9_message_type_counts: Dictionary = {}
var _fix9_in_process: bool = false
var _fix9_frame_message_dispatch_ms: float = 0.0
var _fix9_frame_input_flush_ms: float = 0.0
var _fix9_frame_telemetry_ms: float = 0.0
var _fix9_unattributed_last_duration_ms: float = 0.0
var _fix9_unattributed_max_duration_ms: float = 0.0
var _fix9_unattributed_slow_frames: int = 0


func _process(delta: float) -> void:
	var fix6_process_started_us: int = Time.get_ticks_usec()
	_fix9_frame_message_dispatch_ms = 0.0
	_fix9_frame_input_flush_ms = 0.0
	_fix9_frame_telemetry_ms = 0.0
	_fix9_in_process = true
	# M5 keeps this transport-session binding visible at the production source
	# boundary. The inherited NX6 process sends JOIN with the same value; this
	# assignment makes the composed adapter explicitly preserve that contract.
	if _handshake_verified and not _join_sent and not _transport_session_id.is_empty():
		_join_operation_id = Support.transport_bound_operation_id(_logical_player_id, "join", _transport_session_id)
	super._process(delta)
	_fix9_in_process = false
	_fix6_process_last_duration_ms = float(Time.get_ticks_usec() - fix6_process_started_us) / 1000.0
	_fix6_process_max_duration_ms = maxf(
		_fix6_process_max_duration_ms, _fix6_process_last_duration_ms
	)
	if _fix6_process_last_duration_ms >= M7_CLIENT_SLOW_PROCESS_FRAME_MS:
		_fix6_slow_process_frames += 1
	var accounted_ms: float = (
		_fix9_frame_message_dispatch_ms
		+ _fix9_frame_input_flush_ms
		+ _fix9_frame_telemetry_ms
	)
	_fix9_unattributed_last_duration_ms = maxf(_fix6_process_last_duration_ms - accounted_ms, 0.0)
	_fix9_unattributed_max_duration_ms = maxf(
		_fix9_unattributed_max_duration_ms,
		_fix9_unattributed_last_duration_ms
	)
	if _fix9_unattributed_last_duration_ms >= FIX9_PHASE_BUDGET_MS:
		_fix9_unattributed_slow_frames += 1
	_fix9_record_phase("process_unattributed", _fix9_unattributed_last_duration_ms)
	_emit_prediction_health_if_due()


func _handle_message(payload: Dictionary) -> void:
	var started_us: int = Time.get_ticks_usec()
	var message_type: String = String(payload.get("type", "UNKNOWN"))
	super._handle_message(payload)
	var duration_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	if _fix9_in_process:
		_fix9_frame_message_dispatch_ms += duration_ms
	_fix9_message_type_counts[message_type] = int(_fix9_message_type_counts.get(message_type, 0)) + 1
	_fix9_record_phase("message_dispatch", duration_ms)
	match message_type:
		"GAMEPLAY_DELTA", "GAMEPLAY_SNAPSHOT", "COMPACT_GAMEPLAY_SNAPSHOT":
			_fix9_record_phase("snapshot_message", duration_ms)
		"ITEM_GRAPH_SNAPSHOT", "ITEM_GRAPH_DELTA":
			_fix9_record_phase("item_message", duration_ms)
		_:
			_fix9_record_phase("control_message", duration_ms)


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	var started_us: int = Time.get_ticks_usec()
	super._reconcile_prediction_from_snapshot(snapshot)
	_fix9_record_phase(
		"prediction_reconcile",
		float(Time.get_ticks_usec() - started_us) / 1000.0
	)


func _flush_pending_input_batch(force_send: bool) -> bool:
	var started_us: int = Time.get_ticks_usec()
	var result: bool = super._flush_pending_input_batch(force_send)
	var duration_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	if _fix9_in_process:
		_fix9_frame_input_flush_ms += duration_ms
	_fix9_record_phase("input_flush", duration_ms)
	return result


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	var started_us: int = Time.get_ticks_usec()
	var result: Dictionary = super.advance_local_prediction(intent, frame_delta_seconds)
	_fix9_record_phase(
		"local_prediction",
		float(Time.get_ticks_usec() - started_us) / 1000.0
	)
	return result


func _update_runtime_telemetry() -> void:
	var started_us: int = Time.get_ticks_usec()
	_fix9_update_runtime_telemetry_fix6()
	var duration_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	if _fix9_in_process:
		_fix9_frame_telemetry_ms += duration_ms
	_fix9_record_phase("telemetry_update", duration_ms)


func _fix9_update_runtime_telemetry_fix6() -> void:
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


func _fix9_record_phase(phase_name: String, duration_ms: float) -> void:
	var phase: Dictionary = Dictionary(_fix9_phase_stats.get(phase_name, {}))
	var count: int = int(phase.get("count", 0)) + 1
	phase["count"] = count
	phase["last_ms"] = duration_ms
	phase["max_ms"] = maxf(float(phase.get("max_ms", 0.0)), duration_ms)
	phase["total_ms"] = float(phase.get("total_ms", 0.0)) + duration_ms
	if duration_ms >= FIX9_PHASE_BUDGET_MS:
		phase["over_budget"] = int(phase.get("over_budget", 0)) + 1
	else:
		phase["over_budget"] = int(phase.get("over_budget", 0))
	_fix9_phase_stats[phase_name] = phase


func _fix9_phase_report(phase_name: String) -> Dictionary:
	var phase: Dictionary = Dictionary(_fix9_phase_stats.get(phase_name, {}))
	var count: int = int(phase.get("count", 0))
	return {
		"count": count,
		"last_ms": float(phase.get("last_ms", 0.0)),
		"max_ms": float(phase.get("max_ms", 0.0)),
		"mean_ms": (
			float(phase.get("total_ms", 0.0)) / float(count)
			if count > 0
			else 0.0
		),
		"over_budget": int(phase.get("over_budget", 0)),
	}


func _fix9_client_frame_budget_report() -> Dictionary:
	return {
		"policy": FIX9_CLIENT_FRAME_BUDGET_POLICY,
		"phase_budget_ms": FIX9_PHASE_BUDGET_MS,
		"process_last_ms": _fix6_process_last_duration_ms,
		"process_max_ms": _fix6_process_max_duration_ms,
		"process_slow_frames": _fix6_slow_process_frames,
		"unattributed_last_ms": _fix9_unattributed_last_duration_ms,
		"unattributed_max_ms": _fix9_unattributed_max_duration_ms,
		"unattributed_over_budget_frames": _fix9_unattributed_slow_frames,
		"message_type_counts": _fix9_message_type_counts.duplicate(true),
		"phases": {
			"message_dispatch": _fix9_phase_report("message_dispatch"),
			"snapshot_message": _fix9_phase_report("snapshot_message"),
			"item_message": _fix9_phase_report("item_message"),
			"control_message": _fix9_phase_report("control_message"),
			"prediction_reconcile": _fix9_phase_report("prediction_reconcile"),
			"input_flush": _fix9_phase_report("input_flush"),
			"telemetry_update": _fix9_phase_report("telemetry_update"),
			"local_prediction": _fix9_phase_report("local_prediction"),
			"process_unattributed": _fix9_phase_report("process_unattributed"),
		},
	}


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
		"fix9_unattributed_last_ms": _fix9_unattributed_last_duration_ms,
		"fix9_unattributed_max_ms": _fix9_unattributed_max_duration_ms,
		"fix9_unattributed_over_budget_frames": _fix9_unattributed_slow_frames,
		"fix9_message_dispatch_max_ms": float(_fix9_phase_report("message_dispatch").get("max_ms", 0.0)),
		"fix9_prediction_reconcile_max_ms": float(_fix9_phase_report("prediction_reconcile").get("max_ms", 0.0)),
		"fix9_local_prediction_max_ms": float(_fix9_phase_report("local_prediction").get("max_ms", 0.0)),
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
	report["client_frame_budget"] = _fix9_client_frame_budget_report()
	return report
