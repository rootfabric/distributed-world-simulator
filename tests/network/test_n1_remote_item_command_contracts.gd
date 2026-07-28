extends SceneTree

const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")
const MoveResultScript = preload("res://scripts/network/contracts/item_move_to_container_result.gd")
const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_payload_contract()
	_test_result_contract()
	_test_authoritative_move_and_replay()
	_test_authority_and_command_fences()
	_test_transactional_rollback()
	_finish()


func _test_payload_contract() -> void:
	var payload: Dictionary = MovePayloadScript.create(
		"session/test", "sim-n1", "item/n1/test", "container/source", "container/destination", 0
	)
	_assert_ok(MovePayloadScript.validate(payload), "Valid item move payload rejected")
	var normalized_payload: Dictionary = MovePayloadScript.normalize(payload)
	_assert_ok(MovePayloadScript.validate(normalized_payload), "Normalized item move payload invalid")
	_assert(MovePayloadScript.normalize(normalized_payload) == normalized_payload, "Item move payload normalization is not idempotent")
	for field in MovePayloadScript.FIELDS:
		var missing: Dictionary = payload.duplicate(true)
		missing.erase(field)
		_assert(not bool(MovePayloadScript.validate(missing).get("success", false)), "Missing payload field accepted: %s" % field)
	var extra: Dictionary = payload.duplicate(true)
	extra["extra"] = true
	_assert_code(MovePayloadScript.validate(extra), "UNEXPECTED_FIELD", "Extra payload field accepted")
	var same: Dictionary = payload.duplicate(true)
	same["destination_container_id"] = same["source_container_id"]
	_assert_code(MovePayloadScript.validate(same), "SAME_CONTAINER", "Same source/destination accepted")
	var invalid_revision: Dictionary = payload.duplicate(true)
	invalid_revision["expected_item_revision"] = -1
	_assert_code(MovePayloadScript.validate(invalid_revision), "INVALID_ITEM_REVISION", "Negative item revision accepted")
	var bad_identifier: Dictionary = payload.duplicate(true)
	bad_identifier["item_id"] = " item/n1/test"
	_assert_code(MovePayloadScript.validate(bad_identifier), "INVALID_IDENTIFIER", "Noncanonical item identifier accepted")
	var runtime_object: Dictionary = payload.duplicate(true)
	runtime_object["item_id"] = Callable(self, "_finish")
	_assert(not bool(MovePayloadScript.validate(runtime_object).get("success", false)), "Runtime object payload accepted")


func _test_result_contract() -> void:
	var value: Dictionary = MoveResultScript.create(
		"entity/item/test", "item/n1/test", "container/source", "container/destination",
		1, "delta/n1/test", "a".repeat(64), 501
	)
	_assert_ok(MoveResultScript.validate(value), "Valid item move result rejected")
	for field in MoveResultScript.FIELDS:
		var missing: Dictionary = value.duplicate(true)
		missing.erase(field)
		_assert(not bool(MoveResultScript.validate(missing).get("success", false)), "Missing result field accepted: %s" % field)
	var bad_checksum: Dictionary = value.duplicate(true)
	bad_checksum["result_snapshot_checksum"] = "A".repeat(64)
	_assert_code(MoveResultScript.validate(bad_checksum), "INVALID_CHECKSUM", "Uppercase result checksum accepted")
	var false_commit: Dictionary = value.duplicate(true)
	false_commit["mutation_committed"] = false
	_assert_code(MoveResultScript.validate(false_commit), "MUTATION_NOT_COMMITTED", "Uncommitted success result accepted")
	var invalid_identifier: Dictionary = value.duplicate(true)
	invalid_identifier["delta_id"] = "delta/N1/invalid"
	_assert_code(MoveResultScript.validate(invalid_identifier), "INVALID_IDENTIFIER", "Noncanonical result identifier accepted")
	var same_container: Dictionary = value.duplicate(true)
	same_container["destination_container_id"] = same_container["source_container_id"]
	_assert_code(MoveResultScript.validate(same_container), "SAME_CONTAINER", "Result with same source/destination accepted")
	var runtime_result: Dictionary = value.duplicate(true)
	runtime_result["entity_id"] = Callable(self, "_finish")
	_assert(not bool(MoveResultScript.validate(runtime_result).get("success", false)), "Runtime object result accepted")


func _test_authoritative_move_and_replay() -> void:
	var authority = _configured_authority()
	var initial_snapshot: Dictionary = authority.create_snapshot()
	var initial_report: Dictionary = authority.get_report()
	_assert(int(initial_snapshot["state_revision"]) == AuthorityScript.INITIAL_REVISION, "Initial aggregate revision mismatch")
	_assert(int(initial_snapshot["server_tick"]) == AuthorityScript.INITIAL_SERVER_TICK, "Initial server tick mismatch")
	_assert(bool(initial_report["source_contains_item"]), "Command item missing from source before move")
	_assert(not bool(initial_report["destination_contains_item"]), "Command item already in destination")
	var stale_tick_result: Dictionary = authority.aggregate.apply_domain_components(
		{}, -1, authority.authority_epoch, AuthorityScript.INITIAL_SERVER_TICK - 1
	)
	_assert_code(stale_tick_result, "STALE_SIMULATION_TICK", "Aggregate accepted domain tick rollback")
	_assert(int(authority.aggregate.state_revision) == AuthorityScript.INITIAL_REVISION, "Rejected tick changed aggregate revision")
	var command: Dictionary = _make_command(authority, "operation/n1/test/move", "message/n1/test/move")
	var result: Dictionary = authority.handle_command(command)
	_assert_ok(ResultScript.validate(result), "Gateway returned invalid success result")
	_assert(String(result["status"]) == "SUCCEEDED", "Authoritative move did not succeed: %s" % result)
	_assert_ok(MoveResultScript.validate(result["payload"]), "Move success payload invalid")
	var delta: Dictionary = authority.get_delta(String(command["operation_id"]))
	_assert_ok(DeltaScript.validate(delta), "Authoritative move delta invalid")
	var applied: Dictionary = DeltaScript.apply_to_snapshot(initial_snapshot, delta)
	_assert_ok(applied, "Authoritative move delta did not apply")
	var final_snapshot: Dictionary = authority.get_final_snapshot(String(command["operation_id"]))
	_assert(String(applied["snapshot"]["checksum"]) == String(final_snapshot["checksum"]), "Delta result differs from authoritative snapshot")
	_assert(String(result["payload"]["result_snapshot_checksum"]) == String(final_snapshot["checksum"]), "Command result checksum differs from snapshot")
	var after: Dictionary = authority.get_report()
	_assert(not bool(after["source_contains_item"]), "Moved item remained in source")
	_assert(bool(after["destination_contains_item"]), "Moved item missing from destination")
	_assert(int(after["mutation_count"]) == 1, "Move mutation count is not one")
	_assert(int(after["handler_invocation_count"]) == 1, "Move handler invocation count is not one")
	_assert(int(after["aggregate_revision"]) == AuthorityScript.INITIAL_REVISION + 1, "Aggregate revision did not advance once")
	_assert(int(after["item_revision"]) == 1, "Item revision did not advance once")
	_assert(int(after["server_tick"]) == AuthorityScript.INITIAL_SERVER_TICK + 1, "Server tick did not advance once")
	_assert(int(after["operation_ledger_count"]) == 1, "Item operation ledger did not record move")
	var replay: Dictionary = command.duplicate(true)
	replay["message_id"] = "message/n1/test/replay"
	var replay_result: Dictionary = authority.handle_command(replay)
	_assert(String(replay_result["status"]) == "SUCCEEDED", "Exact replay was not returned as success")
	var original_without_message: Dictionary = result.duplicate(true)
	var replay_without_message: Dictionary = replay_result.duplicate(true)
	original_without_message.erase("message_id")
	replay_without_message.erase("message_id")
	_assert(original_without_message == replay_without_message, "Exact replay result changed")
	var replay_report: Dictionary = authority.get_report()
	_assert(int(replay_report["mutation_count"]) == 1, "Exact replay mutated authoritative state")
	_assert(int(replay_report["handler_invocation_count"]) == 1, "Exact replay reached command handler")
	_assert(int(replay_report["operation_ledger_count"]) == 1, "Exact replay duplicated item ledger record")
	var conflict: Dictionary = replay.duplicate(true)
	conflict["message_id"] = "message/n1/test/conflict"
	conflict["payload"] = conflict["payload"].duplicate(true)
	conflict["payload"]["destination_container_id"] = "container/other"
	var conflict_result: Dictionary = authority.handle_command(conflict)
	_assert(String(conflict_result["error_code"]) == "OPERATION_ID_CONFLICT", "Conflicting replay was not fenced")
	_assert(int(authority.get_report()["mutation_count"]) == 1, "Conflicting replay mutated state")
	var stale: Dictionary = _make_command(
		authority, "operation/n1/test/stale", "message/n1/test/stale",
		{"expected_revision": AuthorityScript.INITIAL_REVISION, "expected_item_revision": 1}
	)
	var stale_result: Dictionary = authority.handle_command(stale)
	_assert(String(stale_result["status"]) == "REJECTED", "Stale revision command was not rejected")
	_assert(String(stale_result["error_code"]) == "REVISION_CONFLICT", "Stale revision returned wrong error")
	_assert(int(authority.get_report()["mutation_count"]) == 1, "Stale revision mutated state")


func _test_authority_and_command_fences() -> void:
	var stale_epoch_authority = _configured_authority()
	var stale_epoch: Dictionary = _make_command(
		stale_epoch_authority, "operation/n1/test/stale-epoch", "message/n1/test/stale-epoch",
		{"authority_epoch": stale_epoch_authority.authority_epoch - 1}
	)
	var stale_epoch_result: Dictionary = stale_epoch_authority.handle_command(stale_epoch)
	_assert(String(stale_epoch_result["error_code"]) == "STALE_AUTHORITY_EPOCH", "Stale authority epoch accepted")
	_assert(int(stale_epoch_authority.get_report()["handler_invocation_count"]) == 0, "Stale epoch reached handler")
	for scenario in [
		{"name": "owner", "payload": {"authority_owner_id": "sim-other"}, "code": "AUTHORITY_OWNER_MISMATCH"},
		{"name": "session", "payload": {"session_id": "session/other"}, "code": "SESSION_ID_MISMATCH"},
		{"name": "source", "payload": {"source_container_id": "container/other"}, "code": "SOURCE_CONTAINER_MISMATCH"},
		{"name": "destination", "payload": {"destination_container_id": "container/other"}, "code": "DESTINATION_CONTAINER_MISMATCH"},
		{"name": "item", "payload": {"item_id": "item/missing"}, "code": "ITEM_NOT_FOUND"},
		{"name": "item_revision", "payload": {"expected_item_revision": 9}, "code": "ITEM_REVISION_CONFLICT"},
		{"name": "entity", "command": {"entity_id": "entity/item/other"}, "code": "ENTITY_ID_MISMATCH"},
	]:
		var authority = _configured_authority()
		var operation_id: String = "operation/n1/test/fence-%s" % scenario["name"]
		var overrides: Dictionary = scenario.get("command", {}).duplicate(true)
		overrides["payload"] = scenario.get("payload", {}).duplicate(true)
		var command: Dictionary = _make_command(authority, operation_id, "message/%s" % scenario["name"], overrides)
		var result: Dictionary = authority.handle_command(command)
		_assert(String(result["status"]) == "REJECTED", "Fence scenario succeeded: %s" % scenario["name"])
		_assert(String(result["error_code"]) == String(scenario["code"]), "Fence scenario returned wrong code: %s result=%s" % [scenario["name"], result])
		var report: Dictionary = authority.get_report()
		_assert(int(report["mutation_count"]) == 0, "Fence scenario mutated state: %s" % scenario["name"])
		_assert(bool(report["source_contains_item"]), "Fence scenario removed source item: %s" % scenario["name"])
		_assert(not bool(report["destination_contains_item"]), "Fence scenario inserted destination item: %s" % scenario["name"])


func _test_transactional_rollback() -> void:
	var authority = _configured_authority()
	authority.aggregate.last_simulation_tick = 900
	var before_snapshot: Dictionary = authority.create_snapshot()
	var command: Dictionary = _make_command(authority, "operation/n1/test/rollback", "message/n1/test/rollback")
	var result: Dictionary = authority.handle_command(command)
	_assert(String(result["status"]) == "REJECTED", "Aggregate failure did not reject command")
	_assert(String(result["error_code"]) == "AGGREGATE_UPDATE_FAILED", "Aggregate failure returned wrong error: %s" % result)
	var report: Dictionary = authority.get_report()
	_assert(bool(report["source_contains_item"]), "Rollback did not restore source membership")
	_assert(not bool(report["destination_contains_item"]), "Rollback left destination membership")
	_assert(int(report["mutation_count"]) == 0, "Rollback retained mutation count")
	_assert(int(report["operation_ledger_count"]) == 0, "Rollback retained successful item ledger write")
	_assert(int(report["item_revision"]) == 0, "Rollback did not restore item revision")
	_assert(int(report["aggregate_revision"]) == int(before_snapshot["state_revision"]), "Rollback changed aggregate revision")
	_assert(String(authority.create_snapshot()["checksum"]) == String(before_snapshot["checksum"]), "Rollback changed authoritative snapshot")


func _configured_authority():
	var authority = AuthorityScript.new()
	_assert_ok(authority.setup("sim-n1", 5, 500), "Authority setup failed")
	_assert_ok(authority.bind_session("session/n1/test"), "Authority session bind failed")
	return authority


func _make_command(
	authority,
	operation_id: String,
	message_id: String,
	overrides: Dictionary = {}
) -> Dictionary:
	var snapshot: Dictionary = authority.create_snapshot()
	var inventory: Dictionary = snapshot["domain_components"]["inventory"]
	var payload_overrides: Dictionary = overrides.get("payload", {})
	var payload: Dictionary = MovePayloadScript.create(
		String(payload_overrides.get("session_id", authority.session_id)),
		String(payload_overrides.get("authority_owner_id", snapshot["authority_owner_id"])),
		String(payload_overrides.get("item_id", inventory["command_item_id"])),
		String(payload_overrides.get("source_container_id", inventory["source_container_id"])),
		String(payload_overrides.get("destination_container_id", inventory["destination_container_id"])),
		int(payload_overrides.get("expected_item_revision", inventory["item_revision"]))
	)
	return CommandScript.create(
		message_id,
		operation_id,
		String(overrides.get("entity_id", snapshot["entity_id"])),
		AuthorityScript.COMMAND_TYPE,
		payload,
		int(overrides.get("expected_revision", snapshot["state_revision"])),
		int(overrides.get("authority_epoch", snapshot["authority_epoch"])),
		int(snapshot["server_tick"]),
		1000
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_code(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N1 remote item command contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N1 remote item command contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
