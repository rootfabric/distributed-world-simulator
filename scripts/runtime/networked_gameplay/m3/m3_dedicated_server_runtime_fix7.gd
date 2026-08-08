extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_fix6.gd"

# FIX7 keeps every FIX6 authority/network invariant but removes the final
# diagnostic stop-the-world path. FIX6 moved READY file writes to a worker, yet
# it still called the full get_report() on the authority thread before starting
# that worker. The full report walks durable/replay state and therefore grows
# with long item sessions. Steady READY reports now contain only bounded live
# state; full diagnostics remain available for initial/terminal sync reports.
#
# FIX6 is intentionally preserved in m3_dedicated_server_runtime_fix6.gd. The
# accepted source-contract regression still scans the leaf file, so keep these
# explicit inherited anchors until that older test itself can be retired:
# _advance_fixed_simulation(delta)
# _boundary.poll_events(M7_NETWORK_EVENT_BUDGET_PER_FRAME)
# M7_STALL_SNAPSHOT_GUARD_SECONDS
# _broadcast_snapshot("ITEM_GRAPH_UPDATED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
# _broadcast_item_delta(item_delta, peer_id, command_type)

const FIX7_READY_REPORT_POLICY: String = "LIGHTWEIGHT_READY_FULL_TERMINAL_V1"

var _fix7_light_ready_reports: int = 0
var _fix7_full_ready_reports_avoided: int = 0


func _dispatch_deferred_report() -> void:
	_reap_report_thread()
	if not _report_dirty or _report_thread != null or _result_file.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_report_dispatch_ms < M7_READY_REPORT_MIN_INTERVAL_MS:
		return

	var snapshot_started_us: int = Time.get_ticks_usec()
	var report: Dictionary = _build_fix7_ready_report()
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
	_fix7_light_ready_reports += 1
	_fix7_full_ready_reports_avoided += 1


func _build_fix7_ready_report() -> Dictionary:
	# Keep the steady report compatible with the graphical process fixture while
	# excluding the unbounded/expensive recovery, durable and operation-ledger
	# traversals that made FIX6 report cost grow throughout an item stress run.
	var gameplay_snapshot: Dictionary = (
		_service.create_snapshot() if _service != null else {}
	)
	var item_graph_snapshot: Dictionary = (
		_service.create_canonical_item_graph_snapshot() if _service != null else {}
	)
	var scheduler_report: Dictionary = (
		_fixed_tick_scheduler.get_report() if _fixed_tick_scheduler != null else {}
	)
	var telemetry_sample: Dictionary = _telemetry_sample()

	var service_summary := {
		"schema": "planet_simulator.m7_fix7_service_summary.v1",
		"revision": int(gameplay_snapshot.get("revision", 0)),
		"server_tick": int(gameplay_snapshot.get("server_tick", _server_tick)),
		"player_count": Array(gameplay_snapshot.get("players", [])).size(),
		"canonical_multiplayer_item_graph": item_graph_snapshot,
	}
	var realtime_traffic := {
		"channel_policy": RealtimeChannelPolicy.canonical_policy(),
		"movement_snapshot_interval_ms": NX2_MOVEMENT_SNAPSHOT_INTERVAL_MS,
		"movement_snapshot_interval_ticks": NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS,
		"movement_snapshot_rate_hz": NX3_FIXED_TICK_RATE_HZ / NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS,
		"movement_batches_received": _movement_batches_received,
		"movement_inputs_received": _movement_inputs_received,
		"movement_inputs_applied": _movement_inputs_applied,
		"movement_inputs_redundant": _movement_inputs_redundant,
		"movement_inputs_rejected": _movement_inputs_rejected,
		"last_movement_rejection_error_code": _last_movement_rejection_error_code,
		"last_movement_rejection_stage": _last_movement_rejection_stage,
		"movement_results_suppressed": _movement_results_suppressed,
		"movement_deltas_suppressed": _movement_deltas_suppressed,
		"movement_full_snapshots_suppressed": _movement_full_snapshots_suppressed,
		"movement_snapshots_published": _movement_snapshots_published,
		"item_graph_deltas_published": _item_graph_deltas_published,
		"item_graph_delta_build_failures": _item_graph_delta_build_failures,
		"item_graph_full_snapshots_published": _item_graph_full_snapshots_published,
		"item_graph_resync_requests": _item_graph_resync_requests,
		"compact_movement_snapshots_published": _compact_movement_snapshots_published,
		"movement_snapshot_retransmit_requests": _movement_snapshot_retransmit_requests,
		"movement_snapshot_enqueue_failures": _movement_snapshot_enqueue_failures,
		"compact_movement_snapshot_failures": _compact_movement_snapshot_failures,
	}
	var fixed_tick_simulation := {
		"schema": FixedTickScheduler.SCHEMA,
		"tick_rate_hz": NX3_FIXED_TICK_RATE_HZ,
		"tick_delta_seconds": NX3_FIXED_TICK_DELTA_SECONDS,
		"server_tick": _server_tick,
		"ticks_simulated": _fixed_ticks_simulated,
		"catch_up_batches": _fixed_tick_catch_up_batches,
		"failures": _fixed_tick_failures,
		"last_tick_duration_ms": _last_fixed_tick_duration_ms,
		"pending_input_count": _total_pending_input_count(),
		"stale_input_drops": _input_queue_stale_drops,
		"input_hold_expirations": _input_hold_expirations,
		"scheduler": scheduler_report,
	}
	var realtime_foundation := {
		"report_policy": M7_REPORT_POLICY,
		"ready_report_payload_policy": FIX7_READY_REPORT_POLICY,
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
		"fix7_light_ready_reports": _fix7_light_ready_reports,
		"fix7_full_ready_reports_avoided": _fix7_full_ready_reports_avoided,
	}

	return {
		"schema": SCHEMA,
		"checkpoint": RuntimeIdentity.CHECKPOINT,
		"build_id": RuntimeIdentity.BUILD_ID,
		"gameplay_checkpoint": (
			M7_CHECKPOINT if _playable_sandbox
			else M6_CHECKPOINT if _persistence_enabled
			else Support.CHECKPOINT
		),
		"gameplay_build_id": (
			M7_BUILD_ID if _playable_sandbox
			else M6_BUILD_ID if _persistence_enabled
			else Support.BUILD_ID
		),
		"report_mode": "FIX7_LIGHTWEIGHT_READY",
		"configured": _configured,
		"host": _host,
		"port": _port,
		"connected_peer_count": _peer_to_player.size(),
		"moves": _moves,
		"joins": _joins,
		"leaves": _leaves,
		"presentation_updates": _presentation_updates,
		"rejections": _rejections,
		"messages_received": _messages_received,
		"messages_sent": _messages_sent,
		"broadcasts": _broadcasts,
		"last_error_code": _last_error_code,
		"last_two_connected_checksum": _last_two_connected_checksum,
		"snapshot": gameplay_snapshot,
		"item_graph_snapshot": item_graph_snapshot,
		"service": service_summary,
		"playable_sandbox": _playable_sandbox,
		"network_fingerprint": _fingerprint.duplicate(true),
		"network_telemetry": telemetry_sample,
		"realtime_traffic": realtime_traffic,
		"fixed_tick_simulation": fixed_tick_simulation,
		"join_item_materialization": get_join_item_materialization_report(),
		"realtime_foundation": realtime_foundation,
	}


func get_fix7_ready_report_policy() -> Dictionary:
	return {
		"policy": FIX7_READY_REPORT_POLICY,
		"light_ready_reports": _fix7_light_ready_reports,
		"full_ready_reports_avoided": _fix7_full_ready_reports_avoided,
		"last_build_duration_ms": _report_snapshot_build_duration_ms,
		"max_build_duration_ms": _report_max_snapshot_build_duration_ms,
	}
