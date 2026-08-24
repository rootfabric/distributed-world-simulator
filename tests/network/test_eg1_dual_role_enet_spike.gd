extends SceneTree

## EG1 spike: two live ENetMultiplayerPeer instances (SERVER + CLIENT roles) in ONE process.
## Proves the gateway composition premise: a client-facing listener and a backend
## connection can coexist inside one headless Godot process using the raw packet API
## of enet_multi_peer_transport_port.gd (no SceneMultiplayer involvement).
## Exit code 0 = SPIKE PASS, 1 = SPIKE FAIL. Prints one JSON summary line.

const ENetPort = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")

const CLIENT_PEER_ID := "peer/enet/eg1-spike-gateway-backend"
const CLIENT_SESSION_ID := "transport-session/eg1/spike-gateway-backend"
const CLIENT_ROUTE_ID := "route/eg1/spike-backend"
const PAYLOAD_SCHEMA := "planet_simulator.eg1.spike.v1"

var failures: Array[String] = []


func _fail(message: String) -> void:
	failures.append(message)
	print("[eg1-spike][FAIL] %s" % message)


func _find_free_port() -> int:
	for candidate in range(34000, 34100):
		var probe := PacketPeerUDP.new()
		var bound: int = probe.bind(candidate)
		if bound == OK:
			probe.close()
			return candidate
	return -1


func _endpoint(port: int) -> Dictionary:
	return {"transport": "ENET", "host": "127.0.0.1", "port": port, "channel": "CONTROL", "secure": false}


func _drain_events(port, label: String, sink: Array) -> void:
	var events: Array[Dictionary] = port.poll_events(32)
	for event in events:
		sink.append({
			"leg": label,
			"type": String(event.get("event_type", "")),
			"session": String(event.get("session_id", "")),
			"peer": String(event.get("peer_id", "")),
			"frame": event.get("frame", {}),
		})


func _init() -> void:
	var server := ENetPort.new()
	var client := ENetPort.new()
	var events: Array = []
	var port_number := _find_free_port()
	if port_number < 0:
		_fail("no free port found in probe range")
		_finish(server, client)
		return

	var started: Dictionary = server.start_server(_endpoint(port_number))
	if not bool(started.get("success", false)):
		_fail("server start failed: %s" % str(started))
		_finish(server, client)
		return
	var connected: Dictionary = client.connect_client(_endpoint(port_number), CLIENT_PEER_ID, CLIENT_SESSION_ID, CLIENT_ROUTE_ID, 1)
	if not bool(connected.get("success", false)):
		_fail("client connect failed: %s" % str(connected))
		_finish(server, client)
		return

	var deadline := Time.get_ticks_msec() + 10000
	var client_saw_peer := false
	while Time.get_ticks_msec() < deadline and not client_saw_peer:
		_drain_events(server, "server", events)
		_drain_events(client, "client", events)
		for entry in events:
			if String(entry["type"]) == "PEER_CONNECTED" and entry["leg"] == "client":
				client_saw_peer = true
		events.clear()
	if not client_saw_peer:
		_fail("ENet client-side handshake did not complete within 10s")
		_finish(server, client)
		return
	# Server-side PEER_CONNECTED fires on first inbound packet (raw-API peer
	# registration happens in the packet pump), so the request frame below is
	# what completes the server leg.

	var request := Frame.create(
		"frame/eg1/spike/request/1",
		CLIENT_SESSION_ID,
		1,
		"CONTROL",
		"RELIABLE_ORDERED",
		PAYLOAD_SCHEMA,
		{"probe": "gateway-backend-link", "operation_id": "op/eg1/spike/0001"}
	)
	var sent_up: Dictionary = client.send_to_peer(CLIENT_PEER_ID, request)
	if not bool(sent_up.get("success", false)):
		_fail("backend send failed: %s" % str(sent_up))
		_finish(server, client)
		return

	var received_entries: Array = []
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and received_entries.is_empty():
		_drain_events(server, "server", events)
		for entry in events:
			if String(entry["type"]) == "MESSAGE_RECEIVED":
				received_entries.append(entry)
		events.clear()
	if received_entries.is_empty():
		_fail("server leg received no MESSAGE_RECEIVED within 10s")
		_finish(server, client)
		return
	var up_entry: Dictionary = received_entries[0]
	var up_frame: Dictionary = up_entry.get("frame", {})
	var server_side_peer := String(up_entry.get("peer", ""))
	if String(up_frame.get("payload_schema", "")) != PAYLOAD_SCHEMA:
		_fail("payload schema mismatch on backend leg")
	var up_payload: Dictionary = up_frame.get("payload", {})
	if String(up_payload.get("operation_id", "")) != "op/eg1/spike/0001":
		_fail("OperationId did not survive the backend leg")
	if server_side_peer.is_empty() or not server_side_peer.begins_with("peer/enet/"):
		_fail("server-side logical peer id missing or outside peer/enet/ namespace: '%s'" % server_side_peer)
	if server_side_peer == CLIENT_PEER_ID:
		_fail("server-side logical peer id collided with the client-declared id (namespace separation violated)")

	var reply := Frame.create(
		"frame/eg1/spike/reply/1",
		CLIENT_SESSION_ID,
		1,
		"CONTROL",
		"RELIABLE_ORDERED",
		PAYLOAD_SCHEMA,
		{"reply_to": "op/eg1/spike/0001", "result": "ACCEPTED"}
	)
	var sent_down: Dictionary = server.send_to_peer(server_side_peer, reply)
	if not bool(sent_down.get("success", false)):
		_fail("downstream send failed: %s" % str(sent_down))
		_finish(server, client)
		return

	received_entries.clear()
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and received_entries.is_empty():
		_drain_events(client, "client", events)
		for entry in events:
			if String(entry["type"]) == "MESSAGE_RECEIVED":
				received_entries.append(entry)
		events.clear()
	if received_entries.is_empty():
		_fail("client leg received no MESSAGE_RECEIVED within 10s")
		_finish(server, client)
		return
	var down_payload: Dictionary = received_entries[0].get("frame", {}).get("payload", {})
	if String(down_payload.get("result", "")) != "ACCEPTED":
		_fail("round-trip payload corrupted")

	var server_snapshot: Dictionary = server.get_runtime_snapshot()
	var client_snapshot: Dictionary = client.get_runtime_snapshot()
	if int(server_snapshot.get("peer_count", 0)) != 1 or int(client_snapshot.get("peer_count", 0)) != 1:
		_fail("unexpected peer counts: server=%s client=%s" % [str(server_snapshot.get("peer_count")), str(client_snapshot.get("peer_count"))])

	_finish(server, client)


func _finish(server, client) -> void:
	server.stop()
	client.stop()
	var summary := {
		"spike": "eg1_dual_role_enet_single_process",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions_failed": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-spike] SPIKE PASS")
		quit(0)
	else:
		print("[eg1-spike] SPIKE FAIL")
		quit(1)
