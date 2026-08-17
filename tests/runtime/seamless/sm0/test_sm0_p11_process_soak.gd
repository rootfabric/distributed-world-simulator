extends SceneTree

const PORTS := {
	"authority/sm0/a": 27020,
	"authority/sm0/b": 27021,
	"authority/sm0/c": 27022,
}
const AUTHORITIES: Array[String] = ["authority/sm0/a", "authority/sm0/b", "authority/sm0/c"]

var _socket: PacketPeerUDP
var _assertions := 0
var _failures: Array[String] = []
var _request_sequence := 0
var _iterations := 120

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_iterations = maxi(1, int(args.get("iterations", 120)))
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(0, "127.0.0.1")
	if bind_result != OK:
		push_error("SM0_P11_DRIVER_BIND_FAILED:%d" % bind_result)
		quit(2)
		return

	# Scenario 1: exact cross-swap, with both operations PREPARED concurrently.
	_seed_writer("player/p11/process/x1", "identity/p11/process/x1", "authority/sm0/a", 1)
	_seed_writer("player/p11/process/x2", "identity/p11/process/x2", "authority/sm0/b", 1)
	var tx1 := _tx("p11/process/swap/x1", "player/p11/process/x1", "identity/p11/process/x1", "authority/sm0/a", "authority/sm0/b", 1)
	var tx2 := _tx("p11/process/swap/x2", "player/p11/process/x2", "identity/p11/process/x2", "authority/sm0/b", "authority/sm0/a", 1)
	_check_success(_prepare_source(tx1), "swap x1 source prepared")
	_check_success(_prepare_source(tx2), "swap x2 source prepared")
	_check_success(_prepare_target(tx2), "swap x2 target shadow")
	_check_success(_prepare_target(tx1), "swap x1 target shadow")
	_check_error(_commit_target(tx1, "forged-proof"), "SM0_P11_PROCESS_RETIREMENT_PROOF_INVALID", "commit before retirement proof rejected")
	var retired1 := _retire_source(tx1)
	var retired2 := _retire_source(tx2)
	_check_success(retired1, "swap x1 retired")
	_check_success(retired2, "swap x2 retired")
	_check_success(_commit_target(tx2, _token(retired2)), "swap x2 committed first")
	_check_success(_commit_target(tx1, _token(retired1)), "swap x1 committed second")
	_assert_global("player/p11/process/x1", "identity/p11/process/x1", "authority/sm0/b", 2, "swap x1")
	_assert_global("player/p11/process/x2", "identity/p11/process/x2", "authority/sm0/a", 2, "swap x2")

	# Scenario 2: A->B while B->C.
	_seed_writer("player/p11/process/y1", "identity/p11/process/y1", "authority/sm0/a", 1)
	_seed_writer("player/p11/process/y2", "identity/p11/process/y2", "authority/sm0/b", 1)
	var ty1 := _tx("p11/process/fanout/y1", "player/p11/process/y1", "identity/p11/process/y1", "authority/sm0/a", "authority/sm0/b", 1)
	var ty2 := _tx("p11/process/fanout/y2", "player/p11/process/y2", "identity/p11/process/y2", "authority/sm0/b", "authority/sm0/c", 1)
	_check_success(_prepare_target(ty1), "fanout target y1 prepared before source")
	_check_success(_prepare_target(ty2), "fanout target y2 prepared before source")
	_check_success(_prepare_source(ty1), "fanout source y1")
	_check_success(_prepare_source(ty2), "fanout source y2")
	var ry1 := _retire_source(ty1)
	var ry2 := _retire_source(ty2)
	_check_success(ry1, "fanout retire y1")
	_check_success(ry2, "fanout retire y2")
	_check_success(_commit_target(ty1, _token(ry1)), "fanout commit y1")
	_check_success(_commit_target(ty2, _token(ry2)), "fanout commit y2")
	_assert_global("player/p11/process/y1", "identity/p11/process/y1", "authority/sm0/b", 2, "fanout y1")
	_assert_global("player/p11/process/y2", "identity/p11/process/y2", "authority/sm0/c", 2, "fanout y2")

	# Fault isolation: unavailable C rejects work while unrelated A writer stays live.
	_seed_writer("item/p11/process/control", "identity/p11/process/control", "authority/sm0/a", 1)
	_check_success(_rpc("authority/sm0/c", "SET_AVAILABLE", {"available": false}), "C marked unavailable")
	var unavailable_target := _tx("p11/process/unavailable", "item/p11/process/probe", "identity/p11/process/probe", "authority/sm0/a", "authority/sm0/c", 1)
	_check_error(_prepare_target(unavailable_target), "SM0_P11_PROCESS_AUTHORITY_UNAVAILABLE", "unavailable target rejects shadow")
	_check_success(_rpc("authority/sm0/a", "INTERACT", {"operation_id": "p11/process/control/use", "aggregate_id": "item/p11/process/control", "expected_epoch": 1}), "unrelated A interaction continues")
	_check_success(_rpc("authority/sm0/c", "SET_AVAILABLE", {"available": true}), "C restored")

	# Bounded deterministic soak. Two aggregates cross concurrently every iteration.
	_seed_writer("player/p11/soak/one", "identity/p11/soak/one", "authority/sm0/a", 1)
	_seed_writer("player/p11/soak/two", "identity/p11/soak/two", "authority/sm0/b", 1)
	var owner_one := "authority/sm0/a"
	var owner_two := "authority/sm0/b"
	var epoch_one := 1
	var epoch_two := 1
	for iteration in range(_iterations):
		var target_one := _next_authority(owner_one)
		var target_two := _next_authority_reverse(owner_two)
		var op_one := "p11/soak/%d/one" % iteration
		var op_two := "p11/soak/%d/two" % iteration
		var one := _tx(op_one, "player/p11/soak/one", "identity/p11/soak/one", owner_one, target_one, epoch_one)
		var two := _tx(op_two, "player/p11/soak/two", "identity/p11/soak/two", owner_two, target_two, epoch_two)

		# Deterministic packet reorder: target-first on even rounds, source-first on odd rounds.
		if iteration % 2 == 0:
			_check_success(_prepare_target(one), "soak %d target one first" % iteration)
			_check_success(_prepare_target(two), "soak %d target two first" % iteration)
			_check_success(_prepare_source(one), "soak %d source one second" % iteration)
			_check_success(_prepare_source(two), "soak %d source two second" % iteration)
		else:
			_check_success(_prepare_source(one), "soak %d source one first" % iteration)
			_check_success(_prepare_source(two), "soak %d source two first" % iteration)
			_check_success(_prepare_target(two), "soak %d target two second" % iteration)
			_check_success(_prepare_target(one), "soak %d target one second" % iteration)

		if iteration % 9 == 0:
			var duplicate_prepare := _prepare_source(one)
			_check_success(duplicate_prepare, "soak duplicate prepare")
			_check(bool(Dictionary(duplicate_prepare.get("details", {})).get("replay", false)), "duplicate prepare marked replay")
		if iteration % 11 == 0:
			_check_error(_rpc(owner_one, "INTERACT", {"operation_id": "p11/soak/frozen/%d" % iteration, "aggregate_id": "player/p11/soak/one", "expected_epoch": epoch_one}), "SM0_P11_PROCESS_INTERACTION_FROZEN", "frozen source interaction rejected")

		var retire_one := _retire_source(one)
		var retire_two := _retire_source(two)
		_check_success(retire_one, "soak retire one")
		_check_success(retire_two, "soak retire two")
		if iteration % 2 == 0:
			_check_success(_commit_target(two, _token(retire_two)), "soak commit two first")
			_check_success(_commit_target(one, _token(retire_one)), "soak commit one second")
		else:
			_check_success(_commit_target(one, _token(retire_one)), "soak commit one first")
			_check_success(_commit_target(two, _token(retire_two)), "soak commit two second")

		owner_one = target_one
		owner_two = target_two
		epoch_one += 1
		epoch_two += 1

		if iteration % 7 == 0:
			var replay_commit := _commit_target(one, _token(retire_one))
			_check_success(replay_commit, "duplicate fast commit replay")
			_check(bool(Dictionary(replay_commit.get("details", {})).get("replay", false)), "duplicate commit marked replay")
		if iteration % 13 == 0:
			_check_error(_rpc(_previous_authority(owner_one), "INTERACT", {"operation_id": "p11/soak/stale/%d" % iteration, "aggregate_id": "player/p11/soak/one", "expected_epoch": epoch_one - 1}), "SM0_P11_PROCESS_INTERACTION_NOT_WRITER", "stale ghost cannot interact")

		_assert_global("player/p11/soak/one", "identity/p11/soak/one", owner_one, epoch_one, "soak one %d" % iteration)
		_assert_global("player/p11/soak/two", "identity/p11/soak/two", owner_two, epoch_two, "soak two %d" % iteration)

	# Shutdown is part of the process lifecycle proof.
	_check_success(_rpc("authority/sm0/a", "SHUTDOWN", {}), "shutdown A")
	_check_success(_rpc("authority/sm0/b", "SHUTDOWN", {}), "shutdown B")
	_check_success(_rpc("authority/sm0/c", "SHUTDOWN", {}), "shutdown C")
	_finish()

func _seed_writer(aggregate_id: String, identity_id: String, owner: String, epoch: int) -> void:
	_check_success(_rpc(owner, "SEED", {"aggregate_id": aggregate_id, "identity_id": identity_id, "authority_epoch": epoch, "active_writer": true}), "seed %s" % aggregate_id)

func _tx(operation_id: String, aggregate_id: String, identity_id: String, source: String, target: String, source_epoch: int) -> Dictionary:
	return {"operation_id": operation_id, "aggregate_id": aggregate_id, "identity_id": identity_id, "source": source, "target": target, "source_epoch": source_epoch, "target_epoch": source_epoch + 1}

func _prepare_source(tx: Dictionary) -> Dictionary:
	return _rpc(String(tx["source"]), "PREPARE_SOURCE", {"operation_id": tx["operation_id"], "aggregate_id": tx["aggregate_id"], "target_authority_id": tx["target"], "expected_epoch": tx["source_epoch"]})

func _prepare_target(tx: Dictionary) -> Dictionary:
	return _rpc(String(tx["target"]), "PREPARE_TARGET", {"operation_id": tx["operation_id"], "aggregate_id": tx["aggregate_id"], "identity_id": tx["identity_id"], "source_authority_id": tx["source"], "source_epoch": tx["source_epoch"], "target_epoch": tx["target_epoch"]})

func _retire_source(tx: Dictionary) -> Dictionary:
	return _rpc(String(tx["source"]), "RETIRE_SOURCE", {"operation_id": tx["operation_id"]})

func _commit_target(tx: Dictionary, token: String) -> Dictionary:
	return _rpc(String(tx["target"]), "COMMIT_TARGET", {"operation_id": tx["operation_id"], "retirement_token": token})

func _token(response: Dictionary) -> String:
	return String(Dictionary(response.get("details", {})).get("retirement_token", ""))

func _assert_global(aggregate_id: String, identity_id: String, expected_owner: String, expected_epoch: int, label: String) -> void:
	var statuses := _statuses()
	var writers := 0
	var identity_matches := 0
	var observed_epoch := 0
	for authority_id in AUTHORITIES:
		var details: Dictionary = Dictionary(Dictionary(statuses[authority_id]).get("details", {}))
		var aggregates: Dictionary = Dictionary(details.get("aggregates", {}))
		if not aggregates.has(aggregate_id):
			continue
		var record: Dictionary = Dictionary(aggregates[aggregate_id])
		if String(record.get("identity_id", "")) == identity_id:
			identity_matches += 1
		if bool(record.get("active_writer", false)):
			writers += 1
			_check_equal(authority_id, expected_owner, "%s writer owner" % label)
			observed_epoch = int(record.get("authority_epoch", 0))
	_check_equal(writers, 1, "%s exactly one active writer" % label)
	_check(identity_matches >= 1, "%s identity remains represented" % label)
	_check_equal(observed_epoch, expected_epoch, "%s authority epoch" % label)

func _statuses() -> Dictionary:
	return {
		"authority/sm0/a": _rpc("authority/sm0/a", "STATUS", {}),
		"authority/sm0/b": _rpc("authority/sm0/b", "STATUS", {}),
		"authority/sm0/c": _rpc("authority/sm0/c", "STATUS", {}),
	}

func _next_authority(authority_id: String) -> String:
	match authority_id:
		"authority/sm0/a": return "authority/sm0/b"
		"authority/sm0/b": return "authority/sm0/c"
		_: return "authority/sm0/a"

func _next_authority_reverse(authority_id: String) -> String:
	match authority_id:
		"authority/sm0/a": return "authority/sm0/c"
		"authority/sm0/c": return "authority/sm0/b"
		_: return "authority/sm0/a"

func _previous_authority(authority_id: String) -> String:
	match authority_id:
		"authority/sm0/a": return "authority/sm0/c"
		"authority/sm0/b": return "authority/sm0/a"
		_: return "authority/sm0/b"

func _rpc(authority_id: String, command: String, payload: Dictionary) -> Dictionary:
	_request_sequence += 1
	var request_id := "p11-driver-%d" % _request_sequence
	var port := int(PORTS.get(authority_id, 0))
	if port < 1:
		return {"success": false, "error_code": "SM0_P11_DRIVER_AUTHORITY_UNKNOWN", "details": {}}
	if _socket.set_dest_address("127.0.0.1", port) != OK:
		return {"success": false, "error_code": "SM0_P11_DRIVER_DESTINATION_FAILED", "details": {}}
	var message := {"request_id": request_id, "command": command, "payload": payload.duplicate(true)}
	if _socket.put_packet(JSON.stringify(message, "", false, true).to_utf8_buffer()) != OK:
		return {"success": false, "error_code": "SM0_P11_DRIVER_SEND_FAILED", "details": {}}
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		while _socket.get_available_packet_count() > 0:
			var decoded = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
			if decoded is Dictionary and String(Dictionary(decoded).get("request_id", "")) == request_id:
				return Dictionary(decoded)
		OS.delay_msec(1)
	return {"success": false, "error_code": "SM0_P11_DRIVER_TIMEOUT", "details": {"authority_id": authority_id, "command": command}}

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s expected success, got %s" % [label, String(result.get("error_code", ""))])

func _check_error(result: Dictionary, error_code: String, label: String) -> void:
	_check(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s expected %s got %s" % [label, error_code, String(result.get("error_code", ""))])

func _check_equal(actual, expected, label: String) -> void:
	_check(actual == expected, "%s expected %s got %s" % [label, str(expected), str(actual)])

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error("P11 process assertion failed: %s" % failure)
		print("SM0 P11 process-isolated simultaneous crossings + soak: FAIL (%d iterations / %d assertions / %d failures)" % [_iterations, _assertions, _failures.size()])
		quit(1)
		return
	print("SM0 P11 process-isolated simultaneous crossings + soak: PASS (%d iterations / %d assertions)" % [_iterations, _assertions])
	quit(0)

static func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for raw in args:
		var text := String(raw)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var separator := body.find("=")
		if separator < 0:
			parsed[body] = true
		else:
			parsed[body.substr(0, separator)] = body.substr(separator + 1)
	return parsed
