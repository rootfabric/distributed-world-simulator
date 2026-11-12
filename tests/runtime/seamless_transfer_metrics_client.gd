extends SceneTree

# Headless seamless-transfer metrics client (SM1.6 process topology).
# One process opens two ENet peers against the Gateway:
#   - writer peer  (client_id "a") drives MOVE +11 / MOVE -11 crossings,
#   - observer peer (client_id "b") only keeps the second Gateway binding alive
#     (the Gateway requires two HELLO clients before it sends START).
# Measures per-pivot client pause (last STATE before epoch pivot -> first STATE
# after) and per-command latency (EXECUTE send -> COMMAND_RESULT receive).

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"crossings": {"kind": "int", "default": 10},
	"timeout-ms": {"kind": "int", "default": 100000},
}

const WRITER_PEER_ID := "peer/enet/sm1/metrics-writer"
const OBSERVER_PEER_ID := "peer/enet/sm1/metrics-observer"
# The production Gateway begins shutdown when it completes this OperationId.
const FINAL_OPERATION_ID := "operation/sm1/graphical/5"

var _options: Dictionary = {}
var _commands: Array = []
var _writer = null
var _observer = null
var _finished := false
var _started_ms := 0
var _started_usec := 0
var _writer_hello_sent := false
var _observer_hello_sent := false
var _start_received := false
var _command_index := 0
var _commands_sent := 0
var _command_results := 0
var _command_failures: Array = []
var _command_send_usec: Dictionary = {}
var _latency_us: Array = []
var _connect_count := 0
var _observer_connect_count := 0
var _disconnects := 0
var _gateway_endpoint_id := ""
var _gateway_endpoint_stable := true
var _spawn_generation := 1
var _last_state_epoch := -1
var _last_state_revision := -1
var _last_state_usec := -1
var _epochs: Array = []
var _revisions: Array = []
var _route_history: Array = []
var _last_authority := ""
var _pivot_pause_us: Array = []
var _pivot_epoch_deltas: Array = []
var _state_times_us: Array = []
var _continuity_errors: Array = []
var _identity_failures: Array = []
var _final_payload: Dictionary = {}


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_commands = _build_commands(int(_options.get("crossings", 10)))
	_writer = Support.make_boundary()
	_observer = Support.make_boundary()
	if _writer == null or _observer == null:
		_finish_failure("BOUNDARY_CONFIGURE_FAILED", {})
		return
	var endpoint := Support.endpoint(String(_options["host"]), int(_options["port"]))
	var writer_connected: Dictionary = _writer.connect_client(endpoint, WRITER_PEER_ID, "transport-session/sm1/metrics-writer", "route/sm1/metrics-writer", 1)
	if not bool(writer_connected.get("success", false)):
		_finish_failure(String(writer_connected.get("error_code", "WRITER_CONNECT_FAILED")), {})
		return
	var observer_connected: Dictionary = _observer.connect_client(endpoint, OBSERVER_PEER_ID, "transport-session/sm1/metrics-observer", "route/sm1/metrics-observer", 1)
	if not bool(observer_connected.get("success", false)):
		_finish_failure(String(observer_connected.get("error_code", "OBSERVER_CONNECT_FAILED")), {})
		return
	_connect_count = 1
	_observer_connect_count = 1
	_started_ms = Time.get_ticks_msec()
	_started_usec = Time.get_ticks_usec()
	Support.write_state(String(_options["result-file"]), "CONNECTING", {
		"client_kind": "seamless-transfer-metrics",
		"display_server": DisplayServer.get_name(),
		"crossings": int(_options.get("crossings", 10)),
	})


func _build_commands(crossings: int) -> Array:
	var commands: Array = []
	var sequence := 0
	sequence += 1
	commands.append({"operation_id": "operation/sm1/metrics/%d" % sequence, "input_sequence": sequence, "command_kind": "ACTION", "delta_x": 0.0})
	for _crossing in range(maxi(1, crossings)):
		sequence += 1
		commands.append({"operation_id": "operation/sm1/metrics/%d" % sequence, "input_sequence": sequence, "command_kind": "MOVE", "delta_x": 11.0})
		sequence += 1
		commands.append({"operation_id": "operation/sm1/metrics/%d" % sequence, "input_sequence": sequence, "command_kind": "MOVE", "delta_x": -11.0})
	sequence += 1
	commands.append({"operation_id": FINAL_OPERATION_ID, "input_sequence": sequence, "command_kind": "ACTION", "delta_x": 0.0})
	return commands


func _process(_delta: float) -> bool:
	if _finished or _writer == null:
		return false
	_poll(_writer, WRITER_PEER_ID, true)
	if _finished:
		return false
	_poll(_observer, OBSERVER_PEER_ID, false)
	if _finished:
		return false
	if not _writer_hello_sent and String(_writer.get_peer_snapshot(WRITER_PEER_ID).get("state", "")) == "READY":
		_send_hello(_writer, WRITER_PEER_ID, "a")
	if not _observer_hello_sent and String(_observer.get_peer_snapshot(OBSERVER_PEER_ID).get("state", "")) == "READY":
		_send_hello(_observer, OBSERVER_PEER_ID, "b")
	_writer.flush_outbound(128)
	_observer.flush_outbound(128)
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 100000)):
		_finish_failure("CLIENT_TIMEOUT", {
			"commands_sent": _commands_sent,
			"command_results": _command_results,
			"last_epoch": _last_state_epoch,
			"last_revision": _last_state_revision,
		})
	return false


func _poll(boundary, peer_id: String, is_writer: bool) -> void:
	var polled: Dictionary = boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "CLIENT_POLL_FAILED")), {"peer_id": peer_id})
		return
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		var event_type := String(event.get("event_type", ""))
		if event_type == "PEER_CONNECTED":
			if not Support.mark_ready(boundary, peer_id):
				_finish_failure("GATEWAY_PEER_NOT_READY", {"peer_id": peer_id})
				return
		elif event_type == "PEER_DISCONNECTED" and not _finished:
			_disconnects += 1
			_finish_failure("GATEWAY_DISCONNECTED_BEFORE_COMPLETE", {"peer_id": peer_id})
			return
		elif event_type == "MESSAGE_RECEIVED" and is_writer:
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_handle(payload)


func _handle(payload: Dictionary) -> void:
	if _finished:
		return
	match String(payload.get("type", "")):
		"START":
			_handle_start(payload)
		"STATE":
			_handle_state(payload)
		"COMMAND_RESULT":
			_handle_command_result(payload)
		"COMPLETE":
			_finish_success(payload)
		"ERROR":
			_finish_failure(String(payload.get("error_code", "GATEWAY_ERROR")), {"payload": payload})


func _handle_start(payload: Dictionary) -> void:
	if _start_received:
		return
	_start_received = true
	_gateway_endpoint_id = String(payload.get("gateway_endpoint_id", ""))
	if _gateway_endpoint_id != Support.GATEWAY_ENDPOINT_ID:
		_gateway_endpoint_stable = false
	_send_next_command()


func _handle_state(payload: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	if String(payload.get("gateway_endpoint_id", "")) != Support.GATEWAY_ENDPOINT_ID:
		_gateway_endpoint_stable = false
	var state_value = payload.get("shared_state", {})
	if not state_value is Dictionary:
		_identity_failures.append("shared_state")
		return
	var state: Dictionary = Dictionary(state_value)
	var epoch := int(payload.get("authority_epoch", 0))
	var revision := int(state.get("world_revision", 0))
	if int(state.get("spawn_generation", 0)) != 1:
		_identity_failures.append("spawn_generation")
	if String(state.get("logical_player_id", "")) != Support.LOGICAL_PLAYER_ID:
		_identity_failures.append("logical_player_id")
	if String(state.get("player_entity_id", "")) != Support.PLAYER_ENTITY_ID:
		_identity_failures.append("player_entity_id")
	if _last_state_revision >= 0:
		if revision != _last_state_revision + 1:
			_continuity_errors.append({"expected_revision": _last_state_revision + 1, "actual_revision": revision})
		if epoch > _last_state_epoch:
			_pivot_pause_us.append(int(now - _last_state_usec))
			_pivot_epoch_deltas.append(epoch - _last_state_epoch)
		elif epoch < _last_state_epoch:
			_continuity_errors.append({"epoch_regression": [_last_state_epoch, epoch]})
	else:
		if revision != 1:
			_continuity_errors.append({"first_revision": revision})
	if not _epochs.has(epoch):
		_epochs.append(epoch)
	if not _revisions.has(revision):
		_revisions.append(revision)
	_state_times_us.append(int(now - _started_usec))
	var authority_id := String(payload.get("active_authority_id", ""))
	if authority_id != _last_authority:
		_last_authority = authority_id
		_route_history.append(authority_id)
	_last_state_epoch = epoch
	_last_state_revision = revision
	_last_state_usec = now


func _handle_command_result(payload: Dictionary) -> void:
	var request_id := String(payload.get("request_id", ""))
	if _command_send_usec.has(request_id):
		_latency_us.append(int(Time.get_ticks_usec() - int(_command_send_usec[request_id])))
		_command_send_usec.erase(request_id)
	if not bool(payload.get("success", false)):
		_command_failures.append(payload.duplicate(true))
		_finish_failure("COMMAND_REJECTED", {"payload": payload})
		return
	_command_results += 1
	_command_index += 1
	if _command_index < _commands.size():
		_send_next_command()


func _send_hello(boundary, peer_id: String, client_id: String) -> void:
	var sent: Dictionary = Support.send(boundary, peer_id, {"type": "HELLO", "client_id": client_id})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "HELLO_SEND_FAILED")), {"client_id": client_id})
		return
	if client_id == "a":
		_writer_hello_sent = true
	else:
		_observer_hello_sent = true


func _send_next_command() -> void:
	if _command_index >= _commands.size():
		return
	var command: Dictionary = Dictionary(_commands[_command_index])
	var request_id := "metrics/request/%d" % (_command_index + 1)
	var sent: Dictionary = Support.send(_writer, WRITER_PEER_ID, {
		"type": "EXECUTE",
		"request_id": request_id,
		"operation_id": String(command["operation_id"]),
		"input_sequence": int(command["input_sequence"]),
		"command_kind": String(command["command_kind"]),
		"delta_x": float(command["delta_x"]),
	})
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "COMMAND_SEND_FAILED")), {"command_index": _command_index})
		return
	_commands_sent += 1
	_command_send_usec[request_id] = Time.get_ticks_usec()


func _finish_success(payload: Dictionary) -> void:
	if _finished:
		return
	_final_payload = payload.duplicate(true)
	var crossings := maxi(1, int(_options.get("crossings", 10)))
	var expected_commands := 2 * crossings + 2
	var expected_pivots := 2 * crossings
	var expected_final_epoch := 2 * crossings + 1
	var expected_final_revision := 2 * crossings + 2
	var route_ok: bool = _route_history.size() == expected_pivots + 1 \
		and String(_route_history[0]) == Support.AUTHORITY_A \
		and String(_route_history[_route_history.size() - 1]) == Support.AUTHORITY_A
	if route_ok:
		for i in range(1, _route_history.size()):
			if String(_route_history[i]) == String(_route_history[i - 1]):
				route_ok = false
				break
	var epoch_pivot_ok := _pivot_epoch_deltas.size() == expected_pivots
	if epoch_pivot_ok:
		for delta in _pivot_epoch_deltas:
			if int(delta) != 1:
				epoch_pivot_ok = false
				break
	var passed := _connect_count == 1 \
		and _observer_connect_count == 1 \
		and _disconnects == 0 \
		and _start_received \
		and _gateway_endpoint_stable \
		and _identity_failures.is_empty() \
		and _continuity_errors.is_empty() \
		and _commands_sent == expected_commands \
		and _command_results == expected_commands \
		and _command_failures.is_empty() \
		and _latency_us.size() == expected_commands \
		and _revisions.size() == expected_final_revision \
		and _pivot_pause_us.size() == expected_pivots \
		and epoch_pivot_ok \
		and route_ok \
		and String(payload.get("active_authority_id", "")) == Support.AUTHORITY_A \
		and int(payload.get("authority_epoch", 0)) == expected_final_epoch \
		and int(payload.get("world_revision", 0)) == expected_final_revision
	var report := {
		"schema": "planet_simulator.seamless_transfer_metrics_client.v1",
		"state": "COMPLETE" if passed else "FAILED",
		"passed": passed,
		"process_id": OS.get_process_id(),
		"client_kind": "seamless-transfer-metrics",
		"display_server": DisplayServer.get_name(),
		"crossings": crossings,
		"connect_count": _connect_count,
		"observer_connect_count": _observer_connect_count,
		"disconnects": _disconnects,
		"respawn_count": 0,
		"despawn_count": 0,
		"gateway_endpoint_id": _gateway_endpoint_id,
		"gateway_endpoint_stable": _gateway_endpoint_stable,
		"logical_player_id": Support.LOGICAL_PLAYER_ID,
		"player_entity_id": Support.PLAYER_ENTITY_ID,
		"spawn_generation": _spawn_generation,
		"route_history": _route_history.duplicate(),
		"epochs": _epochs.duplicate(),
		"revisions": _revisions.duplicate(),
		"revision_continuity_errors": _continuity_errors.duplicate(),
		"pivot_pause_us": _pivot_pause_us.duplicate(),
		"pivot_epoch_deltas": _pivot_epoch_deltas.duplicate(),
		"command_latency_us": _latency_us.duplicate(),
		"state_receive_offsets_us": _state_times_us.duplicate(),
		"commands_sent": _commands_sent,
		"command_results": _command_results,
		"command_failures": _command_failures.duplicate(),
		"states_received": _state_times_us.size(),
		"identity_failures": _identity_failures.duplicate(),
		"final_active_authority_id": String(payload.get("active_authority_id", "")),
		"final_authority_epoch": int(payload.get("authority_epoch", 0)),
		"final_world_revision": int(payload.get("world_revision", 0)),
		"totals": {
			"duration_us": int(Time.get_ticks_usec() - _started_usec),
			"handoff_pivots": _pivot_pause_us.size(),
			"commands": _commands_sent,
			"pivot_pause": _stats(_pivot_pause_us),
			"command_latency": _stats(_latency_us),
		},
	}
	Support.write_json(String(_options["result-file"]), report)
	_finish("COMPLETE" if passed else "FAILED", passed)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.seamless_transfer_metrics_client.v1",
		"state": "FAILED",
		"passed": false,
		"process_id": OS.get_process_id(),
		"failure_code": error_code,
		"details": details,
		"crossings": int(_options.get("crossings", 10)),
		"connect_count": _connect_count,
		"observer_connect_count": _observer_connect_count,
		"disconnects": _disconnects,
		"commands_sent": _commands_sent,
		"command_results": _command_results,
		"epochs": _epochs.duplicate(),
		"revisions": _revisions.duplicate(),
		"route_history": _route_history.duplicate(),
		"pivot_pause_us": _pivot_pause_us.duplicate(),
		"command_latency_us": _latency_us.duplicate(),
		"pivot_epoch_deltas": _pivot_epoch_deltas.duplicate(),
		"revision_continuity_errors": _continuity_errors.duplicate(),
		"identity_failures": _identity_failures.duplicate(),
	})
	_finish(error_code, false)


func _finish(reason: String, passed: bool) -> void:
	_finished = true
	if _writer != null:
		_writer.stop()
	if _observer != null:
		_observer.stop()
	print("SEAMLESS_TRANSFER_METRICS_CLIENT_%s passed=%s" % [reason, str(passed)])
	quit(0 if passed else 1)


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "min_us": 0, "p50_us": 0, "p95_us": 0, "max_us": 0}
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	return {
		"count": sorted_values.size(),
		"min_us": int(sorted_values[0]),
		"p50_us": _percentile(sorted_values, 50.0),
		"p95_us": _percentile(sorted_values, 95.0),
		"max_us": int(sorted_values[sorted_values.size() - 1]),
	}


func _percentile(sorted_values: Array, p: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := int(floor(p / 100.0 * (sorted_values.size() - 1)))
	return int(sorted_values[clampi(index, 0, sorted_values.size() - 1)])
