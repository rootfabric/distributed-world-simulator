extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_base.gd"

# M7 composition corrections and realtime hardening. A successful player JOIN
# materializes the canonical sandbox inventory before JOIN_ACK captures the Item
# Graph. READY diagnostic reports are coalesced and written on a worker thread so
# filesystem latency can never block the 60 Hz authority loop. Canonical Item
# Graph payloads replicate through ITEM/RESYNC contracts; the lightweight gameplay
# snapshot is retained only to publish the gameplay revision advanced by the
# canonical item command itself.
#
# FIX4 also makes transient authority stalls lossless. The default NX3 scheduler
# deliberately drops excess wall-clock time after a catch-up cap, which is safe
# for generic bounded simulation but wrong for a predicted player: a 300-400 ms
# item/diagnostic stall makes the server simulate less travelled distance than the
# client and the next snapshot pulls the character backwards. M7 therefore keeps
# up to one second of transient fixed-tick debt, drains it in bounded batches and
# suppresses movement snapshots while that debt is being recovered.
#
# FIX6 removes two remaining diagnostic hot paths seen in long two-client item
# stress. Transport peer-stat snapshots are sampled at 4 Hz instead of rebuilding
# the full boundary snapshot every authority frame, and READY report materializing
# is limited to 1 Hz. Terminal reports remain synchronous. Together with the
# telemetry collector's bounded ring storage this keeps observability off the
# realtime allocation path without weakening gameplay authority semantics.

const M7_NETWORK_EVENT_BUDGET_PER_FRAME: int = 32
const M7_READY_REPORT_MIN_INTERVAL_MS: int = 1000
const M7_REPORT_POLICY: String = "ASYNC_COALESCED_READY_SYNC_TERMINAL_V1"
const M7_EVENT_LOOP_POLICY: String = "FIXED_TICK_BEFORE_NETWORK_DRAIN_V1"
const M7_ITEM_REPLICATION_POLICY: String = "ITEM_GRAPH_DELTA_WITH_GAMEPLAY_REVISION_SYNC_V2"
const M7_FIXED_TICK_MAX_CATCH_UP_TICKS: int = 16
const M7_FIXED_TICK_MAX_FRAME_DELTA_SECONDS: float = 1.0
const M7_FIXED_TICK_BACKLOG_POLICY: String = "RETAIN_TRANSIENT_STALL_TIME_V1"
const M7_STALL_SNAPSHOT_GUARD_SECONDS: float = 0.05
const M7_INPUT_SNAPSHOT_BACKLOG_GUARD: int = 8
const M7_MOVEMENT_SNAPSHOT_RECOVERY_POLICY: String = "SUPPRESS_WHILE_STALL_OR_AUTHORITY_BACKLOG_V1"
const M7_PEER_TELEMETRY_INTERVAL_MS: int = 250
const M7_TELEMETRY_HOT_PATH_POLICY: String = "RING_BUFFER_OBSERVE_THROTTLED_PEER_STATS_V1"
const M7_SLOW_PROCESS_FRAME_MS: float = 50.0

var _join_item_materializations: int = 0
var _join_item_materialization_failures: int = 0

var _report_thread: Thread
var _initial_report_written: bool = false
var _report_dirty: bool = false
var _report_requested_state: String = "READY"
var _report_requested_passed: bool = false
var _last_report_dispatch_ms: int = 0
var _report_requests: int = 0
var _report_requests_coalesced: int = 0
var _report_writes_started: int = 0
var _report_writes_completed: int = 0
var _report_write_failures: int = 0
var _report_snapshot_build_duration_ms: float = 0.0
var _report_max_snapshot_build_duration_ms: float = 0.0
var _report_last_write_duration_ms: float = 0.0
var _report_max_write_duration_ms: float = 0.0
var _item_gameplay_revision_snapshots_published: int = 0
var _max_pending_input_count_observed: int = 0
var _movement_snapshot_recovery_suppressions: int = 0
var _transient_stall_frames: int = 0
var _max_scheduler_backlog_ticks_observed: int = 0
var _server_process_last_duration_ms: float = 0.0
var _server_process_max_duration_ms: float = 0.0
var _slow_process_frames: int = 0
var _last_peer_telemetry_sample_ms: int = 0
var _peer_telemetry_samples: int = 0
var _peer_telemetry_skips: int = 0
var _peer_telemetry_last_duration_ms: float = 0.0
var _peer_telemetry_max_duration_ms: float = 0.0


func setup(config: Dictionary) -> Dictionary:
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)):
		return result
	if _fixed_tick_scheduler == null:
		return _failure("M7_FIXED_TICK_SCHEDULER_MISSING")
	var scheduler_setup: Dictionary = _fixed_tick_scheduler.configure(
		NX3_FIXED_TICK_RATE_HZ,
		M7_FIXED_TICK_MAX_CATCH_UP_TICKS,
		_server_tick,
		M7_FIXED_TICK_MAX_FRAME_DELTA_SECONDS,
		true
	)
	if not bool(scheduler_setup.get("success", false)):
		_last_error_code = String(scheduler_setup.get("error_code", "M7_FIXED_TICK_RECOVERY_SETUP_FAILED"))
		return scheduler_setup
	# Base setup already emitted the deterministic initial READY report. Queue one
	# refreshed report so diagnostics expose the runtime-specific scheduler policy.
	_write_report("READY", false)
	return result


func _process(delta: float) -> void:
	if not _configured or _boundary == null or _fatal_persistence_failure:
		return
	_reap_report_thread()
	var process_started_us: int = Time.get_ticks_usec()
	_telemetry.increment("server_process_iterations")

	# Authority time always gets the first budget of the frame. A backlog of
	# inbound packets may wait one frame; fixed simulation must never wait behind
	# diagnostic I/O or a large network drain.
	_advance_fixed_simulation(delta)
	var scheduler_backlog_ticks: int = _scheduler_pending_catch_up_ticks()
	_max_scheduler_backlog_ticks_observed = maxi(
		_max_scheduler_backlog_ticks_observed, scheduler_backlog_ticks
	)
	var input_backlog_before_drain: int = _total_pending_input_count()
	var transient_stall: bool = delta > M7_STALL_SNAPSHOT_GUARD_SECONDS
	if transient_stall:
		_transient_stall_frames += 1
	if (
		transient_stall
		or scheduler_backlog_ticks > 0
		or input_backlog_before_drain > M7_INPUT_SNAPSHOT_BACKLOG_GUARD
	):
		# Publishing a snapshot in the middle of catch-up would make a locally
		# predicted player reconcile against a deliberately incomplete authority
		# state and visibly snap backwards. Keep the dirty flag and publish once the
		# server has caught up.
		_movement_snapshot_recovery_suppressions += 1
	else:
		_maybe_publish_movement_snapshot()

	# 32 events/frame is still >15x the sustained two-client LOCAL traffic seen in
	# acceptance, while halving the amount of work a post-stall frame can inherit.
	var polled: Dictionary = _boundary.poll_events(M7_NETWORK_EVENT_BUDGET_PER_FRAME)
	if not bool(polled.get("success", false)):
		_last_error_code = String(polled.get("error_code", "M3_SERVER_POLL_FAILED"))
		_write_report("FAILED", false)
		return
	for event_value in polled.get("details", {}).get("events", []):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		var session_id := String(event.get("session_id", ""))
		if event_type == "MESSAGE_RECEIVED":
			_messages_received += 1
			_handle_message(peer_id, session_id, event.get("frame", {}).get("payload", {}))
		elif event_type == "PEER_DISCONNECTED":
			_handle_disconnect(peer_id, session_id)

	_maybe_persist_movement_checkpoint()
	_update_runtime_telemetry()
	_max_pending_input_count_observed = maxi(
		_max_pending_input_count_observed, _total_pending_input_count()
	)
	_dispatch_deferred_report()

	_server_process_last_duration_ms = float(Time.get_ticks_usec() - process_started_us) / 1000.0
	_server_process_max_duration_ms = maxf(
		_server_process_max_duration_ms, _server_process_last_duration_ms
	)
	if _server_process_last_duration_ms >= M7_SLOW_PROCESS_FRAME_MS:
		_slow_process_frames += 1
	_telemetry.observe("server_process_duration_ms", _server_process_last_duration_ms)
	if _debug_logging and Time.get_ticks_msec() - _last_debug_report_ms >= 2000:
		_last_debug_report_ms = Time.get_ticks_msec()
		_debug_event("SERVER_HEALTH", {
			"connected_peers": _peer_to_player.size(),
			"moves": _moves,
			"rejections": _rejections,
			"messages_received": _messages_received,
			"messages_sent": _messages_sent,
			"checkpoint_generation": _checkpoint_generation,
			"movement_dirty": _movement_checkpoint_dirty,
			"movement_commands_since_checkpoint": _movement_commands_since_checkpoint,
			"pending_inputs": _total_pending_input_count(),
			"max_pending_inputs": _max_pending_input_count_observed,
			"scheduler_backlog_ticks": scheduler_backlog_ticks,
			"max_scheduler_backlog_ticks": _max_scheduler_backlog_ticks_observed,
			"movement_snapshot_recovery_suppressions": _movement_snapshot_recovery_suppressions,
			"transient_stall_frames": _transient_stall_frames,
			"server_process_duration_ms": _server_process_last_duration_ms,
			"server_process_max_duration_ms": _server_process_max_duration_ms,
			"slow_process_frames": _slow_process_frames,
			"report_thread_active": _report_thread != null,
			"report_requests_coalesced": _report_requests_coalesced,
			"report_snapshot_build_duration_ms": _report_snapshot_build_duration_ms,
			"report_max_snapshot_build_duration_ms": _report_max_snapshot_build_duration_ms,
			"report_last_write_duration_ms": _report_last_write_duration_ms,
			"peer_telemetry_samples": _peer_telemetry_samples,
			"peer_telemetry_skips": _peer_telemetry_skips,
			"peer_telemetry_last_duration_ms": _peer_telemetry_last_duration_ms,
			"peer_telemetry_max_duration_ms": _peer_telemetry_max_duration_ms,
			"last_error_code": _last_error_code,
		})


func _scheduler_pending_catch_up_ticks() -> int:
	if _fixed_tick_scheduler == null:
		return 0
	if _fixed_tick_scheduler.has_method("get_pending_catch_up_ticks"):
		return int(_fixed_tick_scheduler.call("get_pending_catch_up_ticks"))
	var scheduler_report: Dictionary = _fixed_tick_scheduler.get_report()
	return int(scheduler_report.get("pending_catch_up_ticks", 0))


func _update_runtime_telemetry() -> void:
	if _telemetry == null:
		return
	# Cheap gauges stay frame-current. The expensive transport snapshot and peer
	# statistics are observability, not simulation input, so sample them at 4 Hz.
	_telemetry.set_gauge("connected_gameplay_peers", float(_peer_to_player.size()))
	_telemetry.set_gauge("compatible_transport_peers", float(_peer_compatibility.size()))
	_telemetry.set_gauge("handshake_replay_count", float(_handshake_replays))
	_telemetry.set_gauge("checkpoint_generation", float(_checkpoint_generation))
	_telemetry.set_gauge("fixed_server_tick", float(_server_tick))
	_telemetry.set_gauge("pending_input_count", float(_total_pending_input_count()))
	_telemetry.set_gauge("fixed_tick_failures", float(_fixed_tick_failures))

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_peer_telemetry_sample_ms < M7_PEER_TELEMETRY_INTERVAL_MS:
		_peer_telemetry_skips += 1
		return
	_last_peer_telemetry_sample_ms = now_ms
	var sample_started_us: int = Time.get_ticks_usec()
	var boundary_snapshot: Dictionary = _boundary.get_snapshot() if _boundary != null else {}
	var port_runtime: Dictionary = boundary_snapshot.get("port_runtime", {})
	var peer_statistics: Dictionary = port_runtime.get("peer_statistics", {})
	for stats_value in peer_statistics.values():
		if not stats_value is Dictionary:
			continue
		var stats: Dictionary = stats_value
		_telemetry.observe("peer_rtt_ms", float(stats.get("rtt_ms", 0)))
		_telemetry.observe("peer_jitter_ms", float(stats.get("rtt_variance_ms", 0)))
		_telemetry.observe("peer_packet_loss_percent", float(stats.get("packet_loss_percent", 0.0)))
	_peer_telemetry_last_duration_ms = float(Time.get_ticks_usec() - sample_started_us) / 1000.0
	_peer_telemetry_max_duration_ms = maxf(
		_peer_telemetry_max_duration_ms, _peer_telemetry_last_duration_ms
	)
	_peer_telemetry_samples += 1


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


func _handle_item_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, String(payload.get("operation_id", "")), "ITEM_COMMAND", _failure("STALE_TRANSPORT_SESSION"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	var command_type := String(payload.get("command_type", "")).strip_edges()
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id, operation_id, "ITEM_COMMAND",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		return
	if command_type.is_empty():
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_TYPE_REQUIRED")
		return
	var command_payload_value = payload.get("payload", {})
	if not command_payload_value is Dictionary:
		_reject_uncommitted_command(peer_id, operation_id, "ITEM_COMMAND", "ITEM_COMMAND_PAYLOAD_REQUIRED")
		return

	var before_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var result: Dictionary = _service.handle_canonical_item_command(
		logical_id, session_id, int(payload.get("ownership_epoch", 0)),
		operation_id, command_type, Dictionary(command_payload_value)
	)
	if not _persist_command_result(operation_id, command_type, logical_id, result):
		_send_result(peer_id, operation_id, command_type, _failure("M6_DURABLE_COMMIT_FAILED"))
		return
	var item_delta: Dictionary = {}
	var item_delta_fallback_required: bool = false
	if bool(result.get("success", false)) and not _is_replay_result(result):
		var after_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
		var delta_result: Dictionary = CanonicalItemGraphDelta.create(before_item_snapshot, after_item_snapshot)
		if not bool(delta_result.get("success", false)):
			item_delta_fallback_required = true
			_item_graph_delta_build_failures += 1
			_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
		else:
			item_delta = Dictionary(delta_result.get("details", {}).get("delta", {})).duplicate(true)
	var result_sent := _send_result(peer_id, operation_id, command_type, result, item_delta)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			if item_delta_fallback_required:
				_broadcast_item_snapshot("ITEM_GRAPH_DELTA_BUILD_FALLBACK")
			else:
				_broadcast_item_delta(item_delta, peer_id, command_type)
			# Canonical item execution currently advances NetworkedGameplayService's
			# gameplay revision even though Item Graph state has its own revision. The
			# ITEM delta carries the item payload; this small reliable gameplay snapshot
			# carries the new gameplay revision so every player replica can converge.
			_broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
			_item_gameplay_revision_snapshots_published += 1
			_capture_two_connected_checksum()
	else:
		_rejections += 1
	if result_sent:
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


func _write_report(state: String, passed: bool) -> void:
	if _result_file.is_empty():
		return
	_report_requests += 1
	if not _initial_report_written:
		_write_report_sync(state, passed)
		_initial_report_written = true
		return
	if state != "READY":
		_drain_report_thread()
		_write_report_sync(state, passed)
		return
	if _report_dirty or _report_thread != null:
		_report_requests_coalesced += 1
	_report_dirty = true
	_report_requested_state = state
	_report_requested_passed = passed


func _dispatch_deferred_report() -> void:
	_reap_report_thread()
	if not _report_dirty or _report_thread != null or _result_file.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_report_dispatch_ms < M7_READY_REPORT_MIN_INTERVAL_MS:
		return
	var snapshot_started_us: int = Time.get_ticks_usec()
	var report: Dictionary = get_report()
	report["state"] = _report_requested_state
	report["passed"] = _report_requested_passed
	report["process_id"] = OS.get_process_id()
	_record_report_snapshot_build(report, snapshot_started_us)
	_report_thread = Thread.new()
	var start_error: Error = _report_thread.start(
		Callable(self, "_report_worker_write").bind(_result_file, report)
	)
	if start_error != OK:
		_report_thread = null
		_report_write_failures += 1
		return
	_report_dirty = false
	_report_writes_started += 1
	_last_report_dispatch_ms = now_ms


func _record_report_snapshot_build(report: Dictionary, snapshot_started_us: int) -> void:
	_report_snapshot_build_duration_ms = float(Time.get_ticks_usec() - snapshot_started_us) / 1000.0
	_report_max_snapshot_build_duration_ms = maxf(
		_report_max_snapshot_build_duration_ms, _report_snapshot_build_duration_ms
	)
	# get_report() necessarily contains the previous build duration because the
	# current build is only known after it returns. Stamp the just-measured values
	# into the outgoing snapshot so the JSON and SERVER_HEALTH agree.
	var foundation: Dictionary = Dictionary(report.get("realtime_foundation", {}))
	foundation["report_snapshot_build_duration_ms"] = _report_snapshot_build_duration_ms
	foundation["report_max_snapshot_build_duration_ms"] = _report_max_snapshot_build_duration_ms
	report["realtime_foundation"] = foundation


func _report_worker_write(path: String, report: Dictionary) -> Dictionary:
	var started_us: int = Time.get_ticks_usec()
	var success: bool = Support.write(path, report)
	return {
		"success": success,
		"duration_ms": float(Time.get_ticks_usec() - started_us) / 1000.0,
	}


func _reap_report_thread() -> void:
	if _report_thread == null or _report_thread.is_alive():
		return
	var result_value = _report_thread.wait_to_finish()
	_report_thread = null
	_report_writes_completed += 1
	if result_value is Dictionary:
		var result: Dictionary = result_value
		_report_last_write_duration_ms = float(result.get("duration_ms", 0.0))
		_report_max_write_duration_ms = maxf(
			_report_max_write_duration_ms, _report_last_write_duration_ms
		)
		if not bool(result.get("success", false)):
			_report_write_failures += 1
	else:
		_report_write_failures += 1


func _drain_report_thread() -> void:
	if _report_thread == null:
		return
	var result_value = _report_thread.wait_to_finish()
	_report_thread = null
	_report_writes_completed += 1
	if result_value is Dictionary:
		var result: Dictionary = result_value
		_report_last_write_duration_ms = float(result.get("duration_ms", 0.0))
		_report_max_write_duration_ms = maxf(
			_report_max_write_duration_ms, _report_last_write_duration_ms
		)
		if not bool(result.get("success", false)):
			_report_write_failures += 1
	else:
		_report_write_failures += 1


func _write_report_sync(state: String, passed: bool) -> void:
	var snapshot_started_us: int = Time.get_ticks_usec()
	var report: Dictionary = get_report()
	report["state"] = state
	report["passed"] = passed
	report["process_id"] = OS.get_process_id()
	_record_report_snapshot_build(report, snapshot_started_us)
	var write_started_us: int = Time.get_ticks_usec()
	var success: bool = Support.write(_result_file, report)
	_report_last_write_duration_ms = float(Time.get_ticks_usec() - write_started_us) / 1000.0
	_report_max_write_duration_ms = maxf(
		_report_max_write_duration_ms, _report_last_write_duration_ms
	)
	_report_writes_started += 1
	_report_writes_completed += 1
	_last_report_dispatch_ms = Time.get_ticks_msec()
	if not success:
		_report_write_failures += 1


func get_join_item_materialization_report() -> Dictionary:
	return {
		"join_item_materializations": _join_item_materializations,
		"join_item_materialization_failures": _join_item_materialization_failures,
	}


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var scheduler_report: Dictionary = {}
	if _fixed_tick_scheduler != null:
		scheduler_report = _fixed_tick_scheduler.get_report()
	report["realtime_foundation"] = {
		"report_policy": M7_REPORT_POLICY,
		"event_loop_policy": M7_EVENT_LOOP_POLICY,
		"item_replication_policy": M7_ITEM_REPLICATION_POLICY,
		"network_event_budget_per_frame": M7_NETWORK_EVENT_BUDGET_PER_FRAME,
		"ready_report_min_interval_ms": M7_READY_REPORT_MIN_INTERVAL_MS,
		"telemetry_hot_path_policy": M7_TELEMETRY_HOT_PATH_POLICY,
		"peer_telemetry_interval_ms": M7_PEER_TELEMETRY_INTERVAL_MS,
		"peer_telemetry_samples": _peer_telemetry_samples,
		"peer_telemetry_skips": _peer_telemetry_skips,
		"peer_telemetry_last_duration_ms": _peer_telemetry_last_duration_ms,
		"peer_telemetry_max_duration_ms": _peer_telemetry_max_duration_ms,
		"fixed_tick_backlog_policy": M7_FIXED_TICK_BACKLOG_POLICY,
		"fixed_tick_max_catch_up_ticks": M7_FIXED_TICK_MAX_CATCH_UP_TICKS,
		"fixed_tick_max_frame_delta_seconds": M7_FIXED_TICK_MAX_FRAME_DELTA_SECONDS,
		"scheduler_backlog_policy": String(scheduler_report.get("backlog_policy", "")),
		"scheduler_pending_catch_up_ticks": int(scheduler_report.get("pending_catch_up_ticks", 0)),
		"scheduler_retained_backlog_peak_ticks": int(scheduler_report.get("retained_backlog_peak_ticks", 0)),
		"scheduler_dropped_time_seconds": float(scheduler_report.get("dropped_time_seconds", 0.0)),
		"movement_snapshot_recovery_policy": M7_MOVEMENT_SNAPSHOT_RECOVERY_POLICY,
		"movement_snapshot_recovery_suppressions": _movement_snapshot_recovery_suppressions,
		"transient_stall_frames": _transient_stall_frames,
		"max_scheduler_backlog_ticks_observed": _max_scheduler_backlog_ticks_observed,
		"server_process_last_duration_ms": _server_process_last_duration_ms,
		"server_process_max_duration_ms": _server_process_max_duration_ms,
		"slow_process_frame_threshold_ms": M7_SLOW_PROCESS_FRAME_MS,
		"slow_process_frames": _slow_process_frames,
		"report_requests": _report_requests,
		"report_requests_coalesced": _report_requests_coalesced,
		"report_dirty": _report_dirty,
		"report_thread_active": _report_thread != null,
		"report_writes_started": _report_writes_started,
		"report_writes_completed": _report_writes_completed,
		"report_write_failures": _report_write_failures,
		"report_snapshot_build_duration_ms": _report_snapshot_build_duration_ms,
		"report_max_snapshot_build_duration_ms": _report_max_snapshot_build_duration_ms,
		"report_last_write_duration_ms": _report_last_write_duration_ms,
		"report_max_write_duration_ms": _report_max_write_duration_ms,
		"item_gameplay_revision_snapshots_published": _item_gameplay_revision_snapshots_published,
		"max_pending_input_count_observed": _max_pending_input_count_observed,
	}
	report["join_item_materialization"] = get_join_item_materialization_report()
	return report
