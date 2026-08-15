extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd"

const FAULT_PROFILE_H2_TARGET_CRASH_AFTER_COMMIT_PERSIST_V1 := "h2-target-crash-after-commit-persist-v1"
const FAULT_PROFILE_H2_SOURCE_CRASH_AFTER_RETIRE_PERSIST_V1 := "h2-source-crash-after-retire-persist-v1"

var _recovery_fault_profile := ""
var _h22_crash_point_emitted := false
var _h22_activate_suppressed_logged := false
var _h23_crash_point_emitted := false
var _h23_commit_suppressed_logged := false
var _h23_redirect_suppressed_logged := false


func setup(config: Dictionary) -> Dictionary:
	_recovery_fault_profile = String(config.get("fault_profile", "")).strip_edges()
	if _recovery_fault_profile not in [
		FAULT_PROFILE_H2_TARGET_CRASH_AFTER_COMMIT_PERSIST_V1,
		FAULT_PROFILE_H2_SOURCE_CRASH_AFTER_RETIRE_PERSIST_V1,
	]:
		return _failure("SM0_UNKNOWN_RECOVERY_FAULT_PROFILE", {"fault_profile": _recovery_fault_profile})
	if String(config.get("recovery_dir", "")).strip_edges().is_empty():
		return _failure("SM0_RECOVERY_FAULT_DIR_REQUIRED")
	var result: Dictionary = super.setup(config)
	if bool(result.get("success", false)):
		_event("SM0_FAULT_PROFILE_ENABLED", {"fault_profile": _recovery_fault_profile})
	return result


func _commit_source_transfer() -> void:
	super._commit_source_transfer()
	if _recovery_fault_profile != FAULT_PROFILE_H2_SOURCE_CRASH_AFTER_RETIRE_PERSIST_V1:
		return
	if _h23_crash_point_emitted or _source_transfer.is_empty():
		return
	var transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()
	if (
		transfer_id.is_empty()
		or String(_source_transfer.get("stage", "")) != "COMMIT_SENT"
		or _recovery_last_phase != "SOURCE_RETIRED"
		or _recovery_last_transfer_id != transfer_id
		or String(_directory.get("owner_authority_id", "")) == _authority_id
	):
		return
	_h23_crash_point_emitted = true
	_event("SM0_H2_CRASH_POINT", {
		"fault_profile": _recovery_fault_profile,
		"crash_point": "SOURCE_AFTER_RETIRE_PERSIST_BEFORE_COMMIT",
		"transfer_id": transfer_id,
		"recovery_generation": _recovery_generation,
		"recovery_phase": _recovery_last_phase,
		"directory": _directory,
	})


func _send_source_commit() -> void:
	if _recovery_fault_profile == FAULT_PROFILE_H2_SOURCE_CRASH_AFTER_RETIRE_PERSIST_V1:
		if not _h23_commit_suppressed_logged:
			_h23_commit_suppressed_logged = true
			_event("SM0_H2_SOURCE_SEND_SUPPRESSED", {
				"fault_profile": _recovery_fault_profile,
				"message_type": "PLAYER_HANDOFF_COMMIT",
				"transfer_id": String(_source_transfer.get("transfer_id", "")),
			})
		return
	super._send_source_commit()


func _send_client_redirect() -> void:
	if _recovery_fault_profile == FAULT_PROFILE_H2_SOURCE_CRASH_AFTER_RETIRE_PERSIST_V1:
		if not _h23_redirect_suppressed_logged:
			_h23_redirect_suppressed_logged = true
			_event("SM0_H2_SOURCE_SEND_SUPPRESSED", {
				"fault_profile": _recovery_fault_profile,
				"message_type": "HANDOFF_REDIRECT",
				"transfer_id": String(_source_transfer.get("transfer_id", "")),
			})
		return
	super._send_client_redirect()


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_recovery_fault_profile == FAULT_PROFILE_H2_TARGET_CRASH_AFTER_COMMIT_PERSIST_V1
		and message_type == "PLAYER_HANDOFF_COMMITTED"
		and bool(payload.get("success", false))
	):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var persisted := _ensure_target_commit_persisted(transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_H2_2_TARGET_COMMIT_PERSIST_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})
			return
		if not _h22_crash_point_emitted:
			_h22_crash_point_emitted = true
			_event("SM0_H2_CRASH_POINT", {
				"fault_profile": _recovery_fault_profile,
				"crash_point": "TARGET_AFTER_COMMIT_PERSIST_BEFORE_ACK",
				"message_type": message_type,
				"transfer_id": transfer_id,
				"request_id": request_id,
				"recovery_generation": _recovery_generation,
				"recovery_phase": _recovery_last_phase,
			})
		# Keep every successful COMMITTED response suppressed until the external
		# supervisor kills this target. This makes the process crash boundary
		# deterministic even when source retries faster than the supervisor reacts.
		return
	super._send_control(message_type, payload, request_id)


func _handle_client_activate(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if (
		_recovery_fault_profile == FAULT_PROFILE_H2_TARGET_CRASH_AFTER_COMMIT_PERSIST_V1
		and _h22_crash_point_emitted
	):
		if not _h22_activate_suppressed_logged:
			_h22_activate_suppressed_logged = true
			_event("SM0_H2_ACTIVATE_SUPPRESSED", {
				"fault_profile": _recovery_fault_profile,
				"transfer_id": String(payload.get("transfer_id", "")),
				"request_id": request_id,
			})
		return
	super._handle_client_activate(request_id, payload, remote_ip, remote_port)
