extends "res://scripts/world/testing/playground_view_relative_runtime_fix7.gd"

# FIX8 remains the accepted playground script identity so all existing scene and
# inventory regression contracts keep composing the same runtime path. FIX9 is
# layered here as presentation/performance instrumentation only. FIX10 fix3 adds
# a presentation-only remote snapshot lane while preserving the same scene script
# identity, local prediction, authority and Item Graph composition.

const InventoryRev6EnhancerFix9Script = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix9.gd"
)
const RemotePlayerPresenterFix10Fix3Script = preload(
	"res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd"
)

const FIX9_PRESENTATION_BUDGET_POLICY: String = "CLIENT_WORLD_PHASE_ACCOUNTING_V1"
const FIX9_PRESENTATION_PHASE_BUDGET_MS: float = 16.667
const FIX10_FIX3_REMOTE_PRESENTATION_POLICY: String = "EXACT_SNAPSHOT_CONTEXT_PRESENTATION_CONTINUITY_V1"
const FIX10_FIX3_REMOTE_HEALTH_INTERVAL_MS: int = 2000

var _fix9_phase_stats: Dictionary = {}
var _fix9_frame_prediction_sync_ms: float = 0.0
var _fix9_frame_presentation_flush_ms: float = 0.0
var _fix9_physics_unattributed_last_ms: float = 0.0
var _fix9_physics_unattributed_max_ms: float = 0.0
var _fix9_presentation_apply_count: int = 0
var _fix9_presentation_idle_flushes: int = 0

var _fix10_fix3_remote_signal_connected: bool = false
var _fix10_fix3_remote_wire_snapshots: int = 0
var _fix10_fix3_remote_canonical_snapshots: int = 0
var _fix10_fix3_remote_apply_attempts: int = 0
var _fix10_fix3_remote_apply_failures: int = 0
var _fix10_fix3_remote_stale_source_skips: int = 0
var _fix10_fix3_remote_duplicate_source_skips: int = 0
var _fix10_fix3_remote_same_clock_conflicts: int = 0
var _fix10_fix3_remote_canonical_conflict_hints: int = 0
var _fix10_fix3_remote_last_clock: Dictionary = {}
var _fix10_fix3_last_health_ms: int = 0


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	var result: Dictionary = super.attach_m3_multiplayer_client(runtime)
	if not bool(result.get("success", false)):
		return result
	if runtime != null and runtime.has_signal("remote_presentation_snapshot"):
		var callback := Callable(self, "_on_fix10_fix3_remote_presentation_snapshot")
		if not runtime.is_connected("remote_presentation_snapshot", callback):
			runtime.connect("remote_presentation_snapshot", callback)
		_fix10_fix3_remote_signal_connected = true
	return result


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result

	# Fix9's enhancer extends the accepted fix8 activation/presentation chain and
	# changes only redundant Control property writes. Remove the parent's overlay
	# controls before replacing its enhancer exactly as the accepted fix6-8
	# composition already does.
	_cleanup_inventory_enhancer_overlay(_inventory_rev6_enhancer)
	if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer):
		_inventory_rev6_enhancer.free()

	_inventory_rev6_enhancer = InventoryRev6EnhancerFix9Script.new()
	_inventory_rev6_enhancer.name = "InventoryNetworkRev6EnhancerFix9"
	add_child(_inventory_rev6_enhancer)
	var enhancer_setup: Dictionary = _inventory_rev6_enhancer.setup(
		item_gameplay,
		_m7_item_bridge
	)
	if not bool(enhancer_setup.get("success", false)):
		return enhancer_setup
	return setup_result


func _process(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()
	super._process(delta)
	_fix9_record_phase("world_render_process", float(Time.get_ticks_usec() - started_us) / 1000.0)
	_fix10_fix3_emit_remote_health_if_due()


func _physics_process(delta: float) -> void:
	_fix9_frame_prediction_sync_ms = 0.0
	_fix9_frame_presentation_flush_ms = 0.0
	var started_us: int = Time.get_ticks_usec()
	super._physics_process(delta)
	var duration_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	_fix9_record_phase("world_physics_process", duration_ms)
	_fix9_physics_unattributed_last_ms = maxf(
		duration_ms - _fix9_frame_prediction_sync_ms - _fix9_frame_presentation_flush_ms,
		0.0
	)
	_fix9_physics_unattributed_max_ms = maxf(
		_fix9_physics_unattributed_max_ms,
		_fix9_physics_unattributed_last_ms
	)
	_fix9_record_phase("world_physics_unattributed", _fix9_physics_unattributed_last_ms)


func _sync_m7_predicted_player_state(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()
	super._sync_m7_predicted_player_state(delta)
	var duration_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	_fix9_frame_prediction_sync_ms += duration_ms
	_fix9_record_phase("prediction_sync", duration_ms)


func _on_m3_prediction_updated(
	predicted_state: Dictionary,
	presentation_state: Dictionary,
	prediction_report: Dictionary
) -> void:
	var started_us: int = Time.get_ticks_usec()
	super._on_m3_prediction_updated(predicted_state, presentation_state, prediction_report)
	_fix9_record_phase("prediction_callback", float(Time.get_ticks_usec() - started_us) / 1000.0)


func _flush_pending_prediction_presentation() -> void:
	var dirty_before: bool = _pending_prediction_presentation_dirty
	var started_us: int = Time.get_ticks_usec()
	super._flush_pending_prediction_presentation()
	var duration_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	_fix9_frame_presentation_flush_ms += duration_ms
	_fix9_record_phase("presentation_flush", duration_ms)
	if dirty_before:
		_fix9_presentation_apply_count += 1
	else:
		_fix9_presentation_idle_flushes += 1


func _on_m3_replica_updated(snapshot: Dictionary) -> void:
	var started_us: int = Time.get_ticks_usec()
	_fix10_fix3_remote_canonical_snapshots += 1
	_fix10_fix3_apply_authoritative_snapshot(snapshot, "CANONICAL_REPLICA", true)
	_fix9_record_phase("replica_presentation", float(Time.get_ticks_usec() - started_us) / 1000.0)


func _on_fix10_fix3_remote_presentation_snapshot(
	snapshot: Dictionary,
	source: String,
	canonical_conflict_hint: bool
) -> void:
	_fix10_fix3_remote_wire_snapshots += 1
	if canonical_conflict_hint:
		_fix10_fix3_remote_canonical_conflict_hints += 1
	_fix10_fix3_apply_authoritative_snapshot(
		snapshot,
		"WIRE_%s" % source,
		false
	)


func _fix10_fix3_apply_authoritative_snapshot(
	snapshot: Dictionary,
	source: String,
	include_local_and_lifecycle: bool
) -> void:
	if not _m3_attached or m3_multiplayer_client_runtime == null or player == null:
		return
	if snapshot.is_empty():
		return
	var snapshot_context: Dictionary = {
		"server_tick": int(snapshot.get("server_tick", -1)),
		"snapshot_revision": int(snapshot.get("revision", -1)),
		"authority_epoch": int(snapshot.get("authority_epoch", 0)),
	}
	if (
		int(snapshot_context.get("server_tick", -1)) < 0
		or int(snapshot_context.get("snapshot_revision", -1)) < 0
		or int(snapshot_context.get("authority_epoch", 0)) < 1
	):
		return

	var local_id: String = m3_multiplayer_client_runtime.get_local_player_id()
	var seen: Dictionary = {}
	for player_value in snapshot.get("players", []):
		if not player_value is Dictionary:
			continue
		var record: Dictionary = player_value
		var logical_id := String(record.get("logical_player_id", ""))
		if logical_id == local_id:
			if include_local_and_lifecycle:
				_fix10_fix3_apply_local_authoritative_record(record)
			continue
		if not bool(record.get("connected", false)):
			continue
		seen[logical_id] = true
		_fix10_fix3_apply_remote_record(
			logical_id,
			record,
			snapshot_context,
			source
		)

	# A wire-presentation snapshot is intentionally presentation-only. Canonical
	# replica state remains the sole owner of despawn/lifecycle decisions.
	if not include_local_and_lifecycle:
		return
	for logical_id_value in _m3_remote_presenters.keys().duplicate():
		var logical_id := String(logical_id_value)
		if seen.has(logical_id):
			continue
		var presenter = _m3_remote_presenters.get(logical_id)
		if presenter != null and is_instance_valid(presenter):
			presenter.queue_free()
		_m3_remote_presenters.erase(logical_id)
		_fix10_fix3_remote_last_clock.erase(logical_id)
		_m3_remote_despawn_count += 1


func _fix10_fix3_apply_local_authoritative_record(record: Dictionary) -> void:
	if not bool(record.get("connected", false)):
		return
	var position: Dictionary = record.get("position", {})
	var authoritative_position := Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	)
	var velocity: Dictionary = record.get("velocity", {})
	var authoritative_velocity := Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	if _network_playground_enabled:
		var authoritative_sequence := int(record.get("last_input_sequence", -1))
		if authoritative_sequence >= _m7_authoritative_target_sequence:
			_m7_authoritative_target_position = authoritative_position
			_m7_authoritative_target_velocity = authoritative_velocity
			_m7_authoritative_target_sequence = authoritative_sequence
			_m7_authoritative_target_valid = true
		if not _m7_initial_player_replica_applied:
			player.set_world_position(authoritative_position)
			player.velocity = authoritative_velocity
			_m7_initial_player_replica_applied = true
	else:
		player.set_world_position(authoritative_position)
		player.velocity = authoritative_velocity
		_m7_initial_player_replica_applied = true
	_m3_local_sync_count += 1


func _fix10_fix3_apply_remote_record(
	logical_id: String,
	record: Dictionary,
	snapshot_context: Dictionary,
	source: String
) -> void:
	var server_tick: int = int(snapshot_context.get("server_tick", -1))
	var snapshot_revision: int = int(snapshot_context.get("snapshot_revision", -1))
	var state_revision: int = int(record.get("state_revision", -1))
	var previous: Dictionary = Dictionary(
		_fix10_fix3_remote_last_clock.get(logical_id, {})
	)
	if not previous.is_empty():
		var previous_tick: int = int(previous.get("server_tick", -1))
		var previous_revision: int = int(previous.get("snapshot_revision", -1))
		var previous_state_revision: int = int(previous.get("state_revision", -1))
		if server_tick < previous_tick or snapshot_revision < previous_revision:
			_fix10_fix3_remote_stale_source_skips += 1
			return
		if (
			server_tick == previous_tick
			and snapshot_revision == previous_revision
			and state_revision == previous_state_revision
		):
			_fix10_fix3_remote_duplicate_source_skips += 1
			return
		if (
			server_tick == previous_tick
			and snapshot_revision == previous_revision
			and state_revision != previous_state_revision
		):
			# Do not weaken RemoteSnapshotInterpolator's same-clock conflict guard.
			# A newer server tick can preserve visual continuity, but two semantic
			# states claiming the exact same tick/revision remain an invariant error.
			_fix10_fix3_remote_same_clock_conflicts += 1
			return

	var presenter = _m3_remote_presenters.get(logical_id)
	_fix10_fix3_remote_apply_attempts += 1
	var apply_result: Dictionary
	if presenter == null or not is_instance_valid(presenter):
		presenter = RemotePlayerPresenterFix10Fix3Script.new()
		add_child(presenter)
		apply_result = presenter.setup(record, snapshot_context)
		if bool(apply_result.get("success", false)):
			_m3_remote_presenters[logical_id] = presenter
			_m3_remote_spawn_count += 1
		else:
			presenter.queue_free()
	else:
		apply_result = presenter.apply_replica(record, false, snapshot_context)
	if not bool(apply_result.get("success", false)):
		_fix10_fix3_remote_apply_failures += 1
		return

	_fix10_fix3_remote_last_clock[logical_id] = {
		"server_tick": server_tick,
		"snapshot_revision": snapshot_revision,
		"state_revision": state_revision,
		"source": source,
	}
	_m3_remote_update_count += 1


func _fix10_fix3_emit_remote_health_if_due() -> void:
	if runtime_role != "game-client" or not _m3_attached:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _fix10_fix3_last_health_ms < FIX10_FIX3_REMOTE_HEALTH_INTERVAL_MS:
		return
	_fix10_fix3_last_health_ms = now_ms
	var report: Dictionary = get_fix10_fix3_remote_continuity_report()
	if int(report.get("remote_count", 0)) <= 0:
		return
	print("[fix10_fix3_remote] %s" % JSON.stringify(report))


func get_fix10_fix3_remote_continuity_report() -> Dictionary:
	var players: Dictionary = {}
	var total_buffer_underruns: int = 0
	var total_moving_holds: int = 0
	var max_moving_hold_streak: int = 0
	var max_snapshot_gap_ticks: int = 0
	for logical_id_value in _m3_remote_presenters.keys():
		var logical_id := String(logical_id_value)
		var presenter = _m3_remote_presenters.get(logical_id)
		if presenter == null or not is_instance_valid(presenter):
			continue
		var presenter_report: Dictionary = presenter.get_report()
		var interpolation: Dictionary = Dictionary(
			presenter_report.get("interpolation", {})
		)
		var underruns: int = int(
			presenter_report.get("fix8_moving_buffer_underruns", 0)
		)
		var moving_holds: int = int(
			presenter_report.get("fix8_moving_hold_samples", 0)
		)
		var hold_streak: int = int(
			presenter_report.get("fix8_max_moving_hold_streak", 0)
		)
		var snapshot_gap: int = int(
			presenter_report.get("fix8_max_snapshot_gap_ticks", 0)
		)
		total_buffer_underruns += underruns
		total_moving_holds += moving_holds
		max_moving_hold_streak = maxi(max_moving_hold_streak, hold_streak)
		max_snapshot_gap_ticks = maxi(max_snapshot_gap_ticks, snapshot_gap)
		players[logical_id] = {
			"updates": int(presenter_report.get("updates", 0)),
			"mode": String(presenter_report.get("interpolation_mode", "")),
			"render_tick": float(presenter_report.get("render_tick", 0.0)),
			"latest_server_tick": int(interpolation.get("latest_server_tick", -1)),
			"buffer_size": int(interpolation.get("buffer_size", 0)),
			"moving_buffer_underruns": underruns,
			"moving_hold_samples": moving_holds,
			"max_moving_hold_streak": hold_streak,
			"max_snapshot_gap_ticks": snapshot_gap,
			"last_source_clock": Dictionary(
				_fix10_fix3_remote_last_clock.get(logical_id, {})
			).duplicate(true),
		}
	return {
		"policy": FIX10_FIX3_REMOTE_PRESENTATION_POLICY,
		"signal_connected": _fix10_fix3_remote_signal_connected,
		"remote_count": players.size(),
		"wire_snapshots": _fix10_fix3_remote_wire_snapshots,
		"canonical_snapshots": _fix10_fix3_remote_canonical_snapshots,
		"apply_attempts": _fix10_fix3_remote_apply_attempts,
		"apply_failures": _fix10_fix3_remote_apply_failures,
		"stale_source_skips": _fix10_fix3_remote_stale_source_skips,
		"duplicate_source_skips": _fix10_fix3_remote_duplicate_source_skips,
		"same_clock_conflicts": _fix10_fix3_remote_same_clock_conflicts,
		"canonical_conflict_hints": _fix10_fix3_remote_canonical_conflict_hints,
		"moving_buffer_underruns": total_buffer_underruns,
		"moving_hold_samples": total_moving_holds,
		"max_moving_hold_streak": max_moving_hold_streak,
		"max_snapshot_gap_ticks": max_snapshot_gap_ticks,
		"players": players,
	}


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	var started_us: int = Time.get_ticks_usec()
	super._on_m4_item_graph_updated(snapshot)
	_fix9_record_phase("item_projection", float(Time.get_ticks_usec() - started_us) / 1000.0)


func _fix9_record_phase(phase_name: String, duration_ms: float) -> void:
	var phase: Dictionary = Dictionary(_fix9_phase_stats.get(phase_name, {}))
	var count: int = int(phase.get("count", 0)) + 1
	phase["count"] = count
	phase["last_ms"] = duration_ms
	phase["max_ms"] = maxf(float(phase.get("max_ms", 0.0)), duration_ms)
	phase["total_ms"] = float(phase.get("total_ms", 0.0)) + duration_ms
	if duration_ms >= FIX9_PRESENTATION_PHASE_BUDGET_MS:
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


func get_fix9_client_frame_budget_report() -> Dictionary:
	return {
		"policy": FIX9_PRESENTATION_BUDGET_POLICY,
		"phase_budget_ms": FIX9_PRESENTATION_PHASE_BUDGET_MS,
		"physics_unattributed_last_ms": _fix9_physics_unattributed_last_ms,
		"physics_unattributed_max_ms": _fix9_physics_unattributed_max_ms,
		"presentation_apply_count": _fix9_presentation_apply_count,
		"presentation_idle_flushes": _fix9_presentation_idle_flushes,
		"phases": {
			"world_render_process": _fix9_phase_report("world_render_process"),
			"world_physics_process": _fix9_phase_report("world_physics_process"),
			"world_physics_unattributed": _fix9_phase_report("world_physics_unattributed"),
			"prediction_sync": _fix9_phase_report("prediction_sync"),
			"prediction_callback": _fix9_phase_report("prediction_callback"),
			"presentation_flush": _fix9_phase_report("presentation_flush"),
			"replica_presentation": _fix9_phase_report("replica_presentation"),
			"item_projection": _fix9_phase_report("item_projection"),
		},
	}


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["fix9_client_frame_budget"] = get_fix9_client_frame_budget_report()
	report["fix10_fix3_remote_continuity"] = get_fix10_fix3_remote_continuity_report()
	return report