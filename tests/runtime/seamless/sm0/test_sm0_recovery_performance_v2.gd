extends SceneTree

const RecoveryPerformanceV2Node = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance_v2.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const FINGERPRINT := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

var _assertions := 0
var _failed := false
var _recovery_root := ""


func _init() -> void:
	_recovery_root = OS.get_user_data_dir().path_join("sm0-p22-recovery-performance-%d" % OS.get_process_id())
	_cleanup_recovery()
	var session := "transport-session/sm0/test/p22-active"
	var client_port := 33780

	var first = RecoveryPerformanceV2Node.new()
	root.add_child(first)
	_expect_success(first.setup(_config()), "first P2.2 setup")
	var joined: Dictionary = first._authority.join("a", session, "operation/sm0/a/join/current")
	_expect_success(joined, "P2.2 active owner join")
	first._active_session_id = session
	first._active_client_ip = "127.0.0.1"
	first._active_client_port = client_port

	_inflate_replay_history(first)
	_inflate_transfer_history(first)
	var pre_report: Dictionary = first._authority.get_recovery_report()
	_expect(int(pre_report.get("service_operation_count", 0)) > 10, "service replay history inflated")
	_expect(int(pre_report.get("ownership_operation_count", 0)) > 10, "ownership replay history inflated")
	_expect(first._prepared_transfers.size() >= 5, "prepared transfer history inflated")
	_expect(first._committed_transfers.size() >= 5, "committed transfer history inflated")

	var before: Dictionary = first._authority.get_player("a")
	var moved: Dictionary = first._authority.move_player(
		"a",
		session,
		int(before.get("ownership_epoch", 0)),
		1,
		0.25,
		0.0,
		"operation/sm0/client/a/move/1"
	)
	_expect_success(moved, "P2.2 movement")
	var durable := first._ensure_active_owner_persisted_for_ack(
		"127.0.0.1",
		client_port,
		"MOVE_ACK",
		{"accepted": true}
	)
	_expect_success(durable, "P2.2 durable movement")
	_expect(first._recovery_generation == 1, "P2.2 first generation")

	var report: Dictionary = first._authority.get_recovery_report()
	_expect(int(report.get("service_operation_count", 99)) <= 4, "service replay history bounded")
	_expect(int(report.get("ownership_operation_count", 99)) <= 4, "ownership replay history bounded")
	_expect(first._prepared_transfers.is_empty(), "stale prepared transfer history removed")
	_expect(first._committed_transfers.is_empty(), "stale committed transfer history removed")

	var gameplay_service = first._authority.get_networked_gameplay_service_for_tests()
	var service_ledger: Dictionary = Dictionary(gameplay_service.get("_operation_ledger"))
	_expect(service_ledger.has("operation/sm0/client/a/move/1"), "latest durable movement replay retained")

	var latest_path := _recovery_root.path_join("authority-a").path_join("recovery-00000001.json")
	_expect(FileAccess.file_exists(latest_path), "P2.2 recovery snapshot written")
	var latest := _read_json(latest_path)
	_expect(Dictionary(latest.get("prepared_transfers", {})).is_empty(), "snapshot prepared history bounded")
	_expect(Dictionary(latest.get("committed_transfers", {})).is_empty(), "snapshot committed history bounded")
	var replay_state: Dictionary = Dictionary(latest.get("gameplay_replay_state", {}))
	_expect(Dictionary(replay_state.get("service_operation_ledger", {})).size() <= 4, "snapshot service replay bounded")
	var ownership_replay: Dictionary = Dictionary(replay_state.get("ownership_replay", {}))
	_expect(Dictionary(ownership_replay.get("records", {})).size() <= 4, "snapshot ownership replay bounded")

	var durable_player: Dictionary = first._authority.get_player("a")
	var durable_x := float(Dictionary(durable_player.get("position", {})).get("x", 0.0))
	first._shutdown(0, "test-p22-crash")
	root.remove_child(first)
	first.free()

	var recovered = RecoveryPerformanceV2Node.new()
	root.add_child(recovered)
	_expect_success(recovered.setup(_config()), "recovered P2.2 setup")
	_expect(recovered._recovery_restored, "P2.2 snapshot restored")
	_expect(recovered._recovery_generation == 1, "P2.2 exact generation restored")
	var restored: Dictionary = recovered._authority.get_player("a")
	_expect(int(restored.get("last_input_sequence", -1)) == 1, "P2.2 restored sequence exact")
	_expect(absf(float(Dictionary(restored.get("position", {})).get("x", 0.0)) - durable_x) <= 0.000001, "P2.2 restored position exact")

	recovered._handle_client_move("move/1", {
		"logical_player_id": "a",
		"session_id": session,
		"ownership_epoch": int(restored.get("ownership_epoch", 0)),
		"input_sequence": 1,
		"delta_x": 0.25,
		"delta_z": 0.0,
	}, "127.0.0.1", client_port)
	var rebound: Dictionary = recovered._authority.get_player("a")
	_expect(bool(rebound.get("connected", false)), "P2.2 exact durable retry rebinds")
	_expect(int(rebound.get("last_input_sequence", -1)) == 1, "P2.2 duplicate movement not reapplied")
	_expect(absf(float(Dictionary(rebound.get("position", {})).get("x", 0.0)) - durable_x) <= 0.000001, "P2.2 duplicate preserves position")
	_expect(recovered._recovery_generation == 2, "P2.2 rebound writes next generation")
	var rebound_report: Dictionary = recovered._authority.get_recovery_report()
	_expect(int(rebound_report.get("service_operation_count", 99)) <= 5, "P2.2 service replay stays bounded after recovery")
	_expect(int(rebound_report.get("ownership_operation_count", 99)) <= 5, "P2.2 ownership replay stays bounded after recovery")

	recovered._shutdown(0, "test-p22-recovered")
	root.remove_child(recovered)
	recovered.free()
	_cleanup_recovery()

	if _failed:
		print("SM0 P2.2 bounded recovery replay: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 P2.2 bounded recovery replay: PASS (%d assertions)" % _assertions)
	quit(0)


func _inflate_replay_history(node) -> void:
	var gameplay_service = node._authority.get_networked_gameplay_service_for_tests()
	var service_ledger: Dictionary = Dictionary(gameplay_service.get("_operation_ledger")).duplicate(true)
	for index in range(16):
		service_ledger["operation/sm0/a/recovery-rebind/fake/%02d" % index] = {
			"fingerprint": FINGERPRINT,
			"result": {
				"success": true,
				"error_code": "",
				"details": {"player": {"state_revision": index + 1, "last_input_sequence": index}},
			},
		}
	gameplay_service.set("_operation_ledger", service_ledger)

	var ownership = gameplay_service.get("_ownership")
	var ownership_ledger: Dictionary = Dictionary(ownership.get("_operation_ledger")).duplicate(true)
	for index in range(16):
		ownership_ledger["operation/sm0/a/recovery-rebind/fake/%02d" % index] = {
			"fingerprint": FINGERPRINT,
			"result": {
				"success": true,
				"error_code": "",
				"details": {"player": {
					"ownership_epoch": index + 1,
					"joined_tick": index + 1,
					"left_tick": 0,
				}},
			},
		}
	ownership.set("_operation_ledger", ownership_ledger)


func _inflate_transfer_history(node) -> void:
	var player: Dictionary = node._authority.get_player("a")
	for index in range(5):
		var target_epoch := 3 + index * 2
		var source_epoch := target_epoch - 1
		var transfer_id := "handoff/sm0/b/%d/fake-%d" % [target_epoch, index]
		var package := Contracts.create_handoff_package(
			transfer_id,
			player,
			Contracts.AUTHORITY_B,
			Contracts.AUTHORITY_A,
			Contracts.ZONE_B,
			Contracts.ZONE_A,
			source_epoch,
			target_epoch,
			target_epoch - 1
		)
		node._prepared_transfers[transfer_id] = package
		node._committed_transfers[transfer_id] = {
			"package": package.duplicate(true),
			"session_id": "transport-session/sm0/test/fake/%d" % index,
			"player": player.duplicate(true),
			"directory": Contracts.create_directory(Contracts.AUTHORITY_A, target_epoch, target_epoch),
		}


func _config() -> Dictionary:
	return {
		"authority_id": Contracts.AUTHORITY_A,
		"zone_id": Contracts.ZONE_A,
		"gameplay_host": "127.0.0.1",
		"gameplay_port": 33580,
		"control_host": "127.0.0.1",
		"control_port": 33680,
		"peer_control_host": "127.0.0.1",
		"peer_control_port": 33681,
		"stop_file": "",
		"manifest_hash": "sm0-p22-test",
		"fault_profile": "h4-recovery-of-recovery-same-transfer-v1",
		"recovery_dir": _recovery_root,
		"recovery_performance": "p22",
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "unable to read P2.2 recovery snapshot")
		return {}
	var decoded = JSON.parse_string(file.get_as_text())
	file.close()
	if not decoded is Dictionary:
		_expect(false, "P2.2 recovery snapshot JSON invalid")
		return {}
	return Dictionary(decoded)


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
	push_error("SM0 P2.2 bounded replay assertion failed: %s" % message)
