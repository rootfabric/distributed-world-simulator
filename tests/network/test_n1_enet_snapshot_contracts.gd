extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Wire = preload("res://scripts/network/contracts/network_wire_frame.gd")
const Handshake = preload("res://scripts/network/contracts/network_handshake_envelope.gd")
const HandshakeResult = preload("res://scripts/network/contracts/network_handshake_result_envelope.gd")
const Ack = preload("res://scripts/network/contracts/snapshot_ack_envelope.gd")
const Service = preload("res://scripts/network/session/network_handshake_service.gd")
const ServerSession = preload("res://scripts/network/session/n1_snapshot_server_session.gd")
const ClientSession = preload("res://scripts/network/session/n1_snapshot_client_session.gd")
const Boundary = preload("res://scripts/network/transports/network_transport_boundary.gd")
const Support = preload("res://tools/network/n1_snapshot_process_support.gd")

var failures: Array[String] = []
var assertions: int = 0


class AsyncPort:
	extends "res://scripts/network/transports/network_transport_port.gd"

	func get_descriptor() -> Dictionary:
		return {
			"schema": SCHEMA,
			"transport_kind": "ASYNC_TEST",
			"supports_server": false,
			"supports_client": true,
			"synchronous_delivery": false,
		}

	func connect_client(_endpoint: Dictionary) -> Dictionary:
		return _success()

	func send_message(_message_type: String, _payload: Dictionary) -> Dictionary:
		return _success({"delivered": true})


func _init() -> void:
	_test_wire_frame()
	_test_handshake_contract()
	_test_handshake_result_contract()
	_test_snapshot_ack_contract()
	_test_handshake_service()
	_test_session_contract_alignment()
	_test_async_boundary_transition()
	_finish()


func _test_wire_frame() -> void:
	var payload: Dictionary = {"handshake_id": "handshake/1", "capabilities": ["snapshot.receive"]}
	var frame: Dictionary = Wire.create("wire/test/1", "HANDSHAKE", payload)
	_assert_ok(Wire.validate(frame), "Valid wire frame rejected")
	var encoded: Dictionary = Wire.encode(frame)
	_assert(bool(encoded.get("success", false)), "Valid wire frame did not encode")
	var packet: PackedByteArray = encoded.get("packet", PackedByteArray())
	_assert(not packet.is_empty(), "Encoded wire packet is empty")
	var decoded: Dictionary = Wire.decode(packet)
	_assert(bool(decoded.get("success", false)), "Valid wire packet did not decode")
	_assert(Utils.canonical_json(decoded.get("frame", {})) == Utils.canonical_json(frame), "Wire frame changed after encode/decode")
	_assert(String(decoded.get("frame", {}).get("payload_hash", "")) == Utils.payload_hash(payload), "Wire payload hash changed")

	var missing: Dictionary = frame.duplicate(true)
	missing.erase("message_id")
	_assert_code(Wire.validate(missing), "MISSING_FIELD", "Missing wire field accepted")
	var extra: Dictionary = frame.duplicate(true)
	extra["extra"] = true
	_assert_code(Wire.validate(extra), "UNEXPECTED_FIELD", "Extra wire field accepted")
	var unknown: Dictionary = frame.duplicate(true)
	unknown["message_type"] = "UNKNOWN"
	_assert_code(Wire.validate(unknown), "UNKNOWN_MESSAGE_TYPE", "Unknown wire message accepted")
	var wrong_hash: Dictionary = frame.duplicate(true)
	wrong_hash["payload_hash"] = "0".repeat(64)
	_assert_code(Wire.validate(wrong_hash), "PAYLOAD_HASH_MISMATCH", "Wrong payload hash accepted")
	var runtime_payload: Dictionary = frame.duplicate(true)
	var node := Node.new()
	runtime_payload["payload"] = {"node": node}
	runtime_payload["payload_hash"] = "a"
	_assert_code(Wire.validate(runtime_payload), "NON_CANONICAL_PAYLOAD", "Runtime object in wire payload accepted")
	node.free()
	_assert_code(Wire.decode(PackedByteArray()), "EMPTY_PACKET", "Empty packet accepted")
	_assert_code(Wire.decode(packet, packet.size() - 1), "PACKET_TOO_LARGE", "Oversized packet accepted")
	_assert_code(Wire.decode("not-json".to_utf8_buffer()), "INVALID_JSON", "Invalid JSON accepted")
	var noncanonical: String = JSON.stringify(frame, "  ", true, true)
	_assert_code(Wire.decode(noncanonical.to_utf8_buffer()), "NON_CANONICAL_FRAME", "Non-canonical wire JSON accepted")
	var corrupted_text: String = packet.get_string_from_utf8().replace("snapshot.receive", "snapshot.corrupt")
	_assert_code(Wire.decode(corrupted_text.to_utf8_buffer()), "PAYLOAD_HASH_MISMATCH", "Corrupted wire payload accepted")


func _test_handshake_contract() -> void:
	var handshake: Dictionary = Support.create_handshake("bot-contract")
	_assert_ok(Handshake.validate(handshake), "Valid handshake rejected")
	_assert(String(handshake["checksum"]) == Handshake.compute_checksum(handshake), "Handshake checksum incorrect")
	var round_trip: Dictionary = Utils.json_round_trip(handshake)
	_assert(bool(round_trip.get("success", false)), "Handshake JSON round-trip failed")
	_assert_ok(Handshake.validate(round_trip.get("value", {})), "Round-tripped handshake rejected")

	for field in Handshake.FIELDS:
		var missing: Dictionary = handshake.duplicate(true)
		missing.erase(field)
		_assert(not bool(Handshake.validate(missing).get("success", false)), "Handshake accepted missing field: %s" % field)
	var wrong_protocol: Dictionary = handshake.duplicate(true)
	wrong_protocol["protocol_version"] = 2
	wrong_protocol["checksum"] = Handshake.compute_checksum(wrong_protocol)
	_assert_code(Handshake.validate(wrong_protocol), "UNSUPPORTED_PROTOCOL", "Unsupported handshake protocol accepted")
	var wrong_role: Dictionary = handshake.duplicate(true)
	wrong_role["runtime_role"] = "client"
	wrong_role["checksum"] = Handshake.compute_checksum(wrong_role)
	_assert_code(Handshake.validate(wrong_role), "UNSUPPORTED_ROLE", "Wrong handshake role accepted")
	var unsorted: Dictionary = handshake.duplicate(true)
	unsorted["capabilities"] = ["snapshot.receive", "handshake.v1"]
	unsorted["checksum"] = Handshake.compute_checksum(unsorted)
	_assert_code(Handshake.validate(unsorted), "NON_CANONICAL_ARRAY", "Unsorted capabilities accepted")
	var duplicate: Dictionary = handshake.duplicate(true)
	duplicate["capabilities"] = ["handshake.v1", "handshake.v1"]
	duplicate["checksum"] = Handshake.compute_checksum(duplicate)
	_assert_code(Handshake.validate(duplicate), "NON_CANONICAL_ARRAY", "Duplicate capability accepted")
	var spaced_capability: Dictionary = handshake.duplicate(true)
	spaced_capability["capabilities"] = ["handshake v1", "snapshot.receive"]
	spaced_capability["checksum"] = Handshake.compute_checksum(spaced_capability)
	_assert_code(Handshake.validate(spaced_capability), "INVALID_FIELD_VALUE", "Capability with internal whitespace accepted")
	var empty_versions: Dictionary = handshake.duplicate(true)
	empty_versions["contract_versions"] = {}
	empty_versions["checksum"] = Handshake.compute_checksum(empty_versions)
	_assert_code(Handshake.validate(empty_versions), "INVALID_FIELD_TYPE", "Empty contract versions accepted")
	var unsafe_version: Dictionary = handshake.duplicate(true)
	unsafe_version["contract_versions"] = {"wire": Utils.MAX_SAFE_JSON_INTEGER + 1}
	unsafe_version["checksum"] = "0".repeat(64)
	_assert_code(Handshake.validate(unsafe_version), "INVALID_FIELD_VALUE", "Unsafe contract version accepted")
	var invalid_contract_key: Dictionary = handshake.duplicate(true)
	invalid_contract_key["contract_versions"] = {"Entity Snapshot": 1}
	invalid_contract_key["checksum"] = Handshake.compute_checksum(invalid_contract_key)
	_assert_code(Handshake.validate(invalid_contract_key), "INVALID_FIELD_NAME", "Non-canonical contract key accepted")
	var wrong_checksum: Dictionary = handshake.duplicate(true)
	wrong_checksum["checksum"] = "0".repeat(64)
	_assert_code(Handshake.validate(wrong_checksum), "CHECKSUM_MISMATCH", "Wrong handshake checksum accepted")
	var extra: Dictionary = handshake.duplicate(true)
	extra["presentation_node"] = "forbidden"
	_assert_code(Handshake.validate(extra), "UNEXPECTED_FIELD", "Extra handshake field accepted")


func _test_handshake_result_contract() -> void:
	var service = Service.new()
	_assert_ok(service.configure(Support.create_service_config("sim-contract")), "Handshake service configuration failed")
	var evaluated: Dictionary = service.evaluate(Support.create_handshake("bot-contract"), 42)
	_assert_ok(evaluated, "Valid handshake evaluation failed")
	var result: Dictionary = evaluated.get("details", {}).get("result", {})
	_assert_ok(HandshakeResult.validate(result), "Valid handshake result rejected")
	_assert(bool(result["accepted"]), "Valid handshake was not accepted")
	_assert(not String(result["session_id"]).is_empty(), "Accepted handshake lacks session ID")
	_assert(String(result["error_code"]).is_empty(), "Accepted handshake contains error code")
	_assert(String(result["checksum"]) == HandshakeResult.compute_checksum(result), "Handshake result checksum incorrect")

	var invalid_accepted: Dictionary = result.duplicate(true)
	invalid_accepted["session_id"] = ""
	invalid_accepted["checksum"] = HandshakeResult.compute_checksum(invalid_accepted)
	_assert_code(HandshakeResult.validate(invalid_accepted), "INVALID_ACCEPTED_RESULT", "Accepted result without session accepted")
	var invalid_error: Dictionary = result.duplicate(true)
	invalid_error["error_code"] = "UNEXPECTED"
	invalid_error["checksum"] = HandshakeResult.compute_checksum(invalid_error)
	_assert_code(HandshakeResult.validate(invalid_error), "INVALID_ACCEPTED_RESULT", "Accepted result with error accepted")
	var wrong_role: Dictionary = result.duplicate(true)
	wrong_role["runtime_role"] = "bot-client"
	wrong_role["checksum"] = HandshakeResult.compute_checksum(wrong_role)
	_assert_code(HandshakeResult.validate(wrong_role), "UNSUPPORTED_ROLE", "Wrong result role accepted")
	var unsorted_capabilities: Dictionary = result.duplicate(true)
	unsorted_capabilities["negotiated_capabilities"] = ["snapshot.receive", "handshake.v1"]
	unsorted_capabilities["checksum"] = HandshakeResult.compute_checksum(unsorted_capabilities)
	_assert_code(HandshakeResult.validate(unsorted_capabilities), "NON_CANONICAL_ARRAY", "Unsorted negotiated capabilities accepted")
	var duplicate_capability: Dictionary = result.duplicate(true)
	duplicate_capability["negotiated_capabilities"] = ["handshake.v1", "handshake.v1"]
	duplicate_capability["checksum"] = HandshakeResult.compute_checksum(duplicate_capability)
	_assert_code(HandshakeResult.validate(duplicate_capability), "NON_CANONICAL_ARRAY", "Duplicate negotiated capability accepted")
	var empty_versions: Dictionary = result.duplicate(true)
	empty_versions["contract_versions"] = {}
	empty_versions["checksum"] = HandshakeResult.compute_checksum(empty_versions)
	_assert_code(HandshakeResult.validate(empty_versions), "INVALID_FIELD_TYPE", "Empty negotiated contract versions accepted")
	var wrong_checksum: Dictionary = result.duplicate(true)
	wrong_checksum["checksum"] = "0".repeat(64)
	_assert_code(HandshakeResult.validate(wrong_checksum), "CHECKSUM_MISMATCH", "Wrong result checksum accepted")


func _test_snapshot_ack_contract() -> void:
	var ack: Dictionary = Ack.create("session/1", "snapshot/1", "entity/1", "a".repeat(64), true, "", 10)
	_assert_ok(Ack.validate(ack), "Valid snapshot ack rejected")
	_assert(String(ack["ack_checksum"]) == Ack.compute_checksum(ack), "Snapshot ack checksum incorrect")
	var rejected: Dictionary = Ack.create("session/1", "snapshot/1", "entity/1", "a".repeat(64), false, "CHECKSUM_MISMATCH", 10)
	_assert_ok(Ack.validate(rejected), "Valid rejected snapshot ack rejected")
	var inconsistent: Dictionary = ack.duplicate(true)
	inconsistent["error_code"] = "ERROR"
	inconsistent["ack_checksum"] = Ack.compute_checksum(inconsistent)
	_assert_code(Ack.validate(inconsistent), "INVALID_ACK_RESULT", "Inconsistent snapshot ack accepted")
	var negative_tick: Dictionary = ack.duplicate(true)
	negative_tick["client_tick"] = -1
	negative_tick["ack_checksum"] = Ack.compute_checksum(negative_tick)
	_assert_code(Ack.validate(negative_tick), "INVALID_FIELD_VALUE", "Negative client tick accepted")
	var invalid_snapshot_checksum: Dictionary = ack.duplicate(true)
	invalid_snapshot_checksum["snapshot_checksum"] = "A".repeat(64)
	invalid_snapshot_checksum["ack_checksum"] = Ack.compute_checksum(invalid_snapshot_checksum)
	_assert_code(Ack.validate(invalid_snapshot_checksum), "INVALID_CHECKSUM", "Uppercase snapshot checksum accepted")
	var short_ack_checksum: Dictionary = ack.duplicate(true)
	short_ack_checksum["ack_checksum"] = "a".repeat(63)
	_assert_code(Ack.validate(short_ack_checksum), "INVALID_CHECKSUM", "Short ack checksum accepted")
	var wrong_checksum: Dictionary = ack.duplicate(true)
	wrong_checksum["ack_checksum"] = "0".repeat(64)
	_assert_code(Ack.validate(wrong_checksum), "CHECKSUM_MISMATCH", "Wrong ack checksum accepted")


func _test_handshake_service() -> void:
	var service = Service.new()
	_assert_code(service.evaluate(Support.create_handshake("bot-unconfigured")), "SERVICE_NOT_CONFIGURED", "Unconfigured handshake service accepted request")
	_assert_code(service.configure({}), "INVALID_SERVICE_CONFIG", "Empty handshake service config accepted")
	var duplicate_config: Dictionary = Support.create_service_config("sim-duplicate")
	duplicate_config["required_capabilities"] = ["handshake.v1", "handshake.v1"]
	_assert_code(service.configure(duplicate_config), "INVALID_SERVICE_CONFIG", "Duplicate service capability accepted")
	var invalid_version_config: Dictionary = Support.create_service_config("sim-version-invalid")
	invalid_version_config["contract_versions"]["entity_snapshot"] = 0
	_assert_code(service.configure(invalid_version_config), "INVALID_SERVICE_CONFIG", "Non-positive service contract version accepted")
	var invalid_contract_config: Dictionary = Support.create_service_config("sim-contract-invalid")
	invalid_contract_config["contract_versions"] = {"Entity Snapshot": 1}
	_assert_code(service.configure(invalid_contract_config), "INVALID_SERVICE_CONFIG", "Non-canonical service contract identifier accepted")
	_assert_ok(service.configure(Support.create_service_config("sim-service")), "Valid service config rejected")
	var accepted: Dictionary = service.evaluate(Support.create_handshake("bot-service"), 99)
	_assert_ok(accepted, "Valid service handshake failed")
	_assert(bool(accepted.get("details", {}).get("result", {}).get("accepted", false)), "Valid service handshake rejected")

	var missing_capability: Dictionary = Support.create_handshake("bot-missing-cap")
	missing_capability["capabilities"] = ["handshake.v1"]
	missing_capability["checksum"] = Handshake.compute_checksum(missing_capability)
	var missing_result: Dictionary = service.evaluate(missing_capability).get("details", {}).get("result", {})
	_assert_ok(HandshakeResult.validate(missing_result), "Missing-capability rejection is invalid")
	_assert(not bool(missing_result["accepted"]), "Missing capability was accepted")
	_assert(String(missing_result["error_code"]) == "MISSING_CAPABILITY", "Missing capability error code incorrect")

	var wrong_version: Dictionary = Support.create_handshake("bot-version")
	wrong_version["contract_versions"]["entity_snapshot"] = 2
	wrong_version["checksum"] = Handshake.compute_checksum(wrong_version)
	var version_result: Dictionary = service.evaluate(wrong_version).get("details", {}).get("result", {})
	_assert(not bool(version_result["accepted"]), "Wrong contract version accepted")
	_assert(String(version_result["error_code"]) == "UNSUPPORTED_CONTRACT_VERSION", "Wrong contract version error incorrect")

	var wrong_protocol: Dictionary = Support.create_handshake("bot-protocol")
	wrong_protocol["protocol_version"] = 99
	wrong_protocol["checksum"] = Handshake.compute_checksum(wrong_protocol)
	var protocol_result: Dictionary = service.evaluate(wrong_protocol).get("details", {}).get("result", {})
	_assert_ok(HandshakeResult.validate(protocol_result), "Protocol rejection result invalid")
	_assert(not bool(protocol_result["accepted"]), "Unsupported protocol accepted by service")
	_assert(String(protocol_result["error_code"]) == "UNSUPPORTED_PROTOCOL", "Unsupported protocol rejection code incorrect")

	var damaged: Dictionary = Support.create_handshake("bot-damaged")
	damaged["checksum"] = "0".repeat(64)
	var damaged_result: Dictionary = service.evaluate(damaged).get("details", {}).get("result", {})
	_assert(not bool(damaged_result["accepted"]), "Damaged handshake accepted")
	_assert(String(damaged_result["error_code"]) == "CHECKSUM_MISMATCH", "Damaged handshake rejection code incorrect")


func _test_session_contract_alignment() -> void:
	var endpoint: Dictionary = Support.create_endpoint({"host": "127.0.0.1", "port": 25565})
	var snapshot: Dictionary = Support.create_snapshot()
	var service_config: Dictionary = Support.create_service_config("sim-alignment")
	var server = ServerSession.new()
	_assert_ok(server.configure(endpoint, snapshot, service_config), "Aligned server session configuration failed")

	var wrong_owner: Dictionary = snapshot.duplicate(true)
	wrong_owner["authority_owner_id"] = "sim-other"
	wrong_owner["checksum"] = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd").compute_checksum(wrong_owner)
	_assert_code(ServerSession.new().configure(endpoint, wrong_owner, service_config), "SNAPSHOT_AUTHORITY_OWNER_MISMATCH", "Server accepted snapshot with mismatched authority owner")
	var wrong_epoch: Dictionary = snapshot.duplicate(true)
	wrong_epoch["authority_epoch"] = 6
	wrong_epoch["checksum"] = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd").compute_checksum(wrong_epoch)
	_assert_code(ServerSession.new().configure(endpoint, wrong_epoch, service_config), "SNAPSHOT_AUTHORITY_EPOCH_MISMATCH", "Server accepted snapshot with mismatched authority epoch")
	var future_tick: Dictionary = snapshot.duplicate(true)
	future_tick["server_tick"] = 501
	future_tick["checksum"] = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd").compute_checksum(future_tick)
	_assert_code(ServerSession.new().configure(endpoint, future_tick, service_config), "SNAPSHOT_SERVER_TICK_AHEAD", "Server accepted snapshot ahead of advertised tick")

	var handshake: Dictionary = Support.create_handshake("bot-negotiation")
	var client = ClientSession.new()
	_assert_ok(client.configure(endpoint, handshake), "Client session configuration failed")
	client._state = ClientSession.STATE_HANDSHAKE_SENT
	var accepted_result: Dictionary = {}
	var service = Service.new()
	_assert_ok(service.configure(service_config), "Negotiation service configuration failed")
	accepted_result = service.evaluate(handshake, 7).get("details", {}).get("result", {})
	var unrequested: Dictionary = accepted_result.duplicate(true)
	unrequested["negotiated_capabilities"] = ["handshake.v1", "snapshot.receive", "unexpected.capability"]
	unrequested["checksum"] = HandshakeResult.compute_checksum(unrequested)
	_assert_code(client._handle_message("HANDSHAKE_RESULT", unrequested), "UNREQUESTED_CAPABILITY", "Client accepted unrequested negotiated capability")

	client = ClientSession.new()
	_assert_ok(client.configure(endpoint, handshake), "Second client session configuration failed")
	client._state = ClientSession.STATE_HANDSHAKE_SENT
	var missing_snapshot_capability: Dictionary = accepted_result.duplicate(true)
	missing_snapshot_capability["negotiated_capabilities"] = ["handshake.v1"]
	missing_snapshot_capability["checksum"] = HandshakeResult.compute_checksum(missing_snapshot_capability)
	_assert_code(client._handle_message("HANDSHAKE_RESULT", missing_snapshot_capability), "REQUIRED_CAPABILITY_NOT_NEGOTIATED", "Client accepted handshake without snapshot capability")

	client = ClientSession.new()
	_assert_ok(client.configure(endpoint, handshake), "Third client session configuration failed")
	client._state = ClientSession.STATE_HANDSHAKE_SENT
	var mismatched_version: Dictionary = accepted_result.duplicate(true)
	mismatched_version["contract_versions"]["entity_snapshot"] = 2
	mismatched_version["checksum"] = HandshakeResult.compute_checksum(mismatched_version)
	_assert_code(client._handle_message("HANDSHAKE_RESULT", mismatched_version), "NEGOTIATED_CONTRACT_VERSION_MISMATCH", "Client accepted mismatched negotiated contract version")

	client = ClientSession.new()
	_assert_ok(client.configure(endpoint, handshake), "Fourth client session configuration failed")
	client._state = ClientSession.STATE_HANDSHAKE_SENT
	var missing_contract: Dictionary = accepted_result.duplicate(true)
	missing_contract["contract_versions"].erase("snapshot_ack")
	missing_contract["checksum"] = HandshakeResult.compute_checksum(missing_contract)
	_assert_code(client._handle_message("HANDSHAKE_RESULT", missing_contract), "REQUIRED_CONTRACT_NOT_NEGOTIATED", "Client accepted missing required contract")

	var server_ack = ServerSession.new()
	_assert_ok(server_ack.configure(endpoint, snapshot, service_config), "Server ack test configuration failed")
	server_ack._state = ServerSession.STATE_SNAPSHOT_SENT
	server_ack._session_id = "session/ack-test"
	var wrong_tick_ack: Dictionary = Ack.create(
		"session/ack-test", String(snapshot["snapshot_id"]), String(snapshot["entity_id"]),
		String(snapshot["checksum"]), true, "", int(snapshot["server_tick"]) - 1
	)
	_assert_code(server_ack._handle_message("SNAPSHOT_ACK", wrong_tick_ack), "SNAPSHOT_ACK_TICK_MISMATCH", "Server accepted snapshot ack with wrong tick")


func _test_async_boundary_transition() -> void:
	var boundary = Boundary.new()
	_assert_ok(boundary.configure(AsyncPort.new()), "Async port configuration failed")
	_assert_ok(boundary.connect_client({"host": "probe"}), "Async connect start failed")
	_assert(String(boundary.get_snapshot()["state"]) == Boundary.STATE_CONNECTING, "Async transport became READY before connection event")
	_assert_code(boundary.send("HANDSHAKE", Support.create_handshake("bot-early")), "TRANSPORT_NOT_READY", "Async transport sent before mark_ready")
	_assert_ok(boundary.mark_ready(), "Async transport mark_ready failed")
	_assert(String(boundary.get_snapshot()["state"]) == Boundary.STATE_READY, "Async transport did not become READY")
	_assert_ok(boundary.send("SNAPSHOT_ACK", Ack.create("session/1", "snapshot/1", "entity/1", "a".repeat(64), true, "", 1)), "SNAPSHOT_ACK message type rejected")
	boundary.stop()


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
		print("N1 ENet snapshot contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N1 ENet snapshot contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
