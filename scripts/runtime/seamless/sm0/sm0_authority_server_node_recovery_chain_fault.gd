extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd"

# H4.3: repeatedly crash both authorities while one exact transfer advances
# through TARGET_PREPARED -> TARGET_COMMITTED -> ACTIVE_OWNER.
#
# This is test-only fault orchestration. Durable/canonical recovery semantics
# remain in the existing transaction/active-owner recovery layers.

const FAULT_PROFILE_H43_RECOVERY_CHAIN_V1 := "h4-recovery-of-recovery-same-transfer-v1"

const H43_STAGE_PREPARED := "PREPARED"
const H43_STAGE_COMMITTED := "COMMITTED"
const H43_STAGE_ACTIVE := "ACTIVE"

var _h43_fault_profile := ""
var _h43_boot_restored := false
var _h43_boot_phase := ""
var _h43_boot_transfer_id := ""
var _h43_setup_complete := false
var _h43_crash_keys: Dictionary = {}
var _h43_suppressed_send_keys: Dictionary = {}
var _h43_deferred_activate_keys: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	_h43_fault_profile = String(config.get("fault_profile", "")).strip_edges()
	if _h43_fault_profile != FAULT_PROFILE_H43_RECOVERY_CHAIN_V1:
		return _failure("SM0_H43_UNKNOWN_FAULT_PROFILE", {"fault_profile": _h43_fault_profile})
	if String(config.get("recovery_dir", "")).strip_edges().is_empty():
		return _failure("SM0_H43_RECOVERY_DIR_REQUIRED")

	# Source recovery_resume can send COMMIT/redirect from inside super.setup().
	# Keep an explicit setup window so only the exact restored SOURCE_RETIRED
	# transfer bypasses Stage 1. A later fresh transfer in this same recovered
	# process must still be faulted.
	_h43_setup_complete = false
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)):
		_h43_setup_complete = true
		return result

	_h43_boot_restored = _recovery_restored
	_h43_boot_phase = _recovery_last_phase
	_h43_boot_transfer_id = _recovery_last_transfer_id
	_h43_setup_complete = true
	_event("SM0_H43_PROFILE_ENABLED", {
		"fault_profile": _h43_fault_profile,
		"boot_restored": _h43_boot_restored,
		"boot_phase": _h43_boot_phase,
		"boot_transfer_id": _h43_boot_transfer_id,
		"recovery_generation": _recovery_generation,
		"authority_id": _authority_id,
	})
	return result


func _h43_is_source_setup_replay(transfer_id: String) -> bool:
	return (
		not _h43_setup_complete
		and _recovery_restored
		and _recovery_last_phase == "SOURCE_RETIRED"
		and not transfer_id.is_empty()
		and _recovery_last_transfer_id == transfer_id
	)


func _h43_is_current_retired_source_transfer(transfer_id: String) -> bool:
	return (
		not transfer_id.is_empty()
		and not _source_transfer.is_empty()
		and String(_source_transfer.get("transfer_id", "")) == transfer_id
		and String(_source_transfer.get("stage", "")) == "COMMIT_SENT"
		and _recovery_last_phase == "SOURCE_RETIRED"
		and _recovery_last_transfer_id == transfer_id
		and String(_directory.get("owner_authority_id", "")) != _authority_id
	)


func _h43_emit_crash_point(stage: String, transfer_id: String) -> void:
	var key := "%s|%s" % [stage, transfer_id]
	if _h43_crash_keys.has(key):
		return
	_h43_crash_keys[key] = true
	_event("SM0_H43_CRASH_POINT", {
		"fault_profile": _h43_fault_profile,
		"stage": stage,
		"transfer_id": transfer_id,
		"boot_restored": _h43_boot_restored,
		"boot_phase": _h43_boot_phase,
		"boot_transfer_id": _h43_boot_transfer_id,
		"recovery_generation": _recovery_generation,
		"recovery_phase": _recovery_last_phase,
		"authority_id": _authority_id,
		"directory": _directory,
	})


func _h43_emit_send_suppressed(stage: String, message_type: String, transfer_id: String, request_id: String = "") -> void:
	var key := "%s|%s|%s" % [stage, message_type, transfer_id]
	if _h43_suppressed_send_keys.has(key):
		return
	_h43_suppressed_send_keys[key] = true
	_event("SM0_H43_SEND_SUPPRESSED", {
		"fault_profile": _h43_fault_profile,
		"stage": stage,
		"message_type": message_type,
		"transfer_id": transfer_id,
		"request_id": request_id,
		"recovery_generation": _recovery_generation,
		"recovery_phase": _recovery_last_phase,
		"authority_id": _authority_id,
	})


func _send_source_commit() -> void:
	if _h43_fault_profile != FAULT_PROFILE_H43_RECOVERY_CHAIN_V1:
		super._send_source_commit()
		return

	if _source_transfer.is_empty():
		super._send_source_commit()
		return
	var transfer_id := String(_source_transfer.get("transfer_id", "")).strip_edges()

	# Only the exact SOURCE_RETIRED replay issued from recovery setup is allowed
	# through un-faulted. After setup, even a recovered process can later become
	# source of a new handoff; that new T must create Stage 1 normally.
	if _h43_is_source_setup_replay(transfer_id):
		super._send_source_commit()
		return

	# Parent recovery normally makes SOURCE_RETIRED durable inside its own
	# _send_source_commit() before sending COMMIT. H4.3 must stop before that
	# network send, so reproduce only the canonical durability step here first.
	# Without this ordering the first fresh call sees no durable phase yet and
	# falls through to parent, allowing COMMIT to escape and never creating the
	# PREPARED crash point.
	if (
		not transfer_id.is_empty()
		and String(_source_transfer.get("stage", "")) == "COMMIT_SENT"
		and String(_directory.get("owner_authority_id", "")) != _authority_id
	):
		var persisted := _ensure_source_retire_persisted(transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_H43_SOURCE_RETIRE_PERSIST_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})
			return

	if not _h43_is_current_retired_source_transfer(transfer_id):
		super._send_source_commit()
		return

	_h43_emit_send_suppressed(H43_STAGE_PREPARED, "PLAYER_HANDOFF_COMMIT", transfer_id)
	_h43_emit_crash_point(H43_STAGE_PREPARED, transfer_id)
	return


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_h43_fault_profile == FAULT_PROFILE_H43_RECOVERY_CHAIN_V1
		and _h43_boot_restored
		and _h43_boot_phase == TARGET_PREPARED_PHASE
		and message_type == "PLAYER_HANDOFF_COMMITTED"
		and bool(payload.get("success", false))
	):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		if transfer_id == _h43_boot_transfer_id and not transfer_id.is_empty():
			var persisted := _ensure_target_commit_persisted(transfer_id)
			if not bool(persisted.get("success", false)):
				_invariant("SM0_H43_TARGET_COMMIT_PERSIST_FAILED", {
					"transfer_id": transfer_id,
					"cause": persisted,
				})
				return
			if _recovery_last_phase != "TARGET_COMMITTED":
				_invariant("SM0_H43_TARGET_COMMITTED_PHASE_REQUIRED", {
					"transfer_id": transfer_id,
					"phase": _recovery_last_phase,
				})
				return
			_h43_emit_send_suppressed(H43_STAGE_COMMITTED, message_type, transfer_id, request_id)
			_h43_emit_crash_point(H43_STAGE_COMMITTED, transfer_id)
			return

	super._send_control(message_type, payload, request_id)


func _handle_client_activate(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	# recovery_resume intentionally reissues redirect immediately. While the
	# target booted from TARGET_PREPARED, ignore activation retries so Stage 2
	# remains observably TARGET_COMMITTED until the supervisor performs outage #2.
	if (
		_h43_fault_profile == FAULT_PROFILE_H43_RECOVERY_CHAIN_V1
		and _h43_boot_restored
		and _h43_boot_phase == TARGET_PREPARED_PHASE
	):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		if transfer_id == _h43_boot_transfer_id and not transfer_id.is_empty():
			if not _h43_deferred_activate_keys.has(transfer_id):
				_h43_deferred_activate_keys[transfer_id] = true
				_event("SM0_H43_ACTIVATE_DEFERRED", {
					"stage": H43_STAGE_COMMITTED,
					"transfer_id": transfer_id,
					"boot_phase": _h43_boot_phase,
					"recovery_phase": _recovery_last_phase,
					"authority_id": _authority_id,
				})
			return

	super._handle_client_activate(request_id, payload, remote_ip, remote_port)


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if (
		_h43_fault_profile == FAULT_PROFILE_H43_RECOVERY_CHAIN_V1
		and message_type == "HANDOFF_REDIRECT"
	):
		var redirect_transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		if _h43_is_current_retired_source_transfer(redirect_transfer_id):
			# The redirect emitted from recovery setup belongs to replay of the old T
			# and must pass. A fresh/new T is held together with COMMIT at PREPARED.
			if _h43_is_source_setup_replay(redirect_transfer_id):
				super._send_gameplay(host, port, message_type, payload, request_id)
				return
			_h43_emit_send_suppressed(H43_STAGE_PREPARED, message_type, redirect_transfer_id, request_id)
			return

	if (
		_h43_fault_profile == FAULT_PROFILE_H43_RECOVERY_CHAIN_V1
		and _h43_boot_restored
		and _h43_boot_phase == "TARGET_COMMITTED"
		and message_type == "ACTIVATE_ACK"
	):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		if transfer_id == _h43_boot_transfer_id and not transfer_id.is_empty():
			var persisted := _ensure_active_owner_persisted_for_ack(host, port, message_type, payload)
			if not bool(persisted.get("success", false)):
				_invariant("SM0_H43_ACTIVE_OWNER_PERSIST_FAILED", {
					"transfer_id": transfer_id,
					"request_id": request_id,
					"cause": persisted,
				})
				return
			if _recovery_last_phase != ACTIVE_OWNER_PHASE:
				_invariant("SM0_H43_ACTIVE_OWNER_PHASE_REQUIRED", {
					"transfer_id": transfer_id,
					"phase": _recovery_last_phase,
				})
				return
			_h43_emit_send_suppressed(H43_STAGE_ACTIVE, message_type, transfer_id, request_id)
			_h43_emit_crash_point(H43_STAGE_ACTIVE, transfer_id)
			return

	# A target restored from ACTIVE_OWNER has reached the terminal recovery boot
	# for H4.3. Do not fault it again; existing active recovery must complete.
	super._send_gameplay(host, port, message_type, payload, request_id)
