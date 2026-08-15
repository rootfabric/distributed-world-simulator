extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd"

const FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1 := "h3-inflight-dual-outage-after-source-retire-v1"
const FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1 := "h3-commit-decision-dual-outage-v1"

var _transaction_fault_profile := ""
var _h33_crash_point_emitted := false
var _h33_commit_suppressed_logged := false
var _h33_redirect_suppressed_logged := false
var _h34_crash_point_emitted := false
var _h34_committed_ack_suppressed_logged := false
var _h34_redirect_suppressed_logged := false


func setup(config: Dictionary) -> Dictionary:
	_transaction_fault_profile = String(config.get("fault_profile", "")).strip_edges()
	if _transaction_fault_profile not in [
		FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1,
		FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1,
	]:
		return _failure("SM0_UNKNOWN_TRANSACTION_FAULT_PROFILE", {"fault_profile": _transaction_fault_profile})
	if String(config.get("recovery_dir", "")).strip_edges().is_empty():
		return _failure("SM0_TRANSACTION_FAULT_RECOVERY_DIR_REQUIRED")
	var result: Dictionary = super.setup(config)
	if bool(result.get("success", false)):
		_event("SM0_FAULT_PROFILE_ENABLED", {"fault_profile": _transaction_fault_profile})
	return result


func _commit_source_transfer() -> void:
	super._commit_source_transfer()
	if _transaction_fault_profile != FAULT_PROFILE_H3_INFLIGHT_DUAL_OUTAGE_V1:
		return
	if _authority_id != Contracts.AUTHORITY_A or _h33_crash_point_emitted or _source_transfer.is_empty():
		return
	var transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()
	if (
		transfer_id.is_empty()
		or String(_source_transfer.get("stage", "")) != "COMMIT_SENT"
		or _recovery_last_phase != "SOURCE_RETIRED"
		or _recovery_last_transfer_id != transfer_id
		or String(_directory.get("owner_authority_id", "")) != Contracts.AUTHORITY_B
	):
		return
	_h33_crash_point_emitted = true
	_event("SM0_H3_CRASH_POINT", {
		"fault_profile": _transaction_fault_profile,
		"crash_point": "DUAL_OUTAGE_AFTER_SOURCE_RETIRE_BEFORE_TARGET_COMMIT",
		"transfer_id": transfer_id,
		"recovery_generation": _recovery_generation,
		"recovery_phase": _recovery_last_phase,
		"directory": _directory,
	})


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_transaction_fault_profile == FAULT_PROFILE_H3_COMMIT_DECISION_DUAL_OUTAGE_V1
		and _authority_id == Contracts.AUTHORITY_B
		and message_type == "PLAYER_HANDOFF_COMMITTED"
		and bool(payload.get("success", false))
	):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var persisted := _ensure_target_commit_persisted(transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_RECOVERY_PERSIST_BEFORE_COMMITTED_ACK_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})
			return
		if not _h34_crash_point_emitted:
			_h34_crash_point_emitted = true
			_event("SM0_H3_CRASH_POINT", {
				"fault_profile": _transaction_fault_profile,
				"crash_point": "DUAL_OUTAGE_AFTER_TARGET_COMMIT_BEFORE_OBSERVATION",
				"transfer_id": transfer_id,
				"recovery_generation": _recovery_generation,
				"recovery_phase": _recovery_last_phase,
				"directory": _directory,
			})
		if not _h34_committed_ack_suppressed_logged:
			_h34_committed_ack_suppressed_logged = true
			_event("SM0_H3_TARGET_SEND_SUPPRESSED", {
				"fault_profile": _transaction_fault_profile,
				"message_type": "PLAYER_HANDOFF_COMMITTED",
				"transfer_id": transfer_id,
				"recovery_generation": _recovery_generation,
			})
		return
	super._send_control(message_type, payload, request_id)


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
	super._send_source_commit()


func _send_client_redirect() -> void:
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
