extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Fixture = preload("res://tests/matter/handoff/mw9_test_fixture.gd")
const Token = preload("res://scripts/simulation/matter/handoff/durable/matter_authority_fencing_token.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const Record = preload("res://scripts/simulation/matter/handoff/durable/matter_handoff_journal_record.gd")
const Checkpoint = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_checkpoint.gd")
const Repository = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_repository.gd")
const Coordinator = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_coordinator.gd")
const Gate = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_regional_authority_gate.gd")
const Projector = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_runtime_projector.gd")
const Mw8Adapter = preload("res://scripts/simulation/matter/handoff/durable/matter_mw8_durable_runtime_adapter.gd")
const RecoveryService = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_recovery_service.gd")
const SummaryManifest = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_persistence_manifest.gd")

var assertions := 0
var failures: Array[String] = []
var _roots: Array[String] = []


class FakeRuntimeAdapter extends RefCounted:
	var calls: Array[String] = []
	var reject_method := ""

	func freeze_handoff(record: Dictionary) -> Dictionary:
		return _apply("freeze_handoff", record)

	func persist_handoff_package(record: Dictionary) -> Dictionary:
		return _apply("persist_handoff_package", record)

	func prepare_handoff_target(record: Dictionary) -> Dictionary:
		return _apply("prepare_handoff_target", record)

	func commit_handoff(record: Dictionary) -> Dictionary:
		return _apply("commit_handoff", record)

	func abort_handoff(record: Dictionary) -> Dictionary:
		return _apply("abort_handoff", record)

	func _apply(method_name: String, record: Dictionary) -> Dictionary:
		calls.append("%s:%s" % [method_name, String(record["phase"])])
		if reject_method == method_name:
			return MatterUtils.failure("FAKE_RUNTIME_REJECTION")
		return MatterUtils.success({"method": method_name})


func _init() -> void:
	_test_config_and_contracts()
	_test_lease_and_fencing()
	_test_successful_handoff_and_commit_recovery()
	_test_undecided_crash_recovery()
	_test_begin_only_crash_recovery()
	_test_repository_atomicity_and_fallback()
	_test_checkpoint_and_journal_fences()
	_test_gate_and_runtime_projection()
	_cleanup()
	if failures.is_empty():
		print("MW9 durable handoff recovery: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MW9 durable handoff recovery: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _test_config_and_contracts() -> void:
	var file := FileAccess.open("res://config/matter/mw9-durable-handoff-recovery.v1.json", FileAccess.READ)
	_assert(file != null, "MW9 config missing")
	if file != null:
		var config = JSON.parse_string(file.get_as_text())
		file.close()
		_assert(typeof(config) == TYPE_DICTIONARY, "MW9 config invalid JSON")
		if typeof(config) == TYPE_DICTIONARY:
			_assert(String(config.get("checkpoint", "")) == "v17.11.0-simulation-mw9-durable-handoff-recovery", "MW9 checkpoint changed")
			_assert(String(config.get("accepted_base", "")) == "v17.10.0-simulation-rl1-matter-summary-pyramid", "MW9 base changed")
			_assert(bool(config.get("durability", {}).get("atomic_active_previous", false)), "Atomic active/previous disabled")
			_assert(bool(config.get("recovery", {}).get("commit_decision_irreversible", false)), "Commit decision is not irreversible")
			_assert(bool(config.get("fencing", {}).get("exact_token_required", false)), "Exact fencing token disabled")
	var root: Dictionary = Fixture.root_address()
	var lease: Dictionary = Fixture.initial_lease()
	var manifest: Dictionary = Fixture.summary_manifest()
	_assert_ok(Lease.validate(lease), "Initial durable lease rejected")
	_assert_ok(Token.validate(lease["fencing_token"]), "Initial fencing token rejected")
	_assert_ok(SummaryManifest.validate(manifest), "RL1 summary manifest fixture rejected")
	_assert(String(manifest["body_id"]) == Fixture.BODY_ID, "Summary manifest body changed")
	_assert(Dictionary(manifest["region_root_address"]) == root, "Summary manifest region changed")
	var begin: Dictionary = Record.create_begin(
		"matter-transfer/contracts", Fixture.REGION_ID, Fixture.SOURCE_OWNER,
		Fixture.TARGET_OWNER, 4, 8, String(Fixture.initial_lease()["fencing_token"]["checksum"]),
		"transition/contracts-begin", 20
	)
	_assert_ok(Record.validate(begin), "BEGIN record rejected")
	_assert(String(begin["phase"]) == Record.PHASE_BEGIN, "BEGIN phase changed")
	_assert(String(begin["decision"]) == Record.DECISION_NONE, "BEGIN decision changed")
	var abort_decided: Dictionary = Record.advance(
		begin, Record.PHASE_ABORT_DECIDED, "transition/contracts-abort", 21,
		{"decision": Record.DECISION_ABORT}
	)
	_assert_ok(Record.validate(abort_decided), "Package-less abort decision rejected")
	_assert_ok(Record.validate_progression(abort_decided, begin), "Package-less abort progression rejected")
	var aborted: Dictionary = Record.advance(
		abort_decided, Record.PHASE_ABORTED, "transition/contracts-aborted", 22,
		{"decision": Record.DECISION_ABORT}
	)
	_assert_ok(Record.validate(aborted), "Package-less abort terminal rejected")
	var bad_begin := begin.duplicate(true)
	bad_begin["package_transport"] = "unexpected"
	bad_begin["checksum"] = MatterUtils.compute_checksum(bad_begin)
	_assert_fail(Record.validate(bad_begin), "BEGIN accepted package bytes")
	var extra := begin.duplicate(true)
	extra["runtime_node"] = "forbidden"
	_assert_fail(Record.validate(extra), "Journal accepted extra runtime field")


func _test_lease_and_fencing() -> void:
	var lease: Dictionary = Fixture.initial_lease(10)
	var token: Dictionary = lease["fencing_token"]
	_assert(String(token["region_id"]) == Fixture.REGION_ID, "Token region changed")
	_assert(String(token["owner_id"]) == Fixture.SOURCE_OWNER, "Token owner changed")
	_assert(int(token["authority_epoch"]) == 4, "Token epoch changed")
	_assert(int(token["lease_revision"]) == 7, "Token revision changed")
	_assert(String(token["token_hash"]) == MatterUtils.payload_hash({
		"schema": Token.SCHEMA,
		"region_id": Fixture.REGION_ID,
		"owner_id": Fixture.SOURCE_OWNER,
		"authority_epoch": 4,
		"lease_revision": 7,
		"transition_id": "transition/mw9-initial",
		"issued_tick": 10,
		"expires_at_tick": 130,
	}), "Token hash changed")
	var renewed: Dictionary = Lease.renew(lease, "transition/renew", 50, 90, 170)
	_assert_ok(Lease.validate(renewed), "Renewed lease rejected")
	_assert(int(renewed["authority_epoch"]) == 4, "Renew changed epoch")
	_assert(int(renewed["lease_revision"]) == 8, "Renew did not advance revision")
	_assert(String(renewed["fencing_token"]["checksum"]) != String(token["checksum"]), "Renew reused fencing token")
	var preparing: Dictionary = Lease.create_preparing(
		renewed, "matter-transfer/lease", Fixture.TARGET_OWNER,
		"transition/prepare", 60, 100, 180
	)
	_assert_ok(Lease.validate(preparing), "Preparing lease rejected")
	_assert(String(preparing["status"]) == Lease.STATUS_PREPARING, "Preparing status changed")
	_assert(String(preparing["owner_id"]) == Fixture.SOURCE_OWNER, "Preparing changed owner before commit")
	_assert(int(preparing["authority_epoch"]) == 4, "Preparing changed epoch before commit")
	var target: Dictionary = Lease.activate_target(preparing, "transition/activate", 70, 110, 190)
	_assert_ok(Lease.validate(target), "Target activation lease rejected")
	_assert(String(target["owner_id"]) == Fixture.TARGET_OWNER, "Target owner not activated")
	_assert(int(target["authority_epoch"]) == 5, "Target epoch not advanced")
	_assert(int(target["lease_revision"]) == 10, "Target lease revision changed unexpectedly")
	var source: Dictionary = Lease.reactivate_source(preparing, "transition/reactivate", 70, 110, 190)
	_assert_ok(Lease.validate(source), "Source reactivation lease rejected")
	_assert(String(source["owner_id"]) == Fixture.SOURCE_OWNER, "Abort changed source owner")
	_assert(int(source["authority_epoch"]) == 4, "Abort advanced source epoch")
	var claimed: Dictionary = Lease.claim_expired(
		lease, Fixture.CLAIM_OWNER, "transition/claim", 130, 170, 250
	)
	_assert_ok(Lease.validate(claimed), "Expired lease claim rejected")
	_assert(String(claimed["owner_id"]) == Fixture.CLAIM_OWNER, "Claim owner changed")
	_assert(int(claimed["authority_epoch"]) == 5, "Claim did not fence old epoch")
	var tampered := token.duplicate(true)
	tampered["expires_at_tick"] = 131
	tampered["checksum"] = MatterUtils.compute_checksum(tampered)
	_assert_fail(Token.validate(tampered), "Token accepted altered binding")


func _test_successful_handoff_and_commit_recovery() -> void:
	var root_path: String = _new_root("commit-recovery")
	var coordinator := Coordinator.new()
	_assert_ok(coordinator.configure(root_path, 120, 40), "Commit coordinator configuration failed")
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, [Fixture.initial_lease()], 10), "Commit coordinator initialization failed")
	var source_lease: Dictionary = coordinator.lease(Fixture.REGION_ID)
	_assert_ok(coordinator.validate_write(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, source_lease["fencing_token"], 20), "Initial source write rejected")
	_assert_fail(coordinator.validate_write(Fixture.REGION_ID, Fixture.TARGET_OWNER, 4, source_lease["fencing_token"], 20), "Target wrote before handoff")
	var checksum_only_token: Dictionary = {"checksum": source_lease["fencing_token"]["checksum"]}
	_assert_fail(coordinator.validate_write(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, checksum_only_token, 20), "Checksum-only forged token authorized")
	var begun: Dictionary = coordinator.begin_handoff(
		"matter-transfer/commit-recovery", Fixture.REGION_ID, Fixture.SOURCE_OWNER,
		Fixture.TARGET_OWNER, 4, source_lease["fencing_token"],
		"transition/commit-begin", 20
	)
	_assert_ok(begun, "Durable handoff begin failed")
	_assert(not bool(begun["details"]["replay"]), "First begin reported replay")
	var exact_begin_replay: Dictionary = coordinator.begin_handoff(
		"matter-transfer/commit-recovery", Fixture.REGION_ID, Fixture.SOURCE_OWNER,
		Fixture.TARGET_OWNER, 4, source_lease["fencing_token"],
		"transition/commit-begin-replay", 20
	)
	_assert_ok(exact_begin_replay, "Exact begin replay failed")
	_assert(bool(exact_begin_replay["details"]["replay"]), "Exact begin replay not identified")
	var foreign_token: Dictionary = Fixture.initial_lease(11)["fencing_token"]
	_assert_fail(coordinator.begin_handoff(
		"matter-transfer/commit-recovery", Fixture.REGION_ID, Fixture.SOURCE_OWNER,
		Fixture.TARGET_OWNER, 4, foreign_token, "transition/foreign-replay", 20
	), "Transfer replay accepted foreign fencing token")
	_assert_fail(coordinator.begin_handoff(
		"matter-transfer/commit-recovery", Fixture.REGION_ID, Fixture.SOURCE_OWNER,
		Fixture.TARGET_OWNER, 5, source_lease["fencing_token"], "transition/epoch-replay", 20
	), "Transfer replay accepted foreign source epoch")
	_assert(String(coordinator.lease(Fixture.REGION_ID)["status"]) == Lease.STATUS_PREPARING, "Source not durably frozen")
	_assert_fail(coordinator.validate_write(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, source_lease["fencing_token"], 21), "Frozen source retained authority")
	_assert_fail(coordinator.validate_write(Fixture.REGION_ID, Fixture.TARGET_OWNER, 5, begun["details"]["lease"]["fencing_token"], 21), "Target activated before commit")
	var manifest: Dictionary = Fixture.summary_manifest()
	var packaged: Dictionary = coordinator.record_package(
		"matter-transfer/commit-recovery", Fixture.package_transport(), Fixture.package_checksum(),
		manifest, "transition/commit-package", 21
	)
	_assert_ok(packaged, "Durable package record failed")
	_assert(String(packaged["details"]["record"]["package_transport_hash"]) == MatterUtils.payload_hash(Fixture.package_transport()), "Package transport hash changed")
	_assert(Dictionary(packaged["details"]["record"]["summary_manifest"]) == manifest, "RL1 manifest not journaled")
	_assert_ok(coordinator.record_package("matter-transfer/commit-recovery", Fixture.package_transport(), Fixture.package_checksum(), manifest, "transition/ignored", 22), "Exact package replay failed")
	_assert_fail(coordinator.record_package("matter-transfer/commit-recovery", Fixture.package_transport("other"), Fixture.package_checksum("other"), {}, "transition/conflict", 22), "Conflicting package replay accepted")
	_assert_ok(coordinator.mark_target_prepared("matter-transfer/commit-recovery", Fixture.target_state_hash(), "transition/target-prepared", 22), "Target prepared proof failed")
	var late_package_replay: Dictionary = coordinator.record_package(
		"matter-transfer/commit-recovery", Fixture.package_transport(), Fixture.package_checksum(),
		manifest, "transition/late-package-replay", 22
	)
	_assert_ok(late_package_replay, "Package replay after target preparation failed")
	_assert(bool(late_package_replay["details"]["replay"]), "Late package replay not identified")
	var prepared_replay: Dictionary = coordinator.mark_target_prepared(
		"matter-transfer/commit-recovery", Fixture.target_state_hash(), "transition/prepared-replay", 22
	)
	_assert_ok(prepared_replay, "Target-prepared replay failed")
	_assert(bool(prepared_replay["details"]["replay"]), "Target-prepared replay not identified")
	_assert_ok(coordinator.decide_commit("matter-transfer/commit-recovery", "transition/commit-decision", 23), "Durable commit decision failed")
	var package_after_decision: Dictionary = coordinator.record_package(
		"matter-transfer/commit-recovery", Fixture.package_transport(), Fixture.package_checksum(),
		manifest, "transition/package-after-decision", 23
	)
	_assert_ok(package_after_decision, "Package replay after commit decision failed")
	_assert(bool(package_after_decision["details"]["replay"]), "Post-decision package replay not identified")
	_assert_fail(coordinator.decide_abort("matter-transfer/commit-recovery", "transition/late-abort", 24), "Abort reversed durable commit decision")
	var before_restart: Dictionary = coordinator.checkpoint()
	_assert(String(coordinator.latest_record("matter-transfer/commit-recovery")["phase"]) == Record.PHASE_COMMIT_DECIDED, "Commit decision phase changed")
	var recovered := Coordinator.new()
	_assert_ok(recovered.configure(root_path, 120, 40), "Recovery coordinator configuration failed")
	var restored: Dictionary = recovered.restore_latest()
	_assert_ok(restored, "Commit-decided checkpoint restore failed")
	_assert(int(restored["details"]["checkpoint"]["generation"]) == int(before_restart["generation"]), "Restore changed checkpoint generation")
	var recovery: Dictionary = recovered.recover_incomplete("recovery/mw9-commit", 30)
	_assert_ok(recovery, "Commit recovery failed")
	_assert(Array(recovery["details"]["actions"]).size() == 1, "Commit recovery action count changed")
	_assert(String(recovery["details"]["actions"][0]["action"]) == "COMPLETE_COMMIT", "Commit recovery selected wrong action")
	var target_lease: Dictionary = recovered.lease(Fixture.REGION_ID)
	_assert(String(target_lease["status"]) == Lease.STATUS_ACTIVE, "Recovered target lease not active")
	_assert(String(target_lease["owner_id"]) == Fixture.TARGET_OWNER, "Recovered target owner changed")
	_assert(int(target_lease["authority_epoch"]) == 5, "Recovered target epoch changed")
	_assert_ok(recovered.validate_write(Fixture.REGION_ID, Fixture.TARGET_OWNER, 5, target_lease["fencing_token"], 31), "Recovered target write rejected")
	_assert_fail(recovered.validate_write(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, source_lease["fencing_token"], 31), "Old owner wrote after recovery commit")
	_assert(String(recovered.latest_record("matter-transfer/commit-recovery")["phase"]) == Record.PHASE_COMMITTED, "Recovery did not append COMMITTED")
	var replay: Dictionary = recovered.finalize_commit("matter-transfer/commit-recovery", "transition/replay-finalize", 32)
	_assert_ok(replay, "Committed replay failed")
	_assert(bool(replay["details"]["replay"]), "Committed replay not identified")
	_assert(int(recovered.checkpoint()["generation"]) == int(recovery["details"]["checkpoint"]["generation"]), "Replay mutated checkpoint")


func _test_undecided_crash_recovery() -> void:
	var root_path: String = _new_root("undecided-abort")
	var coordinator := Coordinator.new()
	_assert_ok(coordinator.configure(root_path, 90, 30), "Abort coordinator configure failed")
	_assert_ok(coordinator.initialize("matter-handoff-checkpoint/abort", [Fixture.initial_lease()], 10), "Abort coordinator initialize failed")
	var source: Dictionary = coordinator.lease(Fixture.REGION_ID)
	_assert_ok(coordinator.begin_handoff("matter-transfer/abort-recovery", Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER, 4, source["fencing_token"], "transition/abort-begin", 20), "Abort fixture begin failed")
	_assert_ok(coordinator.record_package("matter-transfer/abort-recovery", Fixture.package_transport("abort"), Fixture.package_checksum("abort"), {}, "transition/abort-package", 21), "Abort fixture package failed")
	_assert_ok(coordinator.mark_target_prepared("matter-transfer/abort-recovery", Fixture.target_state_hash("abort"), "transition/abort-prepared", 22), "Abort fixture target prepare failed")
	var recovered := Coordinator.new()
	_assert_ok(recovered.configure(root_path, 90, 30), "Abort recovery configure failed")
	_assert_ok(recovered.restore_latest(), "Abort recovery restore failed")
	var recovery: Dictionary = recovered.recover_incomplete("recovery/mw9-abort", 30)
	_assert_ok(recovery, "Undecided target recovery failed")
	_assert(String(recovery["details"]["actions"][0]["action"]) == "ABORT_UNDECIDED", "Undecided transfer was not aborted")
	var active: Dictionary = recovered.lease(Fixture.REGION_ID)
	_assert(String(active["owner_id"]) == Fixture.SOURCE_OWNER, "Undecided recovery changed owner")
	_assert(int(active["authority_epoch"]) == 4, "Undecided recovery advanced epoch")
	_assert(String(active["fencing_token"]["checksum"]) != String(source["fencing_token"]["checksum"]), "Undecided recovery reused old token")
	_assert_ok(recovered.validate_write(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, active["fencing_token"], 31), "Recovered source write rejected")
	_assert_fail(recovered.validate_write(Fixture.REGION_ID, Fixture.TARGET_OWNER, 5, active["fencing_token"], 31), "Aborted target retained authority")
	var record: Dictionary = recovered.latest_record("matter-transfer/abort-recovery")
	_assert(String(record["phase"]) == Record.PHASE_ABORTED, "Undecided recovery not terminal")
	_assert(not String(record["package_transport"]).is_empty(), "Abort recovery lost durable package")
	_assert(String(record["target_state_hash"]) == Fixture.target_state_hash("abort"), "Abort recovery lost target proof")


func _test_begin_only_crash_recovery() -> void:
	var root_path: String = _new_root("begin-only")
	var coordinator := Coordinator.new()
	_assert_ok(coordinator.configure(root_path, 90, 30), "Begin-only configure failed")
	_assert_ok(coordinator.initialize("matter-handoff-checkpoint/begin-only", [Fixture.initial_lease()], 10), "Begin-only initialize failed")
	var source: Dictionary = coordinator.lease(Fixture.REGION_ID)
	_assert_ok(coordinator.begin_handoff("matter-transfer/begin-only", Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER, 4, source["fencing_token"], "transition/begin-only", 20), "Begin-only transfer failed")
	var recovered := Coordinator.new()
	_assert_ok(recovered.configure(root_path, 90, 30), "Begin-only recovery configure failed")
	_assert_ok(recovered.restore_latest(), "Begin-only restore failed")
	_assert_ok(recovered.recover_incomplete("recovery/mw9-begin", 30), "Begin-only recovery failed")
	var record: Dictionary = recovered.latest_record("matter-transfer/begin-only")
	_assert(String(record["phase"]) == Record.PHASE_ABORTED, "Begin-only recovery not aborted")
	_assert(String(record["package_transport"]).is_empty(), "Begin-only recovery invented package")
	_assert(String(record["target_state_hash"]).is_empty(), "Begin-only recovery invented target proof")
	_assert_ok(Record.validate(record), "Begin-only terminal record invalid")


func _test_repository_atomicity_and_fallback() -> void:
	var root_path: String = _new_root("repository")
	var repository := Repository.new()
	_assert_ok(repository.configure(root_path), "Repository configuration failed")
	var first: Dictionary = Checkpoint.create({
		"checkpoint_id": "matter-handoff-checkpoint/repository",
		"generation": 1,
		"server_tick": 10,
		"directory_revision": 1,
		"previous_checkpoint_checksum": "",
		"leases": [Fixture.initial_lease()],
		"handoff_records": [],
	})
	_assert_ok(Checkpoint.validate(first), "Repository first checkpoint invalid")
	_assert_ok(repository.save_atomic(first), "Repository first save failed")
	var old_lease: Dictionary = first["leases"][0]
	var renewed: Dictionary = Lease.renew(old_lease, "transition/repository-renew", 50, 90, 170)
	var second: Dictionary = Checkpoint.create({
		"checkpoint_id": first["checkpoint_id"],
		"generation": 2,
		"server_tick": 50,
		"directory_revision": 2,
		"previous_checkpoint_checksum": first["checksum"],
		"leases": [renewed],
		"handoff_records": [],
	})
	_assert_ok(Checkpoint.validate_progression(second, first), "Repository checkpoint progression rejected")
	var prepared: Dictionary = repository.prepare(second)
	_assert_ok(prepared, "Repository prepare failed")
	_assert(repository.list_pending_files().size() == 1, "Prepared checkpoint not visible")
	var loaded_before: Dictionary = repository.load_committed()
	_assert_ok(loaded_before, "Committed checkpoint unavailable with pending file")
	_assert(int(loaded_before["details"]["checkpoint"]["generation"]) == 1, "Pending checkpoint became visible before commit")
	_assert_ok(repository.commit_prepared(prepared["details"]["pending_path"]), "Prepared commit failed")
	var loaded: Dictionary = repository.load_committed()
	_assert_ok(loaded, "Second checkpoint load failed")
	_assert(int(loaded["details"]["checkpoint"]["generation"]) == 2, "Second generation not active")
	_assert(FileAccess.file_exists(repository.previous_path()), "Previous checkpoint not retained")
	var stale_prepare: Dictionary = repository.prepare(second)
	_assert_ok(stale_prepare, "Stale pending fixture prepare failed")
	_assert_fail(repository.commit_prepared(stale_prepare["details"]["pending_path"]), "Same-generation pending checkpoint committed")
	_assert_ok(repository.cleanup_pending_files(), "Pending cleanup failed")
	_assert(repository.list_pending_files().is_empty(), "Pending files survived cleanup")
	var file := FileAccess.open(repository.active_path(), FileAccess.WRITE)
	_assert(file != null, "Active checkpoint corruption fixture open failed")
	if file != null:
		file.store_string("{corrupted")
		file.close()
	var fallback: Dictionary = repository.load_committed()
	_assert_ok(fallback, "Previous checkpoint fallback failed")
	_assert(String(fallback["details"]["source"]) == "PREVIOUS_RECOVERY", "Corrupt active did not select previous")
	_assert(int(fallback["details"]["checkpoint"]["generation"]) == 1, "Fallback selected wrong generation")
	_assert_ok(repository.repair_active_from_previous(), "Active repair from previous failed")
	var repaired: Dictionary = repository.load_committed()
	_assert_ok(repaired, "Repaired active load failed")
	_assert(String(repaired["details"]["source"]) == "ACTIVE", "Repaired checkpoint not active")
	# A crash can leave only the previous file after active -> previous rename.
	DirAccess.remove_absolute(repository.active_path())
	var missing_active: Dictionary = repository.load_committed()
	_assert_ok(missing_active, "Missing active did not fall back to previous")
	_assert(String(missing_active["details"]["source"]) == "PREVIOUS_RECOVERY", "Missing active was not classified as recovery")
	_assert_ok(repository.repair_active_from_previous(), "Missing active repair failed")
	var lock_probe: Dictionary = repository.call("_acquire_lock")
	_assert_ok(lock_probe, "Repository lock probe acquisition failed")
	var release_probe: Dictionary = repository.call(
		"_release_lock", String(lock_probe.get("details", {}).get("token", ""))
	)
	_assert_ok(release_probe, "Repository lock probe release failed")
	_assert(bool(release_probe.get("details", {}).get("released_atomically", false)), "Repository lock release is not atomic")
	_assert(not bool(release_probe.get("details", {}).get("cleanup_deferred", true)), "Repository lock release left deferred cleanup")
	_assert(not DirAccess.dir_exists_absolute(repository.lock_path()), "Atomic lock release left canonical lock path")
	var stale_lock_path: String = repository.lock_path()
	_assert(DirAccess.make_dir_absolute(stale_lock_path) == OK, "Fresh ownerless lock fixture create failed")
	_assert(not bool(repository.call("_remove_stale_lock")), "Fresh ownerless lock was reclaimed without grace")
	_assert(DirAccess.dir_exists_absolute(stale_lock_path), "Fresh ownerless lock disappeared during grace")
	DirAccess.remove_absolute(stale_lock_path)
	_assert(DirAccess.make_dir_absolute(stale_lock_path) == OK, "Stale lock fixture create failed")
	var stale_owner := FileAccess.open(stale_lock_path.path_join("owner.json"), FileAccess.WRITE)
	_assert(stale_owner != null, "Stale lock owner fixture open failed")
	if stale_owner != null:
		stale_owner.store_string(JSON.stringify({"pid": 2147483647, "token": "stale", "created_unix_ms": 1}))
		stale_owner.close()
	_assert_ok(repository.load_committed(), "Stale repository lock blocked recovery")
	_assert(not DirAccess.dir_exists_absolute(stale_lock_path), "Stale repository lock survived recovery")


func _test_checkpoint_and_journal_fences() -> void:
	var lease: Dictionary = Fixture.initial_lease()
	var first: Dictionary = Checkpoint.create({
		"checkpoint_id": "matter-handoff-checkpoint/fences",
		"generation": 1,
		"server_tick": 10,
		"directory_revision": 1,
		"previous_checkpoint_checksum": "",
		"leases": [lease],
		"handoff_records": [],
	})
	_assert_ok(Checkpoint.validate(first), "Fence checkpoint invalid")
	var rollback_lease: Dictionary = lease.duplicate(true)
	rollback_lease["authority_epoch"] = 3
	rollback_lease["checksum"] = MatterUtils.compute_checksum(rollback_lease)
	var bad_checkpoint: Dictionary = first.duplicate(true)
	bad_checkpoint["leases"] = [rollback_lease]
	bad_checkpoint["checksum"] = MatterUtils.compute_checksum(bad_checkpoint)
	_assert_fail(Checkpoint.validate(bad_checkpoint), "Checkpoint accepted token/lease epoch mismatch")
	var reordered := first.duplicate(true)
	reordered["leases"] = [lease.duplicate(true), lease.duplicate(true)]
	reordered["checksum"] = MatterUtils.compute_checksum(reordered)
	_assert_fail(Checkpoint.validate(reordered), "Checkpoint accepted duplicate region")
	var early_renewed: Dictionary = Lease.renew(lease, "transition/early-renew", 20, 60, 140)
	var early_checkpoint: Dictionary = Checkpoint.create({
		"checkpoint_id": first["checkpoint_id"], "generation": 2, "server_tick": 20,
		"directory_revision": 2, "previous_checkpoint_checksum": first["checksum"],
		"leases": [early_renewed], "handoff_records": [],
	})
	_assert_fail(Checkpoint.validate_progression(early_checkpoint, first), "Checkpoint accepted early lease renewal")
	var early_claim: Dictionary = Lease.claim_expired(lease, Fixture.CLAIM_OWNER, "transition/early-claim", 20, 60, 140)
	var claim_checkpoint: Dictionary = Checkpoint.create({
		"checkpoint_id": first["checkpoint_id"], "generation": 2, "server_tick": 20,
		"directory_revision": 2, "previous_checkpoint_checksum": first["checksum"],
		"leases": [early_claim], "handoff_records": [],
	})
	_assert_fail(Checkpoint.validate_progression(claim_checkpoint, first), "Checkpoint accepted pre-expiry authority claim")
	var begin: Dictionary = Record.create_begin("matter-transfer/fence", Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER, 4, 8, String(Fixture.initial_lease()["fencing_token"]["checksum"]), "transition/fence-begin", 20)
	var package: Dictionary = Record.advance(begin, Record.PHASE_PACKAGE_DURABLE, "transition/fence-package", 21, {
		"package_transport": Fixture.package_transport("fence"),
		"package_checksum": Fixture.package_checksum("fence"),
		"summary_manifest": {},
	})
	_assert_ok(Record.validate_progression(package, begin), "Package record progression rejected")
	var internally_tampered_value: Dictionary = Fixture.package_value("internal-tamper")
	var original_internal_checksum: String = String(internally_tampered_value["checksum"])
	internally_tampered_value["payload_hash"] = MatterUtils.payload_hash("altered-after-checksum")
	var internally_tampered: Dictionary = Record.advance(begin, Record.PHASE_PACKAGE_DURABLE, "transition/internal-tamper", 21, {
		"package_transport": MatterUtils.canonical_json(internally_tampered_value),
		"package_checksum": original_internal_checksum,
		"summary_manifest": {},
	})
	_assert(internally_tampered.is_empty(), "Journal accepted package with forged internal checksum")
	var mutated := package.duplicate(true)
	mutated["package_checksum"] = Fixture.package_checksum("mutated")
	mutated["checksum"] = MatterUtils.compute_checksum(mutated)
	_assert_fail(Record.validate(mutated), "Package accepted checksum inconsistent with immutable transport semantics")
	var target: Dictionary = Record.advance(package, Record.PHASE_TARGET_PREPARED, "transition/fence-target", 22, {"target_state_hash": Fixture.target_state_hash("fence")})
	var aborted: Dictionary = Record.advance(target, Record.PHASE_ABORT_DECIDED, "transition/fence-abort", 23, {"decision": Record.DECISION_ABORT})
	_assert_ok(Record.validate_progression(aborted, target), "Abort after target prepared rejected")
	_assert(String(aborted["package_checksum"]) == String(target["package_checksum"]), "Abort mutated package checksum")
	_assert(String(aborted["target_state_hash"]) == String(target["target_state_hash"]), "Abort dropped target state proof")
	var wrong_previous := aborted.duplicate(true)
	wrong_previous["previous_record_checksum"] = MatterUtils.payload_hash("wrong")
	wrong_previous["checksum"] = MatterUtils.compute_checksum(wrong_previous)
	_assert_fail(Record.validate_progression(wrong_previous, target), "Journal accepted wrong previous checksum")
	var commit_after_abort: Dictionary = Record.advance(aborted, Record.PHASE_COMMITTED, "transition/illegal-commit", 24, {"decision": Record.DECISION_COMMIT})
	_assert(commit_after_abort.is_empty(), "Abort branch advanced to COMMITTED")
	var begin_two: Dictionary = Record.create_begin(
		"matter-transfer/2", Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER,
		4, 8, String(lease["fencing_token"]["checksum"]), "transition/two-begin", 30
	)
	var two_decided: Dictionary = Record.advance(begin_two, Record.PHASE_ABORT_DECIDED, "transition/two-decided", 31, {"decision": Record.DECISION_ABORT})
	var two_aborted: Dictionary = Record.advance(two_decided, Record.PHASE_ABORTED, "transition/two-aborted", 32, {"decision": Record.DECISION_ABORT})
	var begin_ten: Dictionary = Record.create_begin(
		"matter-transfer/10", Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER,
		4, 8, String(lease["fencing_token"]["checksum"]), "transition/ten-begin", 30
	)
	var ten_decided: Dictionary = Record.advance(begin_ten, Record.PHASE_ABORT_DECIDED, "transition/ten-decided", 31, {"decision": Record.DECISION_ABORT})
	var ten_aborted: Dictionary = Record.advance(ten_decided, Record.PHASE_ABORTED, "transition/ten-aborted", 32, {"decision": Record.DECISION_ABORT})
	var lexical: Dictionary = Checkpoint.create({
		"checkpoint_id": "matter-handoff-checkpoint/lexical",
		"generation": 1, "server_tick": 32, "directory_revision": 1,
		"previous_checkpoint_checksum": "", "leases": [lease],
		"handoff_records": [begin_two, two_decided, two_aborted, begin_ten, ten_decided, ten_aborted],
	})
	_assert_ok(Checkpoint.validate(lexical), "Lexically sorted checkpoint rejected")
	_assert(String(lexical["handoff_records"][0]["transfer_id"]) == "matter-transfer/10", "Transfer records use natural instead of canonical lexical ordering")
	_assert(String(lexical["handoff_records"][3]["transfer_id"]) == "matter-transfer/2", "Second lexical transfer order changed")


func _test_gate_and_runtime_projection() -> void:
	var root_path: String = _new_root("gate")
	var coordinator := Coordinator.new()
	_assert_ok(coordinator.configure(root_path, 100, 30), "Gate coordinator configure failed")
	_assert_ok(coordinator.initialize("matter-handoff-checkpoint/gate", [Fixture.initial_lease()], 10), "Gate coordinator initialize failed")
	var gate := Gate.new()
	_assert_fail(gate.authorize(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, {}, 20), "Unconfigured gate authorized")
	_assert_ok(gate.configure(coordinator, func(_region_id, _owner_id, _epoch, request):
		return MatterUtils.failure("LEGACY_GATE_REJECTED") if bool(request.get("reject", false)) else MatterUtils.success()
	), "Durable gate configure failed")
	var lease: Dictionary = coordinator.lease(Fixture.REGION_ID)
	_assert_ok(gate.authorize(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, lease["fencing_token"], 20), "Combined durable/legacy gate rejected")
	_assert_fail(gate.authorize(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, lease["fencing_token"], 20, {"reject": true}), "Legacy rejection bypassed")
	_assert_fail(gate.authorize(Fixture.REGION_ID, Fixture.SOURCE_OWNER, 4, {}, 20), "Durable token fence bypassed")
	_assert_ok(coordinator.begin_handoff("matter-transfer/projector", Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER, 4, lease["fencing_token"], "transition/projector-begin", 21), "Projector begin failed")
	var begin: Dictionary = coordinator.latest_record("matter-transfer/projector")
	var adapter := FakeRuntimeAdapter.new()
	var projector := Projector.new()
	_assert_ok(projector.project(adapter, begin), "BEGIN runtime projection failed")
	_assert(adapter.calls.size() == 1 and String(adapter.calls[0]).begins_with("freeze_handoff"), "BEGIN projected to wrong method")
	var replay: Dictionary = projector.project(adapter, begin)
	_assert_ok(replay, "Runtime projection replay failed")
	_assert(bool(replay["details"]["replay"]), "Runtime replay not detected")
	_assert(adapter.calls.size() == 1, "Runtime replay invoked adapter twice")
	_assert_ok(coordinator.record_package("matter-transfer/projector", Fixture.package_transport("projector"), Fixture.package_checksum("projector"), {}, "transition/projector-package", 22), "Projector package failed")
	var package: Dictionary = coordinator.latest_record("matter-transfer/projector")
	_assert_ok(projector.project(adapter, package), "PACKAGE runtime projection failed")
	_assert(String(adapter.calls[-1]).begins_with("persist_handoff_package"), "PACKAGE projected to wrong method")
	adapter.reject_method = "prepare_handoff_target"
	_assert_ok(coordinator.mark_target_prepared("matter-transfer/projector", Fixture.target_state_hash("projector"), "transition/projector-prepared", 23), "Projector target prepare failed")
	var prepared: Dictionary = coordinator.latest_record("matter-transfer/projector")
	_assert_fail(projector.project(adapter, prepared), "Adapter rejection ignored")
	_assert(projector.applied_checksum("matter-transfer/projector") == String(package["checksum"]), "Failed projection advanced replay frontier")
	adapter.reject_method = ""
	_assert_ok(projector.project(adapter, prepared), "Prepared projection retry failed")
	_assert(projector.applied_checksum("matter-transfer/projector") == String(prepared["checksum"]), "Projection frontier not advanced")
	_assert_ok(coordinator.decide_abort("matter-transfer/projector", "transition/projector-abort", 24), "Bridge abort decision failed")
	_assert_ok(coordinator.finalize_abort("matter-transfer/projector", "transition/projector-aborted", 25), "Bridge abort finalize failed")
	var bridge_calls: Array[String] = []
	var durable_adapter := Mw8Adapter.new()
	_assert_fail(durable_adapter.configure({}), "MW8 durable adapter accepted incomplete callbacks")
	_assert_ok(durable_adapter.configure({
		"synchronize_lease": Callable(self, "_bridge_callback").bind("synchronize_lease", bridge_calls),
		"freeze_handoff": Callable(self, "_bridge_callback").bind("freeze_handoff", bridge_calls),
		"persist_handoff_package": Callable(self, "_bridge_callback").bind("persist_handoff_package", bridge_calls),
		"prepare_handoff_target": Callable(self, "_bridge_callback").bind("prepare_handoff_target", bridge_calls),
		"commit_handoff": Callable(self, "_bridge_callback").bind("commit_handoff", bridge_calls),
		"abort_handoff": Callable(self, "_bridge_callback").bind("abort_handoff", bridge_calls),
	}), "MW8 durable adapter configure failed")
	var recovery_service := RecoveryService.new()
	_assert_ok(recovery_service.configure(coordinator, durable_adapter), "Runtime recovery service configure failed")
	var reconciled: Dictionary = recovery_service.reconcile_runtime()
	_assert_ok(reconciled, "Terminal runtime reconciliation failed")
	_assert(int(reconciled["details"]["lease_count"]) == 1, "Runtime reconciliation lease count changed")
	_assert(int(reconciled["details"]["terminal_transfer_count"]) == 1, "Runtime reconciliation transfer count changed")
	_assert(bridge_calls.count("synchronize_lease:ACTIVE") == 1, "Active durable lease not synchronized")
	_assert(bridge_calls.count("abort_handoff:ABORTED") == 1, "Terminal abort not projected to MW8 bridge")
	_assert(bridge_calls.size() >= 2 and bridge_calls[0] == "abort_handoff:ABORTED" and bridge_calls[1] == "synchronize_lease:ACTIVE", "Runtime recovery synchronized lease before terminal handoff projection")
	_assert_ok(recovery_service.reconcile_runtime(), "Runtime reconciliation replay failed")
	_assert(bridge_calls.count("abort_handoff:ABORTED") == 1, "Runtime reconciliation replay applied abort twice")


func _bridge_callback(value: Dictionary, callback_name: String, calls: Array[String]) -> Dictionary:
	calls.append("%s:%s" % [callback_name, String(value.get("phase", value.get("status", "")))])
	return MatterUtils.success()


func _new_root(label: String) -> String:
	var root: String = "user://mw9-focused-%s-%d" % [label, Time.get_ticks_usec()]
	var global: String = ProjectSettings.globalize_path(root)
	_cleanup_path(global)
	_roots.append(global)
	return root


func _cleanup() -> void:
	for root in _roots:
		_cleanup_path(root)


func _cleanup_path(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_cleanup_path(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", "UNKNOWN"))])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
