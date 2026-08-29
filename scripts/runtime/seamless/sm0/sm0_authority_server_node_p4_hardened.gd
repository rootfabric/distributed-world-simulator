extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd"

# P4 closure hardening.
#
# This layer deliberately reuses the existing SM0 recovery journal for canonical
# source/target gameplay state and adds only a small P4 protocol-state journal.
# It closes the fault windows that are specific to an ACKed metadata prewarm:
# - PREWARMED reservations are durable before the success ACK is emitted;
# - an already-retired fast source is persisted through the existing
#   SOURCE_RETIRED recovery snapshot and resumes FAST_COMMIT after restart;
# - generic CLIENT_JOIN cannot manufacture writer truth before peer sync or
#   after the initial A/epoch-1/revision-1 bootstrap;
# - peer process reincarnation is observable and invalidates an ACKed prewarm
#   while the source can still safely fall back before retirement;
# - FAST_COMMIT / COMMITTED replay equality is bound to all P4 fingerprints;
# - only one live reservation may exist for one player/source-epoch/target-epoch.

const P4StateUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P4_STATE_SCHEMA := "distributed_world_simulator.sm0_p4_protocol_recovery.v1"
const P4_STATE_PREFIX := "p4-state-"
const P4_STATE_SUFFIX := ".json"

var _p4_process_incarnation_id := ""
var _p4_peer_process_incarnation_id := ""
var _p4_state_generation := 0
var _p4_committed_fingerprints: Dictionary = {}
var _p4_source_fast: Dictionary = {}
var _p4_fast_source_durable_transfer_id := ""
var _p4_event_sequence := 0


func setup(config: Dictionary) -> Dictionary:
	var effective := config.duplicate(true)
	var requested_p4 := OS.get_environment("SM0_P4_FAST_HANDOFF").strip_edges().to_lower() in ["1", "true", "yes", "on"]
	if requested_p4 and String(effective.get("recovery_dir", "")).strip_edges().is_empty():
		var p4_recovery_root := OS.get_environment("SM0_P4_RECOVERY_DIR").strip_edges()
		if p4_recovery_root.is_empty():
			return _failure("SM0_P4_RECOVERY_DIR_REQUIRED")
		effective["recovery_dir"] = p4_recovery_root

	var authority_hint := String(effective.get("authority_id", "unknown")).get_slice("/", 2)
	_p4_process_incarnation_id = "incarnation/sm0/%s/%d/%d" % [
		authority_hint,
		_p4_now_unix_usec(),
		OS.get_process_id(),
	]
	var result: Dictionary = super.setup(effective)
	if not bool(result.get("success", false)):
		return result
	if not _p4_enabled:
		return result

	# Keep process-local IDs outside the collision range of any restored counter.
	# This is not an ownership fence by itself; it prevents same-id stale replay
	# across process reincarnation while epoch/revision remain the authority fence.
	var counter_seed := maxi(1, _p4_now_unix_usec() + OS.get_process_id())
	_transfer_counter = maxi(_transfer_counter, counter_seed)
	_p4_prewarm_counter = maxi(_p4_prewarm_counter, counter_seed)

	var restored := _p4_restore_latest_state()
	if not bool(restored.get("success", false)):
		return restored
	_event("SM0_P4_HARDENING_READY", {
		"process_incarnation_id": _p4_process_incarnation_id,
		"state_generation": _p4_state_generation,
		"restored_reservations": _prewarmed_transfers.size(),
		"restored_fast_source": not _p4_source_fast.is_empty(),
	})

	# Recovery.gd restores SOURCE_RETIRED as the legacy COMMIT_SENT shape because
	# that snapshot predates P4. The P4 side journal restores the extra immutable
	# prewarm binding before any process-frame socket poll occurs.
	if (
		_recovery_restored
		and _recovery_last_phase == "SOURCE_RETIRED"
		and not _source_transfer.is_empty()
		and not _p4_source_fast.is_empty()
		and String(_source_transfer.get("transfer_id", "")) == String(_p4_source_fast.get("transfer_id", ""))
	):
		var source_package: Dictionary = Dictionary(_source_transfer.get("package", {}))
		if String(source_package.get("checksum", "")) != String(_p4_source_fast.get("package_checksum", "")):
			return _failure("SM0_P4_RECOVERY_SOURCE_PACKAGE_MISMATCH")
		var source_prewarm: Dictionary = Dictionary(_p4_source_fast.get("prewarm", {}))
		var prewarm_check := Contracts.validate_handoff_prewarm(source_prewarm)
		if not bool(prewarm_check.get("success", false)):
			return _failure("SM0_P4_RECOVERY_SOURCE_PREWARM_INVALID", {"cause": prewarm_check})
		_source_transfer["prewarm"] = source_prewarm.duplicate(true)
		_source_transfer["prewarm_id"] = String(source_prewarm.get("prewarm_id", ""))
		_source_transfer["p4_fast"] = true
		_source_transfer["stage"] = "FAST_COMMIT_SENT"
		_source_transfer["last_send_ms"] = 0
		_source_transfer["retries"] = 0
		_frozen_transfer_id = String(_source_transfer.get("transfer_id", ""))
		_p4_fast_source_durable_transfer_id = String(_source_transfer.get("transfer_id", ""))
		_event("SM0_P4_RECOVERY_FAST_SOURCE_RESUMED", {
			"transfer_id": _p4_fast_source_durable_transfer_id,
			"prewarm_id": String(source_prewarm.get("prewarm_id", "")),
			"directory": _directory,
		})
		_send_p4_fast_commit()
		_send_client_redirect()
	return result


func _event(event_name: String, details: Dictionary = {}) -> void:
	_p4_event_sequence += 1
	var enriched := details.duplicate(true)
	enriched["wall_time_unix_usec"] = _p4_now_unix_usec()
	enriched["process_event_sequence"] = _p4_event_sequence
	if not _p4_process_incarnation_id.is_empty():
		enriched["process_incarnation_id"] = _p4_process_incarnation_id
	super._event(event_name, enriched)


func _send_hello() -> void:
	if not _p4_enabled:
		super._send_hello()
		return
	_send_control("AUTHORITY_HELLO", {
		"authority_id": _authority_id,
		"zone_id": _zone_id,
		"manifest_hash": _manifest_hash,
		"directory": _directory,
		"process_incarnation_id": _p4_process_incarnation_id,
	}, "hello/%s/%d" % [_authority_id.get_slice("/", 2), int(Time.get_ticks_msec() / HELLO_INTERVAL_MS)])


func _handle_authority_hello(request_id: String, payload: Dictionary) -> void:
	if _p4_enabled:
		var peer_incarnation := String(payload.get("process_incarnation_id", "")).strip_edges()
		if peer_incarnation.is_empty():
			_invariant("SM0_P4_PEER_INCARNATION_REQUIRED", payload)
			return
		_p4_record_peer_incarnation(peer_incarnation)
		# Reproduce the base HELLO handling so the ACK carries our incarnation.
		if (
			String(payload.get("authority_id", "")) != _peer_authority_id
			or String(payload.get("zone_id", "")) != _peer_zone_id
			or String(payload.get("manifest_hash", "")) != _manifest_hash
		):
			_invariant("SM0_AUTHORITY_HELLO_MISMATCH", payload)
			return
		_adopt_newer_directory(Dictionary(payload.get("directory", {})))
		if not _peer_synced:
			_peer_synced = true
			_event("SM0_AUTHORITY_PEER_SYNCED", {
				"peer_authority_id": _peer_authority_id,
				"peer_process_incarnation_id": _p4_peer_process_incarnation_id,
				"directory": _directory,
			})
		_log_directory_ready()
		_send_control("AUTHORITY_HELLO_ACK", {
			"authority_id": _authority_id,
			"manifest_hash": _manifest_hash,
			"directory": _directory,
			"process_incarnation_id": _p4_process_incarnation_id,
		}, request_id)
		return
	super._handle_authority_hello(request_id, payload)


func _handle_authority_hello_ack(payload: Dictionary) -> void:
	if _p4_enabled:
		var peer_incarnation := String(payload.get("process_incarnation_id", "")).strip_edges()
		if peer_incarnation.is_empty():
			_invariant("SM0_P4_PEER_INCARNATION_REQUIRED", payload)
			return
		_p4_record_peer_incarnation(peer_incarnation)
	super._handle_authority_hello_ack(payload)


func _p4_record_peer_incarnation(peer_incarnation: String) -> void:
	if peer_incarnation.is_empty():
		return
	var previous := _p4_peer_process_incarnation_id
	_p4_peer_process_incarnation_id = peer_incarnation
	if previous.is_empty() or previous == peer_incarnation:
		return
	_event("SM0_P4_PEER_REINCARNATED", {
		"previous_process_incarnation_id": previous,
		"peer_process_incarnation_id": peer_incarnation,
		"directory": _directory,
	})
	# Before source retirement a newly observed target incarnation invalidates the
	# old ACK locally. Falling back here is safe and avoids trusting an ACK from a
	# process that no longer exists. After retirement we must not resurrect the
	# source; durable target reservation recovery handles that race instead.
	if (
		_source_transfer.is_empty()
		and not _source_prewarm.is_empty()
		and String(_source_prewarm.get("stage", "")) == "ACKED"
	):
		_p4_cancel_source_prewarm("peer-reincarnated")


func _handle_client_join(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if not _p4_enabled:
		super._handle_client_join(request_id, payload, remote_ip, remote_port)
		return
	if not _peer_synced:
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
			"error_code": "SM0_P4_JOIN_REQUIRES_PEER_SYNC",
			"directory": _directory,
		}, request_id)
		_event("SM0_P4_JOIN_BLOCKED", {"reason": "PEER_NOT_SYNCED", "directory": _directory})
		return
	var initial_bootstrap := (
		_authority_id == Contracts.AUTHORITY_A
		and String(_directory.get("owner_authority_id", "")) == Contracts.AUTHORITY_A
		and int(_directory.get("authority_epoch", 0)) == 1
		and int(_directory.get("revision", 0)) == 1
	)
	if String(_directory.get("owner_authority_id", "")) == _authority_id and not initial_bootstrap:
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
			"error_code": "SM0_P4_JOIN_REQUIRES_COMMITTED_ACTIVATION",
			"directory": _directory,
		}, request_id)
		_event("SM0_P4_JOIN_BLOCKED", {"reason": "POST_BOOTSTRAP_OWNER", "directory": _directory})
		return
	super._handle_client_join(request_id, payload, remote_ip, remote_port)


func _handle_client_activate(request_id: String, payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	if _p4_enabled and not _peer_synced:
		_send_gameplay(remote_ip, remote_port, "SM0_ERROR", {
			"error_code": "SM0_P4_ACTIVATE_REQUIRES_PEER_SYNC",
			"directory": _directory,
		}, request_id)
		return
	super._handle_client_activate(request_id, payload, remote_ip, remote_port)


func _handle_p4_prewarm(request_id: String, payload: Dictionary) -> void:
	var incoming: Dictionary = Dictionary(payload.get("prewarm", {}))
	var incoming_id := String(incoming.get("prewarm_id", ""))
	_p4_purge_expired_reservations(Time.get_ticks_msec())
	if not incoming_id.is_empty() and not _prewarmed_transfers.has(incoming_id):
		for key in _prewarmed_transfers.keys():
			var existing: Dictionary = Dictionary(_prewarmed_transfers[key])
			var existing_prewarm: Dictionary = Dictionary(existing.get("prewarm", {}))
			if _p4_same_reservation_slot(existing_prewarm, incoming):
				_send_p4_prewarmed(request_id, incoming, false, "SM0_HANDOFF_PREWARM_PLAYER_EPOCH_CONFLICT")
				return
	super._handle_p4_prewarm(request_id, payload)


func _send_p4_prewarmed(request_id: String, prewarm: Dictionary, success: bool, error_code: String) -> void:
	if not _p4_enabled or not success:
		super._send_p4_prewarmed(request_id, prewarm, success, error_code)
		return
	var prewarm_id := String(prewarm.get("prewarm_id", ""))
	if not _prewarmed_transfers.has(prewarm_id):
		super._send_p4_prewarmed(request_id, prewarm, false, "SM0_P4_PREWARM_RESERVATION_REQUIRED")
		return
	var reservation: Dictionary = Dictionary(_prewarmed_transfers[prewarm_id])
	if int(reservation.get("expires_at_unix_usec", 0)) <= 0:
		var remaining_ms := maxi(1, int(reservation.get("expires_at_local_ms", 0)) - Time.get_ticks_msec())
		reservation["expires_at_unix_usec"] = _p4_now_unix_usec() + remaining_ms * 1000
	reservation["durable"] = true
	_prewarmed_transfers[prewarm_id] = reservation
	var persisted := _p4_persist_state("PREWARM_RESERVED", prewarm_id)
	if not bool(persisted.get("success", false)):
		_prewarmed_transfers.erase(prewarm_id)
		_invariant("SM0_P4_PREWARM_PERSIST_FAILED", {"prewarm_id": prewarm_id, "cause": persisted})
		super._send_p4_prewarmed(request_id, prewarm, false, "SM0_P4_PREWARM_DURABILITY_FAILED")
		return
	_send_control("PLAYER_HANDOFF_PREWARMED", {
		"success": true,
		"error_code": "",
		"prewarm_id": prewarm_id,
		"prewarm_checksum": String(prewarm.get("checksum", "")),
		"target_process_incarnation_id": _p4_process_incarnation_id,
	}, request_id)


func _handle_p4_prewarmed(request_id: String, payload: Dictionary) -> void:
	if _p4_enabled and bool(payload.get("success", false)):
		var ack_incarnation := String(payload.get("target_process_incarnation_id", "")).strip_edges()
		if (
			ack_incarnation.is_empty()
			or (not _p4_peer_process_incarnation_id.is_empty() and ack_incarnation != _p4_peer_process_incarnation_id)
		):
			_event("SM0_P4_PREWARM_REJECTED", {
				"prewarm_id": String(payload.get("prewarm_id", "")),
				"error_code": "SM0_P4_PREWARM_ACK_INCARNATION_MISMATCH",
				"ack_process_incarnation_id": ack_incarnation,
				"peer_process_incarnation_id": _p4_peer_process_incarnation_id,
			})
			_source_prewarm.clear()
			return
	super._handle_p4_prewarmed(request_id, payload)
	if not _source_prewarm.is_empty() and String(_source_prewarm.get("stage", "")) == "ACKED":
		_source_prewarm["target_process_incarnation_id"] = String(payload.get("target_process_incarnation_id", ""))


func _handle_p4_prewarm_cancel(payload: Dictionary) -> void:
	var prewarm_id := String(payload.get("prewarm_id", ""))
	var existed := _prewarmed_transfers.has(prewarm_id)
	super._handle_p4_prewarm_cancel(payload)
	if existed and not _prewarmed_transfers.has(prewarm_id):
		var persisted := _p4_persist_state("PREWARM_CANCELLED", prewarm_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_P4_PREWARM_CANCEL_PERSIST_FAILED", {"prewarm_id": prewarm_id, "cause": persisted})


func _p4_purge_expired_reservations(now: int) -> void:
	var before := _prewarmed_transfers.size()
	super._p4_purge_expired_reservations(now)
	if _p4_enabled and _prewarmed_transfers.size() != before and not _recovery_authority_dir.is_empty():
		var persisted := _p4_persist_state("PREWARM_EXPIRED", "")
		if not bool(persisted.get("success", false)):
			_invariant("SM0_P4_PREWARM_EXPIRY_PERSIST_FAILED", {"cause": persisted})


func _send_p4_fast_commit() -> void:
	if _p4_enabled and not _source_transfer.is_empty() and bool(_source_transfer.get("p4_fast", false)):
		var durable := _p4_ensure_fast_source_durable()
		if not bool(durable.get("success", false)):
			_invariant("SM0_P4_FAST_SOURCE_DURABILITY_FAILED", {
				"transfer_id": String(_source_transfer.get("transfer_id", "")),
				"cause": durable,
			})
			return
	super._send_p4_fast_commit()


func _p4_ensure_fast_source_durable() -> Dictionary:
	var transfer_id := String(_source_transfer.get("transfer_id", ""))
	if transfer_id.is_empty():
		return _failure("SM0_P4_FAST_SOURCE_TRANSFER_REQUIRED")
	if _p4_fast_source_durable_transfer_id == transfer_id:
		return _success({"replay": true})
	var package: Dictionary = Dictionary(_source_transfer.get("package", {}))
	var prewarm: Dictionary = Dictionary(_source_transfer.get("prewarm", {}))
	_p4_source_fast = {
		"transfer_id": transfer_id,
		"package_checksum": String(package.get("checksum", "")),
		"prewarm": prewarm.duplicate(true),
	}
	var p4_persisted := _p4_persist_state("SOURCE_FAST_RETIRED", transfer_id)
	if not bool(p4_persisted.get("success", false)):
		return p4_persisted

	# Reuse the existing canonical SOURCE_RETIRED snapshot. Its legacy schema
	# understands COMMIT_SENT; the P4 side journal restores the P4-only metadata.
	var actual_stage := String(_source_transfer.get("stage", ""))
	_source_transfer["stage"] = "COMMIT_SENT"
	var canonical_persisted := _ensure_source_retire_persisted(transfer_id)
	_source_transfer["stage"] = actual_stage
	if not bool(canonical_persisted.get("success", false)):
		return canonical_persisted
	_p4_fast_source_durable_transfer_id = transfer_id
	_event("SM0_P4_FAST_SOURCE_DURABLE", {
		"transfer_id": transfer_id,
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"directory": _directory,
	})
	return _success()


func _handle_p4_fast_commit(request_id: String, payload: Dictionary) -> void:
	var transfer_id := String(payload.get("transfer_id", ""))
	if _p4_enabled and (_committed_transfers.has(transfer_id) or _p4_committed_fingerprints.has(transfer_id)):
		var incoming := _p4_fast_fingerprint_from_payload(payload)
		var expected := _p4_expected_committed_fingerprint(transfer_id)
		if expected.is_empty() or incoming != expected:
			_send_p4_fast_committed(request_id, transfer_id, false, "SM0_P4_FAST_COMMIT_CONFLICT")
			return
	super._handle_p4_fast_commit(request_id, payload)


func _send_p4_fast_committed(request_id: String, transfer_id: String, success: bool, error_code: String) -> void:
	if not _p4_enabled or not success:
		super._send_p4_fast_committed(request_id, transfer_id, success, error_code)
		return
	if not _committed_transfers.has(transfer_id):
		_invariant("SM0_P4_COMMITTED_FINGERPRINT_SOURCE_REQUIRED", {"transfer_id": transfer_id})
		return
	var committed: Dictionary = Dictionary(_committed_transfers[transfer_id])
	var fingerprint_entry := _p4_fingerprint_entry_from_committed(committed)
	if fingerprint_entry.is_empty():
		_invariant("SM0_P4_COMMITTED_FINGERPRINT_INVALID", {"transfer_id": transfer_id})
		return
	_p4_committed_fingerprints[transfer_id] = fingerprint_entry.duplicate(true)
	var persisted := _p4_persist_state("TARGET_FAST_COMMITTED", transfer_id)
	if not bool(persisted.get("success", false)):
		_invariant("SM0_P4_COMMITTED_FINGERPRINT_PERSIST_FAILED", {"transfer_id": transfer_id, "cause": persisted})
		return
	_send_control("PLAYER_HANDOFF_COMMITTED", {
		"success": true,
		"error_code": "",
		"transfer_id": transfer_id,
		"directory": _directory,
		"path": "P4_FAST",
		"package_checksum": String(fingerprint_entry.get("package_checksum", "")),
		"prewarm_id": String(fingerprint_entry.get("prewarm_id", "")),
		"prewarm_checksum": String(fingerprint_entry.get("prewarm_checksum", "")),
		"directory_checksum": String(fingerprint_entry.get("directory_checksum", "")),
		"commit_fingerprint": String(fingerprint_entry.get("commit_fingerprint", "")),
		"target_process_incarnation_id": _p4_process_incarnation_id,
	}, request_id)


func _handle_handoff_committed(request_id: String, payload: Dictionary) -> void:
	if (
		_p4_enabled
		and not _source_transfer.is_empty()
		and bool(_source_transfer.get("p4_fast", false))
		and String(payload.get("transfer_id", "")) == String(_source_transfer.get("transfer_id", ""))
		and bool(payload.get("success", false))
	):
		var package: Dictionary = Dictionary(_source_transfer.get("package", {}))
		var prewarm: Dictionary = Dictionary(_source_transfer.get("prewarm", {}))
		var expected_directory_checksum := String(_directory.get("checksum", ""))
		var expected_fingerprint := _p4_compose_commit_fingerprint(
			String(package.get("checksum", "")),
			String(prewarm.get("prewarm_id", "")),
			String(prewarm.get("checksum", "")),
			expected_directory_checksum
		)
		if (
			String(payload.get("package_checksum", "")) != String(package.get("checksum", ""))
			or String(payload.get("prewarm_id", "")) != String(prewarm.get("prewarm_id", ""))
			or String(payload.get("prewarm_checksum", "")) != String(prewarm.get("checksum", ""))
			or String(payload.get("directory_checksum", "")) != expected_directory_checksum
			or String(payload.get("commit_fingerprint", "")) != expected_fingerprint
		):
			_invariant("SM0_P4_COMMITTED_ACK_FINGERPRINT_MISMATCH", payload)
			return
		var ack_incarnation := String(payload.get("target_process_incarnation_id", ""))
		if not ack_incarnation.is_empty() and ack_incarnation != String(_source_transfer.get("target_process_incarnation_id", _p4_peer_process_incarnation_id)):
			_event("SM0_P4_COMMITTED_BY_REINCARNATED_TARGET", {
				"transfer_id": String(payload.get("transfer_id", "")),
				"target_process_incarnation_id": ack_incarnation,
			})
	super._handle_handoff_committed(request_id, payload)


func _try_finish_source_transfer_tracking() -> void:
	var transfer_id := String(_source_transfer.get("transfer_id", "")) if not _source_transfer.is_empty() else ""
	super._try_finish_source_transfer_tracking()
	if (
		_p4_enabled
		and not transfer_id.is_empty()
		and _source_transfer.is_empty()
		and String(_p4_source_fast.get("transfer_id", "")) == transfer_id
	):
		_p4_source_fast.clear()
		_p4_fast_source_durable_transfer_id = ""
		var persisted := _p4_persist_state("SOURCE_FAST_COMPLETE", transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_P4_SOURCE_FAST_COMPLETE_PERSIST_FAILED", {"transfer_id": transfer_id, "cause": persisted})


func _p4_same_reservation_slot(a: Dictionary, b: Dictionary) -> bool:
	return (
		String(a.get("logical_player_id", "")) == String(b.get("logical_player_id", ""))
		and String(a.get("player_entity_id", "")) == String(b.get("player_entity_id", ""))
		and String(a.get("source_authority_id", "")) == String(b.get("source_authority_id", ""))
		and String(a.get("target_authority_id", "")) == String(b.get("target_authority_id", ""))
		and int(a.get("source_authority_epoch", 0)) == int(b.get("source_authority_epoch", 0))
		and int(a.get("target_authority_epoch", 0)) == int(b.get("target_authority_epoch", 0))
	)


func _p4_fingerprint_entry_from_committed(committed: Dictionary) -> Dictionary:
	var package: Dictionary = Dictionary(committed.get("package", {}))
	var directory: Dictionary = Dictionary(committed.get("directory", {}))
	var package_checksum := String(package.get("checksum", ""))
	var prewarm_id := String(committed.get("prewarm_id", ""))
	var prewarm_checksum := String(committed.get("prewarm_checksum", ""))
	var directory_checksum := String(directory.get("checksum", ""))
	if package_checksum.is_empty() or prewarm_id.is_empty() or prewarm_checksum.is_empty() or directory_checksum.is_empty():
		return {}
	return {
		"package_checksum": package_checksum,
		"prewarm_id": prewarm_id,
		"prewarm_checksum": prewarm_checksum,
		"directory_checksum": directory_checksum,
		"commit_fingerprint": _p4_compose_commit_fingerprint(package_checksum, prewarm_id, prewarm_checksum, directory_checksum),
	}


func _p4_expected_committed_fingerprint(transfer_id: String) -> String:
	if _p4_committed_fingerprints.has(transfer_id):
		return String(Dictionary(_p4_committed_fingerprints[transfer_id]).get("commit_fingerprint", ""))
	if _committed_transfers.has(transfer_id):
		return String(_p4_fingerprint_entry_from_committed(Dictionary(_committed_transfers[transfer_id])).get("commit_fingerprint", ""))
	return ""


func _p4_fast_fingerprint_from_payload(payload: Dictionary) -> String:
	var package: Dictionary = Dictionary(payload.get("package", {}))
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	return _p4_compose_commit_fingerprint(
		String(package.get("checksum", "")),
		String(payload.get("prewarm_id", "")),
		String(payload.get("prewarm_checksum", "")),
		String(directory.get("checksum", ""))
	)


func _p4_compose_commit_fingerprint(package_checksum: String, prewarm_id: String, prewarm_checksum: String, directory_checksum: String) -> String:
	return "%s|%s|%s|%s".format([package_checksum, prewarm_id, prewarm_checksum, directory_checksum], "%s").sha256_text()


func _p4_persist_state(phase: String, subject_id: String) -> Dictionary:
	if not _p4_enabled:
		return _success({"persistence": "disabled"})
	if _recovery_authority_dir.is_empty():
		return _failure("SM0_P4_RECOVERY_DIRECTORY_NOT_READY")
	var next_generation := _p4_state_generation + 1
	var persisted_reservations: Dictionary = {}
	for key in _prewarmed_transfers.keys():
		var prewarm_id := String(key)
		var reservation: Dictionary = Dictionary(_prewarmed_transfers[key])
		var prewarm: Dictionary = Dictionary(reservation.get("prewarm", {}))
		var expires_unix := int(reservation.get("expires_at_unix_usec", 0))
		if expires_unix <= 0:
			var remaining_ms := maxi(1, int(reservation.get("expires_at_local_ms", 0)) - Time.get_ticks_msec())
			expires_unix = _p4_now_unix_usec() + remaining_ms * 1000
		persisted_reservations[prewarm_id] = {
			"prewarm": prewarm.duplicate(true),
			"expires_at_unix_usec": expires_unix,
		}
	var snapshot := {
		"schema": P4_STATE_SCHEMA,
		"generation": next_generation,
		"authority_id": _authority_id,
		"phase": phase,
		"subject_id": subject_id,
		"directory": _directory.duplicate(true),
		"reservations": persisted_reservations,
		"committed_fingerprints": _p4_committed_fingerprints.duplicate(true),
		"source_fast": _p4_source_fast.duplicate(true),
		"checksum": "",
	}
	snapshot = P4StateUtils.finalize_json_checksum(snapshot)
	var validation := _p4_validate_state_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var filename := "%s%08d%s" % [P4_STATE_PREFIX, next_generation, P4_STATE_SUFFIX]
	var final_path := _recovery_authority_dir.path_join(filename)
	var temp_path := "%s.tmp" % final_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("SM0_P4_STATE_OPEN_FAILED", {"path": temp_path, "error": FileAccess.get_open_error()})
	file.store_string(JSON.stringify(snapshot, "", false, true))
	file.flush()
	file.close()
	var rename_error := DirAccess.rename_absolute(temp_path, final_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return _failure("SM0_P4_STATE_RENAME_FAILED", {"path": final_path, "error": rename_error})
	_p4_state_generation = next_generation
	_event("SM0_P4_STATE_PERSISTED", {
		"generation": _p4_state_generation,
		"phase": phase,
		"subject_id": subject_id,
		"reservation_count": persisted_reservations.size(),
		"path": final_path,
	})
	return _success({"generation": _p4_state_generation, "path": final_path})


func _p4_restore_latest_state() -> Dictionary:
	if not _p4_enabled or _recovery_authority_dir.is_empty():
		return _success({"restored": false})
	var dir := DirAccess.open(_recovery_authority_dir)
	if dir == null:
		return _failure("SM0_P4_STATE_DIRECTORY_OPEN_FAILED", {"path": _recovery_authority_dir})
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.begins_with(P4_STATE_PREFIX) and name.ends_with(P4_STATE_SUFFIX):
			candidates.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	candidates.sort()
	candidates.reverse()
	if candidates.is_empty():
		return _success({"restored": false})
	for candidate in candidates:
		var path := _recovery_authority_dir.path_join(candidate)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var decoded = JSON.parse_string(file.get_as_text())
		file.close()
		if not decoded is Dictionary:
			continue
		var snapshot: Dictionary = Dictionary(decoded)
		var validation := _p4_validate_state_snapshot(snapshot)
		if not bool(validation.get("success", false)):
			continue
		var restored_directory: Dictionary = Dictionary(snapshot.get("directory", {}))
		if int(restored_directory.get("revision", 0)) > int(_directory.get("revision", 0)):
			_directory = restored_directory.duplicate(true)
		_p4_state_generation = int(snapshot.get("generation", 0))
		_p4_committed_fingerprints = Dictionary(snapshot.get("committed_fingerprints", {})).duplicate(true)
		_p4_source_fast = Dictionary(snapshot.get("source_fast", {})).duplicate(true)
		_prewarmed_transfers.clear()
		var now_unix := _p4_now_unix_usec()
		var now_local := Time.get_ticks_msec()
		for key in Dictionary(snapshot.get("reservations", {})).keys():
			var entry: Dictionary = Dictionary(snapshot["reservations"][key])
			var expires_unix := int(entry.get("expires_at_unix_usec", 0))
			if expires_unix <= now_unix:
				continue
			var remaining_ms := maxi(1, int((expires_unix - now_unix) / 1000))
			_prewarmed_transfers[String(key)] = {
				"prewarm": Dictionary(entry.get("prewarm", {})).duplicate(true),
				"expires_at_local_ms": now_local + remaining_ms,
				"expires_at_unix_usec": expires_unix,
				"durable": true,
			}
		_event("SM0_P4_STATE_RESTORED", {
			"generation": _p4_state_generation,
			"reservation_count": _prewarmed_transfers.size(),
			"source_fast": not _p4_source_fast.is_empty(),
			"path": path,
			"directory": _directory,
		})
		return _success({"restored": true, "generation": _p4_state_generation, "path": path})
	return _failure("SM0_P4_STATE_NO_VALID_SNAPSHOT")


func _p4_validate_state_snapshot(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != P4_STATE_SCHEMA:
		return _failure("SM0_P4_STATE_SCHEMA_INVALID")
	if String(value.get("authority_id", "")) != _authority_id:
		return _failure("SM0_P4_STATE_AUTHORITY_MISMATCH")
	if int(value.get("generation", 0)) < 1:
		return _failure("SM0_P4_STATE_GENERATION_INVALID")
	var directory: Dictionary = Dictionary(value.get("directory", {}))
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		return _failure("SM0_P4_STATE_DIRECTORY_INVALID", {"cause": directory_check})
	if typeof(value.get("reservations", {})) != TYPE_DICTIONARY or typeof(value.get("committed_fingerprints", {})) != TYPE_DICTIONARY:
		return _failure("SM0_P4_STATE_MAP_INVALID")
	for key in Dictionary(value.get("reservations", {})).keys():
		var entry_value = value["reservations"][key]
		if not entry_value is Dictionary:
			return _failure("SM0_P4_STATE_RESERVATION_INVALID", {"prewarm_id": String(key)})
		var entry: Dictionary = Dictionary(entry_value)
		var prewarm: Dictionary = Dictionary(entry.get("prewarm", {}))
		var prewarm_check := Contracts.validate_handoff_prewarm(prewarm)
		if (
			not bool(prewarm_check.get("success", false))
			or String(prewarm.get("prewarm_id", "")) != String(key)
			or String(prewarm.get("target_authority_id", "")) != _authority_id
			or int(entry.get("expires_at_unix_usec", 0)) <= 0
		):
			return _failure("SM0_P4_STATE_RESERVATION_INVALID", {"prewarm_id": String(key)})
	var source_fast: Dictionary = Dictionary(value.get("source_fast", {}))
	if not source_fast.is_empty():
		var source_prewarm: Dictionary = Dictionary(source_fast.get("prewarm", {}))
		var source_check := Contracts.validate_handoff_prewarm(source_prewarm)
		if (
			not bool(source_check.get("success", false))
			or String(source_fast.get("transfer_id", "")).is_empty()
			or String(source_fast.get("package_checksum", "")).is_empty()
			or String(source_prewarm.get("source_authority_id", "")) != _authority_id
		):
			return _failure("SM0_P4_STATE_SOURCE_FAST_INVALID")
	var expected_checksum := String(value.get("checksum", ""))
	var checksum_payload := value.duplicate(true)
	checksum_payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != P4StateUtils.payload_hash(checksum_payload):
		return _failure("SM0_P4_STATE_CHECKSUM_MISMATCH")
	return _success()


func _p4_now_unix_usec() -> int:
	return int(Time.get_unix_time_from_system() * 1000000.0)
