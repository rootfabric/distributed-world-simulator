extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const P4Server = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd")
const P4Client = preload("res://scripts/runtime/seamless/sm0/sm0_automated_client_node_p4_hardened.gd")

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_test_fast_commit_fingerprint()
	_test_single_reservation_slot()
	_test_redirect_fingerprint()
	_finish()


func _test_fast_commit_fingerprint() -> void:
	var server = P4Server.new()
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
	var prewarm := Contracts.create_handoff_prewarm(
		"prewarm/sm0/a/2/test",
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
	var payload := {
		"transfer_id": String(package.get("transfer_id", "")),
		"package": package.duplicate(true),
		"directory": directory.duplicate(true),
		"prewarm_id": String(prewarm.get("prewarm_id", "")),
		"prewarm_checksum": String(prewarm.get("checksum", "")),
	}
	var fingerprint := server._p4_fast_fingerprint_from_payload(payload)
	_assert(not fingerprint.is_empty(), "FAST_COMMIT fingerprint exists")
	var same := payload.duplicate(true)
	_assert(server._p4_fast_fingerprint_from_payload(same) == fingerprint, "exact FAST_COMMIT duplicate has identical fingerprint")
	var wrong_prewarm_checksum := payload.duplicate(true)
	wrong_prewarm_checksum["prewarm_checksum"] = "conflicting-prewarm-checksum"
	_assert(server._p4_fast_fingerprint_from_payload(wrong_prewarm_checksum) != fingerprint, "prewarm checksum participates in FAST_COMMIT replay identity")
	var wrong_package := payload.duplicate(true)
	var package_copy: Dictionary = package.duplicate(true)
	package_copy["checksum"] = "conflicting-package-checksum"
	wrong_package["package"] = package_copy
	_assert(server._p4_fast_fingerprint_from_payload(wrong_package) != fingerprint, "package checksum participates in FAST_COMMIT replay identity")
	var wrong_directory := payload.duplicate(true)
	var directory_copy: Dictionary = directory.duplicate(true)
	directory_copy["checksum"] = "conflicting-directory-checksum"
	wrong_directory["directory"] = directory_copy
	_assert(server._p4_fast_fingerprint_from_payload(wrong_directory) != fingerprint, "directory checksum participates in FAST_COMMIT replay identity")
	server.free()


func _test_single_reservation_slot() -> void:
	var server = P4Server.new()
	var first := Contracts.create_handoff_prewarm(
		"prewarm/sm0/a/2/one",
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
	var second_same_epoch := Contracts.create_handoff_prewarm(
		"prewarm/sm0/a/2/two",
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


func _test_redirect_fingerprint() -> void:
	var client = P4Client.new()
	var directory := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
	var redirect := {
		"transfer_id": "handoff/sm0/a/2/test",
		"target_authority_id": Contracts.AUTHORITY_B,
		"target_zone_id": Contracts.ZONE_B,
		"target_host": "127.0.0.1",
		"target_port": 24581,
		"authority_epoch": 2,
		"player_entity_id": "player/a",
		"directory": directory.duplicate(true),
	}
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
