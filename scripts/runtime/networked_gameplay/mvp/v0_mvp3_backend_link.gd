extends RefCounted

# Bounded synchronous server RPC over the existing reliable ENet boundary.
# No retries, reconnects, independent simulation, or ownership decisions.
const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
var boundary = null
var config: Dictionary = {}
var authority := ""
var peer := ""
var key := ""
var sequence := 0
var connects := 0
var disconnects := 0
var last_signed_reply: Dictionary = {}
var failure_code := ""

func start(cfg: Dictionary, authority_id: String, port: int, capability: String) -> Dictionary:
	if boundary != null or not Protocol.valid_key(capability) or port < 1 or port > 65535:
		return Protocol.failure("MVP3_BACKEND_LINK_CONFIGURATION_INVALID")
	config = cfg.duplicate(true)
	authority = authority_id
	key = capability
	peer = "peer/enet/mvp3/" + authority_id.replace("/", "-")
	boundary = Support.make_boundary()
	if boundary == null:
		return Protocol.failure("MVP3_BACKEND_BOUNDARY_FAILED")
	var result: Dictionary = boundary.connect_client(Support.endpoint("127.0.0.1", port), peer, "transport-session/mvp3/backend/" + String(cfg["run_id"]) + "/" + authority_id, "route/mvp3/" + authority_id, 1)
	if not bool(result.get("success", false)):
		return result
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		poll()
		if not failure_code.is_empty():
			return Protocol.failure(failure_code)
		if boundary.get_peer_snapshot(peer).get("state") == "READY":
			return Protocol.success()
		OS.delay_msec(1)
	return Protocol.failure("MVP3_BACKEND_CONNECT_TIMEOUT")

func poll() -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	var polled: Dictionary = boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		failure_code = "MVP3_BACKEND_POLL_FAILED"
		return packets
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		if event.get("event_type") == "PEER_CONNECTED":
			connects += 1
			if connects != 1 or not Support.mark_ready(boundary, peer):
				failure_code = "MVP3_BACKEND_RECONNECT_FORBIDDEN"
		elif event.get("event_type") == "PEER_DISCONNECTED":
			disconnects += 1
			failure_code = "MVP3_BACKEND_DISCONNECTED"
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			var packet := Protocol.payload(event)
			if not Protocol.verify(config, packet, authority, "gateway", key):
				failure_code = "MVP3_BACKEND_REPLY_AUTH_FAILED"
				continue
			packets.append(packet)
	return packets

func call(body: Dictionary) -> Dictionary:
	if not failure_code.is_empty() or sequence >= Protocol.MAX_RPC_CALLS:
		return Protocol.failure("MVP3_BACKEND_LINK_UNAVAILABLE")
	sequence += 1
	var sent := Protocol.send(boundary, peer, Protocol.seal(config, "gateway", authority, sequence, body, key))
	if not bool(sent.get("success", false)):
		failure_code = "MVP3_BACKEND_SEND_FAILED"
		return Protocol.failure(failure_code)
	boundary.flush_outbound(64)
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		var packets := poll()
		if not failure_code.is_empty():
			return Protocol.failure(failure_code)
		for packet in packets:
			if int(packet["sequence"]) != sequence:
				failure_code = "MVP3_BACKEND_REPLY_SEQUENCE_MISMATCH"
				return Protocol.failure(failure_code)
			last_signed_reply = packet.duplicate(true)
			return Dictionary(packet["body"]).duplicate(true)
		OS.delay_msec(1)
	failure_code = "MVP3_BACKEND_RPC_TIMEOUT_NO_RETRY"
	return Protocol.failure(failure_code)

func shutdown() -> void:
	if boundary != null:
		boundary.stop()
	boundary = null
	key = ""
	config.clear()
