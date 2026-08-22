extends SceneTree

## EG2 L1 exit predicate: WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE
## (+ NEAREST_GATEWAY_SELECTION_INDEPENDENT_FROM_SAVED_WORLD_AUTHORITY).
##
## One process, loopback transport ports, real EG1 gateway node with the EG2
## placement handler installed: full AUTHENTICATE -> PLACE -> WORLD_READY flow;
## an endpoint-redaction scan over EVERY client-leg captured frame (the sim bind
## host/port substrings must appear nowhere); WARM degradation during a
## directory outage plus recovery; resume preserving logical identity across a
## NEW transport peer; and the gateway-selection independence invariant over two
## different saved-world profiles.

const AuthService = preload("res://scripts/network/gateway/runtime/eg2_auth_session_service.gd")
const WorldDirectory = preload("res://scripts/network/gateway/runtime/eg2_world_directory.gd")
const PlacementFlow = preload("res://scripts/network/gateway/runtime/eg2_placement_flow.gd")
const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const GATEWAY_INSTANCE_ID := "gateway/eg2/l1-placement"
const BACKEND_LINK_PEER_ID := "peer/loopback/eg2-backend-link"
const MAIN_WORLD_ID := "world/eg2/main-l1"
const ISLAND_WORLD_ID := "world/eg2/island-l1"
const PROFILE_WORLD_ID := "world/eg2/saved-profile-l1"
# Hypothetical sim bind coordinates: they exist ONLY so the redaction scan has
# concrete forbidden substrings; nothing in this L1 ever binds a real socket.
const SIM_BIND_HOST := "127.0.0.1"
const SIM_BIND_PORT := "37788"
const FORBIDDEN_SUBSTRINGS: Array[String] = [
	"127.0.0.1", "localhost", "::1", "0.0.0.0", SIM_BIND_PORT,
]
const FORBIDDEN_KEYS: Array[String] = [
	"host", "hostname", "port", "endpoint", "address", "ip", "url", "bind",
]

var assertions := 0
var failures: Array[String] = []

var _auth
var _directory
var _flow
var _gateway
var _port_client
var _port_backend
var _clients: Dictionary = {}
var _captured_client_frames: Array = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg2-l1][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


## ---- client-leg plumbing ----------------------------------------------------


func _register_client(tag: String) -> Dictionary:
	var peer_id := "peer/loopback/eg2-%s" % tag
	var wire_session := "transport-session/eg2/l1-%s" % tag
	var attached: Dictionary = _port_client.attach_peer(peer_id, wire_session, "route/eg2/l1-%s" % tag, 1)
	_assert(bool(attached.get("success", false)), "loopback attach failed for %s: %s" % [tag, _err(attached)])
	var client := {
		"tag": tag,
		"peer_id": peer_id,
		"wire_session": wire_session,
		"wire_sequence": 0,
	}
	_clients[tag] = client
	return client


func _inject_wire(client: Dictionary, spec: Dictionary) -> void:
	var wire: Dictionary = FrameScript.create(
			String(spec["frame_id"]), String(spec["session_id"]),
			int(spec["sequence"]), String(spec["channel"]),
			String(spec["delivery_mode"]), String(spec["payload_schema"]),
			Dictionary(spec["payload"]))
	var injected: Dictionary = _port_client.inject_received_frame(String(client["peer_id"]), wire)
	_assert(bool(injected.get("success", false)), "client frame injection failed (%s)" % String(client["tag"]))


func _send_session_control(client: Dictionary, frame_name: String, payload_schema: String, payload: Dictionary) -> void:
	client["wire_sequence"] = int(client["wire_sequence"]) + 1
	var seq := int(client["wire_sequence"])
	var inner := ClientWorldFrameScript.create(
			"frame/eg2/l1/%s/%d" % [frame_name, seq],
			"gateway-session/eg2/probe/%s" % String(client["tag"]),
			"CLIENT_TO_WORLD", "SESSION_CONTROL", seq, payload_schema, payload)
	_inject_wire(client, {
		"frame_id": "frame/eg2/l1/wire/%s/%d" % [frame_name, seq],
		"session_id": String(client["wire_session"]),
		"sequence": seq,
		"channel": "CONTROL",
		"delivery_mode": "RELIABLE_ORDERED",
		"payload_schema": payload_schema,
		"payload": inner,
	})


func _pump(stage: String) -> void:
	var pumped: Dictionary = _gateway.pump()
	_assert(bool(pumped.get("success", false)), "gateway pump failed during %s: %s" % [stage, _err(pumped)])


## Pull only the frames that arrived for this client since the last drain,
## capture ALL of them for the redaction scan, and return them.
func _drain_inbox(client: Dictionary) -> Array:
	var inbox: Array = _port_client.get_messages_for_peer(String(client["peer_id"]))
	var consumed := int(client.get("consumed", 0))
	var fresh: Array = []
	for index in range(consumed, inbox.size()):
		fresh.append(inbox[index])
	client["consumed"] = inbox.size()
	for frame_value in fresh:
		_captured_client_frames.append(frame_value)
	return fresh


## The single SESSION_CONTROL ack produced by the most recent exchange.
func _take_ack(client: Dictionary, stage: String) -> Dictionary:
	for frame_value in _drain_inbox(client):
		var frame: Dictionary = frame_value
		var inner: Dictionary = frame.get("payload", {})
		if String(inner.get("channel", "")) == "SESSION_CONTROL":
			return inner
	_assert(false, "no SESSION_CONTROL ack reached client %s during %s" % [String(client["tag"]), stage])
	return {}


## ---- scenario steps ---------------------------------------------------------


func _authenticate(client: Dictionary, client_session_id: String, expected_status: String) -> void:
	var minted: Dictionary = _auth.mint_auth_ticket(client_session_id)
	_assert(bool(minted.get("success", false)), "ticket mint failed for %s: %s" % [client_session_id, _err(minted)])
	var ticket_id := String(minted.get("details", {}).get("ticket_id", ""))
	_send_session_control(client, "auth", GatewayUtils.EG2_SESSION_AUTHENTICATE_PAYLOAD_SCHEMA, {
		"client_session_id": client_session_id,
		"ticket_id": ticket_id,
	})
	_pump("authenticate(%s)" % String(client["tag"]))
	var ack := _take_ack(client, "authenticate")
	if ack.is_empty():
		return
	_assert(String(ack["payload"]["ticket_status"]) == expected_status,
			"authenticate(%s) status %s != %s" % [client_session_id, String(ack["payload"].get("ticket_status", "")), expected_status])
	client["last_ticket_id"] = ticket_id


func _place(client: Dictionary, client_session_id: String, world_id: String, resume_token: String) -> Dictionary:
	_send_session_control(client, "place", GatewayUtils.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA, {
		"client_session_id": client_session_id,
		"ticket_id": String(client.get("last_ticket_id", "")),
		"resume_token": resume_token,
		"world_id": world_id,
	})
	_pump("place(%s)" % String(client["tag"]))
	var ack := _take_ack(client, "place")
	if ack.is_empty():
		return {}
	var payload: Dictionary = ack["payload"]
	var schema_check: Dictionary = GatewayUtils.validate_eg2_gateway_ack_payload(
			payload.duplicate(true), String(ack["payload_schema"]))
	_assert(bool(schema_check.get("success", false)),
			"ack failed its registered schema validation: %s" % _err(schema_check))
	return payload


func _route_row(gateway_session_id: String) -> Dictionary:
	var lookup: Dictionary = _gateway._route_table.lookup(gateway_session_id)
	if not bool(lookup.get("success", false)):
		return {}
	return lookup["details"]["row"]


## ---- main -------------------------------------------------------------------


func _init() -> void:
	_auth = AuthService.new()
	_directory = WorldDirectory.new()
	_flow = PlacementFlow.new()
	_assert(bool(_auth.configure({}).get("success", false)), "auth service configure failed")
	_assert(bool(_flow.configure(_auth, _directory).get("success", false)), "placement flow configure failed")

	var registered: Dictionary = _directory.register_world(MAIN_WORLD_ID, "authority/eg2/main-a", "server-instance/eg2/main-a-1", 3)
	_assert(bool(registered.get("success", false)), "main world registration failed: %s" % _err(registered))
	_directory.register_world(ISLAND_WORLD_ID, "authority/eg2/island-a", "server-instance/eg2/island-a-1", 1)

	_port_client = LoopbackPort.new()
	_port_backend = LoopbackPort.new()
	_port_client.setup()
	_port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg2-l1-client"},
			{"transport": "LOOPBACK", "name": "eg2-l1-backend"},
			GATEWAY_INSTANCE_ID,
			{"client_port": _port_client, "backend_port": _port_backend, "backend_peer_id": BACKEND_LINK_PEER_ID})
	_assert(bool(started.get("success", false)), "gateway start failed: %s" % _err(started))
	var handler_installed: Dictionary = _gateway.set_placement_handler(_flow)
	_assert(bool(handler_installed.get("success", false)), "placement handler install failed")

	_run_configure_rejections()
	_run_full_flow_to_world_ready()
	_run_reject_paths()
	_run_resume_preserves_identity()
	_run_warm_degradation_and_recovery()
	_run_gateway_selection_independence()
	_run_redaction_scan()
	_run_report_hygiene()

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "gateway stop failed: %s" % _err(stopped))
	_finish()


func _run_configure_rejections() -> void:
	var probe = PlacementFlow.new()
	_assert(_err(probe.configure(null, _directory)) == "INVALID_AUTH_SERVICE", "null auth service accepted")
	_assert(_err(probe.configure(_auth, null)) == "INVALID_DIRECTORY", "null directory accepted")


func _run_full_flow_to_world_ready() -> void:
	var alpha := _register_client("alpha")
	_authenticate(alpha, "client-session/eg2/l1-alpha", "OK")
	var payload := _place(alpha, "client-session/eg2/l1-alpha", MAIN_WORLD_ID, "")
	if payload.is_empty():
		return
	_assert(String(payload["world_id"]) == MAIN_WORLD_ID, "WORLD_READY lost the world id")
	_assert(String(payload["authority_id"]) == "authority/eg2/main-a", "WORLD_READY lost the directory authority id")
	_assert(String(payload["server_instance_id"]) == "server-instance/eg2/main-a-1", "WORLD_READY lost the server instance id")
	_assert(String(payload["route_role"]) == "ACTIVE", "fresh placement did not report ACTIVE route role")
	_assert(bool(payload["resumed"]) == false, "fresh placement reported resumed=true")
	_assert(String(payload["logical_player_id"]) == "player/eg2-eg2-l1-alpha", "identity grant mismatch")
	_assert(String(payload["player_entity_id"]) == "entity/eg2-player-eg2-l1-alpha", "entity grant mismatch")
	_assert(String(payload["resume_token"]).begins_with("resume-token/eg2/"), "resume token outside its namespace")
	_assert(String(payload["gateway_session_id"]).begins_with("gateway-session/"), "gateway session id outside its namespace")
	var row := _route_row(String(payload["gateway_session_id"]))
	_assert(not row.is_empty(), "placed gateway session missing from the route table")
	_assert(not String(row.get("backend_link_id", "")).is_empty(), "backend link was not bound after placement")
	alpha["resume_token"] = String(payload["resume_token"])
	alpha["gateway_session_id"] = String(payload["gateway_session_id"])


func _run_reject_paths() -> void:
	var intruder := _register_client("intruder")
	# Place without authenticate on this transport peer.
	_send_session_control(intruder, "place", GatewayUtils.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA, {
		"client_session_id": "client-session/eg2/l1-intruder",
		"ticket_id": "auth-ticket/eg2/none",
		"resume_token": "",
		"world_id": MAIN_WORLD_ID,
	})
	_pump("unauthenticated place")
	_drain_inbox(intruder)
	var flow_report: Dictionary = _flow.get_report()
	_assert(int(flow_report["counters"]["placement_frames_rejected"]) >= 1,
			"unauthenticated placement was not rejected")
	# Unsupported schema falls through the additive chain unserved.
	var node_before_schema: Dictionary = _gateway.get_report()["counters"]
	_send_session_control(intruder, "unknown", "planet_simulator.eg9_unknown_schema.v1", {})
	_pump("unsupported schema")
	_drain_inbox(intruder)
	var node_after_schema: Dictionary = _gateway.get_report()["counters"]
	_assert(int(node_after_schema["placement_handled"]) == int(node_before_schema["placement_handled"]),
			"unsupported schema was handled by the placement flow")
	_assert(int(node_after_schema["placement_rejected"]) > int(node_before_schema["placement_rejected"]),
			"unsupported schema rejection was not accounted")


func _run_resume_preserves_identity() -> void:
	var alpha: Dictionary = _clients["alpha"]
	var phoenix := _register_client("phoenix")
	_authenticate(phoenix, "client-session/eg2/l1-alpha", "OK")
	var payload := _place(phoenix, "client-session/eg2/l1-alpha", MAIN_WORLD_ID, String(alpha["resume_token"]))
	if payload.is_empty():
		return
	_assert(bool(payload["resumed"]) == true, "token resume did not report resumed=true")
	_assert(String(payload["logical_player_id"]) == "player/eg2-eg2-l1-alpha"
			and String(payload["player_entity_id"]) == "entity/eg2-player-eg2-l1-alpha",
			"resume did not preserve the logical identity")
	_assert(String(payload["gateway_session_id"]) != String(alpha["gateway_session_id"]),
			"resume reused the previous gateway session id")
	_assert(String(payload["resume_token"]) != String(alpha["resume_token"]),
			"resume did not rotate the resume token")
	_assert(_auth.is_resume_token_live(String(payload["resume_token"])), "rotated token is not live")
	_assert(not _auth.is_resume_token_live(String(alpha["resume_token"])), "old token stayed live after rotation")
	_assert(_route_row(String(alpha["gateway_session_id"])).is_empty(),
			"superseded gateway session row survived the resume")
	_assert(not _route_row(String(payload["gateway_session_id"])).is_empty(),
			"resumed gateway session row missing")


func _run_warm_degradation_and_recovery() -> void:
	# Cache exists for MAIN_WORLD_ID -> degrade to WARM, never to endpoints.
	_directory.set_unavailable(MAIN_WORLD_ID)
	var warm := _register_client("warm")
	_authenticate(warm, "client-session/eg2/l1-warm", "OK")
	var warm_payload := _place(warm, "client-session/eg2/l1-warm", MAIN_WORLD_ID, "")
	if not warm_payload.is_empty():
		_assert(String(warm_payload["status"]) == "WARM",
				"degraded placement did not report WARM: %s" % str(warm_payload))
		_assert(String(warm_payload["world_id"]) == MAIN_WORLD_ID, "degraded ack lost the world id")
		var row := _route_row(String(warm_payload["gateway_session_id"]))
		_assert(not row.is_empty(), "WARM placement left no route row")
		if not row.is_empty():
			_assert(String(row["route_binding"]["route_role"]) == "WARM", "route row role is not WARM during outage")

	# No cache for ISLAND_WORLD_ID -> PLACEMENT_PENDING, no route row at all.
	_directory.set_unavailable(ISLAND_WORLD_ID)
	var island := _register_client("island")
	_authenticate(island, "client-session/eg2/l1-island", "OK")
	var island_payload := _place(island, "client-session/eg2/l1-island", ISLAND_WORLD_ID, "")
	if not island_payload.is_empty():
		_assert(String(island_payload["status"]) == "PLACEMENT_PENDING",
				"cacheless outage did not report PLACEMENT_PENDING: %s" % str(island_payload))
		_assert(_route_row(String(island_payload["gateway_session_id"])).is_empty(),
				"PENDING placement created a route row anyway")

	# Recovery: directory restored -> fresh placements go ACTIVE again.
	_directory.set_available(MAIN_WORLD_ID)
	_directory.set_available(ISLAND_WORLD_ID)
	var recovered := _register_client("recovered")
	_authenticate(recovered, "client-session/eg2/l1-recovered", "OK")
	var recovered_payload := _place(recovered, "client-session/eg2/l1-recovered", MAIN_WORLD_ID, "")
	if not recovered_payload.is_empty():
		_assert(String(recovered_payload.get("route_role", "")) == "ACTIVE",
				"post-outage placement did not return to ACTIVE")
	var flow_report: Dictionary = _flow.get_report()
	_assert(int(flow_report["counters"]["placements_degraded_warm"]) == 1, "WARM counter mismatch")
	_assert(int(flow_report["counters"]["placements_pending"]) == 1, "PENDING counter mismatch")


## Two different saved-world profiles (different saved authority/server-instance
## truth in the directory) must yield IDENTICAL gateway selection: the same
## gateway instance serves both clients over the same bound backend link. Only
## the identifier projection from the directory may differ.
func _run_gateway_selection_independence() -> void:
	_directory.register_world(PROFILE_WORLD_ID, "authority/eg2/saved-alpha", "server-instance/eg2/saved-alpha-1", 4)
	var profile_a := _register_client("profile-a")
	_authenticate(profile_a, "client-session/eg2/l1-prof-a", "OK")
	var payload_a := _place(profile_a, "client-session/eg2/l1-prof-a", PROFILE_WORLD_ID, "")
	_assert(not payload_a.is_empty(), "saved-profile A placement failed")
	if payload_a.is_empty():
		return

	# Profile B: the saved-world truth moved to a different authority entirely.
	_directory.register_world(PROFILE_WORLD_ID, "authority/eg2/saved-beta", "server-instance/eg2/saved-beta-2", 5)
	var profile_b := _register_client("profile-b")
	_authenticate(profile_b, "client-session/eg2/l1-prof-b", "OK")
	var payload_b := _place(profile_b, "client-session/eg2/l1-prof-b", PROFILE_WORLD_ID, "")
	_assert(not payload_b.is_empty(), "saved-profile B placement failed")
	if payload_b.is_empty():
		return

	_assert(String(payload_a["authority_id"]) == "authority/eg2/saved-alpha"
			and String(payload_b["authority_id"]) == "authority/eg2/saved-beta",
			"directory identifier projection did not follow the profiles")
	var row_a := _route_row(String(payload_a["gateway_session_id"]))
	var row_b := _route_row(String(payload_b["gateway_session_id"]))
	_assert(not row_a.is_empty() and not row_b.is_empty(), "saved-profile rows missing")
	if row_a.is_empty() or row_b.is_empty():
		return
	_assert(String(row_a["backend_link_id"]) == String(row_b["backend_link_id"]),
			"gateway link selection differed across saved-world profiles")
	_assert(int(row_a["session_slot"]) > 0 and int(row_b["session_slot"]) > 0,
			"slots were not allocated for both profiles")


func _run_redaction_scan() -> void:
	_assert(_captured_client_frames.size() >= 10,
			"redaction corpus suspiciously small: %d" % _captured_client_frames.size())
	var corpus := ""
	for frame_value in _captured_client_frames:
		var frame: Dictionary = frame_value
		corpus += JSON.stringify(frame)
		_scan_keys_recursive(frame.get("payload", {}), "payload")
	# Non-vacuous scan: identifiers really do travel on this leg.
	_assert(corpus.contains("server-instance/") and corpus.contains("authority/"),
			"redaction corpus lacks the identifier projection it must guard")
	for needle in FORBIDDEN_SUBSTRINGS:
		_assert(not corpus.contains(needle), "client leg leaked endpoint substring '%s'" % needle)


func _scan_keys_recursive(value, path: String) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				var key := String(raw_key)
				_assert(not FORBIDDEN_KEYS.has(key), "forbidden endpoint-ish key '%s' at %s" % [key, path])
				_scan_keys_recursive(value[raw_key], "%s.%s" % [path, key])
		TYPE_ARRAY:
			for index in range(value.size()):
				_scan_keys_recursive(value[index], "%s[%d]" % [path, index])


func _run_report_hygiene() -> void:
	# The directory itself refuses endpoint-shaped identifiers.
	var hostile: Dictionary = _directory.register_world("world/eg2/hostile", SIM_BIND_HOST, "server-instance/eg2/hostile", 1)
	_assert(not bool(hostile.get("success", false)), "directory accepted a host literal as authority id")
	var report_text := JSON.stringify(_flow.get_report())
	for needle in ["127.0.0.1", "localhost", SIM_BIND_PORT]:
		_assert(not report_text.contains(needle), "flow report leaked endpoint substring '%s'" % needle)
	var counters: Dictionary = _flow.get_report()["counters"]
	_assert(int(counters["authenticate_ok"]) >= 7, "authenticate_ok counter too low")
	_assert(int(counters["placements_created"]) >= 5, "placements_created counter too low")
	_assert(int(counters["placements_resumed"]) == 1, "placements_resumed counter mismatch")
	# Fail-closed client send: nothing was dropped for lack of a wire session.
	var node_counters: Dictionary = _gateway.get_report()["counters"]
	_assert(int(node_counters.get("client_send_dropped_no_wire_session", -1)) == 0,
			"fail-closed client-send drop counter advanced unexpectedly")
	_assert(int(node_counters.get("client_send_failures", -1)) == 0, "client send failures recorded")


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg2_placement_flow_l1",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"secondary_predicate": "NEAREST_GATEWAY_SELECTION_INDEPENDENT_FROM_SAVED_WORLD_AUTHORITY" if ok else "NOT_DEMONSTRATED",
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg2-l1] L1 PASS — WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg2-l1] L1 FAIL")
		quit(1)
