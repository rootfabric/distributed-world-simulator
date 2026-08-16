extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const P4Server = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd")
const P4Client = preload("res://scripts/runtime/seamless/sm0/sm0_automated_client_node_p4_hardened.gd")
const P4TestServer = preload("res://tests/runtime/seamless/sm0/sm0_p4_hardening_test_server.gd")
const P4TestClient = preload("res://tests/runtime/seamless/sm0/sm0_p4_hardening_test_client.gd")

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_test_fast_commit_fingerprint()
	_test_fast_commit_replay_handler()
	_test_single_reservation_slot()
	_test_join_admission_fences()
	_test_completed_source_tombstone_ignores_newer_unrelated_snapshot()
	_test_reservation_conflict_handler()
	_test_redirect_fingerprint()
	_test_redirect_replay_handler()
	_finish()


func _test_fast_commit_fingerprint() -> void:
	var server = P4Server.new()
	var fixture := _make_fast_fixture()
	var payload: Dictionary = fixture.payload
	var fingerprint := server._p4_fast_fingerprint_from_payload(payload)
	_assert(not fingerprint.is_empty(), "FAST_COMMIT fingerprint exists")
	var same := payload.duplicate(true)
	_assert(server._p4_fast_fingerprint_from_payload(same) == fingerprint, "exact FAST_COMMIT duplicate has identical fingerprint")
	var wrong_prewarm_checksum := payload.duplicate(true)
	wrong_prewarm_checksum["prewarm_checksum"] = "conflicting-prewarm-checksum"
	_assert(server._p4_fast_fingerprint_from_payload(wrong_prewarm_checksum) != fingerprint, "prewarm checksum participates in FAST_COMMIT replay identity")
	var wrong_package := payload.duplicate(true)
	var package_copy: Dictionary = Dictionary(fixture.package).duplicate(true)
	package_copy["checksum"] = "conflicting-package-checksum"
	wrong_package["package"] = package_copy
	_assert(server._p4_fast_fingerprint_from_payload(wrong_package) != fingerprint, "package checksum participates in FAST_COMMIT replay identity")
	var wrong_directory := payload.duplicate(true)
	var directory_copy: Dictionary = Dictionary(fixture.directory).duplicate(true)
	directory_copy["checksum"] = "conflicting-directory-checksum"
	wrong_directory["directory"] = directory_copy
	_assert(server._p4_fast_fingerprint_from_payload(wrong_directory) != fingerprint, "directory checksum participates in FAST_COMMIT replay identity")
	server.free()


func _test_fast_commit_replay_handler() -> void:
	var server = P4TestServer.new()
	var fixture := _make_fast_fixture()
	server.configure_admission_fixture(Contracts.AUTHORITY_B, Dictionary(fixture.directory), true)
	server.install_committed_fast_transfer(
		Dictionary(fixture.package),
		Dictionary(fixture.directory),
		Dictionary(fixture.prewarm)
	)
	server.invoke_fast_commit(Dictionary(fixture.payload))
	_assert(server.last_fast_commit_success(), "exact committed FAST_COMMIT replay is ACKed")
	_assert(server.last_fast_commit_error().is_empty(), "exact committed FAST_COMMIT replay has no error")

	var conflicting: Dictionary = Dictionary(fixture.payload).duplicate(true)
	conflicting["prewarm_checksum"] = "conflicting-prewarm-checksum"
	server.invoke_fast_commit(conflicting)
	_assert(not server.last_fast_commit_success(), "same transfer id with changed prewarm checksum is not ACKed")
	_assert(server.last_fast_commit_error() == "SM0_P4_FAST_COMMIT_CONFLICT", "changed prewarm checksum is classified as FAST_COMMIT conflict")
	server.free()


func _test_single_reservation_slot() -> void:
	var server = P4Server.new()
	var first := _make_a_to_b_prewarm("prewarm/sm0/a/2/one")
	var second_same_epoch := _make_a_to_b_prewarm("prewarm/sm0/a/2/two")
	_assert(String(first.get("prewarm_id", "")) != String(second_same_epoch.get("prewarm_id", "")), "fixture uses distinct prewarm ids")
	_assert(server._p4_same_reservation_slot(first, second_same_epoch), "distinct ids for same player/source-target epoch conflict in one reservation slot")
	var next_epoch := Contracts.create_handoff_prewarm(
		"prewarm/sm0/a/3/three",
		"a",
		"player/a",
		Contracts.AUTHORITY_B,
		Contracts.AUTHORITY_A,
		Contracts.ZONE_B,
		Contracts.ZONE_A,
		2,
		3,
		2,
		3000
	)
	_assert(not server._p4_same_reservation_slot(first, next_epoch), "next authority epoch uses a different reservation slot")
	server.free()


func _test_join_admission_fences() -> void:
	var server = P4TestServer.new()
	server.configure_admission_fixture(
		Contracts.AUTHORITY_A,
		Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1),
		false
	)
	server.invoke_join({"logical_player_id": "a", "session_id": "session/reconnect"})
	_assert(server.last_gameplay_error() == "SM0_P4_JOIN_REQUIRES_PEER_SYNC", "restarted bootstrap authority cannot JOIN before peer synchronization")

	server.configure_admission_fixture(
		Contracts.AUTHORITY_B,
		Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2),
		true
	)
	server.invoke_join({"logical_player_id": "a", "session_id": "session/reconnect"})
	_assert(server.last_gameplay_error() == "SM0_P4_JOIN_REQUIRES_COMMITTED_ACTIVATION", "HELLO-advanced target cannot generic-JOIN before transfer commit")
	server.free()


func _test_completed_source_tombstone_ignores_newer_unrelated_snapshot() -> void:
	var server = P4TestServer.new()
	var transfer_id := "handoff/sm0/a/2/tombstone"
	var recovery_dir := ProjectSettings.globalize_path(
		"user://sm0-p4-tombstone-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	var make_error := DirAccess.make_dir_recursive_absolute(recovery_dir)
	_assert(make_error == OK, "tombstone regression recovery directory is created")
	if make_error != OK:
		server.free()
		return

	server.configure_admission_fixture(
		Contracts.AUTHORITY_A,
		Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2),
		true
	)
	server._recovery_authority_dir = recovery_dir
	server._recovery_restored = true
	server._recovery_last_phase = "SOURCE_RETIRED"
	server._source_transfer = {"transfer_id": transfer_id}
	server._frozen_transfer_id = transfer_id
	server._p4_state_generation = 0
	server._p4_source_fast.clear()

	var completed := server._p4_persist_state("SOURCE_FAST_COMPLETE", transfer_id)
	_assert(bool(completed.get("success", false)), "completed source side evidence persists")
	var unrelated := server._p4_persist_state("PREWARM_RESERVED", "prewarm/sm0/b/3/reverse")
	_assert(bool(unrelated.get("success", false)), "newer unrelated reverse-prewarm side state persists")

	var global_latest := server._p4_latest_valid_side_snapshot()
	var global_snapshot: Dictionary = Dictionary(global_latest.get("details", {}).get("snapshot", {}))
	_assert(
		String(global_snapshot.get("phase", "")) == "PREWARM_RESERVED",
		"fixture proves unrelated reverse-prewarm is globally newer than source completion"
	)

	var tombstone := server._p4_apply_completed_source_tombstone()
	_assert(
		bool(tombstone.get("success", false)) and bool(Dictionary(tombstone.get("details", {})).get("applied", false)),
		"completed source tombstone uses transfer-scoped evidence despite newer unrelated side state"
	)
	_assert(server._source_transfer.is_empty(), "completed source transfer is cleared by transfer-scoped tombstone")
	server.free()
	_cleanup_directory(recovery_dir)


func _test_reservation_conflict_handler() -> void:
	var server = P4TestServer.new()
	server.configure_admission_fixture(
		Contracts.AUTHORITY_B,
		Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1),
		true
	)
	var first := _make_a_to_b_prewarm("prewarm/sm0/a/2/one")
	var second := _make_a_to_b_prewarm("prewarm/sm0/a/2/two")
	server.install_reservation(first, Time.get_ticks_msec() + 3000)
	server.invoke_prewarm(second)
	_assert(server.last_control_error() == "SM0_HANDOFF_PREWARM_PLAYER_EPOCH_CONFLICT", "second live reservation for same player/epoch is rejected")
	server.free()


func _test_redirect_fingerprint() -> void:
	var client = P4Client.new()
	var redirect := _make_redirect_fixture()
	var base_check: Dictionary = client._p4_validate_redirect_payload(redirect)
	_assert(bool(base_check.get("success", false)), "valid redirect produces replay fingerprint")
	var fingerprint := String(Dictionary(base_check.get("details", {})).get("fingerprint", ""))
	_assert(not fingerprint.is_empty(), "redirect fingerprint exists")
	var exact_check: Dictionary = client._p4_validate_redirect_payload(redirect.duplicate(true))
	_assert(String(Dictionary(exact_check.get("details", {})).get("fingerprint", "")) == fingerprint, "exact redirect duplicate has identical fingerprint")

	var wrong_route := redirect.duplicate(true)
	wrong_route["target_port"] = 24582
	var wrong_route_check: Dictionary = client._p4_validate_redirect_payload(wrong_route)
	_assert(bool(wrong_route_check.get("success", false)), "alternate syntactically-valid redirect route can be fingerprinted")
	_assert(String(Dictionary(wrong_route_check.get("details", {})).get("fingerprint", "")) != fingerprint, "target port participates in redirect replay identity")

	var wrong_player := redirect.duplicate(true)
	wrong_player["player_entity_id"] = "player/a-copy"
	var wrong_player_check: Dictionary = client._p4_validate_redirect_payload(wrong_player)
	_assert(bool(wrong_player_check.get("success", false)), "alternate syntactically-valid player id can be fingerprinted")
	_assert(String(Dictionary(wrong_player_check.get("details", {})).get("fingerprint", "")) != fingerprint, "player entity id participates in redirect replay identity")

	var wrong_epoch := redirect.duplicate(true)
	wrong_epoch["authority_epoch"] = 3
	var wrong_epoch_check: Dictionary = client._p4_validate_redirect_payload(wrong_epoch)
	_assert(not bool(wrong_epoch_check.get("success", false)), "redirect epoch inconsistent with directory is rejected before replay ACK")
	client.free()


func _test_redirect_replay_handler() -> void:
	var client = P4TestClient.new()
	var redirect := _make_redirect_fixture()
	var installed: Dictionary = client.install_completed_redirect(redirect)
	_assert(bool(installed.get("success", false)), "completed redirect replay fixture installs")

	client.invoke_redirect(redirect)
	_assert(client.captured_redirect_acks.size() == 1, "exact completed REDIRECT replay is ACKed")
	_assert(client.last_failure_code().is_empty(), "exact completed REDIRECT replay does not fail client")

	var conflicting := redirect.duplicate(true)
	conflicting["target_port"] = 24582
	client.invoke_redirect(conflicting)
	_assert(client.captured_redirect_acks.is_empty(), "same transfer id with changed REDIRECT route is not ACKed")
	_assert(client.last_failure_code() == "SM0_CLIENT_REDIRECT_REPLAY_CONFLICT", "same transfer id with changed REDIRECT route fails closed")
	client.free()


func _make_fast_fixture() -> Dictionary:
	var directory := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
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
		"handoff/sm0/a/2/test",
		player,
		Contracts.AUTHORITY_A,
		Contracts.AUTHORITY_B,
		Contracts.ZONE_A,
		Contracts.ZONE_B,
		1,
		2,
		1
	)
	var prewarm := _make_a_to_b_prewarm("prewarm/sm0/a/2/test")
	return {
		"directory": directory,
		"package": package,
		"prewarm": prewarm,
		"payload": {
			"transfer_id": String(package.get("transfer_id", "")),
			"package": package.duplicate(true),
			"directory": directory.duplicate(true),
			"prewarm_id": String(prewarm.get("prewarm_id", "")),
			"prewarm_checksum": String(prewarm.get("checksum", "")),
		},
	}


func _make_redirect_fixture() -> Dictionary:
	return {
		"transfer_id": "handoff/sm0/a/2/test",
		"target_authority_id": Contracts.AUTHORITY_B,
		"target_zone_id": Contracts.ZONE_B,
		"target_host": "127.0.0.1",
		"target_port": 24581,
		"authority_epoch": 2,
		"player_entity_id": "player/a",
		"directory": Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2),
	}


func _make_a_to_b_prewarm(prewarm_id: String) -> Dictionary:
	return Contracts.create_handoff_prewarm(
		prewarm_id,
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


func _cleanup_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir():
			DirAccess.remove_absolute(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("SM0 P4 hardening: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SM0 P4 hardening: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
	quit(1)