extends SceneTree

const CommandEnvelopeScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const GatewayScript = preload("res://scripts/network/loopback/network_command_gateway.gd")
const TransportScript = preload("res://scripts/network/loopback/loopback_command_transport.gd")

var failures: Array[String] = []
var assertions: int = 0
var handler_calls: int = 0
var current_revision: int = 10
var current_authority_epoch: int = 4
var invalid_handler_calls: int = 0
var invalid_handler_node: Node
var contradictory_handler_calls: int = 0
var retryable_handler_calls: int = 0


func _init() -> void:
	var gateway = GatewayScript.new()
	gateway.setup(current_authority_epoch, Callable(self, "_resolve_epoch"))
	_assert(gateway.register_handler("probe.increment", Callable(self, "_handle_increment")), "Handler registration failed")
	_assert(gateway.register_handler("probe.invalid_result", Callable(self, "_handle_invalid_result")), "Invalid-result handler registration failed")
	_assert(gateway.register_handler("probe.contradictory_result", Callable(self, "_handle_contradictory_result")), "Contradictory-result handler registration failed")
	_assert(gateway.register_handler("probe.retryable", Callable(self, "_handle_retryable")), "Retryable handler registration failed")
	_assert(not gateway.register_handler("probe.increment", Callable(self, "_handle_increment")), "Duplicate handler registration succeeded")
	var transport = TransportScript.new()
	transport.setup(gateway)

	var command: Dictionary = CommandEnvelopeScript.create(
		"message/1", "operation/1", "entity/probe", "probe.increment",
		{"amount": 2}, current_revision, current_authority_epoch, 12, 100
	)
	var first_delivery: Dictionary = transport.send(command)
	_assert(bool(first_delivery.get("success", false)), "Loopback transport failed")
	var first_result: Dictionary = first_delivery.get("result", {})
	_assert(String(first_result.get("status", "")) == "SUCCEEDED", "Command did not succeed")
	_assert(int(first_result.get("result_revision", -1)) == 12, "Result revision is incorrect")
	_assert(handler_calls == 1, "Handler was not called exactly once")

	var replay: Dictionary = command.duplicate(true)
	replay["message_id"] = "message/2"
	replay["sent_at_monotonic_ms"] = 200
	var replay_delivery: Dictionary = transport.send(replay)
	_assert(String(replay_delivery.get("result", {}).get("status", "")) == "SUCCEEDED", "Exact replay did not return success")
	_assert(String(replay_delivery.get("result", {}).get("message_id", "")) == "message/2", "Replay response did not correlate the current transport message")
	_assert(handler_calls == 1, "Exact replay executed handler twice")
	_assert(int(replay_delivery.get("result", {}).get("result_revision", -1)) == 12, "Replay changed result revision")

	var conflict: Dictionary = replay.duplicate(true)
	conflict["message_id"] = "message/3"
	conflict["payload"] = {"amount": 3}
	var conflict_delivery: Dictionary = transport.send(conflict)
	_assert(String(conflict_delivery.get("result", {}).get("error_code", "")) == "OPERATION_ID_CONFLICT", "Operation id conflict was not detected")
	_assert(handler_calls == 1, "Conflicting operation executed handler")

	var stale: Dictionary = CommandEnvelopeScript.create(
		"message/4", "operation/2", "entity/probe", "probe.increment",
		{"amount": 1}, current_revision, current_authority_epoch - 1, 13, 300
	)
	var stale_delivery: Dictionary = transport.send(stale)
	_assert(String(stale_delivery.get("result", {}).get("error_code", "")) == "STALE_AUTHORITY_EPOCH", "Stale authority epoch was accepted")
	_assert(int(stale_delivery.get("result", {}).get("authority_epoch", 0)) == current_authority_epoch, "Stale response did not route current epoch")
	_assert(handler_calls == 1, "Stale command executed handler")

	var unknown: Dictionary = CommandEnvelopeScript.create(
		"message/5", "operation/3", "entity/probe", "probe.unknown",
		{}, current_revision, current_authority_epoch, 14, 400
	)
	var unknown_delivery: Dictionary = transport.send(unknown)
	_assert(String(unknown_delivery.get("result", {}).get("error_code", "")) == "UNKNOWN_COMMAND_TYPE", "Unknown command type was accepted")

	var empty_message_id: Dictionary = command.duplicate(true)
	empty_message_id["message_id"] = ""
	empty_message_id["operation_id"] = "operation/invalid-message"
	var empty_message_delivery: Dictionary = transport.send(empty_message_id)
	_assert(bool(empty_message_delivery.get("success", false)), "Malformed empty message_id did not return a valid rejection envelope")
	_assert(String(empty_message_delivery.get("result", {}).get("status", "")) == "REJECTED", "Malformed empty message_id was not rejected")
	_assert(String(empty_message_delivery.get("result", {}).get("error_code", "")) == "EMPTY_FIELD", "Malformed empty message_id lost its validation error")
	_assert(String(empty_message_delivery.get("result", {}).get("message_id", "")) == "message/invalid", "Malformed message_id did not receive a safe correlation placeholder")
	_assert(String(empty_message_delivery.get("result", {}).get("operation_id", "")) == "operation/invalid-message", "Valid operation_id was not preserved for malformed message_id")

	var empty_operation_id: Dictionary = command.duplicate(true)
	empty_operation_id["message_id"] = "message/invalid-operation"
	empty_operation_id["operation_id"] = "   "
	var empty_operation_delivery: Dictionary = transport.send(empty_operation_id)
	_assert(bool(empty_operation_delivery.get("success", false)), "Malformed empty operation_id did not return a valid rejection envelope")
	_assert(String(empty_operation_delivery.get("result", {}).get("status", "")) == "REJECTED", "Malformed empty operation_id was not rejected")
	_assert(String(empty_operation_delivery.get("result", {}).get("error_code", "")) == "EMPTY_FIELD", "Malformed empty operation_id lost its validation error")
	_assert(String(empty_operation_delivery.get("result", {}).get("message_id", "")) == "message/invalid-operation", "Valid message_id was not preserved for malformed operation_id")
	_assert(String(empty_operation_delivery.get("result", {}).get("operation_id", "")) == "operation/invalid", "Malformed operation_id did not receive a safe correlation placeholder")

	var numeric_correlation: Dictionary = command.duplicate(true)
	numeric_correlation["message_id"] = 42
	numeric_correlation["operation_id"] = 84
	var numeric_correlation_delivery: Dictionary = transport.send(numeric_correlation)
	_assert(bool(numeric_correlation_delivery.get("success", false)), "Malformed numeric correlation IDs did not return a valid rejection envelope")
	_assert(String(numeric_correlation_delivery.get("result", {}).get("error_code", "")) == "INVALID_FIELD_TYPE", "Malformed numeric correlation IDs lost their validation error")
	_assert(String(numeric_correlation_delivery.get("result", {}).get("message_id", "")) == "message/invalid", "Numeric message_id was string-coerced instead of replaced")
	_assert(String(numeric_correlation_delivery.get("result", {}).get("operation_id", "")) == "operation/invalid", "Numeric operation_id was string-coerced instead of replaced")

	var invalid_handler_command: Dictionary = CommandEnvelopeScript.create(
		"message/6", "operation/4", "entity/probe", "probe.invalid_result",
		{"amount": 1}, current_revision, current_authority_epoch, 15, 500
	)
	var invalid_handler_delivery: Dictionary = transport.send(invalid_handler_command)
	_assert(bool(invalid_handler_delivery.get("success", false)), "Gateway did not convert invalid handler output into a valid result envelope")
	var invalid_handler_result: Dictionary = invalid_handler_delivery.get("result", {})
	_assert(String(invalid_handler_result.get("status", "")) == "REJECTED", "Invalid handler output was not rejected")
	_assert(String(invalid_handler_result.get("error_code", "")) == "INVALID_HANDLER_RESULT", "Invalid handler output returned the wrong error")
	_assert(bool(invalid_handler_result.get("payload", {}).get("requires_snapshot", false)), "Invalid handler result did not request authoritative resynchronization")
	_assert(invalid_handler_calls == 1, "Invalid handler did not execute exactly once")
	var invalid_handler_replay: Dictionary = invalid_handler_command.duplicate(true)
	invalid_handler_replay["message_id"] = "message/7"
	var invalid_handler_replay_delivery: Dictionary = transport.send(invalid_handler_replay)
	_assert(bool(invalid_handler_replay_delivery.get("success", false)), "Cached invalid-handler rejection is not serializable")
	_assert(String(invalid_handler_replay_delivery.get("result", {}).get("error_code", "")) == "INVALID_HANDLER_RESULT", "Invalid-handler replay changed terminal result")
	_assert(String(invalid_handler_replay_delivery.get("result", {}).get("message_id", "")) == "message/7", "Invalid-handler replay did not correlate current message")
	_assert(invalid_handler_calls == 1, "Invalid-handler replay executed the mutation twice")
	if invalid_handler_node != null:
		invalid_handler_node.free()
		invalid_handler_node = null

	var contradictory_command: Dictionary = CommandEnvelopeScript.create(
		"message/8", "operation/5", "entity/probe", "probe.contradictory_result",
		{"amount": 1}, current_revision, current_authority_epoch, 16, 600
	)
	var contradictory_delivery: Dictionary = transport.send(contradictory_command)
	_assert(bool(contradictory_delivery.get("success", false)), "Contradictory handler output was not converted into a valid rejection")
	_assert(String(contradictory_delivery.get("result", {}).get("error_code", "")) == "INVALID_HANDLER_RESULT", "success=true retryable=true was not rejected")
	_assert(contradictory_handler_calls == 1, "Contradictory handler did not execute exactly once")
	var contradictory_replay: Dictionary = contradictory_command.duplicate(true)
	contradictory_replay["message_id"] = "message/9"
	var contradictory_replay_delivery: Dictionary = transport.send(contradictory_replay)
	_assert(String(contradictory_replay_delivery.get("result", {}).get("error_code", "")) == "INVALID_HANDLER_RESULT", "Contradictory handler replay changed terminal result")
	_assert(contradictory_handler_calls == 1, "Contradictory handler replay repeated the mutation")

	var retryable_command: Dictionary = CommandEnvelopeScript.create(
		"message/10", "operation/6", "entity/probe", "probe.retryable",
		{}, current_revision, current_authority_epoch, 17, 700
	)
	var retryable_first: Dictionary = transport.send(retryable_command)
	_assert(String(retryable_first.get("result", {}).get("status", "")) == "RETRYABLE", "Retryable failure did not produce RETRYABLE status")
	var retryable_replay: Dictionary = retryable_command.duplicate(true)
	retryable_replay["message_id"] = "message/11"
	var retryable_second: Dictionary = transport.send(retryable_replay)
	_assert(String(retryable_second.get("result", {}).get("status", "")) == "RETRYABLE", "Retryable redelivery did not stay retryable")
	_assert(retryable_handler_calls == 2, "Retryable result was incorrectly stored as terminal")

	gateway = null
	transport = null
	_finish()


func _resolve_epoch(_entity_id: String) -> int:
	return current_authority_epoch


func _handle_increment(payload: Dictionary, envelope: Dictionary) -> Dictionary:
	handler_calls += 1
	if int(envelope.get("expected_revision", -1)) != current_revision:
		return {
			"success": false,
			"error_code": "REVISION_CONFLICT",
			"result_revision": current_revision,
		}
	current_revision += int(payload.get("amount", 0))
	return {
		"success": true,
		"result_revision": current_revision,
		"payload": {"value": current_revision},
	}


func _handle_invalid_result(_payload: Dictionary, _envelope: Dictionary) -> Dictionary:
	invalid_handler_calls += 1
	invalid_handler_node = Node.new()
	return {
		"success": true,
		"result_revision": current_revision + 1,
		"payload": {"forbidden_node": invalid_handler_node},
	}


func _handle_contradictory_result(_payload: Dictionary, _envelope: Dictionary) -> Dictionary:
	contradictory_handler_calls += 1
	current_revision += 1
	return {
		"success": true,
		"retryable": true,
		"result_revision": current_revision,
		"payload": {"value": current_revision},
	}


func _handle_retryable(_payload: Dictionary, _envelope: Dictionary) -> Dictionary:
	retryable_handler_calls += 1
	return {
		"success": false,
		"retryable": true,
		"error_code": "DEPENDENCY_BUSY",
		"result_revision": current_revision,
		"payload": {},
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 loopback command transport: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 loopback command transport: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
