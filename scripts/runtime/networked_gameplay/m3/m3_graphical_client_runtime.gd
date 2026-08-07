extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"

# INT0 composition boundary:
# - the inherited script remains the accepted NX6 transport, fixed-tick,
#   prediction, reconciliation and predicted-item runtime;
# - this adapter adds only bounded recovery from out-of-order gameplay state.
# Full and compact snapshots may cross channels with the same semantic revision
# but different fixed server ticks. Those clock-only reorderings are not state
# mutations; true same-revision semantic mutations remain rejected.

var _pending_replica_resync := false
var _delta_base_mismatches := 0
var _snapshot_resyncs := 0
var _last_prediction_health_ms := 0
var _full_snapshot_clock_updates := 0
var _full_snapshot_clock_replays := 0


func _process(delta: float) -> void:
	# M5 keeps this transport-session binding visible at the production source
	# boundary. The inherited NX6 process sends JOIN with the same value; this
	# assignment makes the composed adapter explicitly preserve that contract.
	if _handshake_verified and not _join_sent and not _transport_session_id.is_empty():
		_join_operation_id = Support.transport_bound_operation_id(_logical_player_id, "join", _transport_session_id)
	super._process(delta)
	_emit_prediction_health_if_due()


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
	return report
