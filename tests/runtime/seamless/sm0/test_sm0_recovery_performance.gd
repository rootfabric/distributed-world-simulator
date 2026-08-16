extends SceneTree

const RecoveryPerformanceNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const MOVE_COUNT := 40
const DELTA_X := 0.1

var _assertions := 0
var _failed := false
var _recovery_root := ""


func _init() -> void:
	_recovery_root = OS.get_user_data_dir().path_join("sm0-p21-recovery-performance-%d" % OS.get_process_id())
	_cleanup_recovery()
	var session := "transport-session/sm0/test/p21-active"
	var client_port := 32780

	var first = RecoveryPerformanceNode.new()
	root.add_child(first)
	_expect_success(first.setup(_config()), "first performance setup")
	var joined: Dictionary = first._authority.join("a", session, "operation/sm0/test/p21/join")
	_expect_success(joined, "performance active owner join")
	var joined_player: Dictionary = Dictionary(joined.get("details", {}).get("player", {}))
	_expect(String(joined_player.get("player_entity_id", "")) == "player/a", "initial identity")
	first._active_session_id = session
	first._active_client_ip = "127.0.0.1"
	first._active_client_port = client_port

	var first_snapshot_bytes := -1
	for sequence in range(1, MOVE_COUNT + 1):
		var before: Dictionary = first._authority.get_player("a")
		var moved: Dictionary = first._authority.move_player(
			"a",
			session,
			int(before.get("ownership_epoch", 0)),
			sequence,
			DELTA_X,
			0.0,
			"operation/sm0/client/a/move/%d" % sequence
		)
		_expect_success(moved, "movement %d" % sequence)
		var durable := first._ensure_active_owner_persisted_for_ack(
			"127.0.0.1",
			client_port,
			"MOVE_ACK",
			{"accepted": true}
		)
		_expect_success(durable, "durable movement %d" % sequence)
		_expect(first._recovery_generation == sequence, "generation follows movement %d" % sequence)
		var report: Dictionary = first._authority.get_recovery_report()
		_expect(int(report.get("service_operation_count", 99)) <= 2, "movement replay ledger bounded at sequence %d" % sequence)
		if sequence == 1:
			first_snapshot_bytes = int(durable.get("details", {}).get("snapshot_bytes", -1))
			_expect(first_snapshot_bytes > 0, "first snapshot bytes reported")

	var final_player: Dictionary = first._authority.get_player("a")
	_expect(int(final_player.get("last_input_sequence", -1)) == MOVE_COUNT, "final durable sequence")
	_expect(absf(float(Dictionary(final_player.get("position", {})).get("x", 0.0)) - (-5.0 + MOVE_COUNT * DELTA_X)) <= 0.000001, "final durable position")
	_expect(_recovery_file_count() <= 8, "recovery file history bounded")
	var latest_path := _recovery_root.path_join("authority-a").path_join("recovery-%08d.json" % MOVE_COUNT)
	_expect(FileAccess.file_exists(latest_path), "latest recovery generation retained")
	var latest := _read_json(latest_path)
	var replay_state: Dictionary = Dictionary(latest.get("gameplay_replay_state", {}))
	var service_ledger: Dictionary = Dictionary(replay_state.get("service_operation_ledger", {}))
	_expect(service_ledger.size() <= 2, "durable replay ledger bounded")
	_expect(service_ledger.has("operation/sm0/client/a/move/%d" % MOVE_COUNT), "latest durable movement replay retained")
	var movement_records := 0
	for operation_id_value in service_ledger.keys():
		if String(operation_id_value).begins_with("operation/sm0/client/a/move/"):
			movement_records += 1
	_expect(movement_records == 1, "exactly one movement replay retained")
	var final_snapshot_bytes := _file_size(latest_path)
	_expect(final_snapshot_bytes > 0, "final snapshot exists with bytes")
	_expect(final_snapshot_bytes <= first_snapshot_bytes + 4096, "snapshot size does not grow with movement history")

	first._shutdown(0, "test-p21-performance-crash")
	root.remove_child(first)
	first.free()

	var recovered = RecoveryPerformanceNode.new()
	root.add_child(recovered)
	_expect_success(recovered.setup(_config()), "recovered performance setup")
	_expect(recovered._recovery_restored, "latest performance snapshot restored")
	_expect(recovered._recovery_generation == MOVE_COUNT, "exact latest generation restored")
	var restored_player: Dictionary = recovered._authority.get_player("a")
	_expect(not bool(restored_player.get("connected", true)), "restored player starts disconnected")
	_expect(int(restored_player.get("last_input_sequence", -1)) == MOVE_COUNT, "restored sequence exact")
	_expect(absf(float(Dictionary(restored_player.get("position", {})).get("x", 0.0)) - (-5.0 + MOVE_COUNT * DELTA_X)) <= 0.000001, "restored position exact")

	var duplicate := {
		"logical_player_id": "a",
		"session_id": session,
		"ownership_epoch": 1,
		"input_sequence": MOVE_COUNT,
		"delta_x": DELTA_X,
		"delta_z": 0.0,
	}
	var conflicting := duplicate.duplicate(true)
	conflicting["delta_x"] = DELTA_X * 2.0
	recovered._handle_client_move("move/%d-conflict" % MOVE_COUNT, conflicting, "127.0.0.1", client_port)
	var after_conflict: Dictionary = recovered._authority.get_player("a")
	_expect(not bool(after_conflict.get("connected", true)), "conflicting durable retry cannot rebind")
	_expect(int(after_conflict.get("last_input_sequence", -1)) == MOVE_COUNT, "conflicting retry preserves sequence")
	_expect(absf(float(Dictionary(after_conflict.get("position", {})).get("x", 0.0)) - (-5.0 + MOVE_COUNT * DELTA_X)) <= 0.000001, "conflicting retry preserves position")

	recovered._handle_client_move("move/%d" % MOVE_COUNT, duplicate, "127.0.0.1", client_port)
	var rebound: Dictionary = recovered._authority.get_player("a")
	_expect(bool(rebound.get("connected", false)), "exact durable retry rebinds")
	_expect(String(rebound.get("player_entity_id", "")) == "player/a", "identity preserved after bounded replay restore")
	_expect(int(rebound.get("last_input_sequence", -1)) == MOVE_COUNT, "exact duplicate not reapplied")
	_expect(absf(float(Dictionary(rebound.get("position", {})).get("x", 0.0)) - (-5.0 + MOVE_COUNT * DELTA_X)) <= 0.000001, "exact duplicate position unchanged")
	_expect(recovered._recovery_generation == MOVE_COUNT + 1, "rebind ACK writes next durable generation")
	_expect(_recovery_file_count() <= 8, "recovery history stays bounded after rebind")

	recovered._shutdown(0, "test-p21-performance-recovered")
	root.remove_child(recovered)
	recovered.free()
	_cleanup_recovery()

	if _failed:
		print("SM0 P2.1 recovery performance: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 P2.1 recovery performance: PASS (%d assertions, %d durable moves)" % [_assertions, MOVE_COUNT])
	quit(0)


func _config() -> Dictionary:
	return {
		"authority_id": Contracts.AUTHORITY_A,
		"zone_id": Contracts.ZONE_A,
		"gameplay_host": "127.0.0.1",
		"gameplay_port": 32580,
		"control_host": "127.0.0.1",
		"control_port": 32680,
		"peer_control_host": "127.0.0.1",
		"peer_control_port": 32681,
		"stop_file": "",
		"manifest_hash": "sm0-p21-test",
		"fault_profile": "h4-recovery-of-recovery-same-transfer-v1",
		"recovery_dir": _recovery_root,
		"recovery_performance": "p21",
	}


func _recovery_file_count() -> int:
	var authority_dir := _recovery_root.path_join("authority-a")
	var dir := DirAccess.open(authority_dir)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.begins_with("recovery-") and name.ends_with(".json"):
			count += 1
		name = dir.get_next()
	dir.list_dir_end()
	return count


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


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func _cleanup_recovery() -> void:
	var authority_dir := _recovery_root.path_join("authority-a")
	var dir := DirAccess.open(authority_dir)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while not name.is_empty():
			if not dir.current_is_dir():
				DirAccess.remove_absolute(authority_dir.path_join(name))
			name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(authority_dir)
	DirAccess.remove_absolute(_recovery_root)


func _expect_success(result: Dictionary, label: String) -> void:
	_expect(bool(result.get("success", false)), "%s failed: %s" % [label, result])


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("SM0 P2.1 recovery performance assertion failed: %s" % message)
