extends RefCounted

# Bounded synchronous server RPC over the existing reliable ENet boundary.
# No retries, reconnects, independent simulation, or ownership decisions.
const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
# Weak references avoid retaining another link (or an authority owner). Every
# idle boundary needs ENet service even while a sibling is awaiting its reply.
static var _live_links: Array[WeakRef] = []
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
var idle_service_count := 0
var _rpc_in_flight := false
var _frame_loop: SceneTree = null

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
	_live_links.append(weakref(self))
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		_service_other_links()
		poll()
		if not failure_code.is_empty():
			return Protocol.failure(failure_code)
		if boundary.get_peer_snapshot(peer).get("state") == "READY":
			var loop = Engine.get_main_loop()
			if loop is SceneTree:
				_frame_loop = loop
				_frame_loop.process_frame.connect(_service_idle)
			return Protocol.success()
		OS.delay_msec(1)
	return Protocol.failure("MVP3_BACKEND_CONNECT_TIMEOUT")

func _service_idle() -> void:
	if boundary == null or _rpc_in_flight or not failure_code.is_empty():
		return
	idle_service_count += 1
	# No RPC is outstanding on this link. A data reply here cannot be silently
	# discarded or claimed by a later request; fail closed instead.
	var unexpected := poll()
	if not unexpected.is_empty() and failure_code.is_empty():
		failure_code = "MVP3_UNSOLICITED_BACKEND_REPLY"
	boundary.flush_outbound(64)

func _service_other_links() -> void:
	var retained: Array[WeakRef] = []
	for reference in _live_links:
		var link = reference.get_ref()
		if link == null or link.boundary == null:
			continue
		retained.append(reference)
		if link != self:
			link._service_idle()
	_live_links = retained

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
			var verification_error := Protocol.verify_error(config, packet, authority, "gateway", key)
			if not verification_error.is_empty():
				failure_code = "MVP3_BACKEND_REPLY_AUTH_FAILED:" + verification_error
				continue
			packets.append(packet)
	return packets

func _complete_rpc(result: Dictionary) -> Dictionary:
	_rpc_in_flight = false
	return result

func rpc_call(body: Dictionary) -> Dictionary:
	if not failure_code.is_empty() or sequence >= Protocol.MAX_RPC_CALLS or _rpc_in_flight:
		return Protocol.failure("MVP3_BACKEND_LINK_UNAVAILABLE")
	_rpc_in_flight = true
	sequence += 1
	var sent := Protocol.send(boundary, peer, Protocol.seal(config, "gateway", authority, sequence, body, key))
	if not bool(sent.get("success", false)):
		failure_code = "MVP3_BACKEND_SEND_FAILED:" + String(sent.get("error_code", "UNKNOWN"))
		return _complete_rpc(Protocol.failure(failure_code))
	boundary.flush_outbound(64)
	var deadline := Time.get_ticks_msec() + int(config.get("backend_rpc_timeout_ms", 10000))
	while Time.get_ticks_msec() < deadline:
		_service_other_links()
		var packets := poll()
		if not failure_code.is_empty():
			return _complete_rpc(Protocol.failure(failure_code))
		for packet in packets:
			if int(packet["sequence"]) != sequence:
				failure_code = "MVP3_BACKEND_REPLY_SEQUENCE_MISMATCH"
				return _complete_rpc(Protocol.failure(failure_code))
			last_signed_reply = packet.duplicate(true)
			return _complete_rpc(Dictionary(packet["body"]).duplicate(true))
		OS.delay_msec(1)
	failure_code = "MVP3_BACKEND_RPC_TIMEOUT_NO_RETRY"
	return _complete_rpc(Protocol.failure(failure_code))

func shutdown() -> void:
	if _frame_loop != null and _frame_loop.process_frame.is_connected(_service_idle):
		_frame_loop.process_frame.disconnect(_service_idle)
	_frame_loop = null
	_rpc_in_flight = false
	if boundary != null:
		boundary.stop()
	boundary = null
	key = ""
	config.clear()
	_service_other_links()
