extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd"

const FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1 := "h3-inflight-dual-outage-after-source-retire-v1"
const FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1 := "h3-commit-decision-dual-outage-v1"
const FAULT_PROFILE_H3_ACTIVATION_DUAL_OUTAGE_V1 := "h3-activation-dual-outage-before-ack-v1"
const FAULT_PROFILE_H4_REPEATED_ACTIVATION_DUAL_OUTAGE_V1 := "h4-repeated-activation-dual-outage-v1"
const FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1 := "h4-mixed-boundary-dual-outage-v1"

const H42_BOUNDARY_INFLIGHT_RETIRE := "INFLIGHT_RETIRE"
const H42_BOUNDARY_COMMIT_DECISION := "COMMIT_DECISION"
const H42_BOUNDARY_ACTIVATION := "ACTIVATION"

var _transaction_fault_profile := ""
var _h33_crash_point_emitted := false
var _h33_commit_suppressed_logged := false
var _h33_redirect_suppressed_logged := false
var _h34_crash_point_emitted := false
var _h34_committed_ack_suppressed_logged := false
var _h34_redirect_suppressed_logged := false
var _h35_crash_point_emitted := false
var _h35_activate_ack_suppressed_logged := false
var _h41_crash_point_emitted := false
var _h41_activate_ack_suppressed_logged := false
var _h42_crash_point_emitted := false
var _h42_send_suppressed_logged := false
var _h42_setup_complete := false


func setup(config: Dictionary) -> Dictionary:
	_transaction_fault_profile = String(config.get("fault_profile", "")).strip_edges()
	if _transaction_fault_profile not in [
		FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1,
		FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1,
		FAULT_PROFILE_H3_ACTIVATION_DUAL_OUTAGE_V1,
		FAULT_PROFILE_H4_REPEATED_ACTIVATION_DUAL_OUTAGE_V1,
		FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1,
	]:
		return _failure("SM0_UNKNOWN_TRANSACTION_FAULT_PROFILE", {"fault_profile": _transaction_fault_profile})
	if String(config.get("recovery_dir", "")).strip_edges().is_empty():
		return _failure("SM0_TRANSACTION_FAULT_RECOVERY_DIR_REQUIRED")
	_h42_setup_complete = false
	var result: Dictionary = super.setup(config)
	_h42_setup_complete = true
	if bool(result.get("success", false)):
		_event("SM0_FAULT_PROFILE_ENABLED", {
			"fault_profile": _transaction_fault_profile,
			"recovery_restored": _recovery_restored,
			"recovery_phase": _recovery_last_phase,
			"recovery_transfer_id": _recovery_last_transfer_id,
		})
	return result


func _h42_boundary_for_epoch(target_epoch: int) -> String:
	if target_epoch < 2:
		return ""
	var index := (target_epoch - 2) % 3
	if index == 0:
		return H42_BOUNDARY_INFLIGHT_RETIRE
	if index == 1:
		return H42_BOUNDARY_COMMIT_DECISION
	return H42_BOUNDARY_ACTIVATION


func _h42_current_boundary() -> String:
	return _h42_boundary_for_epoch(int(_directory.get("authority_epoch", 0)))


func _h42_is_setup_source_replay(transfer_id: String) -> bool:
	return (
		_transaction_fault_profile == FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1
		and not _h42_setup_complete
		and _recovery_restored
		and _recovery_last_phase == "SOURCE_RETIRED"
		and not transfer_id.is_empty()
		and _recovery_last_transfer_id == transfer_id
	)


func _h42_emit_crash_point(boundary: String, transfer_id: String) -> void:
	if _h42_crash_point_emitted:
		return
	_h42_crash_point_emitted = true
	_event("SM0_H4_MIXED_CRASH_POINT", {
		"fault_profile": _transaction_fault_profile,
		"boundary": boundary,
		"transfer_id": transfer_id,
		"target_epoch": int(_directory.get("authority_epoch", 0)),
		"recovery_generation": _recovery_generation,
		"recovery_phase": _recovery_last_phase,
		"authority_id": _authority_id,
		"directory": _directory,
	})


func _h42_emit_send_suppressed(boundary: String, message_type: String, transfer_id: String, request_id: String = "") -> void:
	if _h42_send_suppressed_logged:
		return
	_h42_send_suppressed_logged = true
	_event("SM0_H4_MIXED_SEND_SUPPRESSED", {
		"fault_profile": _transaction_fault_profile,
		"boundary": boundary,
		"message_type": message_type,
		"transfer_id": transfer_id,
		"request_id": request_id,
		"target_epoch": int(_directory.get("authority_epoch", 0)),
		"authority_id": _authority_id,
		"recovery_generation": _recovery_generation,
	})


func _commit_source_transfer() -> void:
	super._commit_source_transfer()
	if _transaction_fault_profile == FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1:
		if _authority_id != Contracts.AUTHORITY_A or _h33_crash_point_emitted or _source_transfer.is_empty():
			return
		var h33_transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()
		if (
			h33_transfer_id.is_empty()
			or String(_source_transfer.get("stage", "")) != "COMMIT_SENT"
			or _recovery_last_phase != "SOURCE_RETIRED"
			or _recovery_last_transfer_id != h33_transfer_id
			or String(_directory.get("owner_authority_id", "")) != Contracts.AUTHORITY_B
		):
			return
		_h33_crash_point_emitted = true
		_event("SM0_H3_CRASH_POINT", {
			"fault_profile": _transaction_fault_profile,
			"crash_point": "DUAL_OUTAGE_AFTER_SOURCE_RETIRE_BEFORE_TARGET_COMMIT",
			"transfer_id": h33_transfer_id,
			"recovery_generation": _recovery_generation,
			"recovery_phase": _recovery_last_phase,
			"directory": _directory,
		})
		return

	if (
		_transaction_fault_profile != FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1
		or _source_transfer.is_empty()
		or _h42_current_boundary() != H42_BOUNDARY_INFLIGHT_RETIRE
	):
		return
	var transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()
	if _h42_is_setup_source_replay(transfer_id):
		return
	if (
		transfer_id.is_empty()
		or String(_source_transfer.get("stage", "")) != "COMMIT_SENT"
		or _recovery_last_phase != "SOURCE_RETIRED"
		or _recovery_last_transfer_id != transfer_id
		or String(_directory.get("owner_authority_id", "")) == _authority_id
	):
		return
	_h42_emit_crash_point(H42_BOUNDARY_INFLIGHT_RETIRE, transfer_id)


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_transaction_fault_profile == FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1
		and _authority_id == Contracts.AUTHORITY_B
		and message_type == "PLAYER_HANDOFF_COMMITTED"
		and bool(payload.get("success", false))
	):
		var h34_transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var h34_persisted := _ensure_target_commit_persisted(h34_transfer_id)
		if not bool(h34_persisted.get("success", false)):
			_invariant("SM0_RECOVERY_PERSIST_BEFORE_COMMITTED_ACK_FAILED", {
				"transfer_id": h34_transfer_id,
				"cause": h34_persisted,
			})
			return
		if not _h34_crash_point_emitted:
			_h34_crash_point_emitted = true
			_event("SM0_H3_CRASH_POINT", {
				"fault_profile": _transaction_fault_profile,
				"crash_point": "DUAL_OUTAGE_AFTER_TARGET_COMMIT_BEFORE_OBSERVATION",
				"transfer_id": h34_transfer_id,
				"recovery_generation": _recovery_generation,
				"recovery_phase": _recovery_last_phase,
				"directory": _directory,
			})
		if not _h34_committed_ack_suppressed_logged:
			_h34_committed_ack_suppressed_logged = true
			_event("SM0_H3_TARGET_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "PLAYER_HANDOFF_COMMITTED",
				"transfer_id": h34_transfer_id,
				"recovery_generation": _recovery_generation,
			})
		return

	if (
		_transaction_fault_profile == FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1
		and message_type == "PLAYER_HANDOFF_COMMITTED"
		and bool(payload.get("success", false))
		and _h42_current_boundary() == H42_BOUNDARY_COMMIT_DECISION
	):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var already_persisted := _recovery_persisted_commits.has(transfer_id)
		var persisted := _ensure_target_commit_persisted(transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_H4_MIXED_TARGET_COMMIT_PERSIST_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})
			return
		if already_persisted:
			super._send_control(message_type, payload, request_id)
			return
		_h42_emit_crash_point(H42_BOUNDARY_COMMIT_DECISION, transfer_id)
		_h42_emit_send_suppressed(H42_BOUNDARY_COMMIT_DECISION, message_type, transfer_id, request_id)
		return

	super._send_control(message_type, payload, request_id)


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_transaction_fault_profile == FAULT_PROFILE_H3_ACTIVATION_DUAL_OUTAGE_V1
		and _authority_id == Contracts.AUTHORITY_B
		and message_type == "ACTIVATE_ACK"
	):
		var h35_transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var h35_persisted := _ensure_active_owner_persisted_for_ack(host, port, message_type, payload)
		if not bool(h35_persisted.get("success", false)):
			_invariant("SM0_H3_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK_FAILED", {
				"transfer_id": h35_transfer_id,
				"request_id": request_id,
				"cause": h35_persisted,
			})
			return
		if _recovery_last_phase != ACTIVE_OWNER_PHASE:
			_invariant("SM0_H3_ACTIVE_OWNER_PHASE_REQUIRED", {
				"transfer_id": h35_transfer_id,
				"phase": _recovery_last_phase,
			})
			return
		if not _h35_crash_point_emitted:
			_h35_crash_point_emitted = true
			var h35_player: Dictionary = _authority.get_player("a")
			_event("SM0_H3_CRASH_POINT", {
				"fault_profile": _transaction_fault_profile,
				"crash_point": "DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK",
				"transfer_id": h35_transfer_id,
				"recovery_generation": _recovery_generation,
				"recovery_phase": _recovery_last_phase,
				"directory": _directory,
				"ownership_epoch": int(h35_player.get("ownership_epoch", 0)),
				"last_input_sequence": int(h35_player.get("last_input_sequence", 0)),
			})
		if not _h35_activate_ack_suppressed_logged:
			_h35_activate_ack_suppressed_logged = true
			_event("SM0_H3_TARGET_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "ACTIVATE_ACK",
				"transfer_id": h35_transfer_id,
				"request_id": request_id,
				"recovery_generation": _recovery_generation,
			})
		return

	if (
		_transaction_fault_profile == FAULT_PROFILE_H4_REPEATED_ACTIVATION_DUAL_OUTAGE_V1
		and message_type == "ACTIVATE_ACK"
	):
		if not _active_recovery_metadata.is_empty():
			super._send_gameplay(host, port, message_type, payload, request_id)
			return
		var h41_transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var h41_persisted := _ensure_active_owner_persisted_for_ack(host, port, message_type, payload)
		if not bool(h41_persisted.get("success", false)):
			_invariant("SM0_H4_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK_FAILED", {
				"transfer_id": h41_transfer_id,
				"request_id": request_id,
				"cause": h41_persisted,
			})
			return
		if _recovery_last_phase != ACTIVE_OWNER_PHASE:
			_invariant("SM0_H4_ACTIVE_OWNER_PHASE_REQUIRED", {
				"transfer_id": h41_transfer_id,
				"phase": _recovery_last_phase,
			})
			return
		if not _h41_crash_point_emitted:
			_h41_crash_point_emitted = true
			var h41_player: Dictionary = _authority.get_player("a")
			_event("SM0_H4_CRASH_POINT", {
				"fault_profile": _transaction_fault_profile,
				"crash_point": "REPEATED_DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK",
				"transfer_id": h41_transfer_id,
				"recovery_generation": _recovery_generation,
				"recovery_phase": _recovery_last_phase,
				"target_authority_id": _authority_id,
				"directory": _directory,
				"ownership_epoch": int(h41_player.get("ownership_epoch", 0)),
				"last_input_sequence": int(h41_player.get("last_input_sequence", 0)),
			})
		if not _h41_activate_ack_suppressed_logged:
			_h41_activate_ack_suppressed_logged = true
			_event("SM0_H4_TARGET_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "ACTIVATE_ACK",
				"transfer_id": h41_transfer_id,
				"request_id": request_id,
				"target_authority_id": _authority_id,
				"recovery_generation": _recovery_generation,
			})
		return

	if (
		_transaction_fault_profile == FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1
		and message_type == "ACTIVATE_ACK"
		and _h42_current_boundary() == H42_BOUNDARY_ACTIVATION
	):
		if not _active_recovery_metadata.is_empty():
			super._send_gameplay(host, port, message_type, payload, request_id)
			return
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var persisted := _ensure_active_owner_persisted_for_ack(host, port, message_type, payload)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_H4_MIXED_ACTIVE_OWNER_PERSIST_FAILED", {
				"transfer_id": transfer_id,
				"request_id": request_id,
				"cause": persisted,
			})
			return
		if _recovery_last_phase != ACTIVE_OWNER_PHASE:
			_invariant("SM0_H4_MIXED_ACTIVE_OWNER_PHASE_REQUIRED", {
				"transfer_id": transfer_id,
				"phase": _recovery_last_phase,
			})
			return
		_h42_emit_crash_point(H42_BOUNDARY_ACTIVATION, transfer_id)
		_h42_emit_send_suppressed(H42_BOUNDARY_ACTIVATION, message_type, transfer_id, request_id)
		return

	super._send_gameplay(host, port, message_type, payload, request_id)


func _send_source_commit() -> void:
	if (
		_transaction_fault_profile == FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1
		and _authority_id == Contracts.AUTHORITY_A
	):
		if not _h33_commit_suppressed_logged:
			_h33_commit_suppressed_logged = true
			_event("SM0_H3_SOURCE_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "PLAYER_HANDOFF_COMMIT",
				"transfer_id": String(_source_transfer.get("transfer_id", "")),
			})
		return

	if (
		_transaction_fault_profile == FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1
		and _h42_current_boundary() == H42_BOUNDARY_INFLIGHT_RETIRE
	):
		var transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()
		if _h42_is_setup_source_replay(transfer_id):
			super._send_source_commit()
			return
		_h42_emit_send_suppressed(H42_BOUNDARY_INFLIGHT_RETIRE, "PLAYER_HANDOFF_COMMIT", transfer_id)
		return

	super._send_source_commit()


func _send_client_redirect() -> void:
	if _transaction_fault_profile == FAULT_PROFILE_H4_MIXED_BOUNDARY_DUAL_OUTAGE_V1:
		var transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()
		var boundary := _h42_current_boundary()
		if boundary in [H42_BOUNDARY_INFLIGHT_RETIRE, H42_BOUNDARY_COMMIT_DECISION]:
			if _h42_is_setup_source_replay(transfer_id):
				super._send_client_redirect()
				return
			_h42_emit_send_suppressed(boundary, "HANDOFF_REDIRECT", transfer_id)
			return
		super._send_client_redirect()
		return

	if _authority_id != Contracts.AUTHORITY_A:
		super._send_client_redirect()
		return
	if _transaction_fault_profile == FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1:
		if not _h33_redirect_suppressed_logged:
			_h33_redirect_suppressed_logged = true
			_event("SM0_H3_SOURCE_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "HANDOFF_REDIRECT",
				"transfer_id": String(_source_transfer.get("transfer_id", "")),
			})
		return
	if _transaction_fault_profile == FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1:
		if not _h34_redirect_suppressed_logged:
			_h34_redirect_suppressed_logged = true
			_event("SM0_H3_SOURCE_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "HANDOFF_REDIRECT",
				"transfer_id": String(_source_transfer.get("transfer_id", "")),
			})
		return
	super._send_client_redirect()
