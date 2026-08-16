extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_hardened.gd"

# Final P4 closure layer.
#
# This layer adds the two pieces that must outlive ordinary in-memory protocol
# timing without weakening authority fencing:
# 1. canonical replay fingerprint composition + completed-source tombstone;
# 2. durable PREWARM proof retained beyond the *live* reservation TTL.
#
# The 3 s prewarm TTL still controls whether a source may begin a new FAST
# crossing. Once the target has durably validated a prewarm and is about to ACK
# it, however, that fact is kept as a proof until explicit cancel, successful
# commit or a later authority epoch supersedes it. If the target process is down
# longer than the live TTL after the source has already retired, FAST_COMMIT may
# rehydrate a short-lived local reservation only from that durable proof and
# only after all package/directory/checksum fences still match. FAST_COMMIT alone
# can never manufacture the proof.

const P4_PROOF_SCHEMA := "distributed_world_simulator.sm0_p4_prewarm_proofs.v1"
const P4_PROOF_PREFIX := "p4-proof-"
const P4_PROOF_SUFFIX := ".json"
const P4_REHYDRATED_RESERVATION_MS := 5000

var _p4_proof_generation := 0
var _p4_durable_prewarm_proofs: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)) or not _p4_enabled:
		return result

	var proof_restore := _p4_restore_latest_proofs()
	if not bool(proof_restore.get("success", false)):
		return proof_restore
	var proof_prune := _p4_prune_superseded_proofs()
	if not bool(proof_prune.get("success", false)):
		return proof_prune

	var tombstone := _p4_apply_completed_source_tombstone()
	if not bool(tombstone.get("success", false)):
		return tombstone

	_event("SM0_P4_CLOSURE_READY", {
		"proof_generation": _p4_proof_generation,
		"durable_proof_count": _p4_durable_prewarm_proofs.size(),
		"directory": _directory,
	})
	return result


func _p4_compose_commit_fingerprint(
	package_checksum: String,
	prewarm_id: String,
	prewarm_checksum: String,
	directory_checksum: String
) -> String:
	return ("%s|%s|%s|%s" % [
		package_checksum,
		prewarm_id,
		prewarm_checksum,
		directory_checksum,
	]).sha256_text()


func _send_p4_prewarmed(request_id: String, prewarm: Dictionary, success: bool, error_code: String) -> void:
	if not _p4_enabled or not success:
		super._send_p4_prewarmed(request_id, prewarm, success, error_code)
		return

	var prewarm_id := String(prewarm.get("prewarm_id", ""))
	var previous_proofs := _p4_durable_prewarm_proofs.duplicate(true)
	# A new successfully validated reservation supersedes any older proof for the
	# same player/source-target epoch. Live conflicts are rejected earlier by the
	# hardened parent; this only cleans expired durable proof from a prior attempt.
	for key in _p4_durable_prewarm_proofs.keys():
		var existing: Dictionary = Dictionary(_p4_durable_prewarm_proofs[key])
		var existing_prewarm: Dictionary = Dictionary(existing.get("prewarm", {}))
		if String(key) != prewarm_id and _p4_same_reservation_slot(existing_prewarm, prewarm):
			_p4_durable_prewarm_proofs.erase(key)
	_p4_durable_prewarm_proofs[prewarm_id] = {
		"prewarm": prewarm.duplicate(true),
		"accepted_at_unix_usec": _p4_now_unix_usec(),
	}
	var proof_persisted := _p4_persist_proofs("PREWARM_ACKED", prewarm_id)
	if not bool(proof_persisted.get("success", false)):
		_p4_durable_prewarm_proofs = previous_proofs
		_prewarmed_transfers.erase(prewarm_id)
		_invariant("SM0_P4_PREWARM_PROOF_PERSIST_FAILED", {"prewarm_id": prewarm_id, "cause": proof_persisted})
		super._send_p4_prewarmed(request_id, prewarm, false, "SM0_P4_PREWARM_PROOF_DURABILITY_FAILED")
		return

	# Parent now persists the ordinary live reservation before the ACK. If that
	# persistence fails it removes the live reservation and emits a failure ACK;
	# restore the prior proof set so a failed handshake cannot leave a new proof.
	super._send_p4_prewarmed(request_id, prewarm, true, "")
	if not _prewarmed_transfers.has(prewarm_id):
		_p4_durable_prewarm_proofs = previous_proofs
		var cleanup := _p4_persist_proofs("PREWARM_ACK_ABORTED", prewarm_id)
		if not bool(cleanup.get("success", false)):
			_invariant("SM0_P4_PREWARM_PROOF_ABORT_PERSIST_FAILED", {"prewarm_id": prewarm_id, "cause": cleanup})


func _handle_p4_prewarm_cancel(payload: Dictionary) -> void:
	var prewarm_id := String(payload.get("prewarm_id", ""))
	var proof_before: Dictionary = Dictionary(_p4_durable_prewarm_proofs.get(prewarm_id, {}))
	var proof_prewarm: Dictionary = Dictionary(proof_before.get("prewarm", {}))
	var cancel_matches_proof := (
		not proof_before.is_empty()
		and String(payload.get("prewarm_checksum", "")) == String(proof_prewarm.get("checksum", ""))
	)
	super._handle_p4_prewarm_cancel(payload)
	if not cancel_matches_proof:
		return
	var previous_proofs := _p4_durable_prewarm_proofs.duplicate(true)
	_p4_durable_prewarm_proofs.erase(prewarm_id)
	var persisted := _p4_persist_proofs("PREWARM_CANCELLED", prewarm_id)
	if not bool(persisted.get("success", false)):
		_p4_durable_prewarm_proofs = previous_proofs
		_invariant("SM0_P4_PREWARM_PROOF_CANCEL_PERSIST_FAILED", {"prewarm_id": prewarm_id, "cause": persisted})


func _handle_p4_fast_commit(request_id: String, payload: Dictionary) -> void:
	var transfer_id := String(payload.get("transfer_id", ""))
	var prewarm_id := String(payload.get("prewarm_id", ""))
	var rehydrated := false

	# Exact committed replays are handled by the hardened parent first and never
	# need a proof. For an uncommitted transfer with no live reservation, a
	# durable proof is the only legal recovery path.
	if (
		_p4_enabled
		and not _committed_transfers.has(transfer_id)
		and not _prewarmed_transfers.has(prewarm_id)
		and _p4_durable_prewarm_proofs.has(prewarm_id)
	):
		var proof_check := _p4_validate_durable_proof_for_fast_commit(payload)
		if not bool(proof_check.get("success", false)):
			_send_p4_fast_committed(
				request_id,
				transfer_id,
				false,
				String(proof_check.get("error_code", "SM0_P4_FAST_DURABLE_PROOF_INVALID"))
			)
			return
		var proof_entry: Dictionary = Dictionary(_p4_durable_prewarm_proofs[prewarm_id])
		var proof_prewarm: Dictionary = Dictionary(proof_entry.get("prewarm", {}))
		_prewarmed_transfers[prewarm_id] = {
			"prewarm": proof_prewarm.duplicate(true),
			"expires_at_local_ms": Time.get_ticks_msec() + P4_REHYDRATED_RESERVATION_MS,
			"expires_at_unix_usec": _p4_now_unix_usec() + P4_REHYDRATED_RESERVATION_MS * 1000,
			"durable": true,
			"rehydrated_from_proof": true,
		}
		rehydrated = true
		_event("SM0_P4_PREWARM_REHYDRATED_FROM_DURABLE_PROOF", {
			"prewarm_id": prewarm_id,
			"transfer_id": transfer_id,
			"directory": _directory,
		})

	super._handle_p4_fast_commit(request_id, payload)

	if _committed_transfers.has(transfer_id) and _p4_durable_prewarm_proofs.has(prewarm_id):
		var committed: Dictionary = Dictionary(_committed_transfers[transfer_id])
		if String(committed.get("prewarm_id", "")) == prewarm_id:
			var previous_proofs := _p4_durable_prewarm_proofs.duplicate(true)
			_p4_durable_prewarm_proofs.erase(prewarm_id)
			var persisted := _p4_persist_proofs("FAST_COMMITTED", prewarm_id)
			if not bool(persisted.get("success", false)):
				_p4_durable_prewarm_proofs = previous_proofs
				_invariant("SM0_P4_PREWARM_PROOF_COMMIT_CLEANUP_FAILED", {"prewarm_id": prewarm_id, "cause": persisted})
	elif rehydrated and _prewarmed_transfers.has(prewarm_id):
		# A transient activation/persistence failure may retry from the same proof;
		# keep the rehydrated reservation bounded in memory.
		var reservation: Dictionary = Dictionary(_prewarmed_transfers[prewarm_id])
		reservation["expires_at_local_ms"] = mini(
			int(reservation.get("expires_at_local_ms", 0)),
			Time.get_ticks_msec() + P4_REHYDRATED_RESERVATION_MS
		)
		_prewarmed_transfers[prewarm_id] = reservation


func _p4_validate_durable_proof_for_fast_commit(payload: Dictionary) -> Dictionary:
	var prewarm_id := String(payload.get("prewarm_id", ""))
	if prewarm_id.is_empty() or not _p4_durable_prewarm_proofs.has(prewarm_id):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_REQUIRED")
	var proof_entry: Dictionary = Dictionary(_p4_durable_prewarm_proofs[prewarm_id])
	var prewarm: Dictionary = Dictionary(proof_entry.get("prewarm", {}))
	var prewarm_check := Contracts.validate_handoff_prewarm(prewarm)
	if not bool(prewarm_check.get("success", false)):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_INVALID", {"cause": prewarm_check})
	if String(payload.get("prewarm_checksum", "")) != String(prewarm.get("checksum", "")):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_CHECKSUM_MISMATCH")
	var package: Dictionary = Dictionary(payload.get("package", {}))
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	var package_check := Contracts.validate_handoff_package(package)
	if not bool(package_check.get("success", false)):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_PACKAGE_INVALID", {"cause": package_check})
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_DIRECTORY_INVALID", {"cause": directory_check})
	if not _p4_prewarm_matches_package(prewarm, package, directory):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_PACKAGE_MISMATCH")
	if not _p4_target_directory_allows_fast_commit(prewarm, directory):
		return _failure("SM0_P4_FAST_DURABLE_PROOF_STALE_DIRECTORY")

	# A recovered canonical player record is still canonical truth even while its
	# transport session is intentionally disconnected. An old durable PREWARM
	# proof must never overwrite any existing canonical player record unless this
	# transfer is already in _committed_transfers (handled before proof recovery).
	# The valid target-restart recovery snapshot taken at PREWARM_RESERVED has no
	# target player record, so this stronger fence does not block the intended path.
	if _p4_target_has_player_truth():
		return _failure("SM0_P4_FAST_DURABLE_PROOF_TARGET_ALREADY_ACTIVE")
	return _success()


func _p4_target_has_player_truth() -> bool:
	if _authority == null:
		return false
	var player: Dictionary = _authority.get_player("a")
	return not player.is_empty()


func _p4_apply_completed_source_tombstone() -> Dictionary:
	if (
		not _recovery_restored
		or _recovery_last_phase != "SOURCE_RETIRED"
		or _source_transfer.is_empty()
		or _recovery_authority_dir.is_empty()
	):
		return _success({"applied": false})
	var transfer_id := String(_source_transfer.get("transfer_id", ""))
	if transfer_id.is_empty():
		return _success({"applied": false})
	var latest := _p4_latest_valid_side_snapshot()
	if not bool(latest.get("success", false)):
		return latest
	var snapshot: Dictionary = Dictionary(latest.get("details", {}).get("snapshot", {}))
	if snapshot.is_empty():
		return _success({"applied": false})
	if (
		String(snapshot.get("phase", "")) != "SOURCE_FAST_COMPLETE"
		or String(snapshot.get("subject_id", "")) != transfer_id
		or not Dictionary(snapshot.get("source_fast", {})).is_empty()
	):
		return _success({"applied": false})
	_source_transfer.clear()
	_frozen_transfer_id = ""
	_p4_source_fast.clear()
	_p4_fast_source_durable_transfer_id = ""
	_event("SM0_P4_RECOVERY_COMPLETED_SOURCE_TOMBSTONE_APPLIED", {
		"transfer_id": transfer_id,
		"side_generation": int(snapshot.get("generation", 0)),
		"directory": _directory,
	})
	return _success({"applied": true, "transfer_id": transfer_id})


func _p4_latest_valid_side_snapshot() -> Dictionary:
	var dir := DirAccess.open(_recovery_authority_dir)
	if dir == null:
		return _failure("SM0_P4_TOMBSTONE_DIRECTORY_OPEN_FAILED", {"path": _recovery_authority_dir})
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
		return _success({"snapshot": {}})
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
		return _success({"snapshot": snapshot, "path": path})
	return _failure("SM0_P4_TOMBSTONE_NO_VALID_SIDE_SNAPSHOT")


func _p4_persist_proofs(phase: String, subject_id: String) -> Dictionary:
	if _recovery_authority_dir.is_empty():
		return _failure("SM0_P4_PROOF_RECOVERY_DIRECTORY_NOT_READY")
	var next_generation := _p4_proof_generation + 1
	var snapshot := {
		"schema": P4_PROOF_SCHEMA,
		"generation": next_generation,
		"authority_id": _authority_id,
		"phase": phase,
		"subject_id": subject_id,
		"proofs": _p4_durable_prewarm_proofs.duplicate(true),
		"checksum": "",
	}
	snapshot = P4StateUtils.finalize_json_checksum(snapshot)
	var validation := _p4_validate_proof_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var filename := "%s%08d%s" % [P4_PROOF_PREFIX, next_generation, P4_PROOF_SUFFIX]
	var final_path := _recovery_authority_dir.path_join(filename)
	var temp_path := "%s.tmp" % final_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("SM0_P4_PROOF_OPEN_FAILED", {"path": temp_path, "error": FileAccess.get_open_error()})
	file.store_string(JSON.stringify(snapshot, "", false, true))
	file.flush()
	file.close()
	var rename_error := DirAccess.rename_absolute(temp_path, final_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return _failure("SM0_P4_PROOF_RENAME_FAILED", {"path": final_path, "error": rename_error})
	_p4_proof_generation = next_generation
	_event("SM0_P4_PREWARM_PROOFS_PERSISTED", {
		"generation": _p4_proof_generation,
		"phase": phase,
		"subject_id": subject_id,
		"proof_count": _p4_durable_prewarm_proofs.size(),
		"path": final_path,
	})
	return _success({"generation": _p4_proof_generation, "path": final_path})


func _p4_restore_latest_proofs() -> Dictionary:
	if _recovery_authority_dir.is_empty():
		return _failure("SM0_P4_PROOF_RECOVERY_DIRECTORY_NOT_READY")
	var dir := DirAccess.open(_recovery_authority_dir)
	if dir == null:
		return _failure("SM0_P4_PROOF_DIRECTORY_OPEN_FAILED", {"path": _recovery_authority_dir})
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.begins_with(P4_PROOF_PREFIX) and name.ends_with(P4_PROOF_SUFFIX):
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
		var validation := _p4_validate_proof_snapshot(snapshot)
		if not bool(validation.get("success", false)):
			continue
		_p4_proof_generation = int(snapshot.get("generation", 0))
		_p4_durable_prewarm_proofs = Dictionary(snapshot.get("proofs", {})).duplicate(true)
		_event("SM0_P4_PREWARM_PROOFS_RESTORED", {
			"generation": _p4_proof_generation,
			"proof_count": _p4_durable_prewarm_proofs.size(),
			"path": path,
		})
		return _success({"restored": true, "generation": _p4_proof_generation, "path": path})
	return _failure("SM0_P4_PROOF_NO_VALID_SNAPSHOT")


func _p4_validate_proof_snapshot(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != P4_PROOF_SCHEMA:
		return _failure("SM0_P4_PROOF_SCHEMA_INVALID")
	if String(value.get("authority_id", "")) != _authority_id:
		return _failure("SM0_P4_PROOF_AUTHORITY_MISMATCH")
	if int(value.get("generation", 0)) < 1:
		return _failure("SM0_P4_PROOF_GENERATION_INVALID")
	if typeof(value.get("proofs", {})) != TYPE_DICTIONARY:
		return _failure("SM0_P4_PROOF_MAP_INVALID")
	for key in Dictionary(value.get("proofs", {})).keys():
		var entry_value = value["proofs"][key]
		if not entry_value is Dictionary:
			return _failure("SM0_P4_PROOF_ENTRY_INVALID", {"prewarm_id": String(key)})
		var entry: Dictionary = Dictionary(entry_value)
		var prewarm: Dictionary = Dictionary(entry.get("prewarm", {}))
		var prewarm_check := Contracts.validate_handoff_prewarm(prewarm)
		if (
			not bool(prewarm_check.get("success", false))
			or String(prewarm.get("prewarm_id", "")) != String(key)
			or String(prewarm.get("target_authority_id", "")) != _authority_id
			or int(entry.get("accepted_at_unix_usec", 0)) <= 0
		):
			return _failure("SM0_P4_PROOF_ENTRY_INVALID", {"prewarm_id": String(key)})
	var expected_checksum := String(value.get("checksum", ""))
	var checksum_payload := value.duplicate(true)
	checksum_payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != P4StateUtils.payload_hash(checksum_payload):
		return _failure("SM0_P4_PROOF_CHECKSUM_MISMATCH")
	return _success()


func _p4_prune_superseded_proofs() -> Dictionary:
	if _p4_durable_prewarm_proofs.is_empty():
		return _success({"removed": 0})
	var previous_proofs := _p4_durable_prewarm_proofs.duplicate(true)
	var removed := 0
	var current_epoch := int(_directory.get("authority_epoch", 0))
	var current_revision := int(_directory.get("revision", 0))
	var current_owner := String(_directory.get("owner_authority_id", ""))
	for key in _p4_durable_prewarm_proofs.keys():
		var entry: Dictionary = Dictionary(_p4_durable_prewarm_proofs[key])
		var prewarm: Dictionary = Dictionary(entry.get("prewarm", {}))
		var source_revision := int(prewarm.get("source_directory_revision", 0))
		var target_epoch := int(prewarm.get("target_authority_epoch", 0))
		var target_authority := String(prewarm.get("target_authority_id", ""))
		var superseded := (
			current_epoch > target_epoch
			or current_revision > source_revision + 1
			or (
				current_owner == target_authority
				and current_epoch == target_epoch
				and current_revision == source_revision + 1
				and _p4_target_has_player_truth()
			)
		)
		if superseded:
			_p4_durable_prewarm_proofs.erase(key)
			removed += 1
	if removed <= 0:
		return _success({"removed": 0})
	var persisted := _p4_persist_proofs("SUPERSEDED", "")
	if not bool(persisted.get("success", false)):
		_p4_durable_prewarm_proofs = previous_proofs
		return persisted
	_event("SM0_P4_PREWARM_PROOFS_PRUNED", {"removed": removed, "directory": _directory})
	return _success({"removed": removed})
