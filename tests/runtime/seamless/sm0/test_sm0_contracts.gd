extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_test_directory()
	_test_handoff_package()
	_test_wire_message()
	_finish()


func _test_directory() -> void:
	var directory_a := Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1)
	_assert(_ok(Contracts.validate_directory(directory_a)), "directory A validates")
	_assert(Contracts.zone_for_x(-0.001) == Contracts.ZONE_A, "negative x belongs to zone A")
	_assert(Contracts.zone_for_x(0.0) == Contracts.ZONE_B, "boundary belongs to zone B")
	var directory_b := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
	_assert(_ok(Contracts.validate_directory(directory_b)), "directory B validates")
	_assert(String(directory_b.owner_zone_id) == Contracts.ZONE_B, "directory owner and zone agree")
	var tampered := directory_b.duplicate(true)
	tampered["authority_epoch"] = 99
	_assert(_error(Contracts.validate_directory(tampered)) == "SM0_DIRECTORY_CHECKSUM_MISMATCH", "tampered directory rejected")


func _test_handoff_package() -> void:
	var player := {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"ownership_epoch": 1,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.5, "y": 0.0, "z": 0.0},
		"orientation_yaw": 1.0,
		"last_input_sequence": 10,
		"state_revision": 4,
	}
	var package := Contracts.create_handoff_package(
		"handoff/sm0/a/2/1",
		player,
		Contracts.AUTHORITY_A,
		Contracts.AUTHORITY_B,
		Contracts.ZONE_A,
		Contracts.ZONE_B,
		1,
		2,
		1
	)
	_assert(_ok(Contracts.validate_handoff_package(package)), "handoff package validates")
	_assert(int(package.target_authority_epoch) == 2, "target epoch increments once")
	_assert(String(package.player_entity_id) == "player/a", "player entity identity is stable")
	var wrong_route := package.duplicate(true)
	wrong_route["target_zone_id"] = Contracts.ZONE_A
	wrong_route["checksum"] = ""
	wrong_route = _refinalize(wrong_route)
	_assert(_error(Contracts.validate_handoff_package(wrong_route)) == "SM0_HANDOFF_ZONE_ROUTE_INVALID", "wrong zone route rejected")
	var bad_identity := package.duplicate(true)
	bad_identity["player_entity_id"] = "player/a-copy"
	bad_identity["checksum"] = ""
	bad_identity = _refinalize(bad_identity)
	_assert(_error(Contracts.validate_handoff_package(bad_identity)) == "SM0_HANDOFF_PLAYER_IDENTITY_MISMATCH", "identity mutation rejected")


func _test_wire_message() -> void:
	var message := Contracts.create_message("CLIENT_STATUS", {"probe": 1}, "request/1")
	_assert(_ok(Contracts.validate_message(message)), "wire message validates")
	var decoded := Contracts.decode_message(Contracts.encode_message(message))
	_assert(_ok(Contracts.validate_message(decoded)), "wire message round-trip validates")
	_assert(String(decoded.request_id) == "request/1", "request id survives wire round-trip")
	var tampered := decoded.duplicate(true)
	tampered["type"] = "OTHER"
	_assert(_error(Contracts.validate_message(tampered)) == "SM0_MESSAGE_CHECKSUM_MISMATCH", "wire tamper rejected")


func _refinalize(value: Dictionary) -> Dictionary:
	var Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
	return Utils.finalize_json_checksum(value)


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _error(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _finish() -> void:
	if _failures.is_empty():
		print("SM0 contracts: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SM0 contracts: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
	quit(1)
