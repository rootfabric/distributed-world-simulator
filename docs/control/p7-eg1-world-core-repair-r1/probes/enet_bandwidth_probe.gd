extends RefCounted

## Black-box listener-configuration regression, not a ProtocolFrame/gameplay test.
## Deliberately service the sender's first bandwidth window before the receiver
## can recalculate limits. The EG1 three-process scenario runs separately first.

const WARMUP_MS: int = 1200
const RECEIVE_MS: int = 250


static func run(port_script: GDScript) -> Dictionary:
	var cases: Array[Dictionary] = []
	for mode in [MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED]:
		var listener: RefCounted = port_script.new()
		var port: int = _find_port()
		var result: Dictionary = {"passed": false, "error": "PORT_ALLOCATION", "mode": mode}
		if port > 0:
			var started: Dictionary = listener.call("start_server", {
				"transport": "ENET", "host": "127.0.0.1", "port": port,
				"channel": "bandwidth-regression", "secure": false,
			})
			if bool(started.get("success", false)):
				var native: ENetMultiplayerPeer = listener.get("_peer")
				var channels: int = int(port_script.get_script_constant_map()["MAX_CHANNELS"])
				result = measure_listener(native, channels, mode)
			else:
				result = {"passed": false, "error": "LISTENER_START", "details": started, "mode": mode}
		listener.call("stop")
		cases.append(result)
	var passed: bool = cases.size() == 2
	for result in cases:
		passed = passed and bool(result.get("passed", false))
	return {"test": "enet_listener_bandwidth", "passed": passed, "cases": cases}


static func measure_listener(server: ENetMultiplayerPeer, channels: int, mode: int) -> Dictionary:
	if server == null or server.host == null:
		return {"passed": false, "error": "LISTENER_HOST_MISSING", "mode": mode}
	var client := ENetMultiplayerPeer.new()
	var error: Error = client.create_client("127.0.0.1", server.host.get_local_port(), channels)
	if error != OK:
		return {"passed": false, "error": "CLIENT_CREATE", "code": int(error), "mode": mode}
	var result: Dictionary = _measure(server, client, mode)
	client.close()
	return result


static func _measure(server: ENetMultiplayerPeer, client: ENetMultiplayerPeer, mode: int) -> Dictionary:
	_pump(server, client, 150)
	if client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return {"passed": false, "error": "CONNECT_TIMEOUT", "mode": mode}
	var peer: ENetPacketPeer = client.get_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	client.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	client.transfer_channel = 3
	client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var reliable_enqueue: Array[int] = []
	for index in range(3):
		reliable_enqueue.append(int(client.put_packet(("item-%d:" % index + "x".repeat(256)).to_utf8_buffer())))
	var before: Array[Dictionary] = _pump(server, client, 50)
	var reliable_valid: bool = before.size() == 3
	for index in range(before.size()):
		reliable_valid = reliable_valid and before[index]["payload"] == "item-%d:" % index + "x".repeat(256)
		reliable_valid = reliable_valid and before[index]["channel"] == 3
		reliable_valid = reliable_valid and before[index]["mode"] == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var deadline: int = Time.get_ticks_msec() + WARMUP_MS
	while Time.get_ticks_msec() < deadline:
		client.poll()
		while client.get_available_packet_count() > 0:
			client.get_packet()
		OS.delay_msec(1)
	var statistics := {
		"limit": int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT)),
		"throttle": int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)),
		"deceleration": int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION)),
	}
	client.transfer_channel = 1
	client.transfer_mode = mode
	var input_enqueue: Error = client.put_packet("move-1".to_utf8_buffer())
	# Service this one-shot packet before the receiver resumes; never retransmit.
	client.poll()
	var after: Array[Dictionary] = _pump(server, client, RECEIVE_MS)
	var input_received: bool = after.size() == 1
	if input_received:
		input_received = after[0]["payload"] == "move-1" and after[0]["channel"] == 1 and after[0]["mode"] == mode
	var passed: bool = (
		reliable_enqueue == [OK, OK, OK] and reliable_valid and input_enqueue == OK
		and statistics["limit"] == ENetPacketPeer.PACKET_THROTTLE_SCALE
		and statistics["deceleration"] == 2 and input_received
	)
	return {
		"passed": passed, "mode": mode, "reliable_enqueue": reliable_enqueue,
		"reliable_received": before.size(), "reliable_valid": reliable_valid,
		"input_enqueue": int(input_enqueue), "input_received": input_received,
		"statistics_before_input": statistics, "packets_after_input": after,
	}


static func _pump(server: ENetMultiplayerPeer, client: ENetMultiplayerPeer, duration_ms: int) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	var deadline: int = Time.get_ticks_msec() + duration_ms
	while Time.get_ticks_msec() < deadline:
		server.poll()
		client.poll()
		while server.get_available_packet_count() > 0:
			var mode: int = server.get_packet_mode()
			var channel: int = server.get_packet_channel()
			var payload: PackedByteArray = server.get_packet()
			packets.append({"mode": mode, "channel": channel, "payload": payload.get_string_from_utf8()})
		while client.get_available_packet_count() > 0:
			client.get_packet()
		OS.delay_msec(1)
	return packets


static func _find_port() -> int:
	for offset in range(200):
		var port: int = 20000 + ((OS.get_process_id() + offset) % 40000)
		var probe := PacketPeerUDP.new()
		var error: Error = probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return 0
