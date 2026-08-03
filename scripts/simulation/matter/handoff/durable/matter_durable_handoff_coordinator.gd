extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const FencingToken = preload("res://scripts/simulation/matter/handoff/durable/matter_authority_fencing_token.gd")
const JournalRecord = preload("res://scripts/simulation/matter/handoff/durable/matter_handoff_journal_record.gd")
const Checkpoint = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_checkpoint.gd")
const Repository = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_repository.gd")
const SummaryManifest = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_persistence_manifest.gd")

var _repository = Repository.new()
var _checkpoint: Dictionary = {}
var _lease_duration_ticks := 120
var _renew_after_ticks := 40


func configure(repository_root: String, lease_duration_ticks: int = 120, renew_after_ticks: int = 40) -> Dictionary:
	if lease_duration_ticks < 3 or renew_after_ticks < 1 or renew_after_ticks >= lease_duration_ticks:
		return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_LEASE_POLICY")
	var configured: Dictionary = _repository.configure(repository_root)
	if not bool(configured.get("success", false)):
		return configured
	_lease_duration_ticks = lease_duration_ticks
	_renew_after_ticks = renew_after_ticks
	return MatterUtils.success({
		"lease_duration_ticks": _lease_duration_ticks,
		"renew_after_ticks": _renew_after_ticks,
	})


func initialize(checkpoint_id: String, initial_leases: Array, server_tick: int) -> Dictionary:
	if not _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_ALREADY_INITIALIZED")
	var checkpoint: Dictionary = Checkpoint.create({
		"checkpoint_id": checkpoint_id,
		"generation": 1,
		"server_tick": server_tick,
		"directory_revision": 1,
		"previous_checkpoint_checksum": "",
		"leases": initial_leases,
		"handoff_records": [],
	})
	if checkpoint.is_empty():
		return MatterUtils.failure("INVALID_INITIAL_MATTER_DURABLE_HANDOFF_CHECKPOINT")
	var saved: Dictionary = _repository.save_atomic(checkpoint)
	if not bool(saved.get("success", false)):
		return saved
	_checkpoint = checkpoint
	return MatterUtils.success({"checkpoint": checkpoint.duplicate(true)})


func restore_latest() -> Dictionary:
	var loaded: Dictionary = _repository.load_committed()
	if not bool(loaded.get("success", false)):
		return loaded
	var checkpoint: Dictionary = loaded["details"]["checkpoint"]
	var checked: Dictionary = Checkpoint.validate(checkpoint)
	if not bool(checked.get("success", false)):
		return checked
	_checkpoint = checkpoint.duplicate(true)
	var source: String = String(loaded["details"].get("source", ""))
	if source == "PREVIOUS_RECOVERY":
		var repaired: Dictionary = _repository.repair_active_from_previous()
		if not bool(repaired.get("success", false)):
			_checkpoint.clear()
			return repaired
	return MatterUtils.success({
		"checkpoint": _checkpoint.duplicate(true),
		"source": source,
		"pending_files": Array(loaded["details"].get("pending_files", [])).duplicate(),
	})


func checkpoint() -> Dictionary:
	return _checkpoint.duplicate(true)


func lease(region_id: String) -> Dictionary:
	for raw_lease in Array(_checkpoint.get("leases", [])):
		var current: Dictionary = raw_lease
		if String(current["region_id"]) == region_id.strip_edges().to_lower():
			return current.duplicate(true)
	return {}


func latest_record(transfer_id: String) -> Dictionary:
	var result: Dictionary = {}
	var normalized: String = transfer_id.strip_edges().to_lower()
	for raw_record in Array(_checkpoint.get("handoff_records", [])):
		var record: Dictionary = raw_record
		if String(record["transfer_id"]) == normalized:
			result = record
	return result.duplicate(true)


func validate_write(
	region_id: String,
	owner_id: String,
	authority_epoch: int,
	fencing_token: Dictionary,
	server_tick: int
) -> Dictionary:
	var current: Dictionary = lease(region_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_REGION_NOT_FOUND")
	if String(current["status"]) != Lease.STATUS_ACTIVE:
		return MatterUtils.failure("MATTER_AUTHORITY_HANDOFF_IN_PROGRESS")
	if server_tick >= int(current["expires_at_tick"]):
		return MatterUtils.failure("MATTER_AUTHORITY_LEASE_EXPIRED")
	if String(current["owner_id"]) != owner_id.strip_edges().to_lower():
		return MatterUtils.failure("MATTER_REGION_NOT_OWNED_BY_SERVER")
	if int(current["authority_epoch"]) != authority_epoch:
		return MatterUtils.failure("MATTER_AUTHORITY_EPOCH_MISMATCH")
	if typeof(fencing_token) != TYPE_DICTIONARY:
		return MatterUtils.failure("MATTER_AUTHORITY_FENCING_TOKEN_MISMATCH")
	var token_check: Dictionary = FencingToken.validate(fencing_token)
	if not bool(token_check.get("success", false)) or fencing_token != Dictionary(current["fencing_token"]):
		return MatterUtils.failure("MATTER_AUTHORITY_FENCING_TOKEN_MISMATCH")
	return MatterUtils.success({"lease": current})


func renew_lease(
	region_id: String,
	owner_id: String,
	authority_epoch: int,
	fencing_token: Dictionary,
	transition_id: String,
	server_tick: int
) -> Dictionary:
	var authorized: Dictionary = validate_write(region_id, owner_id, authority_epoch, fencing_token, server_tick)
	if not bool(authorized.get("success", false)):
		return authorized
	var current: Dictionary = authorized["details"]["lease"]
	if server_tick < int(current["renew_after_tick"]):
		return MatterUtils.failure("MATTER_AUTHORITY_LEASE_RENEWAL_TOO_EARLY")
	var renewed: Dictionary = Lease.renew(
		current, transition_id, server_tick, server_tick + _renew_after_ticks,
		server_tick + _lease_duration_ticks
	)
	if renewed.is_empty():
		return MatterUtils.failure("MATTER_AUTHORITY_LEASE_RENEWAL_CREATION_FAILED")
	return _replace_lease_and_commit(current, renewed, server_tick, "renewed")


func claim_expired_lease(
	region_id: String,
	claimant_owner_id: String,
	expected_lease_checksum: String,
	transition_id: String,
	server_tick: int
) -> Dictionary:
	var current: Dictionary = lease(region_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_REGION_NOT_FOUND")
	if String(current["status"]) != Lease.STATUS_ACTIVE:
		return MatterUtils.failure("MATTER_AUTHORITY_HANDOFF_IN_PROGRESS")
	if String(current["checksum"]) != expected_lease_checksum:
		return MatterUtils.failure("MATTER_AUTHORITY_LEASE_CAS_MISMATCH")
	if server_tick < int(current["expires_at_tick"]):
		return MatterUtils.failure("MATTER_AUTHORITY_LEASE_NOT_EXPIRED")
	var claimed: Dictionary = Lease.claim_expired(
		current, claimant_owner_id, transition_id, server_tick,
		server_tick + _renew_after_ticks, server_tick + _lease_duration_ticks
	)
	if claimed.is_empty():
		return MatterUtils.failure("MATTER_AUTHORITY_LEASE_CLAIM_CREATION_FAILED")
	return _replace_lease_and_commit(current, claimed, server_tick, "claimed")


func begin_handoff(
	transfer_id: String,
	region_id: String,
	source_owner_id: String,
	target_owner_id: String,
	expected_authority_epoch: int,
	expected_fencing_token: Dictionary,
	transition_id: String,
	server_tick: int
) -> Dictionary:
	var replay: Dictionary = latest_record(transfer_id)
	if not replay.is_empty():
		var token_valid: bool = typeof(expected_fencing_token) == TYPE_DICTIONARY \
			and bool(FencingToken.validate(expected_fencing_token).get("success", false))
		if String(replay["region_id"]) == region_id.strip_edges().to_lower() \
			and String(replay["source_owner_id"]) == source_owner_id.strip_edges().to_lower() \
			and String(replay["target_owner_id"]) == target_owner_id.strip_edges().to_lower() \
			and int(replay["source_authority_epoch"]) == expected_authority_epoch \
			and token_valid \
			and String(replay["source_fencing_token_checksum"]) == String(expected_fencing_token.get("checksum", "")):
			return MatterUtils.success({"replay": true, "record": replay, "lease": lease(region_id)})
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_ID_CONFLICT")
	var authorized: Dictionary = validate_write(
		region_id, source_owner_id, expected_authority_epoch, expected_fencing_token, server_tick
	)
	if not bool(authorized.get("success", false)):
		return authorized
	if source_owner_id.strip_edges().to_lower() == target_owner_id.strip_edges().to_lower():
		return MatterUtils.failure("MATTER_HANDOFF_TARGET_EQUALS_SOURCE")
	var current: Dictionary = authorized["details"]["lease"]
	var preparing: Dictionary = Lease.create_preparing(
		current, transfer_id, target_owner_id, transition_id, server_tick,
		server_tick + _renew_after_ticks, server_tick + _lease_duration_ticks
	)
	if preparing.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_PREPARING_LEASE_CREATION_FAILED")
	var record: Dictionary = JournalRecord.create_begin(
		transfer_id, region_id, source_owner_id, target_owner_id,
		expected_authority_epoch, int(preparing["lease_revision"]),
		String(expected_fencing_token["checksum"]), transition_id, server_tick
	)
	if record.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_BEGIN_RECORD_CREATION_FAILED")
	var leases: Array = _replace_lease(Array(_checkpoint["leases"]), current, preparing)
	var records: Array = Array(_checkpoint["handoff_records"]).duplicate(true)
	records.append(record)
	var committed: Dictionary = _commit(leases, records, server_tick)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({"replay": false, "record": record, "lease": preparing})


func record_package(
	transfer_id: String,
	package_transport: String,
	package_checksum: String,
	summary_manifest: Dictionary,
	transition_id: String,
	server_tick: int
) -> Dictionary:
	var current: Dictionary = latest_record(transfer_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_NOT_FOUND")
	if not String(current["package_transport"]).is_empty():
		if String(current["package_transport"]) == package_transport \
			and String(current["package_checksum"]) == package_checksum.strip_edges().to_lower() \
			and Dictionary(current["summary_manifest"]) == summary_manifest:
			return MatterUtils.success({"replay": true, "record": current})
		return MatterUtils.failure("MATTER_HANDOFF_DURABLE_PACKAGE_CONFLICT")
	if String(current["phase"]) != JournalRecord.PHASE_BEGIN:
		return MatterUtils.failure("MATTER_HANDOFF_PACKAGE_PHASE_MISMATCH")
	if package_transport.is_empty() or not MatterUtils.is_lower_hex_64(package_checksum):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_DURABLE_PACKAGE")
	var manifest_check: Dictionary = _validate_summary_manifest_for_transfer(current, summary_manifest)
	if not bool(manifest_check.get("success", false)):
		return manifest_check
	var next: Dictionary = JournalRecord.advance(
		current, JournalRecord.PHASE_PACKAGE_DURABLE, transition_id, server_tick, {
			"package_transport": package_transport,
			"package_checksum": package_checksum,
			"summary_manifest": summary_manifest,
		}
	)
	return _append_record_and_commit(next, server_tick)


func mark_target_prepared(
	transfer_id: String,
	target_state_hash: String,
	transition_id: String,
	server_tick: int
) -> Dictionary:
	var current: Dictionary = latest_record(transfer_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_NOT_FOUND")
	if not String(current["target_state_hash"]).is_empty():
		return MatterUtils.success({"replay": true, "record": current}) \
			if String(current["target_state_hash"]) == target_state_hash.strip_edges().to_lower() \
			else MatterUtils.failure("MATTER_HANDOFF_TARGET_PREPARED_CONFLICT")
	if String(current["phase"]) != JournalRecord.PHASE_PACKAGE_DURABLE:
		return MatterUtils.failure("MATTER_HANDOFF_TARGET_PREPARED_PHASE_MISMATCH")
	if not MatterUtils.is_lower_hex_64(target_state_hash):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_TARGET_STATE_HASH")
	var next: Dictionary = JournalRecord.advance(
		current, JournalRecord.PHASE_TARGET_PREPARED, transition_id, server_tick,
		{"target_state_hash": target_state_hash}
	)
	return _append_record_and_commit(next, server_tick)


func decide_commit(transfer_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transfer_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_NOT_FOUND")
	if String(current["phase"]) in [JournalRecord.PHASE_COMMIT_DECIDED, JournalRecord.PHASE_COMMITTED]:
		return MatterUtils.success({"replay": true, "record": current})
	if String(current["phase"]) != JournalRecord.PHASE_TARGET_PREPARED:
		return MatterUtils.failure("MATTER_HANDOFF_COMMIT_DECISION_PHASE_MISMATCH")
	var next: Dictionary = JournalRecord.advance(
		current, JournalRecord.PHASE_COMMIT_DECIDED, transition_id, server_tick,
		{"decision": JournalRecord.DECISION_COMMIT}
	)
	return _append_record_and_commit(next, server_tick)


func finalize_commit(transfer_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transfer_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_NOT_FOUND")
	if String(current["phase"]) == JournalRecord.PHASE_COMMITTED:
		return MatterUtils.success({"replay": true, "record": current, "lease": lease(String(current["region_id"]))})
	if String(current["phase"]) != JournalRecord.PHASE_COMMIT_DECIDED:
		return MatterUtils.failure("MATTER_HANDOFF_FINALIZE_COMMIT_PHASE_MISMATCH")
	var preparing: Dictionary = lease(String(current["region_id"]))
	if preparing.is_empty() or String(preparing["active_transfer_id"]) != transfer_id:
		return MatterUtils.failure("MATTER_HANDOFF_PREPARING_LEASE_MISSING")
	var activated: Dictionary = Lease.activate_target(
		preparing, transition_id, server_tick, server_tick + _renew_after_ticks,
		server_tick + _lease_duration_ticks
	)
	if activated.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TARGET_LEASE_ACTIVATION_FAILED")
	var terminal: Dictionary = JournalRecord.advance(
		current, JournalRecord.PHASE_COMMITTED, transition_id, server_tick,
		{"decision": JournalRecord.DECISION_COMMIT}
	)
	if terminal.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_COMMITTED_RECORD_CREATION_FAILED")
	var leases: Array = _replace_lease(Array(_checkpoint["leases"]), preparing, activated)
	var records: Array = Array(_checkpoint["handoff_records"]).duplicate(true)
	records.append(terminal)
	var committed: Dictionary = _commit(leases, records, server_tick)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({"replay": false, "record": terminal, "lease": activated})


func decide_abort(transfer_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transfer_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_NOT_FOUND")
	if String(current["phase"]) in [JournalRecord.PHASE_ABORT_DECIDED, JournalRecord.PHASE_ABORTED]:
		return MatterUtils.success({"replay": true, "record": current})
	if String(current["phase"]) in [JournalRecord.PHASE_COMMIT_DECIDED, JournalRecord.PHASE_COMMITTED]:
		return MatterUtils.failure("MATTER_HANDOFF_COMMIT_DECISION_IS_IRREVERSIBLE")
	if not String(current["phase"]) in [
		JournalRecord.PHASE_BEGIN, JournalRecord.PHASE_PACKAGE_DURABLE,
		JournalRecord.PHASE_TARGET_PREPARED,
	]:
		return MatterUtils.failure("MATTER_HANDOFF_ABORT_DECISION_PHASE_MISMATCH")
	var updates: Dictionary = {"decision": JournalRecord.DECISION_ABORT}
	# A crash immediately after BEGIN has no durable package. The abort chain keeps
	# the empty package fields and remains recoverable without inventing payload bytes.
	var next: Dictionary = JournalRecord.advance(
		current, JournalRecord.PHASE_ABORT_DECIDED, transition_id, server_tick, updates
	)
	return _append_record_and_commit(next, server_tick)


func finalize_abort(transfer_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transfer_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_TRANSFER_NOT_FOUND")
	if String(current["phase"]) == JournalRecord.PHASE_ABORTED:
		return MatterUtils.success({"replay": true, "record": current, "lease": lease(String(current["region_id"]))})
	if String(current["phase"]) != JournalRecord.PHASE_ABORT_DECIDED:
		return MatterUtils.failure("MATTER_HANDOFF_FINALIZE_ABORT_PHASE_MISMATCH")
	var preparing: Dictionary = lease(String(current["region_id"]))
	if preparing.is_empty() or String(preparing["active_transfer_id"]) != transfer_id:
		return MatterUtils.failure("MATTER_HANDOFF_PREPARING_LEASE_MISSING")
	var active: Dictionary = Lease.reactivate_source(
		preparing, transition_id, server_tick, server_tick + _renew_after_ticks,
		server_tick + _lease_duration_ticks
	)
	if active.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_SOURCE_REACTIVATION_FAILED")
	var terminal: Dictionary = JournalRecord.advance(
		current, JournalRecord.PHASE_ABORTED, transition_id, server_tick,
		{"decision": JournalRecord.DECISION_ABORT}
	)
	if terminal.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_ABORTED_RECORD_CREATION_FAILED")
	var leases: Array = _replace_lease(Array(_checkpoint["leases"]), preparing, active)
	var records: Array = Array(_checkpoint["handoff_records"]).duplicate(true)
	records.append(terminal)
	var committed: Dictionary = _commit(leases, records, server_tick)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({"replay": false, "record": terminal, "lease": active})


func recover_incomplete(recovery_id: String, server_tick: int) -> Dictionary:
	if _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_NOT_RESTORED")
	var actions: Array = []
	var incomplete: Array = []
	for raw_lease in _checkpoint["leases"]:
		var current_lease: Dictionary = raw_lease
		if String(current_lease["status"]) == Lease.STATUS_PREPARING:
			incomplete.append(String(current_lease["active_transfer_id"]))
	incomplete.sort()
	var tick: int = server_tick
	for transfer_id in incomplete:
		var record: Dictionary = latest_record(transfer_id)
		if record.is_empty():
			return MatterUtils.failure("MATTER_HANDOFF_RECOVERY_RECORD_MISSING")
		var phase: String = String(record["phase"])
		if phase == JournalRecord.PHASE_COMMIT_DECIDED:
			var committed: Dictionary = finalize_commit(
				transfer_id, "%s-commit-%s" % [recovery_id, transfer_id.replace("/", "-")], tick
			)
			if not bool(committed.get("success", false)):
				return committed
			actions.append({"transfer_id": transfer_id, "action": "COMPLETE_COMMIT"})
			tick += 1
		elif phase == JournalRecord.PHASE_ABORT_DECIDED:
			var aborted: Dictionary = finalize_abort(
				transfer_id, "%s-abort-%s" % [recovery_id, transfer_id.replace("/", "-")], tick
			)
			if not bool(aborted.get("success", false)):
				return aborted
			actions.append({"transfer_id": transfer_id, "action": "COMPLETE_ABORT"})
			tick += 1
		elif phase in [
			JournalRecord.PHASE_BEGIN, JournalRecord.PHASE_PACKAGE_DURABLE,
			JournalRecord.PHASE_TARGET_PREPARED,
		]:
			var decided: Dictionary = decide_abort(
				transfer_id, "%s-decide-abort-%s" % [recovery_id, transfer_id.replace("/", "-")], tick
			)
			if not bool(decided.get("success", false)):
				return decided
			tick += 1
			var finalized: Dictionary = finalize_abort(
				transfer_id, "%s-finalize-abort-%s" % [recovery_id, transfer_id.replace("/", "-")], tick
			)
			if not bool(finalized.get("success", false)):
				return finalized
			actions.append({"transfer_id": transfer_id, "action": "ABORT_UNDECIDED"})
			tick += 1
		else:
			return MatterUtils.failure("MATTER_HANDOFF_RECOVERY_PHASE_INVALID", {"phase": phase})
	return MatterUtils.success({"actions": actions, "checkpoint": _checkpoint.duplicate(true)})


func cleanup_pending_files() -> Dictionary:
	return _repository.cleanup_pending_files()


func repository():
	return _repository


func _append_record_and_commit(next: Dictionary, server_tick: int) -> Dictionary:
	if next.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_JOURNAL_RECORD_CREATION_FAILED")
	var records: Array = Array(_checkpoint["handoff_records"]).duplicate(true)
	records.append(next)
	var committed: Dictionary = _commit(Array(_checkpoint["leases"]), records, server_tick)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({"replay": false, "record": next})


func _replace_lease_and_commit(current: Dictionary, replacement: Dictionary, server_tick: int, result_key: String) -> Dictionary:
	var leases: Array = _replace_lease(Array(_checkpoint["leases"]), current, replacement)
	var committed: Dictionary = _commit(leases, Array(_checkpoint["handoff_records"]), server_tick)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({result_key: replacement, "lease": replacement})


func _commit(leases: Array, records: Array, server_tick: int) -> Dictionary:
	if _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_NOT_INITIALIZED")
	var next: Dictionary = Checkpoint.create({
		"checkpoint_id": _checkpoint["checkpoint_id"],
		"generation": int(_checkpoint["generation"]) + 1,
		"server_tick": server_tick,
		"directory_revision": int(_checkpoint["directory_revision"]) + 1,
		"previous_checkpoint_checksum": _checkpoint["checksum"],
		"leases": leases,
		"handoff_records": records,
	})
	if next.is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_CREATION_FAILED")
	var saved: Dictionary = _repository.save_atomic(next)
	if not bool(saved.get("success", false)):
		return saved
	_checkpoint = next
	return MatterUtils.success({"checkpoint": next.duplicate(true)})


func _replace_lease(leases: Array, current: Dictionary, replacement: Dictionary) -> Array:
	var result: Array = []
	var replaced := false
	for raw_lease in leases:
		var candidate: Dictionary = raw_lease
		if String(candidate["region_id"]) == String(current["region_id"]):
			result.append(replacement.duplicate(true))
			replaced = true
		else:
			result.append(candidate.duplicate(true))
	if not replaced:
		return []
	return result


func _validate_summary_manifest_for_transfer(record: Dictionary, summary_manifest: Dictionary) -> Dictionary:
	if summary_manifest.is_empty():
		return MatterUtils.success({"reusable": false})
	var checked: Dictionary = SummaryManifest.validate(summary_manifest)
	if not bool(checked.get("success", false)):
		return checked
	var current_lease: Dictionary = lease(String(record["region_id"]))
	if current_lease.is_empty():
		return MatterUtils.failure("MATTER_HANDOFF_SUMMARY_REGION_MISSING")
	if String(summary_manifest["body_id"]) != String(current_lease["body_id"]) \
		or Dictionary(summary_manifest["region_root_address"]) != Dictionary(current_lease["region_root_address"]) \
		or String(summary_manifest["grid_profile_hash"]) != String(current_lease["grid_profile_hash"]) \
		or int(summary_manifest["authority_epoch"]) != int(record["source_authority_epoch"]):
		return MatterUtils.failure("MATTER_HANDOFF_SUMMARY_MANIFEST_BINDING_MISMATCH")
	return MatterUtils.success({"reusable": true})
