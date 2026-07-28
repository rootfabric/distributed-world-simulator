extends SceneTree

const BoundaryScript = preload("res://scripts/network/transports/network_transport_boundary.gd")
const PortScript = preload("res://scripts/network/transports/network_transport_port.gd")
const LoopbackPortScript = preload("res://scripts/network/transports/loopback_transport_port.gd")

var failures: Array[String] = []
var assertions: int = 0
var handler_calls: int = 0


class ForgedPort:
	extends RefCounted

	func get_descriptor() -> Dictionary:
		return {
			"schema": "planet_simulator.network_transport_port.v1",
			"transport_kind": "FORGED",
			"supports_server": true,
			"supports_client": true,
			"synchronous_delivery": true,
		}


class InvalidDescriptorPort:
	extends "res://scripts/network/transports/network_transport_port.gd"

	func get_descriptor() -> Dictionary:
		return {
			"schema": SCHEMA,
			"transport_kind": "INVALID",
			"supports_server": true,
			"supports_client": true,
			"synchronous_delivery": true,
			"extra": true,
		}


class FailingPort:
	extends "res://scripts/network/transports/network_transport_port.gd"

	func get_descriptor() -> Dictionary:
		return {
			"schema": SCHEMA,
			"transport_kind": "FAILING",
			"supports_server": false,
			"supports_client": true,
			"synchronous_delivery": true,
		}

	func connect_client(_endpoint: Dictionary) -> Dictionary:
		return _failure("CONNECT_PROBE_FAILURE")


class ReentrantPort:
	extends "res://scripts/network/transports/network_transport_port.gd"

	var boundary

	func get_descriptor() -> Dictionary:
		return {
			"schema": SCHEMA,
			"transport_kind": "REENTRANT",
			"supports_server": false,
			"supports_client": true,
			"synchronous_delivery": true,
		}

	func connect_client(_endpoint: Dictionary) -> Dictionary:
		return _success()

	func send_message(_message_type: String, _payload: Dictionary) -> Dictionary:
		var nested: Dictionary = boundary.send("COMMAND", {"nested": true})
		return _success({"nested_error_code": String(nested.get("error_code", ""))})


func _init() -> void:
	_test_configuration_fences()
	_test_client_lifecycle_and_send()
	_test_server_lifecycle()
	_test_failure_state()
	_test_queue_fence()
	_finish()


func _test_configuration_fences() -> void:
	var boundary = BoundaryScript.new()
	_assert(_error(boundary.connect_client({"host": "loopback"})) == "NOT_CONFIGURED", "Unconfigured client connect was accepted")
	_assert(_error(boundary.start_server({"host": "loopback"})) == "NOT_CONFIGURED", "Unconfigured server start was accepted")
	_assert(_error(boundary.configure(ForgedPort.new())) == "INVALID_TRANSPORT_PORT", "Forged port was accepted")
	_assert(_error(boundary.configure(InvalidDescriptorPort.new())) == "INVALID_PORT_DESCRIPTOR", "Port with extra descriptor field was accepted")
	_assert(_error(boundary.configure(LoopbackPortScript.new(), 0, 1)) == "INVALID_PAYLOAD_LIMIT", "Zero payload limit was accepted")
	_assert(_error(boundary.configure(LoopbackPortScript.new(), 64, 0)) == "INVALID_QUEUE_LIMIT", "Zero queue limit was accepted")
	var first_port = LoopbackPortScript.new()
	_assert(bool(boundary.configure(first_port, 64, 2).get("success", false)), "Valid port configuration failed")
	var replacement_port = LoopbackPortScript.new()
	_assert(bool(boundary.configure(replacement_port, 64, 2).get("success", false)), "Stopped boundary could not replace its port")
	var snapshot: Dictionary = boundary.get_snapshot()
	_assert(bool(snapshot.get("configured", false)), "Configured state was not published")
	_assert(String(snapshot.get("state", "")) == BoundaryScript.STATE_STOPPED, "Initial boundary state is incorrect")
	_assert(int(snapshot.get("max_payload_bytes", 0)) == 64, "Payload limit was not published")
	boundary.stop()


func _test_client_lifecycle_and_send() -> void:
	var port = LoopbackPortScript.new()
	port.setup(Callable(self, "_handle_message"))
	var boundary = BoundaryScript.new()
	_assert(bool(boundary.configure(port, 96, 2).get("success", false)), "Client boundary configuration failed")
	_assert(_error(boundary.send("COMMAND", {"value": 1})) == "TRANSPORT_NOT_READY", "Send before READY was accepted")
	_assert(bool(boundary.connect_client({"host": "loopback", "port": 1}).get("success", false)), "Client connect failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_READY, "Client did not enter READY")
	_assert(_error(boundary.connect_client({"host": "loopback", "port": 1})) == "INVALID_STATE", "Repeated connect was accepted")
	_assert(_error(boundary.send("UNKNOWN", {})) == "UNKNOWN_MESSAGE_TYPE", "Unknown message type was accepted")
	var forbidden_node := Node.new()
	_assert(_error(boundary.send("COMMAND", {"node": forbidden_node})) == "SERIALIZATION_FAILED", "Runtime object payload was accepted")
	forbidden_node.free()
	var oversized := {"text": "x".repeat(200)}
	_assert(_error(boundary.send("COMMAND", oversized)) == "PAYLOAD_TOO_LARGE", "Oversized payload was accepted")
	var delivery: Dictionary = boundary.send("COMMAND", {"operation_id": "operation/1"})
	_assert(bool(delivery.get("success", false)), "Valid command delivery failed")
	_assert(handler_calls == 1, "Message handler was not called exactly once")
	_assert(port.get_messages().size() == 1, "Loopback port did not retain the delivered message")
	_assert(String(port.get_messages()[0].get("message_type", "")) == "COMMAND", "Message type changed during delivery")
	var event_result: Dictionary = boundary.poll_events(1)
	_assert(bool(event_result.get("success", false)), "Event polling failed")
	_assert(event_result.get("details", {}).get("events", []).size() == 1, "Client connect event was not returned")
	_assert(_error(boundary.poll_events(0)) == "INVALID_EVENT_LIMIT", "Zero event limit was accepted")
	_assert(bool(boundary.disconnect_peer().get("success", false)), "Client disconnect failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_STOPPED, "Client disconnect did not return to STOPPED")
	_assert(bool(boundary.connect_client({"host": "loopback", "port": 1}).get("success", false)), "Client reconnect after disconnect failed")
	_assert(bool(boundary.drain().get("success", false)), "Drain failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_DRAINING, "Boundary did not enter DRAINING")
	_assert(_error(boundary.send("COMMAND", {})) == "TRANSPORT_NOT_READY", "Send during drain was accepted")
	var drain_replay: Dictionary = boundary.drain()
	_assert(bool(drain_replay.get("success", false)), "Repeated drain failed")
	_assert(bool(drain_replay.get("details", {}).get("replay", false)), "Repeated drain was not marked as replay")
	_assert(bool(boundary.stop().get("success", false)), "Stop after drain failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_STOPPED, "Boundary did not stop")
	var stop_replay: Dictionary = boundary.stop()
	_assert(bool(stop_replay.get("details", {}).get("replay", false)), "Repeated stop was not idempotent")


func _test_server_lifecycle() -> void:
	var port = LoopbackPortScript.new()
	var boundary = BoundaryScript.new()
	_assert(bool(boundary.configure(port).get("success", false)), "Server boundary configuration failed")
	_assert(_error(boundary.start_server({})) == "INVALID_ENDPOINT", "Empty server endpoint was accepted")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_FAILED, "Start failure did not enter FAILED")
	_assert(bool(boundary.stop().get("success", false)), "Failed server could not be stopped")
	_assert(bool(boundary.start_server({"host": "127.0.0.1", "port": 7777}).get("success", false)), "Server start failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_LISTENING, "Server did not enter LISTENING")
	_assert(_error(boundary.send("SNAPSHOT", {})) == "TRANSPORT_NOT_READY", "Listening server sent before peer readiness")
	_assert(bool(boundary.mark_ready().get("success", false)), "Server peer readiness transition failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_READY, "Server did not enter READY")
	_assert(_error(boundary.mark_ready()) == "INVALID_STATE", "Repeated readiness transition was accepted")
	_assert(bool(boundary.send("SNAPSHOT", {"snapshot_id": "snapshot/1"}).get("success", false)), "Server snapshot send failed")
	_assert(bool(boundary.disconnect_peer().get("success", false)), "Server disconnect failed")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_LISTENING, "Server did not return to LISTENING")
	_assert(bool(boundary.stop().get("success", false)), "Server stop failed")


func _test_failure_state() -> void:
	var boundary = BoundaryScript.new()
	_assert(bool(boundary.configure(FailingPort.new()).get("success", false)), "Failing test port configuration failed")
	_assert(_error(boundary.connect_client({"host": "probe"})) == "CONNECT_PROBE_FAILURE", "Port connect failure was not propagated")
	var snapshot: Dictionary = boundary.get_snapshot()
	_assert(String(snapshot.get("state", "")) == BoundaryScript.STATE_FAILED, "Connect failure did not fence boundary")
	_assert(String(snapshot.get("failure_code", "")) == "CONNECT_PROBE_FAILURE", "Failure code was not retained")
	_assert(_error(boundary.drain()) == "TRANSPORT_FAILED", "Drain accepted a failed boundary")
	_assert(bool(boundary.stop().get("success", false)), "Stop did not recover failed boundary")
	_assert(String(boundary.get_snapshot().get("state", "")) == BoundaryScript.STATE_STOPPED, "Failed boundary did not return to STOPPED")


func _test_queue_fence() -> void:
	var port = ReentrantPort.new()
	var boundary = BoundaryScript.new()
	port.boundary = boundary
	_assert(bool(boundary.configure(port, 256, 1).get("success", false)), "Reentrant port configuration failed")
	_assert(bool(boundary.connect_client({"host": "loopback"}).get("success", false)), "Reentrant port connect failed")
	var delivery: Dictionary = boundary.send("COMMAND", {"operation_id": "outer"})
	_assert(bool(delivery.get("success", false)), "Outer delivery failed")
	var transport_result: Dictionary = delivery.get("details", {}).get("transport_result", {})
	_assert(String(transport_result.get("nested_error_code", "")) == "OUTBOUND_QUEUE_FULL", "Queue limit did not reject reentrant send")
	_assert(int(boundary.get_snapshot().get("pending_messages", -1)) == 0, "Pending counter did not recover after reentrant send")
	boundary.stop()
	port.boundary = null
	boundary = null
	port = null


func _handle_message(message_type: String, payload: Dictionary) -> Dictionary:
	handler_calls += 1
	return {
		"success": message_type == "COMMAND" and String(payload.get("operation_id", "")) == "operation/1",
		"error_code": "",
		"details": {"accepted": true},
	}


func _error(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N1 transport boundary: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N1 transport boundary: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
