extends SceneTree

const ActiveRecoveryNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

var _assertions := 0
var _failed := false
var _recovery_root := ""


func _init() -> void:
	_recovery_root = OS.get_user_data_dir().path_join("sm0-h24-active-owner-recovery-%d" % OS.get_process_id())
	_cleanup_recovery()
	var session := "transport-session/sm0/test/h24-active"
	var client_port := 30780

	var first = ActiveRecoveryNode.new()
	root.add_child(first)
	_expect_success(first.setup(_config()), "first setup")
	var joined: Dictionary = first._authority.join("a", session, "operation/sm0/test/h24/join")
	_expect_success(joined, "active owner join")
	var joined_player: Dictionary = Dictionary(joined.get("details", {}).get("player", {}))
	_expect(String(joined_player.get("player_entity_id", "")) == "player/a", "initial identity")
	_expect(int(joined_player.get("ownership_epoch", 0)) == 1, "initial ownership epoch")
	first._active_session_id = session
	first._active_client_ip = "127.0.0.1"
	first._active_client_port = client_port

	var moved: Dictionary = first._authority.move_player(
		"a",
		session,
		int(joined_player.get("ownership_epoch", 0)),
		1,
		0.5,
		0.0,
		"operation/sm0/client/a/move/1"
	)
	_expect_success(moved, "first movement")
	var durable := first._ensure_active_owner_persisted_for_ack(
		"127.0.0.1",
		client_port,
		"MOVE_ACK",
		{"accepted": true}
	)
	_expect_success(durable, "active owner persist before ack")
	_expect(first._recovery_generation == 1, "first active generation")
	_expect(first._recovery_last_phase == "ACTIVE_OWNER", "active phase persisted")
	var before_crash: Dictionary = first._authority.get_player("a")
	_expect(first._writer_count() == 1, "active owner is writer before crash")
	_expect(int(before_crash.get("last_input_sequence", -1)) == 1, "durable sequence one")
	_expect(absf(float(Dictionary(before_crash.get("position", {})).get("x", 0.0)) + 4.5) <= 0.000001, "durable position reflects first move")
	var snapshot_path := _recovery_root.path_join("authority-a").path_join("recovery-00000001.json")
	_expect(FileAccess.file_exists(snapshot_path), "active owner snapshot exists")
	var snapshot := _read_json(snapshot_path)
	_expect(String(snapshot.get("phase", "")) == "ACTIVE_OWNER", "snapshot phase")
	var metadata: Dictionary = Dictionary(snapshot.get("source_transfer", {}))
	_expect(String(metadata.get("kind", "")) == "ACTIVE_OWNER", "snapshot active metadata kind")
	_expect(String(metadata.get("session_id", "")) == session, "snapshot session metadata")
	_expect(int(metadata.get("last_input_sequence", -1)) == 1, "snapshot sequence metadata")
	_expect(int(metadata.get("ownership_epoch", 0)) == 1, "snapshot ownership metadata")

	first._shutdown(0, "test-active-owner-crash")
	root.remove_child(first)
	first.free()

	var recovered = ActiveRecoveryNode.new()
	root.add_child(recovered)
	_expect_success(recovered.setup(_config()), "recovered setup")
	_expect(recovered._recovery_restored, "active snapshot restored")
	_expect(recovered._recovery_generation == 1, "exact active generation restored")
	_expect(recovered._recovery_last_phase == "ACTIVE_OWNER", "active phase restored")
	_expect(recovered._writer_count() == 0, "recovered owner starts disconnected")
	var restored_player: Dictionary = recovered._authority.get_player("a")
	_expect(not bool(restored_player.get("connected", true)), "canonical player disconnected after durable restore")
	_expect(String(restored_player.get("transport_session_id", "")) == "", "transport session not resurrected by durable restore")
	_expect(String(restored_player.get("player_entity_id", "")) == "player/a", "restored identity")
	_expect(int(restored_player.get("last_input_sequence", -1)) == 1, "restored sequence")
	_expect(absf(float(Dictionary(restored_player.get("position", {})).get("x", 0.0)) + 4.5) <= 0.000001, "restored position")

	var duplicate := {
		"logical_player_id": "a",
		"session_id": session,
		"ownership_epoch": 1,
		"input_sequence": 1,
		"delta_x": 0.5,
		"delta_z": 0.0,
	}
	_expect(recovered._active_recovery_request_matches(duplicate, "127.0.0.1", client_port), "exact recovery request matches")
	_expect(not recovered._active_recovery_request_matches(duplicate, "127.0.0.1", client_port + 1), "foreign endpoint rejected")

	var conflicting := duplicate.duplicate(true)
	conflicting["delta_x"] = 0.25
	recovered._handle_client_move("move/1-conflict", conflicting, "127.0.0.1", client_port)
	var after_conflict: Dictionary = recovered._authority.get_player("a")
	_expect(not bool(after_conflict.get("connected", true)), "conflicting duplicate does not rebind")
	_expect(absf(float(Dictionary(after_conflict.get("position", {})).get("x", 0.0)) + 4.5) <= 0.000001, "conflicting duplicate does not mutate position")

	recovered._handle_client_move("move/1", duplicate, "127.0.0.1", client_port)
	var rebound: Dictionary = recovered._authority.get_player("a")
	_expect(bool(rebound.get("connected", false)), "exact duplicate rebinds session")
	_expect(recovered._writer_count() == 1, "rebound active owner is writer")
	_expect(String(rebound.get("player_entity_id", "")) == "player/a", "identity preserved across rebind")
	_expect(int(rebound.get("ownership_epoch", 0)) == 2, "controlled rebind increments ownership epoch once")
	_expect(int(rebound.get("last_input_sequence", -1)) == 1, "durable duplicate is not applied twice")
	_expect(absf(float(Dictionary(rebound.get("position", {})).get("x", 0.0)) + 4.5) <= 0.000001, "durable duplicate preserves position")
	_expect(recovered._recovery_generation == 2, "rebind ack becomes new durable generation")

	var next_move := {
		"logical_player_id": "a",
		"session_id": session,
		"ownership_epoch": int(rebound.get("ownership_epoch", 0)),
		"input_sequence": 2,
		"delta_x": 0.5,
		"delta_z": 0.0,
	}
	recovered._handle_client_move("move/2", next_move, "127.0.0.1", client_port)
	var after_next: Dictionary = recovered._authority.get_player("a")
	_expect(int(after_next.get("last_input_sequence", -1)) == 2, "next sequence accepted")
	_expect(absf(float(Dictionary(after_next.get("position", {})).get("x", 0.0)) + 4.0) <= 0.000001, "next movement applied exactly once")
	_expect(recovered._recovery_generation == 3, "next move ack becomes durable generation")

	recovered._shutdown(0, "test-active-owner-recovered")
	root.remove_child(recovered)
	recovered.free()
	_cleanup_recovery()

	if _failed:
		print("SM0 active owner recovery: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 active owner recovery: PASS (%d assertions)" % _assertions)
	quit(0)


func _config() -> Dictionary:
	return {
		"authority_id": Contracts.AUTHORITY_A,
		"zone_id": Contracts.ZONE_A,
		"gameplay_host": "127.0.0.1",
		"gameplay_port": 30580,
		"control_host": "127.0.0.1",
		"control_port": 30680,
		"peer_control_host": "127.0.0.1",
		"peer_control_port": 30681,
		"stop_file": "",
		"manifest_hash": "sm0-h24-test",
		"recovery_dir": _recovery_root,
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "unable to read active owner snapshot")
		return {}
	var decoded = JSON.parse_string(file.get_as_text())
	file.close()
	if not decoded is Dictionary:
		_expect(false, "active owner snapshot JSON invalid")
		return {}
	return Dictionary(decoded)


func _cleanup_recovery() -> void:
	var authority_dir := _recovery_root.path_join("authority-a")
	for generation in range(1, 12):
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
	push_error("SM0 active owner recovery assertion failed: %s" % message)
