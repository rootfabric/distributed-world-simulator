extends SceneTree

const ENetPort = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")

const CHANNEL_COUNT := 6
const SCHEMA := "planet_simulator.test.v1"

var assertions := 0
var failures: Array[String] = []
var _boundary_failure_recorded := false


func _init() -> void:
	_run_peer_local_case(
		"PHYSICAL_CHANNEL_MISMATCH",
		"SNAPSHOT",
		"UNRELIABLE_SEQUENCED",
		0,
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
	)
	_run_peer_local_case(
		"PHYSICAL_DELIVERY_MODE_MISMATCH",
		"CONTROL",
		"RELIABLE_ORDERED",
		0,
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	)
	_finish()


func _run_peer_local_case(
	expected_error: String,
	declared_channel: String,
	declared_delivery: String,
	physical_channel: int,
	physical_mode: int
) -> void:
	var port_number := _find_port()
	_assert(port_number > 0, "%s: could not allocate UDP port" % expected_error)
	if port_number <= 0:
		return

	var port = ENetPort.new()
	var boundary = Boundary.new()
	_assert(_ok(boundary.configure(port)), "%s: boundary configure failed" % expected_error)
	_assert(
		_ok(boundary.start_server({
			"transport": "ENET",
			"host": "127.0.0.1",
			"port": port_number,
			"channel": "nx2-physical",
			"secure": false,
		})),
		"%s: server failed to start" % expected_error
	)

	var healthy := ENetMultiplayerPeer.new()
	var offender := ENetMultiplayerPeer.new()
	_assert(healthy.create_client("127.0.0.1", port_number, CHANNEL_COUNT) == OK, "%s: healthy client failed to start" % expected_error)
	_assert(offender.create_client("127.0.0.1", port_number, CHANNEL_COUNT) == OK, "%s: offender client failed to start" % expected_error)
	_assert(_wait_connected(boundary, [healthy, offender]), "%s: clients did not connect" % expected_error)

	var healthy_session := "transport-session/nx2/healthy-%s" % expected_error.to_lower()
	var offender_session := "transport-session/nx2/offender-%s" % expected_error.to_lower()
	_send_frame(
		healthy,
		Frame.create(
			"frame/nx2/healthy-before-%s" % expected_error.to_lower(),
			healthy_session,
			1,
			"CONTROL",
			"RELIABLE_ORDERED",
			SCHEMA,
			{"marker": "healthy-before"}
		),
		0,
		MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"%s healthy-before" % expected_error
	)
	var healthy_before := _wait_message(boundary, [healthy, offender], "healthy-before")
	_assert(not healthy_before.is_empty(), "%s: healthy peer was not established" % expected_error)
	var healthy_peer_id := String(healthy_before.get("peer_id", ""))
	_assert(not healthy_peer_id.is_empty(), "%s: healthy peer ID missing" % expected_error)

	_send_frame(
		offender,
		Frame.create(
			"frame/nx2/offender-before-%s" % expected_error.to_lower(),
			offender_session,
			1,
			"CONTROL",
			"RELIABLE_ORDERED",
			SCHEMA,
			{"marker": "offender-before"}
		),
		0,
		MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"%s offender-before" % expected_error
	)
	var offender_before := _wait_message(boundary, [healthy, offender], "offender-before")
	_assert(not offender_before.is_empty(), "%s: offending peer was not established before violation" % expected_error)
	var offender_peer_id := String(offender_before.get("peer_id", ""))
	_assert(not offender_peer_id.is_empty(), "%s: offending peer ID missing" % expected_error)
	_assert(offender_peer_id != healthy_peer_id, "%s: peers were assigned the same logical ID" % expected_error)
	_assert(boundary.get_connected_peers().has(offender_peer_id), "%s: offending peer was not active before violation" % expected_error)

	_send_frame(
		offender,
		Frame.create(
			"frame/nx2/offender-%s" % expected_error.to_lower(),
			offender_session,
			2,
			declared_channel,
			declared_delivery,
			SCHEMA,
			{"marker": "offender"}
		),
		physical_channel,
		physical_mode,
		"%s offender" % expected_error
	)
	var violation := _wait_violation(boundary, [healthy, offender], expected_error)
	_assert(not violation.is_empty(), "%s: mismatched frame was not rejected" % expected_error)
	_assert(bool(violation.get("details", {}).get("protocol_violation", false)), "%s: peer-local violation marker missing" % expected_error)
	_assert(
		String(violation.get("details", {}).get("quarantine_policy", "")) == ENetPort.PHYSICAL_MISMATCH_HANDLING_POLICY,
		"%s: quarantine policy mismatch" % expected_error
	)

	var after_violation: Dictionary = boundary.get_snapshot()
	_assert(String(after_violation.get("state", "")) == Boundary.STATE_LISTENING, "%s: listener boundary entered FAILED" % expected_error)
	_assert(String(after_violation.get("failure_code", "")).is_empty(), "%s: listener boundary retained a global failure" % expected_error)
	_assert(boundary.get_connected_peers().has(healthy_peer_id), "%s: healthy peer was disconnected with offender" % expected_error)
	_assert(not boundary.get_connected_peers().has(offender_peer_id), "%s: offending peer remained connected after quarantine" % expected_error)
	var offender_snapshot: Dictionary = boundary.get_peer_snapshot(offender_peer_id)
	_assert(String(offender_snapshot.get("state", "")) == "FAILED", "%s: offending session was not marked FAILED" % expected_error)
	_assert(String(offender_snapshot.get("failure_code", "")) == expected_error, "%s: offending session failure code mismatch" % expected_error)
	_assert(_wait_disconnected(offender, boundary, [healthy]), "%s: offending peer was not disconnected" % expected_error)

	_send_frame(
		healthy,
		Frame.create(
			"frame/nx2/healthy-after-%s" % expected_error.to_lower(),
			healthy_session,
			2,
			"CONTROL",
			"RELIABLE_ORDERED",
			SCHEMA,
			{"marker": "healthy-after"}
		),
		0,
		MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"%s healthy-after" % expected_error
	)
	var healthy_after := _wait_message(boundary, [healthy], "healthy-after")
	_assert(not healthy_after.is_empty(), "%s: healthy peer could not exchange messages after quarantine" % expected_error)
	_assert(String(healthy_after.get("peer_id", "")) == healthy_peer_id, "%s: healthy peer identity changed after quarantine" % expected_error)
	_assert(String(boundary.get_snapshot().get("state", "")) == Boundary.STATE_LISTENING, "%s: boundary stopped listening after healthy follow-up" % expected_error)

	healthy.close()
	offender.close()
	boundary.stop()


func _wait_connected(boundary, clients: Array) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		_poll(boundary, clients)
		var all_connected := true
		for client_value in clients:
			var client: ENetMultiplayerPeer = client_value
			if client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				all_connected = false
		if all_connected:
			return true
		OS.delay_msec(5)
	return false


func _wait_disconnected(offender: ENetMultiplayerPeer, boundary, healthy_clients: Array) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		_poll(boundary, healthy_clients + [offender])
		if offender.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return true
		OS.delay_msec(5)
	return false


func _wait_message(boundary, clients: Array, marker: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		for event in _poll(boundary, clients):
			if String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
				continue
			if String(event.get("frame", {}).get("payload", {}).get("marker", "")) == marker:
				return event
		OS.delay_msec(5)
	return {}


func _wait_violation(boundary, clients: Array, error_code: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		for event in _poll(boundary, clients):
			if String(event.get("event_type", "")) != "PEER_DISCONNECTED":
				continue
			if String(event.get("error_code", "")) == error_code:
				return event
		OS.delay_msec(5)
	return {}


func _poll(boundary, clients: Array) -> Array:
	for client_value in clients:
		var client: ENetMultiplayerPeer = client_value
		client.poll()
	var result: Dictionary = boundary.poll_events(64)
	if not _ok(result):
		if not _boundary_failure_recorded:
			failures.append("Boundary poll failed: %s" % result)
			_boundary_failure_recorded = true
		return []
	return result.get("details", {}).get("events", [])


func _send_frame(
	client: ENetMultiplayerPeer,
	frame: Dictionary,
	channel: int,
	mode: int,
	label: String
) -> void:
	var encoded: Dictionary = Frame.encode(frame)
	_assert(_ok(encoded), "%s: frame encoding failed" % label)
	if not _ok(encoded):
		return
	client.transfer_channel = channel
	client.transfer_mode = mode
	client.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	_assert(
		client.put_packet(encoded.get("details", {}).get("packet", PackedByteArray())) == OK,
		"%s: packet send failed" % label
	)
	for _index in range(4):
		client.poll()
		OS.delay_msec(2)


func _find_port() -> int:
	for port_number in range(27000 + OS.get_process_id() % 1000, 30000):
		var probe := PacketPeerUDP.new()
		if probe.bind(port_number, "127.0.0.1") == OK:
			probe.close()
			return port_number
	return 0


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("NX2 physical channel processes: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NX2 physical channel processes: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
