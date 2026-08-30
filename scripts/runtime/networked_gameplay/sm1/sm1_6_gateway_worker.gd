extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const OPTION_SPEC := {
	"client-host": {"kind": "string", "default": "127.0.0.1"},
	"client-port": {"kind": "int", "default": 0, "required": true},
	"authority-a-host": {"kind": "string", "default": "127.0.0.1"},
	"authority-a-port": {"kind": "int", "default": 0, "required": true},
	"authority-b-host": {"kind": "string", "default": "127.0.0.1"},
	"authority-b-port": {"kind": "int", "default": 0, "required": true},
	"client-network-profile": {"kind": "string", "default": ""},
	"authority-network-profile": {"kind": "string", "default": ""},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 120000},
}

var _options: Dictionary = {}
var _client_boundary = null
var _client_network_simulator = null
var _client_network_profile: Dictionary = {}
var _authority_boundaries: Dictionary = {}
var _authority_network_simulators: Dictionary = {}
var _authority_network_profiles: Dictionary = {}
var _authority_peer_ids := {
	Support.AUTHORITY_A: "peer/enet/sm1/gateway-authority-a",
	Support.AUTHORITY_B: "peer/enet/sm1/gateway-authority-b",
}
var _authority_ready := {Support.AUTHORITY_A: false, Support.AUTHORITY_B: false}
var _authority_connection_generation := {Support.AUTHORITY_A: 1, Support.AUTHORITY_B: 1}
var _authority_reconnect_due_ms := {Support.AUTHORITY_A: -1, Support.AUTHORITY_B: -1}
var _runtime_authority_recovery: Dictionary = {}
var _runtime_authority_requests: Dictionary = {}
var _authority_recovery_blocks_writes := false
var _client_by_peer: Dictionary = {}
var _peer_by_client: Dictionary = {}
var _ever_connected_clients: Dictionary = {}
var _resuming_peers: Dictionary = {}
var _resume_requests: Dictionary = {}
var _pending_restart_hellos: Dictionary = {}
var _authority_status_requests: Dictionary = {}
var _authority_status_results: Dictionary = {}
var _authority_recovery_requested := false
var _authority_recovery_complete := false
var _restart_recovery_session := false
var _bootstrap_authority_id := ""
var _bootstrap_authority_epoch := 0
var _session_ready_announced := false
var _started_ms := 0
var _started_clients := false
var _finished := false
var _shutdown_at_ms := -1
var _active_authority_id := ""
var _authority_epoch := 0
var _pending_command: Dictionary = {}
var _transfer: Dictionary = {}
var _request_serial := 0
var _handoff_count := 0
var _last_world_revision := 0
var _last_state_checksum := ""
var _counters := {
	"client_messages": 0,
	"authority_messages": 0,
	"commands": 0,
	"handoffs": 0,
	"state_broadcasts": 0,
	"route_changes": 0,
	"busy_rejections": 0,
	"client_disconnects": 0,
	"client_reconnects": 0,
	"resume_queries": 0,
	"resume_successes": 0,
	"authority_status_queries": 0,
	"authority_recoveries": 0,
	"restart_resume_sessions": 0,
	"session_ready_announcements": 0,
	"authority_disconnects": 0,
	"authority_reconnects": 0,
	"authority_recovery_status_queries": 0,
	"authority_recovery_state_queries": 0,
	"standby_syncs": 0,
	"active_authority_recoveries": 0,
	"authority_recovery_events": 0,
}



func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	var client_bundle: Dictionary = Support.make_boundary_bundle(String(_options.get("client-network-profile", "")), 101)
	_client_boundary = client_bundle.get("boundary")
	_client_network_simulator = client_bundle.get("simulator")
	_client_network_profile = Dictionary(client_bundle.get("profile", {})).duplicate(true)
	if _client_boundary == null:
		_finish_failure("CLIENT_BOUNDARY_CONFIGURE_FAILED", {"network_profile": String(_options.get("client-network-profile", ""))})
		return
	var listening: Dictionary = _client_boundary.start_server(Support.endpoint(String(_options["client-host"]), int(_options["client-port"])))
	if not bool(listening.get("success", false)):
		_finish_failure(String(listening.get("error_code", "GATEWAY_LISTEN_FAILED")), {})
		return
	if not _connect_authority(Support.AUTHORITY_A, String(_options["authority-a-host"]), int(_options["authority-a-port"])):
		return
	if not _connect_authority(Support.AUTHORITY_B, String(_options["authority-b-host"]), int(_options["authority-b-port"])):
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "LISTENING", {
		"process_id": OS.get_process_id(),
		"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
		"client_port": int(_options["client-port"]),
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"authority_recovery_complete": false,
	})
	print("SM1_6_GATEWAY_LISTENING port=%d" % int(_options["client-port"]))


func _connect_authority(authority_id: String, host: String, port: int) -> bool:
	var seed_offset := 201 if authority_id == Support.AUTHORITY_A else 202
	seed_offset += int(_authority_connection_generation.get(authority_id, 1)) * 10
	var bundle: Dictionary = Support.make_boundary_bundle(String(_options.get("authority-network-profile", "")), seed_offset)
	var boundary = bundle.get("boundary")
	if boundary == null:
		_finish_failure("AUTHORITY_BOUNDARY_CONFIGURE_FAILED", {"authority_id": authority_id, "network_profile": String(_options.get("authority-network-profile", ""))})
		return false
	_authority_network_simulators[authority_id] = bundle.get("simulator")
	_authority_network_profiles[authority_id] = Dictionary(bundle.get("profile", {})).duplicate(true)
	var peer_id := String(_authority_peer_ids[authority_id])
	var generation := int(_authority_connection_generation.get(authority_id, 1))
	var connected: Dictionary = boundary.connect_client(
		Support.endpoint(host, port), peer_id,
		"transport-session/sm1/gateway/%s/%d" % [authority_id.replace("/", "-"), generation],
		"route/sm1/gateway/%s/%d" % [authority_id.replace("/", "-"), generation], generation)
	if not bool(connected.get("success", false)):
		boundary.stop()
		return false
	_authority_boundaries[authority_id] = boundary
	return true


func _process(_delta: float) -> bool:
	if _finished:
		return false
	_poll_clients()
	_maybe_reconnect_authorities()
	_poll_authority(Support.AUTHORITY_A)
	_poll_authority(Support.AUTHORITY_B)
	_maybe_start_authority_recovery()
	_flush_all()
	_maybe_start_clients()
	if _shutdown_at_ms > 0 and Time.get_ticks_msec() >= _shutdown_at_ms:
		_finish_success()
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options.get("timeout-ms", 120000)):
		_finish_failure("GATEWAY_TIMEOUT", {"pending_command": _pending_command, "transfer": _transfer})
	return false


func _maybe_start_authority_recovery() -> void:
	if _authority_recovery_requested or _authority_recovery_complete:
		return
	if not bool(_authority_ready.get(Support.AUTHORITY_A, false)) or not bool(_authority_ready.get(Support.AUTHORITY_B, false)):
		return
	_authority_recovery_requested = true
	for authority_id in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		_request_serial += 1
		var request_id := "sm1/gateway/status/%d" % _request_serial
		_authority_status_requests[request_id] = authority_id
		_counters["authority_status_queries"] = int(_counters["authority_status_queries"]) + 1
		_send_authority(authority_id, {"type": "STATUS_QUERY", "request_id": request_id})


func _handle_status_query_result(authority_id: String, payload: Dictionary) -> void:
	var request_id := String(payload.get("request_id", ""))
	if not _authority_status_requests.has(request_id) or String(_authority_status_requests[request_id]) != authority_id:
		_finish_failure("AUTHORITY_STATUS_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	_authority_status_requests.erase(request_id)
	if not bool(payload.get("success", false)):
		_finish_failure("AUTHORITY_STATUS_QUERY_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	if String(payload.get("authority_id", "")) != authority_id:
		_finish_failure("AUTHORITY_STATUS_ID_DIVERGED", {"authority_id": authority_id, "payload": payload})
		return
	_authority_status_results[authority_id] = payload.duplicate(true)
	if _authority_status_results.size() != 2:
		return
	var active_ids: Array[String] = []
	for candidate in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		if bool(Dictionary(_authority_status_results.get(candidate, {})).get("active", false)):
			active_ids.append(candidate)
	if active_ids.size() != 1:
		_finish_failure("AUTHORITY_RECOVERY_ACTIVE_SET_INVALID", {"active_authority_ids": active_ids})
		return
	var selected := String(active_ids[0])
	var status: Dictionary = Dictionary(_authority_status_results[selected])
	var epoch := int(status.get("authority_epoch", 0))
	if epoch < 1:
		_finish_failure("AUTHORITY_RECOVERY_EPOCH_INVALID", {"authority_id": selected, "status": status})
		return
	_active_authority_id = selected
	_authority_epoch = epoch
	_bootstrap_authority_id = selected
	_bootstrap_authority_epoch = epoch
	_last_world_revision = int(status.get("world_revision", 0))
	_last_state_checksum = String(status.get("state_checksum", ""))
	_authority_recovery_complete = true
	_counters["authority_recoveries"] = int(_counters["authority_recoveries"]) + 1
	for peer_value in _pending_restart_hellos.keys().duplicate():
		var peer_id := String(peer_value)
		var hello: Dictionary = Dictionary(_pending_restart_hellos[peer_id]).duplicate(true)
		_begin_restart_resume(peer_id, String(hello.get("client_id", "")), hello)
	_maybe_start_clients()


func _begin_restart_resume(peer_id: String, client_id: String, hello: Dictionary) -> void:
	if not _authority_recovery_complete:
		_pending_restart_hellos[peer_id] = hello.duplicate(true)
		return
	if not _pending_command.is_empty() or not _transfer.is_empty():
		_finish_failure("CLIENT_RECONNECT_DURING_HANDOFF", {"client_id": client_id})
		return
	var observed_epoch := int(hello.get("observed_authority_epoch", 0))
	var observed_revision := int(hello.get("observed_world_revision", 0))
	var observed_checksum := String(hello.get("observed_state_checksum", ""))
	if observed_epoch != _authority_epoch or observed_revision != _last_world_revision or observed_checksum.is_empty() or observed_checksum != _last_state_checksum:
		_finish_failure("GATEWAY_RESTART_OBSERVED_STATE_DIVERGED", {
			"client_id": client_id,
			"observed_epoch": observed_epoch,
			"observed_revision": observed_revision,
			"expected_epoch": _authority_epoch,
			"expected_revision": _last_world_revision,
		})
		return
	_pending_restart_hellos.erase(peer_id)
	_request_serial += 1
	var request_id := "sm1/gateway/restart-resume/%d" % _request_serial
	_resuming_peers[peer_id] = true
	_resume_requests[request_id] = {
		"peer_id": peer_id,
		"client_id": client_id,
		"restart": true,
		"observed_epoch": observed_epoch,
		"observed_revision": observed_revision,
		"observed_checksum": observed_checksum,
	}
	_counters["client_reconnects"] = int(_counters["client_reconnects"]) + 1
	_counters["resume_queries"] = int(_counters["resume_queries"]) + 1
	_send_authority(_active_authority_id, {
		"type": "STATE_QUERY",
		"request_id": request_id,
		"authority_epoch": _authority_epoch,
	})


func _maybe_announce_recovered_session_ready() -> void:
	if not _restart_recovery_session or _session_ready_announced:
		return
	if _peer_by_client.size() != 2 or not _resuming_peers.is_empty() or not _pending_restart_hellos.is_empty():
		return
	if int(_counters.get("restart_resume_sessions", 0)) != 2:
		return
	_session_ready_announced = true
	_started_clients = true
	_counters["session_ready_announcements"] = int(_counters["session_ready_announcements"]) + 1
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "SESSION_READY",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"product_session_id": Support.PRODUCT_SESSION_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
			"world_revision": _last_world_revision,
		})


func _poll_clients() -> void:
	if _client_boundary == null:
		return
	var polled: Dictionary = _client_boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "CLIENT_POLL_FAILED")), {})
		return
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		var event_type := String(event.get("event_type", ""))
		var peer_id := String(event.get("peer_id", ""))
		if event_type == "PEER_CONNECTED":
			if not Support.mark_ready(_client_boundary, peer_id):
				_finish_failure("CLIENT_PEER_NOT_READY", {"peer_id": peer_id})
				return
		elif event_type == "PEER_DISCONNECTED" and _client_by_peer.has(peer_id) and _shutdown_at_ms < 0:
			_handle_client_disconnect(peer_id)
			if _finished:
				return
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_counters["client_messages"] = int(_counters["client_messages"]) + 1
				_handle_client(peer_id, payload)


func _handle_client_disconnect(peer_id: String) -> void:
	var client_id := String(_client_by_peer.get(peer_id, ""))
	if client_id.is_empty():
		return
	if not _pending_command.is_empty() or not _transfer.is_empty():
		_finish_failure("CLIENT_DISCONNECTED_DURING_HANDOFF", {"client_id": client_id})
		return
	_client_by_peer.erase(peer_id)
	if String(_peer_by_client.get(client_id, "")) == peer_id:
		_peer_by_client.erase(client_id)
	_resuming_peers.erase(peer_id)
	_pending_restart_hellos.erase(peer_id)
	for request_value in _resume_requests.keys():
		var request_id := String(request_value)
		if String(Dictionary(_resume_requests[request_id]).get("peer_id", "")) == peer_id:
			_resume_requests.erase(request_id)
	_counters["client_disconnects"] = int(_counters["client_disconnects"]) + 1


func _begin_client_resume(peer_id: String, client_id: String) -> void:
	if not _started_clients:
		_finish_failure("CLIENT_RECONNECT_BEFORE_INITIAL_START", {"client_id": client_id})
		return
	if not _pending_command.is_empty() or not _transfer.is_empty():
		_finish_failure("CLIENT_RECONNECT_DURING_HANDOFF", {"client_id": client_id})
		return
	_request_serial += 1
	var request_id := "sm1/gateway/resume/%d" % _request_serial
	_resuming_peers[peer_id] = true
	_resume_requests[request_id] = {"peer_id": peer_id, "client_id": client_id}
	_counters["client_reconnects"] = int(_counters["client_reconnects"]) + 1
	_counters["resume_queries"] = int(_counters["resume_queries"]) + 1
	_send_authority(_active_authority_id, {
		"type": "STATE_QUERY",
		"request_id": request_id,
		"authority_epoch": _authority_epoch,
	})


func _handle_state_query_result(authority_id: String, payload: Dictionary) -> void:
	var request_id := String(payload.get("request_id", ""))
	if not _resume_requests.has(request_id):
		_finish_failure("RESUME_QUERY_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	var resume: Dictionary = Dictionary(_resume_requests[request_id])
	var peer_id := String(resume.get("peer_id", ""))
	var client_id := String(resume.get("client_id", ""))
	if authority_id != _active_authority_id or not bool(payload.get("success", false)):
		_finish_failure("RESUME_QUERY_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if int(payload.get("authority_epoch", 0)) != _authority_epoch:
		_finish_failure("RESUME_AUTHORITY_EPOCH_DIVERGED", {"payload": payload})
		return
	var state_value = payload.get("state", {})
	if not state_value is Dictionary:
		_finish_failure("RESUME_STATE_REQUIRED", {"payload": payload})
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	var state_checksum := Support.checksum(state)
	if not _validate_identity(state) or String(payload.get("state_checksum", "")) != state_checksum:
		_finish_failure("RESUME_STATE_INVALID", {"payload": payload})
		return
	if _last_world_revision > 0 and int(state.get("world_revision", 0)) != _last_world_revision:
		_finish_failure("RESUME_WORLD_REVISION_DIVERGED", {"expected": _last_world_revision, "state": state})
		return
	if not _last_state_checksum.is_empty() and state_checksum != _last_state_checksum:
		_finish_failure("RESUME_OBSERVED_STATE_DIVERGED", {"expected_checksum": _last_state_checksum, "actual_checksum": state_checksum})
		return
	if String(_peer_by_client.get(client_id, "")) != peer_id:
		_finish_failure("RESUME_CLIENT_BINDING_CHANGED", {"client_id": client_id})
		return
	var restart_resume := bool(resume.get("restart", false))
	_resume_requests.erase(request_id)
	_resuming_peers.erase(peer_id)
	_counters["resume_successes"] = int(_counters["resume_successes"]) + 1
	if restart_resume:
		_counters["restart_resume_sessions"] = int(_counters["restart_resume_sessions"]) + 1
	_send_client(peer_id, {
		"type": "RESUME",
		"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
		"product_session_id": Support.PRODUCT_SESSION_ID,
		"client_id": client_id,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"shared_state": state,
		"state_checksum": state_checksum,
	})
	if restart_resume:
		_maybe_announce_recovered_session_ready()


func _authority_endpoint(authority_id: String) -> Dictionary:
	if authority_id == Support.AUTHORITY_A:
		return Support.endpoint(String(_options["authority-a-host"]), int(_options["authority-a-port"]))
	return Support.endpoint(String(_options["authority-b-host"]), int(_options["authority-b-port"]))


func _maybe_reconnect_authorities() -> void:
	for authority_id in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		if not _runtime_authority_recovery.has(authority_id):
			continue
		if _authority_boundaries.has(authority_id):
			continue
		var due := int(_authority_reconnect_due_ms.get(authority_id, -1))
		if due < 0 or Time.get_ticks_msec() < due:
			continue
		_authority_reconnect_due_ms[authority_id] = Time.get_ticks_msec() + 300
		var endpoint := _authority_endpoint(authority_id)
		_connect_authority(authority_id, String(endpoint["host"]), int(endpoint["port"]))


func _handle_authority_disconnect(authority_id: String) -> void:
	if not _pending_command.is_empty() or not _transfer.is_empty():
		_finish_failure("AUTHORITY_DISCONNECTED_DURING_HANDOFF", {"authority_id": authority_id})
		return
	if not _runtime_authority_recovery.is_empty() and not _runtime_authority_recovery.has(authority_id):
		_finish_failure("MULTIPLE_AUTHORITY_RECOVERY_UNSUPPORTED", {"authority_id": authority_id, "existing": _runtime_authority_recovery.keys()})
		return
	_authority_ready[authority_id] = false
	if _authority_boundaries.has(authority_id):
		_authority_boundaries[authority_id].stop()
		_authority_boundaries.erase(authority_id)
	_authority_connection_generation[authority_id] = int(_authority_connection_generation.get(authority_id, 1)) + 1
	_authority_reconnect_due_ms[authority_id] = Time.get_ticks_msec() + 200
	_runtime_authority_recovery[authority_id] = {
		"authority_id": authority_id,
		"was_active": authority_id == _active_authority_id,
		"expected_epoch": _authority_epoch if authority_id == _active_authority_id else 0,
		"stage": "WAIT_RECONNECT",
	}
	_authority_recovery_blocks_writes = true
	_counters["authority_disconnects"] = int(_counters["authority_disconnects"]) + 1
	_broadcast_authority_recovery("AUTHORITY_RECOVERY_PENDING", authority_id, authority_id == _active_authority_id)


func _start_reconnected_authority_validation(authority_id: String) -> void:
	if not _runtime_authority_recovery.has(authority_id):
		return
	var recovery: Dictionary = Dictionary(_runtime_authority_recovery[authority_id])
	if String(recovery.get("stage", "")) != "WAIT_RECONNECT":
		return
	recovery["stage"] = "STATUS"
	_runtime_authority_recovery[authority_id] = recovery
	_request_serial += 1
	var request_id := "sm1/gateway/authority-recovery/%d/status" % _request_serial
	_runtime_authority_requests[request_id] = {"kind": "RECOVERY_STATUS", "target": authority_id}
	_counters["authority_recovery_status_queries"] = int(_counters["authority_recovery_status_queries"]) + 1
	_send_authority(authority_id, {"type": "STATUS_QUERY", "request_id": request_id})


func _handle_runtime_recovery_status(authority_id: String, payload: Dictionary, context: Dictionary) -> void:
	var target := String(context.get("target", ""))
	if authority_id != target or not _runtime_authority_recovery.has(target):
		_finish_failure("AUTHORITY_RECOVERY_STATUS_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	if not bool(payload.get("success", false)) or String(payload.get("authority_id", "")) != target:
		_finish_failure("AUTHORITY_RECOVERY_STATUS_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if bool(payload.get("active", false)):
		_finish_failure("AUTHORITY_RECOVERY_REPLACEMENT_SELF_ACTIVE", {"authority_id": authority_id, "payload": payload})
		return
	var recovery: Dictionary = Dictionary(_runtime_authority_recovery[target])
	var source := _active_authority_id if not bool(recovery.get("was_active", false)) else _other_authority(target)
	if source.is_empty() or not bool(_authority_ready.get(source, false)):
		_finish_failure("AUTHORITY_RECOVERY_SOURCE_UNAVAILABLE", {"target": target, "source": source})
		return
	recovery["stage"] = "STATE_QUERY"
	recovery["source"] = source
	_runtime_authority_recovery[target] = recovery
	_request_serial += 1
	var request_id := "sm1/gateway/authority-recovery/%d/state" % _request_serial
	_runtime_authority_requests[request_id] = {"kind": "RECOVERY_STATE", "target": target, "source": source}
	_counters["authority_recovery_state_queries"] = int(_counters["authority_recovery_state_queries"]) + 1
	_send_authority(source, {"type": "RECOVERY_STATE_QUERY", "request_id": request_id})


func _handle_runtime_recovery_state(authority_id: String, payload: Dictionary, context: Dictionary) -> void:
	var target := String(context.get("target", ""))
	var source := String(context.get("source", ""))
	if authority_id != source or not _runtime_authority_recovery.has(target):
		_finish_failure("AUTHORITY_RECOVERY_STATE_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	if not bool(payload.get("success", false)) or String(payload.get("authority_id", "")) != source:
		_finish_failure("AUTHORITY_RECOVERY_STATE_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	var state_value = payload.get("state", {})
	if not state_value is Dictionary:
		_finish_failure("AUTHORITY_RECOVERY_STATE_REQUIRED", {"payload": payload})
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	var checksum := Support.checksum(state)
	if not _validate_identity(state) or checksum != String(payload.get("state_checksum", "")):
		_finish_failure("AUTHORITY_RECOVERY_STATE_IDENTITY_DIVERGED", {"payload": payload})
		return
	if int(state.get("world_revision", 0)) != _last_world_revision or checksum != _last_state_checksum:
		_finish_failure("AUTHORITY_RECOVERY_OBSERVED_STATE_DIVERGED", {
			"expected_revision": _last_world_revision,
			"actual_revision": int(state.get("world_revision", 0)),
			"expected_checksum": _last_state_checksum,
			"actual_checksum": checksum,
		})
		return
	var recovery: Dictionary = Dictionary(_runtime_authority_recovery[target])
	var source_should_be_active := not bool(recovery.get("was_active", false))
	if bool(payload.get("active", false)) != source_should_be_active:
		_finish_failure("AUTHORITY_RECOVERY_SOURCE_ROLE_DIVERGED", {"source": source, "payload": payload})
		return
	recovery["stage"] = "STANDBY_SYNC"
	recovery["state_checksum"] = checksum
	_runtime_authority_recovery[target] = recovery
	_request_serial += 1
	var request_id := "sm1/gateway/authority-recovery/%d/sync" % _request_serial
	_runtime_authority_requests[request_id] = {"kind": "STANDBY_SYNC", "target": target}
	_send_authority(target, {"type": "STANDBY_SYNC", "request_id": request_id, "state": state})


func _handle_runtime_standby_sync(authority_id: String, payload: Dictionary, context: Dictionary) -> void:
	var target := String(context.get("target", ""))
	if authority_id != target or not _runtime_authority_recovery.has(target):
		_finish_failure("AUTHORITY_STANDBY_SYNC_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	var recovery: Dictionary = Dictionary(_runtime_authority_recovery[target])
	if not bool(payload.get("success", false)) or not bool(payload.get("zero_write", false)) or String(payload.get("state_checksum", "")) != String(recovery.get("state_checksum", "")):
		_finish_failure("AUTHORITY_STANDBY_SYNC_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	_counters["standby_syncs"] = int(_counters["standby_syncs"]) + 1
	if not bool(recovery.get("was_active", false)):
		_complete_runtime_authority_recovery(target, false)
		return
	recovery["stage"] = "RECOVER_ACTIVATE"
	_runtime_authority_recovery[target] = recovery
	_request_serial += 1
	var request_id := "sm1/gateway/authority-recovery/%d/activate" % _request_serial
	_runtime_authority_requests[request_id] = {"kind": "RECOVER_ACTIVATE", "target": target}
	_send_authority(target, {"type": "RECOVER_ACTIVATE", "request_id": request_id, "target_epoch": int(recovery.get("expected_epoch", 0))})


func _handle_runtime_recover_activate(authority_id: String, payload: Dictionary, context: Dictionary) -> void:
	var target := String(context.get("target", ""))
	if authority_id != target or not _runtime_authority_recovery.has(target):
		_finish_failure("AUTHORITY_RECOVER_ACTIVATE_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	var recovery: Dictionary = Dictionary(_runtime_authority_recovery[target])
	if not bool(payload.get("success", false)) or int(payload.get("authority_epoch", 0)) != int(recovery.get("expected_epoch", 0)) or String(payload.get("state_checksum", "")) != String(recovery.get("state_checksum", "")):
		_finish_failure("AUTHORITY_RECOVER_ACTIVATE_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	_counters["active_authority_recoveries"] = int(_counters["active_authority_recoveries"]) + 1
	_complete_runtime_authority_recovery(target, true)


func _complete_runtime_authority_recovery(authority_id: String, restored_active: bool) -> void:
	_runtime_authority_recovery.erase(authority_id)
	_authority_reconnect_due_ms[authority_id] = -1
	_authority_recovery_blocks_writes = not _runtime_authority_recovery.is_empty()
	_counters["authority_recovery_events"] = int(_counters["authority_recovery_events"]) + 1
	Support.write_state(String(_options["result-file"]), "AUTHORITY_RECOVERED", {
		"process_id": OS.get_process_id(),
		"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
		"recovered_authority_id": authority_id,
		"restored_active": restored_active,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"world_revision": _last_world_revision,
		"state_checksum": _last_state_checksum,
	})
	_broadcast_authority_recovery("AUTHORITY_RECOVERY_COMPLETE", authority_id, restored_active)


func _broadcast_authority_recovery(event_type: String, recovered_authority_id: String, restored_active: bool) -> void:
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": event_type,
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"product_session_id": Support.PRODUCT_SESSION_ID,
			"recovered_authority_id": recovered_authority_id,
			"restored_active": restored_active,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
			"world_revision": _last_world_revision,
			"state_checksum": _last_state_checksum,
		})


func _other_authority(authority_id: String) -> String:
	if authority_id == Support.AUTHORITY_A:
		return Support.AUTHORITY_B
	if authority_id == Support.AUTHORITY_B:
		return Support.AUTHORITY_A
	return ""


func _poll_authority(authority_id: String) -> void:
	if not _authority_boundaries.has(authority_id):
		return
	var boundary = _authority_boundaries[authority_id]
	var peer_id := String(_authority_peer_ids[authority_id])
	var polled: Dictionary = boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		if _runtime_authority_recovery.has(authority_id):
			boundary.stop()
			_authority_boundaries.erase(authority_id)
			_authority_reconnect_due_ms[authority_id] = Time.get_ticks_msec() + 200
			return
		_finish_failure(String(polled.get("error_code", "AUTHORITY_POLL_FAILED")), {"authority_id": authority_id})
		return
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = Dictionary(raw)
		var event_type := String(event.get("event_type", ""))
		if event_type == "PEER_CONNECTED":
			if not Support.mark_ready(boundary, peer_id):
				_finish_failure("AUTHORITY_PEER_NOT_READY", {"authority_id": authority_id})
				return
			var was_ready := bool(_authority_ready.get(authority_id, false))
			_authority_ready[authority_id] = true
			if _runtime_authority_recovery.has(authority_id) and not was_ready:
				_counters["authority_reconnects"] = int(_counters["authority_reconnects"]) + 1
				_start_reconnected_authority_validation(authority_id)
		elif event_type == "PEER_DISCONNECTED" and _shutdown_at_ms < 0:
			_handle_authority_disconnect(authority_id)
			return
		elif event_type == "MESSAGE_RECEIVED":
			var payload := Support.payload_from_event(event)
			if not payload.is_empty():
				_counters["authority_messages"] = int(_counters["authority_messages"]) + 1
				_handle_authority(authority_id, payload)
	if not bool(_authority_ready.get(authority_id, false)) and String(boundary.get_peer_snapshot(peer_id).get("state", "")) == "READY":
		_authority_ready[authority_id] = true


func _handle_client(peer_id: String, payload: Dictionary) -> void:
	var type := String(payload.get("type", ""))
	if type == "HELLO":
		var client_id := String(payload.get("client_id", ""))
		if client_id not in ["a", "b"]:
			_send_client(peer_id, {"type": "ERROR", "error_code": "SM1_CLIENT_ID_INVALID"})
			return
		if _peer_by_client.has(client_id) and String(_peer_by_client[client_id]) != peer_id:
			_finish_failure("CLIENT_ID_ALREADY_BOUND", {"client_id": client_id})
			return
		var gateway_restart := bool(payload.get("gateway_restart", false))
		var reconnecting := bool(_ever_connected_clients.get(client_id, false))
		_client_by_peer[peer_id] = client_id
		_peer_by_client[client_id] = peer_id
		_ever_connected_clients[client_id] = true
		if gateway_restart:
			_restart_recovery_session = true
			_pending_restart_hellos[peer_id] = payload.duplicate(true)
			_begin_restart_resume(peer_id, client_id, payload)
		elif reconnecting:
			_begin_client_resume(peer_id, client_id)
		else:
			_maybe_start_clients()
		return
	if type != "EXECUTE":
		_send_client(peer_id, {"type": "ERROR", "error_code": "SM1_CLIENT_MESSAGE_UNKNOWN"})
		return
	if bool(_resuming_peers.get(peer_id, false)):
		_send_client(peer_id, {
			"type": "COMMAND_RESULT", "request_id": String(payload.get("request_id", "")),
			"success": false, "error_code": "SM1_GATEWAY_RESUME_PENDING",
		})
		return
	if String(_client_by_peer.get(peer_id, "")) != "a":
		_send_client(peer_id, {
			"type": "COMMAND_RESULT", "request_id": String(payload.get("request_id", "")),
			"success": false, "error_code": "SM1_OBSERVER_CANNOT_WRITE",
		})
		return
	if _authority_recovery_blocks_writes:
		_send_client(peer_id, {
			"type": "COMMAND_RESULT", "request_id": String(payload.get("request_id", "")),
			"success": false, "error_code": "SM1_AUTHORITY_RECOVERY_PENDING",
		})
		return
	if not _started_clients or not _pending_command.is_empty() or not _transfer.is_empty():
		_counters["busy_rejections"] = int(_counters["busy_rejections"]) + 1
		_send_client(peer_id, {
			"type": "COMMAND_RESULT", "request_id": String(payload.get("request_id", "")),
			"success": false, "error_code": "SM1_GATEWAY_COMMAND_BUSY",
		})
		return
	_request_serial += 1
	var gateway_request_id := "sm1/gateway/execute/%d" % _request_serial
	_pending_command = {
		"gateway_request_id": gateway_request_id,
		"client_peer_id": peer_id,
		"client_request_id": String(payload.get("request_id", "")),
		"operation_id": String(payload.get("operation_id", "")),
	}
	_counters["commands"] = int(_counters["commands"]) + 1
	_send_authority(_active_authority_id, {
		"type": "EXECUTE",
		"request_id": gateway_request_id,
		"authority_epoch": _authority_epoch,
		"operation_id": String(payload.get("operation_id", "")),
		"input_sequence": int(payload.get("input_sequence", 0)),
		"command_kind": String(payload.get("command_kind", "")),
		"delta_x": float(payload.get("delta_x", 0.0)),
	})


func _handle_authority(authority_id: String, payload: Dictionary) -> void:
	var type := String(payload.get("type", ""))
	var request_id := String(payload.get("request_id", ""))
	if _runtime_authority_requests.has(request_id):
		var context: Dictionary = Dictionary(_runtime_authority_requests[request_id]).duplicate(true)
		_runtime_authority_requests.erase(request_id)
		match String(context.get("kind", "")):
			"RECOVERY_STATUS":
				_handle_runtime_recovery_status(authority_id, payload, context)
			"RECOVERY_STATE":
				_handle_runtime_recovery_state(authority_id, payload, context)
			"STANDBY_SYNC":
				_handle_runtime_standby_sync(authority_id, payload, context)
			"RECOVER_ACTIVATE":
				_handle_runtime_recover_activate(authority_id, payload, context)
			_:
				_finish_failure("AUTHORITY_RECOVERY_RESPONSE_KIND_UNKNOWN", {"context": context, "payload": payload})
		return
	match type:
		"EXECUTE_RESULT":
			_handle_execute_result(authority_id, payload)
		"FREEZE_RESULT":
			_handle_freeze_result(authority_id, payload)
		"WARM_RESULT":
			_handle_warm_result(authority_id, payload)
		"RETIRE_RESULT":
			_handle_retire_result(authority_id, payload)
		"ACTIVATE_RESULT":
			_handle_activate_result(authority_id, payload)
		"STATE_QUERY_RESULT":
			_handle_state_query_result(authority_id, payload)
		"STATUS_QUERY_RESULT":
			_handle_status_query_result(authority_id, payload)
		"RECOVERY_STATE_RESULT", "STANDBY_SYNC_RESULT", "RECOVER_ACTIVATE_RESULT":
			_finish_failure("AUTHORITY_RECOVERY_RESPONSE_UNCORRELATED", {"authority_id": authority_id, "payload": payload})
		"ERROR":
			_finish_failure(String(payload.get("error_code", "AUTHORITY_ERROR")), {"authority_id": authority_id})


func _handle_execute_result(authority_id: String, payload: Dictionary) -> void:
	if _pending_command.is_empty() or authority_id != _active_authority_id or String(payload.get("request_id", "")) != String(_pending_command.get("gateway_request_id", "")):
		_finish_failure("EXECUTE_RESULT_CORRELATION_FAILED", {"authority_id": authority_id, "payload": payload})
		return
	if not bool(payload.get("success", false)):
		_send_client(String(_pending_command["client_peer_id"]), {
			"type": "COMMAND_RESULT", "request_id": String(_pending_command["client_request_id"]),
			"success": false, "error_code": String(payload.get("error_code", "SM1_EXECUTE_REJECTED")),
		})
		_pending_command = {}
		return
	var state_value = payload.get("state", {})
	if not state_value is Dictionary:
		_finish_failure("EXECUTE_STATE_REQUIRED", {})
		return
	var state: Dictionary = Dictionary(state_value).duplicate(true)
	if not _validate_identity(state):
		_finish_failure("EXECUTE_IDENTITY_DIVERGED", {"state": state})
		return
	var target := String(payload.get("handoff_target", ""))
	if target.is_empty():
		_complete_command(state, false)
		return
	if target == _active_authority_id or target not in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		_finish_failure("HANDOFF_TARGET_INVALID", {"target": target})
		return
	_request_serial += 1
	_transfer = {
		"transfer_id": "transfer/sm1/graphical/%d" % _request_serial,
		"source": _active_authority_id,
		"target": target,
		"source_epoch": _authority_epoch,
		"target_epoch": _authority_epoch + 1,
		"state": state,
		"state_checksum": Support.checksum(state),
	}
	_send_authority(_active_authority_id, {
		"type": "FREEZE", "request_id": String(_transfer["transfer_id"]) + "/freeze",
		"source_epoch": _authority_epoch,
	})


func _handle_freeze_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "source", payload, "/freeze") or not bool(payload.get("success", false)):
		_finish_failure("FREEZE_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if String(payload.get("state_checksum", "")) != String(_transfer.get("state_checksum", "")):
		_finish_failure("FREEZE_STATE_CHANGED", {})
		return
	_send_authority(String(_transfer["target"]), {
		"type": "WARM_LOAD", "request_id": String(_transfer["transfer_id"]) + "/warm",
		"state": Dictionary(_transfer["state"]).duplicate(true),
	})


func _handle_warm_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "target", payload, "/warm") or not bool(payload.get("success", false)) or not bool(payload.get("zero_write", false)):
		_finish_failure("WARM_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if String(payload.get("state_checksum", "")) != String(_transfer.get("state_checksum", "")):
		_finish_failure("WARM_STATE_CHANGED", {})
		return
	_send_authority(String(_transfer["source"]), {
		"type": "RETIRE", "request_id": String(_transfer["transfer_id"]) + "/retire",
	})


func _handle_retire_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "source", payload, "/retire") or not bool(payload.get("success", false)):
		_finish_failure("RETIRE_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	_send_authority(String(_transfer["target"]), {
		"type": "ACTIVATE", "request_id": String(_transfer["transfer_id"]) + "/activate",
		"target_epoch": int(_transfer["target_epoch"]),
	})


func _handle_activate_result(authority_id: String, payload: Dictionary) -> void:
	if not _transfer_matches(authority_id, "target", payload, "/activate") or not bool(payload.get("success", false)):
		_finish_failure("ACTIVATE_RESULT_INVALID", {"authority_id": authority_id, "payload": payload})
		return
	if int(payload.get("authority_epoch", 0)) != int(_transfer.get("target_epoch", 0)):
		_finish_failure("ACTIVATION_EPOCH_DIVERGED", {})
		return
	_active_authority_id = String(_transfer["target"])
	_authority_epoch = int(_transfer["target_epoch"])
	_handoff_count += 1
	_counters["handoffs"] = _handoff_count
	_counters["route_changes"] = int(_counters["route_changes"]) + 1
	var state: Dictionary = Dictionary(_transfer["state"]).duplicate(true)
	_transfer.clear()
	_complete_command(state, true)


func _complete_command(state: Dictionary, handoff_complete: bool) -> void:
	_last_world_revision = int(state.get("world_revision", 0))
	_last_state_checksum = Support.checksum(state)
	_broadcast_state(state)
	var peer_id := String(_pending_command.get("client_peer_id", ""))
	var operation_id := String(_pending_command.get("operation_id", ""))
	_send_client(peer_id, {
		"type": "COMMAND_RESULT",
		"request_id": String(_pending_command.get("client_request_id", "")),
		"success": true,
		"handoff_complete": handoff_complete,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"world_revision": _last_world_revision,
	})
	_pending_command.clear()
	if operation_id == "operation/sm1/graphical/5":
		_begin_shutdown()


func _broadcast_state(state: Dictionary) -> void:
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "STATE",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"product_session_id": Support.PRODUCT_SESSION_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
			"shared_state": state.duplicate(true),
			"state_checksum": Support.checksum(state),
		})
	_counters["state_broadcasts"] = int(_counters["state_broadcasts"]) + 1


func _maybe_start_clients() -> void:
	if _started_clients or _restart_recovery_session or not _authority_recovery_complete or _peer_by_client.size() != 2:
		return
	if not bool(_authority_ready.get(Support.AUTHORITY_A, false)) or not bool(_authority_ready.get(Support.AUTHORITY_B, false)):
		return
	_started_clients = true
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "START",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"product_session_id": Support.PRODUCT_SESSION_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
		})


func _begin_shutdown() -> void:
	for peer_value in _client_by_peer.keys():
		_send_client(String(peer_value), {
			"type": "COMPLETE",
			"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
			"active_authority_id": _active_authority_id,
			"authority_epoch": _authority_epoch,
			"world_revision": _last_world_revision,
		})
	_send_authority(Support.AUTHORITY_A, {"type": "SHUTDOWN", "request_id": "shutdown/a"})
	_send_authority(Support.AUTHORITY_B, {"type": "SHUTDOWN", "request_id": "shutdown/b"})
	_flush_all()
	_shutdown_at_ms = Time.get_ticks_msec() + 1000


func _send_client(peer_id: String, payload: Dictionary) -> void:
	if peer_id.is_empty() or _client_boundary == null:
		return
	var sent := Support.send(_client_boundary, peer_id, payload)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "GATEWAY_CLIENT_SEND_FAILED")), {"peer_id": peer_id, "type": String(payload.get("type", ""))})


func _send_authority(authority_id: String, payload: Dictionary) -> void:
	if not _authority_boundaries.has(authority_id):
		_finish_failure("AUTHORITY_ROUTE_MISSING", {"authority_id": authority_id})
		return
	var sent := Support.send(_authority_boundaries[authority_id], String(_authority_peer_ids[authority_id]), payload)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "GATEWAY_AUTHORITY_SEND_FAILED")), {"authority_id": authority_id, "type": String(payload.get("type", ""))})


func _flush_all() -> void:
	if _client_boundary != null:
		_client_boundary.flush_outbound(256)
	for boundary_value in _authority_boundaries.values():
		boundary_value.flush_outbound(256)


func _transfer_matches(authority_id: String, role: String, payload: Dictionary, suffix: String) -> bool:
	return not _transfer.is_empty() \
		and authority_id == String(_transfer.get(role, "")) \
		and String(payload.get("request_id", "")) == String(_transfer.get("transfer_id", "")) + suffix


func _validate_identity(state: Dictionary) -> bool:
	return String(state.get("product_session_id", "")) == Support.PRODUCT_SESSION_ID \
		and String(state.get("logical_player_id", "")) == Support.LOGICAL_PLAYER_ID \
		and String(state.get("player_entity_id", "")) == Support.PLAYER_ENTITY_ID \
		and int(state.get("spawn_generation", 0)) == 1


func _network_condition_report() -> Dictionary:
	var result := {
		"client": {
			"profile": _client_network_profile.duplicate(true),
			"snapshot": _client_network_simulator.get_runtime_snapshot().duplicate(true) if _client_network_simulator != null else {},
		},
		"authorities": {},
	}
	for authority_id in [Support.AUTHORITY_A, Support.AUTHORITY_B]:
		var simulator = _authority_network_simulators.get(authority_id)
		result["authorities"][authority_id] = {
			"profile": Dictionary(_authority_network_profiles.get(authority_id, {})).duplicate(true),
			"snapshot": simulator.get_runtime_snapshot().duplicate(true) if simulator != null else {},
		}
	return result


func _finish_success() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "planet_simulator.sm1_graphical_gateway_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"process_id": OS.get_process_id(),
		"gateway_endpoint_id": Support.GATEWAY_ENDPOINT_ID,
		"client_ids": _peer_by_client.keys(),
		"client_connection_count": _peer_by_client.size(),
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"handoff_count": _handoff_count,
		"authority_recovery_complete": _authority_recovery_complete,
		"bootstrap_authority_id": _bootstrap_authority_id,
		"bootstrap_authority_epoch": _bootstrap_authority_epoch,
		"last_world_revision": _last_world_revision,
		"last_state_checksum": _last_state_checksum,
		"transfer_payload_retained": not _transfer.is_empty(),
		"authority_runtime_recovery_pending": not _runtime_authority_recovery.is_empty(),
		"authority_recovery_blocks_writes": _authority_recovery_blocks_writes,
		"canonical_gameplay_owner": false,
		"client_endpoint_changed": false,
		"counters": _counters.duplicate(true),
		"network_conditions": _network_condition_report(),
	}
	Support.write_json(String(_options["result-file"]), report)
	_stop_boundaries()
	print("SM1_6_GATEWAY_COMPLETE epoch=%d handoffs=%d" % [_authority_epoch, _handoff_count])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	Support.write_json(String(_options.get("result-file", "")), {
		"schema": "planet_simulator.sm1_graphical_gateway_report.v1",
		"state": "FAILED", "passed": false, "process_id": OS.get_process_id(),
		"failure_code": error_code, "details": details,
		"active_authority_id": _active_authority_id, "authority_epoch": _authority_epoch,
		"handoff_count": _handoff_count,
	})
	_stop_boundaries()
	push_error("SM1.6 gateway failed: %s" % error_code)
	quit(1)


func _stop_boundaries() -> void:
	if _client_boundary != null:
		_client_boundary.stop()
	for boundary_value in _authority_boundaries.values():
		boundary_value.stop()
