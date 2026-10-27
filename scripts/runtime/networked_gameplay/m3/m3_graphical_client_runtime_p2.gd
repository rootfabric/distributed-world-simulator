extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"

const R31CodecPolicy = preload("res://scripts/network/contracts/r31_815_compact_codec_negotiation.gd")
const CompactCodecV2 = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot_v2.gd")

# INT0 composition boundary:
# - the inherited script remains the accepted NX6 transport, fixed-tick,
#   prediction, reconciliation and predicted-item runtime;
# - this adapter adds only bounded recovery from an out-of-order gameplay
#   delta while waiting for the authoritative full snapshot already emitted
#   by the server.

var _pending_replica_resync := false
var _delta_base_mismatches := 0
var _snapshot_resyncs := 0
# Strict opt-in. Codec is bound to the NX0 HELLO + transport session, and
# every movement/committed-view snapshot is decoded with ONLY that format.
var _r31_815_client_mode: String = "off"
var _r31_815_selected: String = R31CodecPolicy.LEGACY
var _r31_815_bound_session: String = ""
var _r31_815_bound_handshake: String = ""
var _r31_815_v1_received: int = 0
var _r31_815_v2_received: int = 0
# First successful COMPACT decode PER transport session, including reconnect.
var _r31_815_last_rx_receipt_session: String = ""
var _r31_815_codec_rejections: int = 0


func setup(config: Dictionary) -> Dictionary:
	var mode: String = String(config.get("r31_815_compact_codec_mode",
		OS.get_environment("DWS_NET_815_COMPACT_CLIENT_MODE"))).strip_edges().to_lower()
	if mode.is_empty():
		mode = "off"
	var checked: Dictionary = R31CodecPolicy.validate_mode(mode)
	if not bool(checked.get("success", false)):
		return checked
	if mode != "off" and not bool(config.get("playable_sandbox", false)):
		return _failure("R31_815_CODEC_REQUIRES_PLAYABLE_CLIENT")
	_r31_815_client_mode = mode
	_r31_815_v1_received = 0
	_r31_815_v2_received = 0
	_r31_815_last_rx_receipt_session = ""
	_r31_815_codec_rejections = 0
	return super.setup(config)


func _start_transport_attempt() -> Dictionary:
	# The previous ACK is never reusable for a new reconnect or wrap-rotation.
	_r31_815_bound_session = ""
	_r31_815_bound_handshake = ""
	_r31_815_last_rx_receipt_session = ""
	_r31_815_selected = R31CodecPolicy.LEGACY
	return super._start_transport_attempt()


func _send_control(message_type: String, data: Dictionary) -> bool:
	if message_type != "COMPATIBILITY_HELLO" or _r31_815_client_mode == "off":
		return super._send_control(message_type, data)
	var offered: Dictionary = R31CodecPolicy.create_offer(_r31_815_client_mode, _handshake_id)
	if offered.is_empty():
		return false
	var message: Dictionary = data.duplicate(true)
	message["compact_codec_offer"] = offered
	return super._send_control(message_type, message)


func _handle_compatibility_ack(payload: Dictionary) -> void:
	var ack_value = payload.get("ack", {})
	if not ack_value is Dictionary:
		super._handle_compatibility_ack(payload)
		return
	# Original HELLO/ACK fingerprint checks are performed BEFORE the format
	# choice can be committed. No client downgrade on an unverified ACK.
	var fingerprint_check: Dictionary = CompatibilityHandshake.validate_client_ack(
		_fingerprint, _handshake_hello, Dictionary(ack_value))
	if not bool(fingerprint_check.get("success", false)):
		super._handle_compatibility_ack(payload)
		return
	var choice_value = payload.get("compact_codec_choice", {})
	if not choice_value is Dictionary:
		_fail_connection("COMPACT_CODEC_INVALID_ACK_TYPE")
		return
	var offer: Dictionary = (
		R31CodecPolicy.create_offer(_r31_815_client_mode, _handshake_id)
		if _r31_815_client_mode != "off" else {}
	)
	var selected_check: Dictionary = R31CodecPolicy.client_accept(
		_r31_815_client_mode, offer, Dictionary(choice_value), _handshake_id)
	if not bool(selected_check.get("success", false)):
		_fail_connection(String(selected_check.get(
			"error_code", "COMPACT_CODEC_ACK_REJECTED")))
		return
	var selected: String = String(selected_check["details"]["selected"])
	if _handshake_verified:
		# Duplicate already-authenticated ACK is idempotent; it must never
		# re-run READY transitions or change the active codec in this session.
		if (_r31_815_bound_session != _transport_session_id
			or _r31_815_bound_handshake != _handshake_id
			or _r31_815_selected != selected):
			_fail_connection("COMPACT_CODEC_RENEGOTIATION_FORBIDDEN")
		return
	super._handle_compatibility_ack(payload)
	if not _handshake_verified:
		return
	_r31_815_selected = selected
	_r31_815_bound_session = _transport_session_id
	_r31_815_bound_handshake = _handshake_id
	if SmoothTrace.enabled():
		SmoothTrace.emit("r31_815_compact_codec_negotiated", {
			"selected": selected,
			"session_sha256": _transport_session_id.sha256_text(),
			"handshake_sha256": _handshake_id.sha256_text(),
		})


func _r31_815_record_compact_receive(selected: String, wire: Dictionary) -> void:
	if (not SmoothTrace.enabled() or not _handshake_verified
		or _r31_815_bound_session != _transport_session_id
		or _r31_815_bound_handshake != _handshake_id):
		return
	var receipt_key: String = _transport_session_id + "|" + selected
	if _r31_815_last_rx_receipt_session == receipt_key:
		return
	SmoothTrace.emit(
		"r31_815_compact_v2_received" if selected == R31CodecPolicy.F64
		else "r31_815_compact_v1_received", {
			"server_tick": int(wire.get("t", -1)),
			"schema": CompactCodecV2.SCHEMA if selected == R31CodecPolicy.F64
			else CompactGameplaySnapshot.SCHEMA,
			"session_sha256": _transport_session_id.sha256_text(),
			"handshake_sha256": _handshake_id.sha256_text(),
		})
	_r31_815_last_rx_receipt_session = receipt_key


func _decode_compact_snapshot(wire: Dictionary) -> Dictionary:
	if _r31_815_client_mode == "off":
		# Default original v1 decode. Only read-only receipt metadata added
		# after success, so mixed-mode evidence covers B AFTER reconnect.
		var legacy: Dictionary = super._decode_compact_snapshot(wire)
		if bool(legacy.get("success", false)):
			_r31_815_v1_received += 1
			_r31_815_record_compact_receive(R31CodecPolicy.LEGACY, wire)
		return legacy
	if not _handshake_verified or _r31_815_bound_session != _transport_session_id or (
		_r31_815_bound_handshake != _handshake_id
	):
		_r31_815_codec_rejections += 1
		return _failure("COMPACT_CODEC_SESSION_NOT_NEGOTIATED")
	var selected: String = _r31_815_selected
	var schema: String = String(wire.get("schema", ""))
	if selected == R31CodecPolicy.F64:
		if schema != CompactCodecV2.SCHEMA:
			_r31_815_codec_rejections += 1
			return _failure("COMPACT_CODEC_VERSION_MISMATCH")
		var v2: Dictionary = CompactCodecV2.decode(wire)
		if bool(v2.get("success", false)):
			_r31_815_v2_received += 1
			_r31_815_record_compact_receive(R31CodecPolicy.F64, wire)
		return v2
	if selected == R31CodecPolicy.LEGACY:
		if schema != CompactGameplaySnapshot.SCHEMA:
			_r31_815_codec_rejections += 1
			return _failure("COMPACT_CODEC_VERSION_MISMATCH")
		var v1: Dictionary = super._decode_compact_snapshot(wire)
		if bool(v1.get("success", false)):
			_r31_815_v1_received += 1
			_r31_815_record_compact_receive(R31CodecPolicy.LEGACY, wire)
		return v1
	_r31_815_codec_rejections += 1
	return _failure("COMPACT_CODEC_UNKNOWN_NEGOTIATION")


func _process(delta: float) -> void:
	# M5 keeps this transport-session binding visible at the production source
	# boundary. The inherited NX6 process sends JOIN with the same value; this
	# assignment makes the composed adapter explicitly preserve that contract.
	if _handshake_verified and not _join_sent and not _transport_session_id.is_empty():
		_join_operation_id = Support.transport_bound_operation_id(
			_logical_player_id,
			"join",
			_transport_session_id
		)
	super._process(delta)


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

	# This adapter owns snapshot acceptance only to implement gap recovery. Keep
	# the NX4 side effects from the inherited implementation as well: otherwise
	# a full authoritative snapshot would update the replica store while leaving
	# client prediction on an obsolete baseline.
	_reconcile_prediction_from_snapshot(_replica.get_snapshot())
	_prune_acknowledged_inputs()
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
	report["r31_815_compact_client_mode"] = _r31_815_client_mode
	report["r31_815_compact_selected"] = _r31_815_selected
	report["r31_815_compact_bound"] = (
		_handshake_verified
		and _r31_815_bound_session == _transport_session_id
		and _r31_815_bound_handshake == _handshake_id
	)
	report["r31_815_compact_v1_received"] = _r31_815_v1_received
	report["r31_815_compact_v2_received"] = _r31_815_v2_received
	report["r31_815_compact_rejections"] = _r31_815_codec_rejections
	return report
