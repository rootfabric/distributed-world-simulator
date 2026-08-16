extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const ProofTestServer = preload("res://tests/runtime/seamless/sm0/sm0_p4_durable_proof_test_server.gd")

var _assertions := 0
var _failures: Array[String] = []
var _recovery_root := ""


func _init() -> void:
	_recovery_root = ProjectSettings.globalize_path(
		"user://sm0-p4-proof-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	)
	_test_durable_proof_survives_live_ttl()
	_remove_tree(_recovery_root)
	_finish()


func _test_durable_proof_survives_live_ttl() -> void:
	var fixture := _make_fast_fixture()
	var prewarm: Dictionary = Dictionary(fixture.prewarm)
	var prewarm_id := String(prewarm.get("prewarm_id", ""))
	var transfer_id := String(Dictionary(fixture.package).get("transfer_id", ""))
	var source_directory := Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1)
	var accepted_at_unix_usec: int = int(Time.get_unix_time_from_system() * 1000000.0) - 10_000_000

	var writer = ProofTestServer.new()
	var configured: Dictionary = writer.configure_proof_fixture(_recovery_root, source_directory)
	_assert(bool(configured.get("success", false)), "durable-proof writer fixture configures")
	writer.install_durable_proof(prewarm, accepted_at_unix_usec)
	_assert(not writer.has_live_reservation(prewarm_id), "durable proof is independent from live reservation memory")
	var persisted: Dictionary = writer.persist_proofs("PREWARM_ACKED", prewarm_id)
	_assert(bool(persisted.get("success", false)), "durable proof persists to recovery journal")
	writer.free()

	# Recovery intentionally clears transport sessions, so canonical player truth
	# may exist with connected=false. Any such record must fence an old proof just
	# as strongly as a connected player; transport liveness is not ownership truth.
	var stale_target = ProofTestServer.new()
	configured = stale_target.configure_proof_fixture(_recovery_root, source_directory)
	_assert(bool(configured.get("success", false)), "stale-target fixture configures")
	var restored: Dictionary = stale_target.restore_latest_proofs()
	_assert(bool(restored.get("success", false)), "durable proof restores after process-local reservation loss")
	_assert(stale_target.proof_count() == 1, "restored proof count is one")
	_assert(not stale_target.has_live_reservation(prewarm_id), "restart begins without a live reservation")
	stale_target.force_target_player_truth = true
	stale_target.invoke_fast_commit(Dictionary(fixture.payload))
	_assert(not stale_target.last_fast_commit_success(), "old proof cannot overwrite recovered canonical target truth")
	_assert(stale_target.last_fast_commit_error() == "SM0_P4_FAST_DURABLE_PROOF_TARGET_ALREADY_ACTIVE", "existing-target-truth proof rejection is classified")
	_assert(stale_target.fake_activation_count == 0, "existing canonical truth rejects proof before import")
	stale_target.free()

	var bad_checksum = ProofTestServer.new()
	configured = bad_checksum.configure_proof_fixture(_recovery_root, source_directory)
	_assert(bool(configured.get("success", false)), "bad-checksum fixture configures")
	restored = bad_checksum.restore_latest_proofs()
	_assert(bool(restored.get("success", false)), "bad-checksum fixture restores proof")
	var mismatched_checksum: Dictionary = Dictionary(fixture.payload).duplicate(true)
	mismatched_checksum["prewarm_checksum"] = "not-the-acked-prewarm-checksum"
	bad_checksum.invoke_fast_commit(mismatched_checksum)
	_assert(not bad_checksum.last_fast_commit_success(), "changed prewarm checksum cannot use durable proof")
	_assert(bad_checksum.last_fast_commit_error() == "SM0_P4_FAST_DURABLE_PROOF_CHECKSUM_MISMATCH", "changed checksum fails at durable-proof fence")
	_assert(bad_checksum.fake_activation_count == 0, "checksum mismatch occurs before import")
	bad_checksum.free()

	var bad_directory = ProofTestServer.new()
	configured = bad_directory.configure_proof_fixture(_recovery_root, source_directory)
	_assert(bool(configured.get("success", false)), "bad-directory fixture configures")
	restored = bad_directory.restore_latest_proofs()
	_assert(bool(restored.get("success", false)), "bad-directory fixture restores proof")
	var mismatched_directory: Dictionary = Dictionary(fixture.payload).duplicate(true)
	mismatched_directory["directory"] = Contracts.create_directory(Contracts.AUTHORITY_B, 2, 3)
	bad_directory.invoke_fast_commit(mismatched_directory)
	_assert(not bad_directory.last_fast_commit_success(), "directory revision drift cannot use durable proof")
	_assert(bad_directory.last_fast_commit_error() == "SM0_P4_FAST_DURABLE_PROOF_PACKAGE_MISMATCH", "directory drift fails package/proof fence")
	_assert(bad_directory.fake_activation_count == 0, "directory mismatch occurs before import")
	bad_directory.free()

	var recovered = ProofTestServer.new()
	configured = recovered.configure_proof_fixture(_recovery_root, source_directory)
	_assert(bool(configured.get("success", false)), "recovery fixture configures")
	restored = recovered.restore_latest_proofs()
	_assert(bool(restored.get("success", false)), "proof restores after simulated target restart")
	_assert(recovered.proof_count() == 1, "proof remains available more than one live TTL after ACK")
	_assert(not recovered.has_live_reservation(prewarm_id), "no live reservation exists before FAST_COMMIT rehydration")
	recovered.invoke_fast_commit(Dictionary(fixture.payload))
	_assert(recovered.last_fast_commit_success(), "exact FAST_COMMIT rehydrates from durable proof")
	_assert(recovered.last_fast_commit_error().is_empty(), "durable-proof recovery has no error")
	_assert(recovered.fake_activation_count == 1, "durable-proof recovery imports exactly once")
	_assert(recovered.has_committed_transfer(transfer_id), "recovered FAST_COMMIT becomes committed target truth")
	_assert(not recovered.has_live_reservation(prewarm_id), "rehydrated reservation is consumed by successful commit")
	_assert(recovered.proof_count() == 0, "successful FAST_COMMIT durably consumes prewarm proof")

	recovered.invoke_fast_commit(Dictionary(fixture.payload))
	_assert(recovered.last_fast_commit_success(), "exact post-recovery FAST_COMMIT replay is ACKed")
	_assert(recovered.fake_activation_count == 1, "exact replay does not import a second time")
	var conflicting_replay: Dictionary = Dictionary(fixture.payload).duplicate(true)
	conflicting_replay["prewarm_checksum"] = "conflicting-replay-checksum"
	recovered.invoke_fast_commit(conflicting_replay)
	_assert(not recovered.last_fast_commit_success(), "same transfer id with changed proof binding fails closed after recovery")
	_assert(recovered.last_fast_commit_error() == "SM0_P4_FAST_COMMIT_CONFLICT", "post-recovery conflict is classified")
	_assert(recovered.fake_activation_count == 1, "conflicting replay cannot import again")
	recovered.free()


func _make_fast_fixture() -> Dictionary:
	var player := {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"ownership_epoch": 1,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.5, "y": 0.0, "z": 0.0},
		"orientation_yaw": 0.0,
		"last_input_sequence": 10,
		"state_revision": 4,
	}
	var package := Contracts.create_handoff_package(
		"handoff/sm0/a/2/durable-proof",
		player,
		Contracts.AUTHORITY_A,
		Contracts.AUTHORITY_B,
		Contracts.ZONE_A,
		Contracts.ZONE_B,
		1,
		2,
		1
	)
	var prewarm := Contracts.create_handoff_prewarm(
		"prewarm/sm0/a/2/durable-proof",
		"a",
		"player/a",
		Contracts.AUTHORITY_A,
		Contracts.AUTHORITY_B,
		Contracts.ZONE_A,
		Contracts.ZONE_B,
		1,
		2,
		1,
		3000
	)
	var target_directory := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
	return {
		"package": package,
		"prewarm": prewarm,
		"payload": {
			"transfer_id": String(package.get("transfer_id", "")),
			"package": package.duplicate(true),
			"directory": target_directory,
			"prewarm_id": String(prewarm.get("prewarm_id", "")),
			"prewarm_checksum": String(prewarm.get("checksum", "")),
		},
	}


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("SM0 P4 durable proof recovery: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SM0 P4 durable proof recovery: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
	quit(1)
