extends SceneTree

## EG2 gateway worker: a REAL gateway process composing the EG1 gateway node
## with the EG2 truths that live gateway-side — the auth/session service and
## the identifier-only world directory — plus the placement flow installed as
## the additive SESSION_CONTROL handler. Clients CONNECT -> AUTH -> PLACE over
## real ENET here; the worker never talks to the domain.
##
## On startup it mints one-time tickets for the declared client session and
## publishes them in its LISTENING state file so the test orchestrator can
## hand them to the two client processes.

const Support = preload("res://tools/network/eg2_process_support.gd")
const GatewayNodeScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const AuthServiceScript = preload("res://scripts/network/gateway/runtime/eg2_auth_session_service.gd")
const WorldDirectoryScript = preload("res://scripts/network/gateway/runtime/eg2_world_directory.gd")
const PlacementFlowScript = preload("res://scripts/network/gateway/runtime/eg2_placement_flow.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

const OPTION_SPEC := {
	"client-host": {"kind": "string", "default": "127.0.0.1"},
	"client-port": {"kind": "int", "default": 0, "required": true},
	"sim-host": {"kind": "string", "default": "127.0.0.1"},
	"sim-port": {"kind": "int", "default": 0, "required": true},
	"world-id": {"kind": "string", "default": Support.WORLD_ID},
	"authority-id": {"kind": "string", "default": Support.AUTHORITY_ID},
	"server-instance-id": {"kind": "string", "default": Support.SERVER_INSTANCE_ID},
	"catalog-revision": {"kind": "int", "default": Support.CATALOG_REVISION},
	"premint-client-session": {"kind": "string", "default": Support.CLIENT_SESSION_ID},
	"premint-count": {"kind": "int", "default": 2},
	"expected-placements": {"kind": "int", "default": 2},
	"result-file": {"kind": "string", "default": "", "required": true},
	"player-binding-file": {"kind": "string", "default": ""},
	"timeout-ms": {"kind": "int", "default": 60000},
	"user-data-dir": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _node
var _auth_service
var _directory
var _placement
var _published_bindings: Dictionary = {}
var _started_ms: int = 0
var _finished := false
var _completion_at_ms: int = -1


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]

	_auth_service = AuthServiceScript.new()
	var auth_config: Dictionary = _auth_service.configure({})
	if not bool(auth_config.get("success", false)):
		_finish_failure("AUTH_CONFIGURE_FAILED", {})
		return
	_directory = WorldDirectoryScript.new()
	var registered: Dictionary = _directory.register_world(
			String(_options["world-id"]), String(_options["authority-id"]),
			String(_options["server-instance-id"]), int(_options["catalog-revision"]))
	if not bool(registered.get("success", false)):
		_finish_failure("WORLD_REGISTRATION_FAILED", {"error_code": String(registered.get("error_code", ""))})
		return
	_placement = PlacementFlowScript.new()
	var flow_config: Dictionary = _placement.configure(_auth_service, _directory)
	if not bool(flow_config.get("success", false)):
		_finish_failure("PLACEMENT_CONFIGURE_FAILED", {})
		return

	_node = GatewayNodeScript.new()
	var started: Dictionary = _node.start(
			Support.enet_endpoint(String(_options["client-host"]), int(_options["client-port"])),
			Support.enet_endpoint(String(_options["sim-host"]), int(_options["sim-port"])),
			"gateway/eg2/l2-worker",
			{
				"client_port": EnetPortScript.new(),
				"backend_port": EnetPortScript.new(),
				"backend_peer_id": "peer/enet/eg2-gateway-backend",
				"backend_session_id": "transport-session/eg2/gateway-backend",
				"backend_route_id": "route/eg2/gateway-backend",
				"backend_link_id": "backend-link/eg2/l2-sim",
			})
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "GATEWAY_START_FAILED")), {})
		return
	var handler: Dictionary = _node.set_placement_handler(_placement)
	if not bool(handler.get("success", false)):
		_finish_failure("PLACEMENT_HANDLER_INSTALL_FAILED", {})
		return

	var tickets: Array[String] = []
	for index in range(int(_options["premint-count"])):
		var minted: Dictionary = _auth_service.mint_auth_ticket(String(_options["premint-client-session"]))
		if not bool(minted.get("success", false)):
			_finish_failure("TICKET_PREMINT_FAILED", {"index": index})
			return
		tickets.append(String(minted["details"]["ticket_id"]))

	_started_ms = Time.get_ticks_msec()
	Support.write_json(String(_options["result-file"]), {
		"schema": "planet_simulator.eg2_process_state.v1",
		"state": "LISTENING",
		"passed": false,
		"process_id": OS.get_process_id(),
		"tickets": {String(_options["premint-client-session"]): tickets},
	})
	print("EG2_GATEWAY_LISTENING client_port=%d sim_port=%d tickets=%d" % [
		int(_options["client-port"]), int(_options["sim-port"]), tickets.size()])


func _process(_delta: float) -> bool:
	if _finished or _node == null:
		return false
	var pumped: Dictionary = _node.pump(64)
	if not bool(pumped.get("success", false)):
		_finish_failure(String(pumped.get("error_code", "PUMP_FAILED")), {})
		return false
	_publish_player_bindings()
	var counters: Dictionary = _node.get_report()["counters"]
	var detached := int(counters.get("session_control_detached", 0))
	var placements_done := int(counters.get("placement_handled", 0))
	if detached >= int(_options["expected-placements"]) \
			and placements_done >= int(_options["expected-placements"]) and _completion_at_ms < 0:
		_completion_at_ms = Time.get_ticks_msec()
	if _completion_at_ms >= 0 and Time.get_ticks_msec() - _completion_at_ms >= 500:
		_finish_success()
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("GATEWAY_TIMEOUT", {"counters": counters})
	return false


## Publish the GATEWAY-GRANTED domain identity for every live placement so the
## sim-side worker can bind operations to the granted logical player id
## (player/eg2-*) instead of a fixed identity. Identifier-only sidecar file:
## the wire contract (ingress envelope) stays untouched.
func _publish_player_bindings() -> void:
	var path := String(_options.get("player-binding-file", ""))
	if path.is_empty():
		return
	var flow_report: Dictionary = _placement.get_report()
	var dirty := false
	for entry_value in flow_report.get("live_placements", []):
		var entry: Dictionary = entry_value
		var gateway_session_id := String(entry["gateway_session_id"])
		if _published_bindings.has(gateway_session_id):
			continue
		var session_result: Dictionary = _auth_service.get_session(gateway_session_id)
		if not bool(session_result.get("success", false)):
			continue
		var session: Dictionary = session_result.get("details", {}).get("session", {})
		if session.is_empty():
			continue
		_published_bindings[gateway_session_id] = {
			"gateway_session_id": gateway_session_id,
			"client_session_id": String(session["client_session_id"]),
			"logical_player_id": String(session["logical_player_id"]),
			"player_entity_id": String(session["player_entity_id"]),
		}
		dirty = true
	if dirty:
		Support.write_json(path, {
			"schema": "planet_simulator.eg2_player_bindings.v1",
			"bindings": _published_bindings.duplicate(true),
		})


func _finish_success() -> void:
	_finished = true
	_publish_player_bindings()
	var report: Dictionary = _node.get_report()
	report["schema"] = "planet_simulator.eg2_gateway_worker_report.v1"
	report["state"] = "COMPLETE"
	report["passed"] = true
	report["placement_flow"] = _placement.get_report()
	report["user_data_dir"] = String(_options["user-data-dir"])
	report["process_id"] = OS.get_process_id()
	Support.write_json(String(_options["result-file"]), report)
	_node.stop()
	print("EG2_GATEWAY_COMPLETE placements=%d rejected=%d forwarded_c2w=%d forwarded_w2c=%d" % [
		int(report["counters"]["placement_handled"]),
		int(report["counters"]["placement_rejected"]),
		int(report["counters"]["forwarder"]["forwarded_client_to_world"]),
		int(report["counters"]["forwarder"]["forwarded_world_to_client"]),
	])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg2_gateway_worker_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"process_id": OS.get_process_id(),
	}
	if _node != null:
		report["gateway"] = _node.get_report()
		_node.stop()
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG2 gateway worker failed: %s" % error_code)
	quit(1)
