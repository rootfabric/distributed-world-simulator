extends SceneTree

const RecoveryNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

var _assertions := 0
var _failed := false
var _recovery_root := ""


func _init() -> void:
	_recovery_root = OS.get_user_data_dir().path_join("sm0-h23-source-recovery-%d" % OS.get_process_id())
	_cleanup_recovery()

	var first = RecoveryNode.new()
	root.add_child(first)
	_expect_success(first.setup(_config()), "first setup")
	var session := "transport-session/sm0/test/source"
	var joined: Dictionary = first._authority.join("a", session, "operation/sm0/test/h23/join")
	_expect_success(joined, "source join")
	var player: Dictionary = Dictionary(joined.get("details", {}).get("player", {}))
	var transfer_id := "handoff/sm0/a/2/1"
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
	first._active_session_id = session
	first._active_client_ip = "127.0.0.1"
	first._active_client_port = 29780
	first._frozen_transfer_id = transfer_id
	first._source_transfer = {
		"transfer_id": transfer_id,
		"package": package.duplicate(true),
		"stage": "PREPARE_SENT",
		"last_send_ms": 0,
		"retries": 0,
		"client_ip": "127.0.0.1",
		"client_port": 29780,
	}
	first._commit_source_transfer()
	_expect(first._recovery_last_phase == "SOURCE_RETIRED", "source retired phase persisted")
	_expect(first._recovery_generation == 1, "source retired generation is one")
	_expect(String(first._directory.get("owner_authority_id", "")) == Contracts.AUTHORITY_B, "directory moved to target")
	_expect(first._writer_count() == 0, "retired source is not writer")
	var retired_player: Dictionary = first._authority.get_player("a")
	_expect(not bool(retired_player.get("connected", true)), "canonical source player is retired")
	_expect(String(first._source_transfer.get("stage", "")) == "COMMIT_SENT", "pending source transfer is commit stage")
	_expect(
		first._is_retired_source_pending_move(
			{"logical_player_id": "a", "session_id": session},
			"127.0.0.1",
			29780
		),
		"late move from exact retired source client is held as handoff pending"
	)
	_expect(
		not first._is_retired_source_pending_move(
			{"logical_player_id": "a", "session_id": session},
			"127.0.0.1",
			29781
		),
		"late move from unrelated endpoint is not treated as pending handoff"
	)
	_expect(
		not first._is_retired_source_pending_move(
			{"logical_player_id": "b", "session_id": session},
			"127.0.0.1",
			29780
		),
		"late move for unrelated logical player is not treated as pending handoff"
	)
	var snapshot_path := _recovery_root.path_join("authority-a").path_join("recovery-00000001.json")
	_expect(FileAccess.file_exists(snapshot_path), "source recovery snapshot exists")
	var snapshot := _read_json(snapshot_path)
	_expect(String(snapshot.get("phase", "")) == "SOURCE_RETIRED", "snapshot phase is source retired")
	_expect(String(Dictionary(snapshot.get("source_transfer", {})).get("transfer_id", "")) == transfer_id, "snapshot carries source transfer id")
	_expect(String(Dictionary(snapshot.get("source_transfer", {})).get("stage", "")) == "COMMIT_SENT", "snapshot carries commit stage")
	_expect(not bool(Dictionary(snapshot.get("source_transfer", {})).get("target_committed", true)), "snapshot target ack is false")
	_expect(not bool(Dictionary(snapshot.get("source_transfer", {})).get("client_redirect_acked", true)), "snapshot redirect ack is false")

	first._shutdown(0, "test-source-retire")
	root.remove_child(first)
	first.free()

	var recovered = RecoveryNode.new()
	root.add_child(recovered)
	_expect_success(recovered.setup(_config()), "recovered setup")
	_expect(recovered._recovery_restored, "recovery snapshot restored")
	_expect(recovered._recovery_generation == 1, "exact generation restored")
	_expect(recovered._recovery_last_phase == "SOURCE_RETIRED", "source retired phase restored")
	_expect(recovered._recovery_last_transfer_id == transfer_id, "exact transfer restored")
	_expect(String(recovered._source_transfer.get("transfer_id", "")) == transfer_id, "pending source transfer restored")
	_expect(String(recovered._source_transfer.get("stage", "")) == "COMMIT_SENT", "restored transfer is commit stage")
	_expect(int(recovered._source_transfer.get("last_send_ms", -1)) == 0, "retry timestamp reset")
	_expect(int(recovered._source_transfer.get("retries", -1)) == 0, "retry counter reset")
	_expect(String(recovered._source_transfer.get("client_ip", "")) == "127.0.0.1", "client ip restored")
	_expect(int(recovered._source_transfer.get("client_port", 0)) == 29780, "client port restored")
	_expect(recovered._writer_count() == 0, "recovered source remains non-writer")
	var recovered_player: Dictionary = recovered._authority.get_player("a")
	_expect(not recovered_player.is_empty(), "recovered canonical player exists")
	_expect(String(recovered_player.get("player_entity_id", "")) == "player/a", "player identity preserved")
	_expect(not bool(recovered_player.get("connected", true)), "recovered canonical player remains disconnected")
	_expect(String(recovered_player.get("transport_session_id", "")) == "", "recovery does not resurrect source session")
	_expect(String(recovered._directory.get("owner_authority_id", "")) == Contracts.AUTHORITY_B, "recovered directory still targets peer")
	_expect(
		recovered._is_retired_source_pending_move(
			{"logical_player_id": "a", "session_id": session},
			"127.0.0.1",
			29780
		),
		"restored source still holds exact late client move as handoff pending"
	)
	_expect(
		not recovered._is_retired_source_pending_move(
			{"logical_player_id": "a", "session_id": session},
			"127.0.0.2",
			29780
		),
		"restored source does not classify foreign endpoint as pending handoff"
	)

	recovered._shutdown(0, "test-source-recovered")
	root.remove_child(recovered)
	recovered.free()
	_cleanup_recovery()

	if _failed:
		print("SM0 source retire recovery: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 source retire recovery: PASS (%d assertions)" % _assertions)
	quit(0)


func _config() -> Dictionary:
	return {
		"authority_id": Contracts.AUTHORITY_A,
		"zone_id": Contracts.ZONE_A,
		"gameplay_host": "127.0.0.1",
		"gameplay_port": 29580,
		"control_host": "127.0.0.1",
		"control_port": 29680,
		"peer_control_host": "127.0.0.1",
		"peer_control_port": 29681,
		"stop_file": "",
		"manifest_hash": "sm0-h23-test",
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


func _cleanup_recovery() -> void:
	var authority_dir := _recovery_root.path_join("authority-a")
	for generation in range(1, 5):
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
	push_error("SM0 source retire recovery assertion failed: %s" % message)
