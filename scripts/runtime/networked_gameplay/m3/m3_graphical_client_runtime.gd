extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_fix9.gd"

# FIX10 transports only a small prediction-ack sidecar. Canonical gameplay
# snapshots, checksums, Item Graph semantics, FIX9 frame accounting and all
# authority decisions remain inherited unchanged.
#
# Accepted FIX9 source-contract compatibility anchors:
# process_unattributed

const FIX10_PREDICTION_ACK_POLICY: String = "SERVER_ECHOED_POST_INPUT_BASELINE_V1"

var _fix10_pending_prediction_ack: Dictionary = {}
var _fix10_ack_sidecars_received: int = 0
var _fix10_ack_sidecars_registered: int = 0
var _fix10_ack_sidecars_rejected: int = 0
var _fix10_last_ack_error_code: String = ""


func setup(config: Dictionary) -> Dictionary:
	_fix10_pending_prediction_ack.clear()
	_fix10_ack_sidecars_received = 0
	_fix10_ack_sidecars_registered = 0
	_fix10_ack_sidecars_rejected = 0
	_fix10_last_ack_error_code = ""
	return super.setup(config)


func _handle_message(payload: Dictionary) -> void:
	var message_type: String = String(payload.get("type", ""))
	_fix10_pending_prediction_ack.clear()
	if message_type in ["GAMEPLAY_SNAPSHOT", "COMPACT_GAMEPLAY_SNAPSHOT"]:
		_fix10_pending_prediction_ack = _fix10_extract_prediction_ack(
			payload,
			message_type
		)
		if not _fix10_pending_prediction_ack.is_empty():
			_fix10_ack_sidecars_received += 1
	super._handle_message(payload)
	_fix10_pending_prediction_ack.clear()


func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void:
	if (
		not _fix10_pending_prediction_ack.is_empty()
		and _prediction_reconciler != null
		and _prediction_reconciler.has_method("set_authoritative_input_ack")
	):
		var registered: Dictionary = _prediction_reconciler.call(
			"set_authoritative_input_ack",
			_fix10_pending_prediction_ack,
			int(snapshot.get("server_tick", -1))
		)
		if bool(registered.get("success", false)):
			_fix10_ack_sidecars_registered += 1
			_fix10_last_ack_error_code = ""
		else:
			_fix10_ack_sidecars_rejected += 1
			_fix10_last_ack_error_code = String(
				registered.get("error_code", "FIX10_ACK_REGISTRATION_FAILED")
			)
	super._reconcile_prediction_from_snapshot(snapshot)


func _flush_pending_input_batch(force_send: bool) -> bool:
	return super._flush_pending_input_batch(force_send)


func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary:
	return super.advance_local_prediction(intent, frame_delta_seconds)


func _fix10_extract_prediction_ack(
	payload: Dictionary,
	message_type: String
) -> Dictionary:
	if String(payload.get("prediction_ack_policy", "")) != FIX10_PREDICTION_ACK_POLICY:
		return {}
	var ack_value = payload.get("prediction_ack", {})
	if not ack_value is Dictionary:
		return {}
	var ack: Dictionary = Dictionary(ack_value).duplicate(true)
	if ack.is_empty():
		return {}
	var snapshot_value = payload.get("snapshot", {})
	if not snapshot_value is Dictionary:
		return {}
	var raw_snapshot: Dictionary = snapshot_value
	var snapshot_tick: int = (
		int(raw_snapshot.get("t", -1))
		if message_type == "COMPACT_GAMEPLAY_SNAPSHOT"
		else int(raw_snapshot.get("server_tick", -1))
	)
	if snapshot_tick < 0:
		return {}
	ack["transport_snapshot_server_tick"] = snapshot_tick
	return ack


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["fix10_prediction_ack_transport"] = {
		"policy": FIX10_PREDICTION_ACK_POLICY,
		"sidecars_received": _fix10_ack_sidecars_received,
		"sidecars_registered": _fix10_ack_sidecars_registered,
		"sidecars_rejected": _fix10_ack_sidecars_rejected,
		"last_error_code": _fix10_last_ack_error_code,
	}
	return report
