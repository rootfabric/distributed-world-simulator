extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd"

# H3.3 transaction-durability layer.
#
# A successful PREPARED response is itself a recovery promise: once the source
# is allowed to retire, the target must not forget the exact validated package
# after a process crash. Persist TARGET_PREPARED before that acknowledgement.

const TARGET_PREPARED_PHASE := "TARGET_PREPARED"

var _recovery_persisted_prepares: Dictionary = {}


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if message_type == "PLAYER_HANDOFF_PREPARED" and bool(payload.get("success", false)):
		var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
		var persisted := _ensure_target_prepare_persisted(transfer_id)
		if not bool(persisted.get("success", false)):
			_invariant("SM0_RECOVERY_PERSIST_BEFORE_PREPARED_ACK_FAILED", {
				"transfer_id": transfer_id,
				"cause": persisted,
			})
			return
	super._send_control(message_type, payload, request_id)


func _ensure_target_prepare_persisted(transfer_id: String) -> Dictionary:
	if _recovery_root.is_empty():
		return _success({"persistence": "disabled"})
	if transfer_id.is_empty() or not _prepared_transfers.has(transfer_id):
		return _failure("SM0_RECOVERY_PREPARED_TRANSFER_REQUIRED", {"transfer_id": transfer_id})
	# A delayed exact PREPARE may arrive after this transaction was already
	# committed. Never regress the durable phase back to TARGET_PREPARED.
	if _committed_transfers.has(transfer_id):
		return _success({
			"generation": int(_recovery_persisted_commits.get(transfer_id, _recovery_generation)),
			"replay": true,
			"phase": "TARGET_COMMITTED",
		})
	if _recovery_persisted_prepares.has(transfer_id):
		return _success({
			"generation": int(_recovery_persisted_prepares[transfer_id]),
			"replay": true,
			"phase": TARGET_PREPARED_PHASE,
		})
	var persisted := _persist_recovery_snapshot(TARGET_PREPARED_PHASE, transfer_id)
	if bool(persisted.get("success", false)):
		_recovery_persisted_prepares[transfer_id] = int(
			persisted.get("details", {}).get("generation", _recovery_generation)
		)
		_event("SM0_TARGET_PREPARED_DURABLE", {
			"generation": _recovery_generation,
			"transfer_id": transfer_id,
			"directory": _directory,
		})
	return persisted


func _validate_recovery_snapshot(value: Dictionary) -> Dictionary:
	if String(value.get("phase", "")) != TARGET_PREPARED_PHASE:
		return super._validate_recovery_snapshot(value)

	var expected_checksum := String(value.get("checksum", ""))
	var checksum_payload: Dictionary = value.duplicate(true)
	checksum_payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != RecoveryUtils.payload_hash(checksum_payload):
		return _failure("SM0_RECOVERY_CHECKSUM_MISMATCH")

	# Reuse every established shared-section check by normalizing only the phase.
	# TARGET_COMMITTED validation does not require a committed entry, so this
	# safely validates schema, authority, canonical durable state, transfer maps,
	# replay state and checksum structure before the phase-specific checks below.
	var normalized: Dictionary = value.duplicate(true)
	normalized["phase"] = "TARGET_COMMITTED"
	normalized["source_transfer"] = {}
	normalized["checksum"] = ""
	normalized = RecoveryUtils.finalize_json_checksum(normalized)
	var base_check := super._validate_recovery_snapshot(normalized)
	if not bool(base_check.get("success", false)):
		return _failure("SM0_TARGET_PREPARED_BASE_SNAPSHOT_INVALID", {"cause": base_check})

	if not Dictionary(value.get("source_transfer", {})).is_empty():
		return _failure("SM0_TARGET_PREPARED_SOURCE_TRANSFER_FORBIDDEN")
	var transfer_id := String(value.get("transfer_id", "")).strip_edges()
	if transfer_id.is_empty():
		return _failure("SM0_TARGET_PREPARED_TRANSFER_ID_REQUIRED")
	var prepared: Dictionary = Dictionary(value.get("prepared_transfers", {}))
	var committed: Dictionary = Dictionary(value.get("committed_transfers", {}))
	if not prepared.has(transfer_id):
		return _failure("SM0_TARGET_PREPARED_PACKAGE_MISSING", {"transfer_id": transfer_id})
	if committed.has(transfer_id):
		return _failure("SM0_TARGET_PREPARED_ALREADY_COMMITTED", {"transfer_id": transfer_id})
	var package: Dictionary = Dictionary(prepared[transfer_id])
	var directory: Dictionary = Dictionary(value.get("directory", {}))
	if (
		String(package.get("transfer_id", "")) != transfer_id
		or String(package.get("target_authority_id", "")) != _authority_id
		or String(package.get("source_authority_id", "")) != _peer_authority_id
		or String(directory.get("owner_authority_id", "")) != _peer_authority_id
		or int(directory.get("authority_epoch", 0)) != int(package.get("source_authority_epoch", 0))
		or int(directory.get("revision", 0)) != int(package.get("directory_revision", 0))
	):
		return _failure("SM0_TARGET_PREPARED_ROUTE_INVALID", {"transfer_id": transfer_id})
	return _success()


func _apply_recovery_snapshot(snapshot: Dictionary, path: String) -> Dictionary:
	var result: Dictionary = super._apply_recovery_snapshot(snapshot, path)
	if not bool(result.get("success", false)):
		return result
	if String(snapshot.get("phase", "")) != TARGET_PREPARED_PHASE:
		return result
	var transfer_id := String(snapshot.get("transfer_id", "")).strip_edges()
	if transfer_id.is_empty() or not _prepared_transfers.has(transfer_id):
		return _failure("SM0_RECOVERY_TARGET_PREPARED_NOT_RESTORED", {"transfer_id": transfer_id})
	if _writer_count() != 0:
		return _failure("SM0_RECOVERY_TARGET_PREPARED_WRITER_PRESENT", {"transfer_id": transfer_id})
	_recovery_persisted_prepares[transfer_id] = _recovery_generation
	_event("SM0_RECOVERY_TARGET_PREPARED_PENDING", {
		"generation": _recovery_generation,
		"transfer_id": transfer_id,
		"package_checksum": String(Dictionary(_prepared_transfers[transfer_id]).get("checksum", "")),
		"directory": _directory,
	})
	return result
