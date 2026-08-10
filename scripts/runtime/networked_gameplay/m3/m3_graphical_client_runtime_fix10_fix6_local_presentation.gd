extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix10_fix6_semantic_cadence.gd"

# Local prediction presentation has exactly one render writer: the normal
# advance_local_prediction() frame path. Authoritative snapshots still reconcile
# prediction state, history, correction debt and telemetry immediately, but they
# never emit a second presentation pose from the network-dispatch path.
#
# Previously the snapshot path called sample_presentation(0.0) and emitted
# prediction_updated while the regular render path also sampled/emitted later in
# the frame. Under frequent corrections this produced a visible backward/forward
# spring on the locally controlled character even though remote interpolation was
# smooth.

const FIX10_FIX6_LOCAL_PRESENTATION_POLICY: String = \
	"FRAME_PREDICTION_SINGLE_WRITER_AUTHORITY_STATE_ONLY_V1"

var _fix10_fix6_authority_reconciliations_without_render_emit: int = 0
var _fix10_fix6_frame_presentation_emits: int = 0


func setup(config: Dictionary) -> Dictionary:
	_fix10_fix6_authority_reconciliations_without_render_emit = 0
	_fix10_fix6_frame_presentation_emits = 0
	return super.setup(config)


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	_fix10_fix6_flush_deferred_snapshot_ack()
	if _prediction_reconciler == null:
		return
	if not _prediction_reconciler.is_configured():
		_initialize_prediction_from_snapshot(snapshot)
		return
	var local_player: Dictionary = _player_from_snapshot(snapshot, _logical_player_id)
	if local_player.is_empty():
		return
	var reconciled: Dictionary = _prediction_reconciler.reconcile(
		local_player,
		int(snapshot.get("server_tick", 0))
	)
	if not bool(reconciled.get("success", false)):
		_prediction_reconcile_failures += 1
		return

	var details: Dictionary = Dictionary(reconciled.get("details", {}))
	_telemetry.observe(
		"prediction_error_m",
		float(details.get("prediction_error_m", 0.0))
	)
	_telemetry.observe(
		"prediction_replayed_ticks",
		float(details.get("replayed_ticks", 0))
	)
	if String(details.get("correction_mode", "NONE")) != "NONE":
		_telemetry.increment("prediction_corrections")
	if bool(details.get("hard_correction", false)):
		_telemetry.increment("prediction_hard_corrections")

	# Deliberately do not sample presentation and do not emit prediction_updated
	# here. The corrected predicted state and visual offset are consumed by the
	# next normal frame sample, so the player transform has one writer per frame.
	_fix10_fix6_authority_reconciliations_without_render_emit += 1


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	var result: Dictionary = super.advance_local_prediction(intent, frame_delta_seconds)
	if bool(result.get("success", false)):
		_fix10_fix6_frame_presentation_emits += 1
	return result


func _emit_prediction_health_if_due() -> void:
	var previous_health_ms: int = _last_prediction_health_ms
	super._emit_prediction_health_if_due()
	if _last_prediction_health_ms == previous_health_ms:
		return
	_debug_event("FIX10_FIX6_LOCAL_PRESENTATION_HEALTH", {
		"policy": FIX10_FIX6_LOCAL_PRESENTATION_POLICY,
		"authority_reconciliations_without_render_emit": _fix10_fix6_authority_reconciliations_without_render_emit,
		"frame_presentation_emits": _fix10_fix6_frame_presentation_emits,
	})


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var transport: Dictionary = Dictionary(
		report.get("fix10_prediction_ack_transport", {})
	).duplicate(true)
	transport["fix6_local_presentation_policy"] = FIX10_FIX6_LOCAL_PRESENTATION_POLICY
	transport["fix6_authority_reconciliations_without_render_emit"] = \
		_fix10_fix6_authority_reconciliations_without_render_emit
	transport["fix6_frame_presentation_emits"] = _fix10_fix6_frame_presentation_emits
	report["fix10_prediction_ack_transport"] = transport
	return report
