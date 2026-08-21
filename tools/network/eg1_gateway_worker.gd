extends SceneTree

## EG1 gateway worker: a REAL gateway process. Composes the eg1_gateway_node
## over two real ENET boundaries: a client-facing listener (game clients
## connect here) and a backend client leg into the sim server worker.
## Pumps until the client detaches, then publishes the forwarding report.

const Support = preload("res://tools/network/eg1_process_support.gd")
const GatewayNodeScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

const OPTION_SPEC := {
	"client-host": {"kind": "string", "default": "127.0.0.1"},
	"client-port": {"kind": "int", "default": 0, "required": true},
	"sim-host": {"kind": "string", "default": "127.0.0.1"},
	"sim-port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 60000},
	"user-data-dir": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _node
var _started_ms: int = 0
var _finished := false
var _completion_at_ms: int = -1


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_node = GatewayNodeScript.new()
	var started: Dictionary = _node.start(
			Support.enet_endpoint(String(_options["client-host"]), int(_options["client-port"])),
			Support.enet_endpoint(String(_options["sim-host"]), int(_options["sim-port"])),
			"gateway/eg1/p2p-worker",
			{
				"client_port": EnetPortScript.new(),
				"backend_port": EnetPortScript.new(),
				"backend_peer_id": "peer/enet/eg1-gateway-backend",
				"backend_session_id": "transport-session/eg1/gateway-backend",
				"backend_route_id": "route/eg1/gateway-backend",
				"backend_link_id": "backend-link/eg1/p2p-sim",
			})
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "GATEWAY_START_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "LISTENING", {
		"client_port": int(_options["client-port"]),
		"sim_port": int(_options["sim-port"]),
	})
	print("EG1_GATEWAY_LISTENING client_port=%d sim_port=%d" % [int(_options["client-port"]), int(_options["sim-port"])])


func _process(_delta: float) -> bool:
	if _finished or _node == null:
		return false
	var pumped: Dictionary = _node.pump(64)
	if not bool(pumped.get("success", false)):
		_finish_failure(String(pumped.get("error_code", "PUMP_FAILED")), {})
		return false
	var counters: Dictionary = _node.get_report()["counters"]
	if int(counters.get("session_control_detached", 0)) >= 1 and _completion_at_ms < 0:
		_completion_at_ms = Time.get_ticks_msec()
	if _completion_at_ms >= 0 and Time.get_ticks_msec() - _completion_at_ms >= 500:
		_finish_success()
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("GATEWAY_TIMEOUT", {"counters": counters})
	return false


func _finish_success() -> void:
	_finished = true
	var report: Dictionary = _node.get_report()
	report["schema"] = "planet_simulator.eg1_gateway_worker_report.v1"
	report["state"] = "COMPLETE"
	report["passed"] = true
	report["user_data_dir"] = String(_options["user-data-dir"])
	report["process_id"] = OS.get_process_id()
	Support.write_json(String(_options["result-file"]), report)
	_node.stop()
	print("EG1_GATEWAY_COMPLETE forwarded_c2w=%d forwarded_w2c=%d" % [
		int(report["counters"]["forwarder"]["forwarded_client_to_world"]),
		int(report["counters"]["forwarder"]["forwarded_world_to_client"]),
	])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg1_gateway_worker_report.v1",
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
	push_error("EG1 gateway worker failed: %s" % error_code)
	quit(1)
