extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"

# INT0 composition boundary:
# - the inherited script remains the accepted NX6 transport, fixed-tick,
#   prediction, reconciliation and predicted-item runtime;
# - this adapter adds only bounded recovery from an out-of-order gameplay
#   delta while waiting for the authoritative full snapshot already emitted
#   by the server.

var _pending_replica_resync := false
var _delta_base_mismatches := 0
var _snapshot_resyncs := 0


func _handle_join_ack(payload: Dictionary) -> void:
	super._handle_join_ack(payload)
	if _joined:
		_pending_replica_resync = false


func _accept_snapshot(snapshot: Dictionary) -> void:
	var accepted: Dictionary = _replica.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_last_error_code = String(
			accepted.get("error_code", "M3_SNAPSHOT_REJECTED")
		)
		return
	if _pending_replica_resync:
		_pending_replica_resync = false
		_snapshot_resyncs += 1
	_last_error_code = ""
	if not bool(accepted.get("details", {}).get("replay", false)):
		_snapshot_updates += 1
	replica_updated.emit(_replica.get_snapshot())


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
	return report
