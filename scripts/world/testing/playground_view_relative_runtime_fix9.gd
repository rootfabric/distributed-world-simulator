extends "res://scripts/world/testing/playground_view_relative_runtime_fix8.gd"

# FIX9 is a presentation/performance-only composition layer. It keeps FIX8
# prediction-clock semantics, FIX7 manual presentation and all M7 authority
# contracts intact while measuring the graphical client hot path around the
# world callbacks that are executed synchronously from network message dispatch
# and the physics-rate local prediction/presentation path.

const InventoryRev6EnhancerFix9Script = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix9.gd"
)

const FIX9_PRESENTATION_BUDGET_POLICY: String = "CLIENT_WORLD_PHASE_ACCOUNTING_V1"
const FIX9_PRESENTATION_PHASE_BUDGET_MS: float = 16.667

var _fix9_phase_stats: Dictionary = {}
var _fix9_frame_prediction_sync_ms: float = 0.0
var _fix9_frame_presentation_flush_ms: float = 0.0
var _fix9_physics_unattributed_last_ms: float = 0.0
var _fix9_physics_unattributed_max_ms: float = 0.0
var _fix9_presentation_apply_count: int = 0
var _fix9_presentation_idle_flushes: int = 0


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result

	# FIX8 remains the accepted behavior implementation. Replace only the active
	# enhancer instance with FIX9's write-on-change presentation specialization.
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
	super._on_m3_replica_updated(snapshot)
	_fix9_record_phase("replica_presentation", float(Time.get_ticks_usec() - started_us) / 1000.0)


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
	return report
