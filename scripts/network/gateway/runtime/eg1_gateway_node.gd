extends RefCounted

## EG1 gateway core: composes TWO network_transport_boundary_v2 instances
## (a client-facing SERVER leg and a backend CLIENT leg) with the EG1
## route table, forwarder and session control.
##
## pump() drains the client-facing leg first (SESSION_CONTROL goes to session
## control, everything else is forwarded client->world), then the backend leg
## (egress envelopes are forwarded world->client). The node is the only place
## where frame specs are materialized into checksummed protocol frames and
## where per-leg wire sequences are allocated, because acks and forwarded
## gameplay frames share one per-peer outgoing sequence stream per leg.
##
## Zero-ownership: the node never interprets domain payloads and never calls
## domain code. get_report() exposes forwarding/session-control identity and
## counters only.

const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const LoopbackPortScript = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const RouteTableScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_route_table.gd")
const ForwarderScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_forwarder.gd")
const SessionControlScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_session_control.gd")
const BackendMultiplexerScript = preload("res://scripts/network/gateway/runtime/eg3_backend_multiplexer.gd")

const SCHEMA := "planet_simulator.eg1_gateway_node.v1"
const DEFAULT_AUTHORITY_ID := "authority/eg1-local-sim"
const DEFAULT_SERVER_INSTANCE_ID := "server-instance/eg1-sim-a"
const DEFAULT_BACKEND_LINK_ID := "backend-link/eg1/local-sim"

var _route_table
var _forwarder
var _session_control
var _placement_handler = null
# EG3: optional shared-multiplexed backend tunnel scheduler. When absent the
# backend leg behaves exactly as in EG1/EG2 (direct dispatch + retry parking).
var _backend_multiplexer = null
var _client_boundary
var _backend_boundary
var _gateway_instance_id := ""
var _backend_session_id := ""
var _backend_route_id := ""
var _backend_link_id := ""
var _backend_peer_id := ""
# EG2: many clients share one gateway, and the client boundary enforces
# gap-free outgoing sequencing PER PEER — so wire sequences are tracked per
# transport peer instead of one global counter (which only worked while a
# single client leg existed).
var _client_wire_sequence_by_peer: Dictionary = {}
var _backend_wire_sequence: int = 0
var _pending_backend_specs: Array = []
var _pump_count: int = 0
var _counters := {
	"pumps": 0,
	"session_control_handled": 0,
	"session_control_attached": 0,
	"session_control_detached": 0,
	"session_control_rejected": 0,
	"placement_handled": 0,
	"placement_rejected": 0,
	"frames_sent_client_to_world": 0,
	"frames_sent_world_to_client": 0,
	"backend_send_retries": 0,
	"backend_send_failures": 0,
	"backend_mux_rejected": 0,
	"client_send_failures": 0,
	"client_send_dropped_no_wire_session": 0,
}
var _failure_codes := {
	"backend_send": {},
	"backend_retry": {},
	"client_send": {},
}


func start(client_endpoint: Dictionary, backend_endpoint: Dictionary, p_gateway_instance_id: String, options: Dictionary = {}) -> Dictionary:
	if _client_boundary != null:
		return _failure("ALREADY_STARTED", {})
	if not p_gateway_instance_id.begins_with("gateway/") or p_gateway_instance_id.length() <= "gateway/".length():
		return _failure("INVALID_GATEWAY_INSTANCE_ID", {"gateway_instance_id": p_gateway_instance_id})
	_gateway_instance_id = p_gateway_instance_id
	var client_port = options.get("client_port", LoopbackPortScript.new())
	var backend_port = options.get("backend_port", LoopbackPortScript.new())
	_backend_peer_id = String(options.get("backend_peer_id", "peer/loopback/eg1-backend-link"))
	_backend_session_id = String(options.get("backend_session_id", "transport-session/eg1/gateway-backend"))
	_backend_route_id = String(options.get("backend_route_id", "route/eg1/gateway-backend"))
	_backend_link_id = String(options.get("backend_link_id", DEFAULT_BACKEND_LINK_ID))
	var authority_id := String(options.get("authority_id", DEFAULT_AUTHORITY_ID))
	var server_instance_id := String(options.get("server_instance_id", DEFAULT_SERVER_INSTANCE_ID))

	_route_table = RouteTableScript.new()
	_forwarder = ForwarderScript.new()
	var forwarder_configured: Dictionary = _forwarder.configure(_gateway_instance_id)
	if not bool(forwarder_configured.get("success", false)):
		return _failure(String(forwarder_configured.get("error_code", "FORWARDER_CONFIGURE_FAILED")), {})
	_session_control = SessionControlScript.new()
	var control_configured: Dictionary = _session_control.configure(authority_id, server_instance_id)
	if not bool(control_configured.get("success", false)):
		return _failure(String(control_configured.get("error_code", "SESSION_CONTROL_CONFIGURE_FAILED")), {})

	_client_boundary = BoundaryScript.new()
	var client_configured: Dictionary = _client_boundary.configure(client_port)
	if not bool(client_configured.get("success", false)):
		return _failure(String(client_configured.get("error_code", "CLIENT_BOUNDARY_CONFIGURE_FAILED")), {})
	var listening: Dictionary = _client_boundary.start_server(client_endpoint)
	if not bool(listening.get("success", false)):
		return _failure(String(listening.get("error_code", "CLIENT_LISTENER_FAILED")), {})

	_backend_boundary = BoundaryScript.new()
	var backend_configured: Dictionary = _backend_boundary.configure(backend_port)
	if not bool(backend_configured.get("success", false)):
		return _failure(String(backend_configured.get("error_code", "BACKEND_BOUNDARY_CONFIGURE_FAILED")), {})
	var connected: Dictionary = _backend_boundary.connect_client(
			backend_endpoint, _backend_peer_id, _backend_session_id, _backend_route_id, 1)
	if not bool(connected.get("success", false)):
		return _failure(String(connected.get("error_code", "BACKEND_CONNECT_FAILED")), {})
	return _success({"state": "STARTED"})


## Drain both legs. Client-facing leg first; backend flush follows so upstream
## traffic is already queued when the backend leg is polled.
func pump(max_events: int = 64) -> Dictionary:
	if _client_boundary == null:
		return _failure("NOT_STARTED", {})
	_counters["pumps"] = int(_counters["pumps"]) + 1
	var client_poll: Dictionary = _client_boundary.poll_events(max_events)
	if not bool(client_poll.get("success", false)):
		return _failure(String(client_poll.get("error_code", "CLIENT_POLL_FAILED")), {"leg": "client"})
	for event_value in client_poll.get("details", {}).get("events", []):
		_handle_client_event(Dictionary(event_value))
	var dispatch: Dictionary = _client_boundary.flush_outbound(max_events)
	if not bool(dispatch.get("success", false)):
		return _failure(String(dispatch.get("error_code", "CLIENT_FLUSH_FAILED")), {"leg": "client"})
	var backend_poll: Dictionary = _backend_boundary.poll_events(max_events)
	if not bool(backend_poll.get("success", false)):
		return _failure(String(backend_poll.get("error_code", "BACKEND_POLL_FAILED")), {"leg": "backend"})
	for event_value in backend_poll.get("details", {}).get("events", []):
		_handle_backend_event(Dictionary(event_value))
	_pump_backend_multiplexer(max_events)
	_retry_pending_backend_specs()
	var backend_dispatch: Dictionary = _backend_boundary.flush_outbound(max_events)
	if not bool(backend_dispatch.get("success", false)):
		return _failure(String(backend_dispatch.get("error_code", "BACKEND_FLUSH_FAILED")), {"leg": "backend"})
	var tail_client_dispatch: Dictionary = _client_boundary.flush_outbound(max_events)
	if not bool(tail_client_dispatch.get("success", false)):
		return _failure(String(tail_client_dispatch.get("error_code", "CLIENT_FLUSH_FAILED")), {"leg": "client"})
	return _success({"pump": int(_counters["pumps"])})


## Stop the gateway: drain client-facing first, backend afterwards.
func stop() -> Dictionary:
	var failures: Array[String] = []
	if _client_boundary != null:
		var client_drain: Dictionary = _client_boundary.drain()
		if not bool(client_drain.get("success", false)):
			failures.append(String(client_drain.get("error_code", "CLIENT_DRAIN_FAILED")))
		var client_stop: Dictionary = _client_boundary.stop()
		if not bool(client_stop.get("success", false)):
			failures.append(String(client_stop.get("error_code", "CLIENT_STOP_FAILED")))
	if _backend_boundary != null:
		var backend_drain: Dictionary = _backend_boundary.drain()
		if not bool(backend_drain.get("success", false)):
			failures.append(String(backend_drain.get("error_code", "BACKEND_DRAIN_FAILED")))
		var backend_stop: Dictionary = _backend_boundary.stop()
		if not bool(backend_stop.get("success", false)):
			failures.append(String(backend_stop.get("error_code", "BACKEND_STOP_FAILED")))
	if failures.is_empty():
		return _success({"stopped": true})
	return _failure("STOP_INCOMPLETE", {"errors": failures})


## Forwarding/session-control report ONLY: no domain state ever appears here.
func get_report() -> Dictionary:
	var transport_peer_ids: Array[String] = []
	if _backend_peer_id != "":
		transport_peer_ids.append(_backend_peer_id)
	var rows: Array = []
	var gateway_session_ids: Array[String] = []
	var client_session_ids: Array[String] = []
	var session_slots: Array = []
	if _route_table != null:
		for row_value in _route_table.snapshot().get("rows", []):
			var row: Dictionary = row_value
			gateway_session_ids.append(String(row["gateway_session_id"]))
			client_session_ids.append(String(row["binding"]["client_session_id"]))
			session_slots.append(int(row["session_slot"]))
			if not transport_peer_ids.has(String(row["client_transport_peer_id"])):
				transport_peer_ids.append(String(row["client_transport_peer_id"]))
			rows.append({
				"gateway_session_id": String(row["gateway_session_id"]),
				"client_session_id": String(row["binding"]["client_session_id"]),
				"client_transport_peer_id": String(row["client_transport_peer_id"]),
				"session_slot": int(row["session_slot"]),
				"binding_state": String(row["binding"]["state"]),
				"binding_revision": int(row["binding"]["binding_revision"]),
				"route_role": String(row["route_binding"]["route_role"]),
				"route_revision": int(row["route_binding"]["route_revision"]),
				"backend_link_id": String(row["backend_link_id"]),
			})
	transport_peer_ids.sort()
	gateway_session_ids.sort()
	client_session_ids.sort()
	session_slots.sort()
	var counters := _counters.duplicate(true)
	if _forwarder != null:
		counters["forwarder"] = _forwarder.get_counters()
	counters["failure_codes"] = _failure_codes.duplicate(true)
	var report := {
		"schema": SCHEMA,
		"identity": {
			"gateway_instance_id": _gateway_instance_id,
			"transport_peer_ids": transport_peer_ids,
			"gateway_session_ids": gateway_session_ids,
			"client_session_ids": client_session_ids,
			"session_slots": session_slots,
		},
		"counters": counters,
		"sessions": rows,
	}
	if _backend_multiplexer != null:
		# EG3 per-session/per-link tunnel metrics (identity + counters only).
		report["backend_multiplexer"] = _backend_multiplexer.get_report()
	return report


## Install the optional EG2 placement handler (additive dispatch): SESSION_CONTROL
## frames the EG1 session control rejects with UNSUPPORTED_SESSION_CONTROL_SCHEMA
## are offered to this handler instead. EG1 behavior is unchanged when no
## handler is installed.
func set_placement_handler(handler) -> Dictionary:
	if handler == null or not handler.has_method("handle_session_control"):
		return _failure("INVALID_PLACEMENT_HANDLER", {})
	_placement_handler = handler
	return _success({})


## Additive accounting hook: when a client transport peer detaches or its
## connection drops, the installed placement handler may prune per-peer auth
## bindings. Optional-method dispatch keeps EG1-only handlers fully unchanged.
func _notify_placement_peer_gone(peer_id: String) -> void:
	if _placement_handler != null and _placement_handler.has_method("on_client_peer_gone"):
		_placement_handler.on_client_peer_gone(peer_id)


## Install the optional EG3 backend multiplexer (additive dispatch): once
## installed, every client->world backend frame is scheduled through the
## multiplexer's per-session P0..P5 queues instead of direct dispatch.
## EG1/EG2 behavior is unchanged when no multiplexer is installed.
func set_backend_multiplexer(multiplexer) -> Dictionary:
	if multiplexer == null \
			or not multiplexer.has_method("enqueue") \
			or not multiplexer.has_method("drain_link") \
			or not multiplexer.has_method("get_report"):
		return _failure("INVALID_BACKEND_MULTIPLEXER", {})
	_backend_multiplexer = multiplexer
	return _success({})


## ---- EG3 shared-multiplexed backend tunnel ---------------------------------


func _send_to_backend_via_multiplexer(frame_spec: Dictionary) -> void:
	var payload: Dictionary = Dictionary(frame_spec.get("payload", {}))
	# The ingress envelope carries the logical session key and the SEMANTIC
	# channel; the wire frame itself carries only physical channel names.
	var gateway_session_id := String(payload.get("gateway_session_id", ""))
	var semantic_channel := String(Dictionary(payload.get("frame", {})).get("channel", ""))
	if gateway_session_id.is_empty() or semantic_channel.is_empty():
		_counters["backend_send_failures"] = int(_counters["backend_send_failures"]) + 1
		_record_failure_code("backend_send", "MISSING_MUX_IDENTITY")
		return
	if not _backend_multiplexer.has_session(gateway_session_id):
		var registered: Dictionary = _backend_multiplexer.register_session(gateway_session_id)
		if not bool(registered.get("success", false)):
			_counters["backend_mux_rejected"] = int(_counters["backend_mux_rejected"]) + 1
			_record_failure_code("backend_mux_rejected",
					"REGISTER_FAILED:%s" % String(registered.get("error_code", "")))
			return
	var enqueued: Dictionary = _backend_multiplexer.enqueue(
			gateway_session_id, frame_spec, semantic_channel)
	if bool(enqueued.get("success", false)):
		return
	_counters["backend_mux_rejected"] = int(_counters["backend_mux_rejected"]) + 1
	_record_failure_code("backend_mux_rejected",
			"%s:%s" % [String(enqueued.get("error_code", "")), semantic_channel])


## Drain the scheduler onto the ONE physical backend link; wire sequences are
## allocated here (at dispatch time) to keep gap-free per-peer sequencing.
func _pump_backend_multiplexer(budget: int) -> void:
	if _backend_multiplexer == null or _backend_boundary == null:
		return
	var drained: Dictionary = _backend_multiplexer.drain_link(budget)
	if not bool(drained.get("success", false)):
		_record_failure_code("backend_mux_drain", String(drained.get("error_code", "")))
		return
	for entry_value in drained.get("details", {}).get("frames", []):
		var entry: Dictionary = entry_value
		var spec: Dictionary = Dictionary(entry["frame_spec"]).duplicate(true)
		_backend_wire_sequence += 1
		spec["sequence"] = _backend_wire_sequence
		spec["session_id"] = _backend_session_id
		var sent: Dictionary = _dispatch_backend_spec(spec)
		if bool(sent.get("success", false)):
			continue
		if String(sent.get("error_code", "")) in ["PEER_NOT_READY", "UNKNOWN_PEER"]:
			# Backend link not READY yet: park and retry on later pumps.
			_counters["backend_send_retries"] = int(_counters["backend_send_retries"]) + 1
			_record_failure_code("backend_retry", String(sent.get("error_code", "")))
			_pending_backend_specs.append(spec)
			continue
		_counters["backend_send_failures"] = int(_counters["backend_send_failures"]) + 1
		_record_failure_code("backend_send", String(sent.get("error_code", "")))


func _handle_client_event(event: Dictionary) -> void:
	match String(event.get("event_type", "")):
		"MESSAGE_RECEIVED":
			var peer_id := String(event["peer_id"])
			var frame: Dictionary = event.get("frame", {})
			_ensure_client_peer_ready(peer_id)
			var inner: Dictionary = frame.get("payload", {})
			if String(inner.get("channel", "")) == "SESSION_CONTROL":
				_counters["session_control_handled"] = int(_counters["session_control_handled"]) + 1
				var result: Dictionary = _session_control.handle_session_control(frame, _route_table, peer_id)
				var handled_by_placement := false
				if not bool(result.get("success", false)) \
						and String(result.get("error_code", "")) == "UNSUPPORTED_SESSION_CONTROL_SCHEMA" \
						and _placement_handler != null:
					handled_by_placement = true
					result = _placement_handler.handle_session_control(frame, _route_table, peer_id)
				if bool(result.get("success", false)):
					if handled_by_placement:
						_counters["placement_handled"] = int(_counters["placement_handled"]) + 1
						if result["details"].has("gateway_session_id"):
							_route_table.bind_backend_link(
									String(result["details"]["gateway_session_id"]), _backend_link_id)
					else:
						match String(result["details"].get("action", "")):
							"ATTACH":
								_counters["session_control_attached"] = int(_counters["session_control_attached"]) + 1
								_route_table.bind_backend_link(
										String(result["details"]["gateway_session_id"]), _backend_link_id)
							"DETACH":
								_counters["session_control_detached"] = int(_counters["session_control_detached"]) + 1
								_notify_placement_peer_gone(peer_id)
								_purge_mux_session(String(result["details"].get("gateway_session_id", "")))
					if result["details"].has("ack_transport_frame"):
						_send_to_client(peer_id, result["details"]["ack_transport_frame"])
				else:
					if handled_by_placement:
						_counters["placement_rejected"] = int(_counters["placement_rejected"]) + 1
					else:
						_counters["session_control_rejected"] = int(_counters["session_control_rejected"]) + 1
			else:
				var forwarded: Dictionary = _forwarder.forward_client_to_world(
						frame, _route_table, _backend_session_id)
				if bool(forwarded.get("success", false)):
					_send_to_backend(forwarded["details"]["backend_frame"])
		"PEER_DISCONNECTED":
			var lookup: Dictionary = _route_table.lookup_by_client_peer(String(event.get("peer_id", "")))
			if bool(lookup.get("success", false)):
				var dropped_session := String(lookup["details"]["row"]["gateway_session_id"])
				_route_table.set_binding_state(dropped_session, "DETACHED")
				_purge_mux_session(dropped_session)
			_notify_placement_peer_gone(String(event.get("peer_id", "")))
		_:
			pass


func _handle_backend_event(event: Dictionary) -> void:
	match String(event.get("event_type", "")):
		"MESSAGE_RECEIVED":
			var forwarded: Dictionary = _forwarder.forward_world_to_client(
					event.get("frame", {}), _route_table)
			if bool(forwarded.get("success", false)):
				_send_to_client(
						String(forwarded["details"]["client_transport_peer_id"]),
						forwarded["details"]["client_transport_frame"])
		"PEER_CONNECTED":
			_drive_backend_peer_ready()
		"PEER_DISCONNECTED":
			# Fail-predictable backend link loss: parked retries and scheduled
			# frames for the dead link are dropped and accounted — never
			# replayed into a future link incarnation (no stale resurrection).
			_pending_backend_specs.clear()
			if _backend_multiplexer != null and _backend_multiplexer.has_method("purge_all"):
				_backend_multiplexer.purge_all()
			_counters["backend_link_drops"] = int(_counters.get("backend_link_drops", 0)) + 1
		_:
			pass


func _ensure_client_peer_ready(peer_id: String) -> void:
	var snapshot: Dictionary = _client_boundary.get_peer_snapshot(peer_id)
	if snapshot.is_empty():
		return
	var state := String(snapshot.get("state", ""))
	if state == "TRANSPORT_CONNECTED":
		_client_boundary.mark_peer_handshaking(peer_id)
		state = "HANDSHAKING"
	if state == "HANDSHAKING":
		_client_boundary.mark_peer_synchronizing(peer_id)
		state = "SYNCHRONIZING"
	if state == "SYNCHRONIZING":
		_client_boundary.mark_peer_ready(peer_id)


func _drive_backend_peer_ready() -> void:
	var snapshot: Dictionary = _backend_boundary.get_peer_snapshot(_backend_peer_id)
	if snapshot.is_empty():
		return
	match String(snapshot.get("state", "")):
		"CONNECTING":
			pass
		"TRANSPORT_CONNECTED":
			_backend_boundary.mark_peer_handshaking(_backend_peer_id)
			_backend_boundary.mark_peer_synchronizing(_backend_peer_id)
			_backend_boundary.mark_peer_ready(_backend_peer_id)


func _send_to_client(peer_id: String, frame_spec: Dictionary) -> void:
	_client_wire_sequence_by_peer[peer_id] = int(_client_wire_sequence_by_peer.get(peer_id, 0)) + 1
	var spec: Dictionary = frame_spec.duplicate(true)
	spec["sequence"] = int(_client_wire_sequence_by_peer[peer_id])
	# The egress reframe carries the gateway-session identity; the wire frame
	# itself must use the transport-session the boundary registered this peer
	# under, so resolve it from the leg snapshot.
	var peer_snapshot: Dictionary = _client_boundary.get_peer_snapshot(peer_id)
	var wire_session := String(peer_snapshot.get("session_id", ""))
	if wire_session.is_empty():
		# Fail closed (EG2 review hardening): without the boundary-registered
		# transport session no deliverable wire frame can be built, so the
		# frame is DROPPED and accounted instead of sent with a guessed session.
		_counters["client_send_dropped_no_wire_session"] = int(_counters["client_send_dropped_no_wire_session"]) + 1
		_record_failure_code("client_send", "MISSING_WIRE_SESSION:%s" % String(spec.get("channel", "")))
		return
	spec["session_id"] = wire_session
	var wire: Dictionary = FrameScript.create(
			String(spec["frame_id"]),
			String(spec["session_id"]),
			int(spec["sequence"]),
			String(spec["channel"]),
			String(spec["delivery_mode"]),
			String(spec["payload_schema"]),
			Dictionary(spec["payload"])
	)
	var sent: Dictionary = _client_boundary.send_to_peer(peer_id, wire)
	if bool(sent.get("success", false)):
		_counters["frames_sent_world_to_client"] = int(_counters["frames_sent_world_to_client"]) + 1
	else:
		_counters["client_send_failures"] = int(_counters["client_send_failures"]) + 1
		_record_failure_code("client_send", "%s:%s" % [String(sent.get("error_code", "")), String(spec.get("channel", ""))])


func _send_to_backend(frame_spec: Dictionary) -> void:
	if _backend_multiplexer != null:
		# EG3 path: schedule through the shared tunnel; wire sequencing is
		# deferred to drain/dispatch time.
		_send_to_backend_via_multiplexer(frame_spec)
		return
	_backend_wire_sequence += 1
	var spec: Dictionary = frame_spec.duplicate(true)
	spec["sequence"] = _backend_wire_sequence
	var sent: Dictionary = _dispatch_backend_spec(spec)
	if bool(sent.get("success", false)):
		return
	if String(sent.get("error_code", "")) in ["PEER_NOT_READY", "UNKNOWN_PEER"]:
		# Backend link not READY yet (e.g. first pump before the connect
		# handshake completed): park the frame and retry on later pumps.
		_counters["backend_send_retries"] = int(_counters["backend_send_retries"]) + 1
		_record_failure_code("backend_retry", String(sent.get("error_code", "")))
		_pending_backend_specs.append(spec)
		return
	_counters["backend_send_failures"] = int(_counters["backend_send_failures"]) + 1
	_record_failure_code("backend_send", String(sent.get("error_code", "")))


func _retry_pending_backend_specs() -> void:
	if _pending_backend_specs.is_empty():
		return
	var remaining: Array = []
	for spec_value in _pending_backend_specs:
		var spec: Dictionary = spec_value
		var sent: Dictionary = _dispatch_backend_spec(spec)
		if not bool(sent.get("success", false)):
			remaining.append(spec)
	_pending_backend_specs = remaining


func _dispatch_backend_spec(spec: Dictionary) -> Dictionary:
	var wire: Dictionary = FrameScript.create(
			String(spec["frame_id"]),
			String(spec["session_id"]),
			int(spec["sequence"]),
			String(spec["channel"]),
			String(spec["delivery_mode"]),
			String(spec["payload_schema"]),
			Dictionary(spec["payload"])
	)
	if not wire.has("payload_checksum"):
		return _failure("INVALID_FRAME_SPEC", {})
	var sent: Dictionary = _backend_boundary.send_to_peer(_backend_peer_id, wire)
	if bool(sent.get("success", false)):
		_counters["frames_sent_client_to_world"] = int(_counters["frames_sent_client_to_world"]) + 1
	return sent


## Slot-reuse hygiene: drop every queued backend frame of a detached session
## so nothing scheduled for the old identity can ever reach the new occupant.
func _purge_mux_session(gateway_session_id: String) -> void:
	if _backend_multiplexer == null or gateway_session_id.is_empty():
		return
	if _backend_multiplexer.has_method("purge_session") \
			and _backend_multiplexer.has_session(gateway_session_id):
		_backend_multiplexer.purge_session(gateway_session_id)


func _record_failure_code(kind: String, code: String) -> void:
	var bucket: Dictionary = _failure_codes[kind]
	bucket[code] = int(bucket.get(code, 0)) + 1


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
