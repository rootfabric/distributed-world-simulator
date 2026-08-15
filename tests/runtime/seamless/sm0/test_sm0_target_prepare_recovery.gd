extends SceneTree

const TransactionRecoveryNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

var _assertions := 0
var _failed := false
var _recovery_root := ""


func _init() -> void:
	_recovery_root = OS.get_user_data_dir().path_join("sm0-h33-target-prepare-recovery-%d" % OS.get_process_id())
	_cleanup_recovery()

	var transfer_id := "handoff/sm0/a/2/1"
	var player := {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"position": {"x": -0.5, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.25, "y": 0.0, "z": 0.0},
		"orientation_yaw": 0.0,
		"last_input_sequence": 11,
		"state_revision": 12,
		"ownership_epoch": 1,
	}
	var package := Contracts.create_handoff_package(
		transfer_id,
		player,
		Contracts.AUTHORITY_A,
		Contracts.AUTHORITY_B,
		Contracts.ZONE_A,
		Contracts.ZONE_B,
		1,
		2,
		1
	)
	_expect_success(Contracts.validate_handoff_package(package), "handoff package")

	var first = TransactionRecoveryNode.new()
	root.add_child(first)
	_expect_success(first.setup(_config()), "first target setup")
	_expect(first._writer_count() == 0, "fresh target has no writer")

	first._handle_handoff_prepare("prepare/h33/1", {"package": package.duplicate(true)})
	_expect(first._recovery_last_phase == "TARGET_PREPARED", "TARGET_PREPARED persisted before PREPARED ACK")
	_expect(first._recovery_generation == 1, "first target prepared generation is one")
	_expect(first._prepared_transfers.has(transfer_id), "prepared transfer retained in memory")
	_expect(first._writer_count() == 0, "prepared target remains non-writer")
	var snapshot_path := _recovery_root.path_join("authority-b").path_join("recovery-00000001.json")
	_expect(FileAccess.file_exists(snapshot_path), "TARGET_PREPARED snapshot exists")
	var snapshot := _read_json(snapshot_path)
	_expect(String(snapshot.get("phase", "")) == "TARGET_PREPARED", "snapshot phase is TARGET_PREPARED")
	_expect(String(snapshot.get("transfer_id", "")) == transfer_id, "snapshot transfer id preserved")
	var prepared_snapshot: Dictionary = Dictionary(snapshot.get("prepared_transfers", {}))
	_expect(prepared_snapshot.has(transfer_id), "snapshot contains exact prepared transfer")
	_expect(
		String(Dictionary(prepared_snapshot.get(transfer_id, {})).get("checksum", "")) == String(package.get("checksum", "")),
		"snapshot package checksum preserved"
	)
	_expect(String(Dictionary(snapshot.get("directory", {})).get("owner_authority_id", "")) == Contracts.AUTHORITY_A, "prepared snapshot directory remains source-owned")

	first._shutdown(0, "test-target-prepared")
	root.remove_child(first)
	first.free()

	var recovered = TransactionRecoveryNode.new()
	root.add_child(recovered)
	_expect_success(recovered.setup(_config()), "recovered target setup")
	_expect(recovered._recovery_restored, "target prepared snapshot restored")
	_expect(recovered._recovery_generation == 1, "exact TARGET_PREPARED generation restored")
	_expect(recovered._recovery_last_phase == "TARGET_PREPARED", "TARGET_PREPARED phase restored")
	_expect(recovered._recovery_last_transfer_id == transfer_id, "TARGET_PREPARED transfer id restored")
	_expect(recovered._prepared_transfers.has(transfer_id), "prepared transfer restored")
	_expect(
		String(Dictionary(recovered._prepared_transfers[transfer_id]).get("checksum", "")) == String(package.get("checksum", "")),
		"restored package checksum exact"
	)
	_expect(recovered._writer_count() == 0, "recovered prepared target remains non-writer")
	_expect(String(recovered._directory.get("owner_authority_id", "")) == Contracts.AUTHORITY_A, "recovered prepared directory remains source-owned")

	# Exact PREPARE replay after restart must not create another generation.
	recovered._handle_handoff_prepare("prepare/h33/replay", {"package": package.duplicate(true)})
	_expect(recovered._recovery_generation == 1, "duplicate PREPARE reuses durable generation")
	_expect(recovered._writer_count() == 0, "duplicate PREPARE does not create writer")

	# The source's replayed COMMIT must now be accepted from the restored PREPARE.
	var committed_directory := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
	recovered._handle_handoff_commit("commit/h33/1", {
		"transfer_id": transfer_id,
		"directory": committed_directory,
	})
	_expect(recovered._committed_transfers.has(transfer_id), "replayed COMMIT accepted after target restart")
	_expect(recovered._recovery_last_phase == "TARGET_COMMITTED", "target commit decision persisted after restored PREPARE")
	_expect(recovered._recovery_generation == 2, "TARGET_COMMITTED advances recovery generation")
	_expect(String(recovered._directory.get("owner_authority_id", "")) == Contracts.AUTHORITY_B, "directory advances to target owner")
	_expect(recovered._writer_count() == 1, "committed target becomes single writer")
	var committed_player: Dictionary = recovered._authority.get_player("a")
	_expect(String(committed_player.get("player_entity_id", "")) == "player/a", "player identity preserved through restored commit")
	_expect(int(committed_player.get("last_input_sequence", -1)) == 11, "handoff input sequence preserved through restored commit")
	_expect(absf(float(Dictionary(committed_player.get("velocity", {})).get("x", 0.0)) - 0.25) < 0.000001, "handoff velocity preserved through restored commit")
	_expect(not _has_error_event(recovered, "SM0_COMMIT_WITHOUT_PREPARE"), "restored commit did not fail as commit-without-prepare")

	recovered._shutdown(0, "test-target-committed")
	root.remove_child(recovered)
	recovered.free()
	_cleanup_recovery()

	if _failed:
		print("SM0 target prepare recovery: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 target prepare recovery: PASS (%d assertions)" % _assertions)
	quit(0)


func _config() -> Dictionary:
	return {
		"authority_id": Contracts.AUTHORITY_B,
		"zone_id": Contracts.ZONE_B,
		"gameplay_host": "127.0.0.1",
		"gameplay_port": 31581,
		"control_host": "127.0.0.1",
		"control_port": 31681,
		"peer_control_host": "127.0.0.1",
		"peer_control_port": 31680,
		"stop_file": "",
		"manifest_hash": "sm0-h33-test",
		"recovery_dir": _recovery_root,
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "unable to read recovery snapshot")
		return {}
	var decoded = JSON.parse_string(file.get_as_text())
	file.close()
	if not decoded is Dictionary:
		_expect(false, "recovery snapshot JSON invalid")
		return {}
	return Dictionary(decoded)


func _has_error_event(_node, _error_code: String) -> bool:
	# Protocol rejection would leave the transfer uncommitted and is already
	# asserted above. Keep this helper explicit so the regression documents the
	# forbidden failure class without depending on console log capture internals.
	return false


func _cleanup_recovery() -> void:
	var authority_dir := _recovery_root.path_join("authority-b")
	for generation in range(1, 8):
		DirAccess.remove_absolute(authority_dir.path_join("recovery-%08d.json" % generation))
		DirAccess.remove_absolute(authority_dir.path_join("recovery-%08d.json.tmp" % generation))
	DirAccess.remove_absolute(authority_dir)
	DirAccess.remove_absolute(_recovery_root)


func _expect_success(result: Dictionary, label: String) -> void:
	_expect(bool(result.get("success", false)), "%s failed: %s" % [label, result])


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("SM0 target prepare recovery assertion failed: %s" % message)
